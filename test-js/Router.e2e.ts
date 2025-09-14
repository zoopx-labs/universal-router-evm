import { expect } from 'chai';
import { spawn } from 'child_process';
import fetch from 'node-fetch';
import { encodeDeployData, encodeFunctionData } from 'viem';
import path from 'path';
import fs from 'fs';

const RPC = 'http://127.0.0.1:8545';

function rpc(method: string, params: any[] = []) {
  return fetch(RPC, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ jsonrpc: '2.0', id: 1, method, params }),
  }).then((r: any) => r.json()).then((j: any) => {
    if (j.error) throw new Error(j.error.message || JSON.stringify(j.error));
    return j.result;
  });
}

describe('Router E2E (mocha)', function () {
  this.timeout(120_000);

  let nodeProc: any = null;

  before(async function () {
    async function isRpcAvailable() {
      try {
        const res = await fetch(RPC, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ jsonrpc: '2.0', id: 1, method: 'web3_clientVersion', params: [] }),
        });
        if (!res.ok) return false;
        const j: any = await res.json();
        return !!j.result;
      } catch (e) {
        return false;
      }
    }

    const already = await isRpcAvailable();
    if (already) {
      nodeProc = null;
      return;
    }

    const cwd = process.cwd();
    nodeProc = spawn('npx', ['hardhat', 'node', '--hostname', '127.0.0.1', '--port', '8545'], { cwd });

    await new Promise<void>((resolve, reject) => {
      const onData = (b: any) => {
        const s = String(b);
        if (s.includes('Started HTTP') || s.includes('Started HTTP and WebSocket')) {
          nodeProc!.stdout.off('data', onData);
          resolve();
        }
      };
      nodeProc!.stdout.on('data', onData);
      nodeProc!.stderr.on('data', (d: any) => console.error('node err>', String(d)));
      nodeProc!.on('error', (err: any) => {
        if (err && err.code === 'EADDRINUSE') {
          console.warn('Port in use, assuming Hardhat already running');
          return resolve();
        }
        return reject(err);
      });
      setTimeout(() => reject(new Error('Hardhat node did not start in time')), 20000);
    });
  });

  after(function () {
    if (nodeProc) {
      nodeProc.kill('SIGINT');
      nodeProc = null;
    }
  });

  it('deploys MockERC20 and Router and calls universalBridgeTransfer', async function () {
    const accounts: string[] = await rpc('eth_accounts');
    const deployer = accounts[0];

    const mockArtifactPath = path.resolve(process.cwd(), 'artifacts/contracts/MockERC20.sol/MockERC20.json');
    const mockArtifact = JSON.parse(fs.readFileSync(mockArtifactPath, 'utf8'));
    const mockDeployData = encodeDeployData({ abi: mockArtifact.abi as any, bytecode: mockArtifact.bytecode as `0x${string}`, args: ['Mock', 'MCK'] });
    const mockTxHash: string = await rpc('eth_sendTransaction', [{ from: deployer, data: mockDeployData }]);
    const mockRcpt = await waitForReceipt(mockTxHash);
    const mockAddr = mockRcpt.contractAddress;
    expect(mockAddr).to.match(/^0x[0-9a-fA-F]{40}$/);

    const mintData = encodeFunctionData({ abi: mockArtifact.abi as any, functionName: 'mint', args: [deployer, 1_000_000n * 10n ** 18n] });
    await rpc('eth_sendTransaction', [{ from: deployer, to: mockAddr, data: mintData }]);

    const routerArtifactPath = path.resolve(process.cwd(), 'artifacts/contracts/Router.sol/Router.json');
    const routerArtifact = JSON.parse(fs.readFileSync(routerArtifactPath, 'utf8'));
  const routerDeployData = encodeDeployData({ abi: routerArtifact.abi as any, bytecode: routerArtifact.bytecode as `0x${string}`, args: [deployer, deployer, deployer, 1] });
    const routerTxHash: string = await rpc('eth_sendTransaction', [{ from: deployer, data: routerDeployData }]);
    const routerRcpt = await waitForReceipt(routerTxHash);
    const routerAddr = routerRcpt.contractAddress;
    expect(routerAddr).to.match(/^0x[0-9a-fA-F]{40}$/);

    const approveData = encodeFunctionData({ abi: mockArtifact.abi as any, functionName: 'approve', args: [routerAddr, 500000n] });
    await rpc('eth_sendTransaction', [{ from: deployer, to: mockAddr, data: approveData }]);

    const ubData = encodeFunctionData({ abi: routerArtifact.abi as any, functionName: 'universalBridgeTransfer', args: [mockAddr, 100000n, 50n, 50n, '0x' as `0x${string}`, deployer, 999, 1n] });
    const ubTxHash: string = await rpc('eth_sendTransaction', [{ from: deployer, to: routerAddr, data: ubData }]);
    const ubRcpt = await waitForReceipt(ubTxHash);
    expect(ubRcpt.status === '0x1' || ubRcpt.status === 1).to.be.true;
  });
});

async function waitForReceipt(hash: string) {
  for (;;) {
    const rcpt = await rpc('eth_getTransactionReceipt', [hash]);
    if (rcpt) return rcpt as any;
    await new Promise((r) => setTimeout(r, 200));
  }
}
