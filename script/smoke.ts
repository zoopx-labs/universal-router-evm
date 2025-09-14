import hre from 'hardhat';
import { encodeDeployData, encodeFunctionData } from 'viem';
import fetch from 'node-fetch';

const RPC = 'http://127.0.0.1:8545';

async function rpc(method: string, params: any[] = []) {
  const res = await fetch(RPC, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ jsonrpc: '2.0', id: 1, method, params }),
  });
  const j = await res.json();
  if (j.error) throw new Error(j.error.message || JSON.stringify(j.error));
  return j.result;
}

async function main() {
  const accounts: string[] = await rpc('eth_accounts');
  const deployer = accounts[0];
  console.log('Deployer:', deployer);

  // --- Deploy MockERC20 ---
  const mockArtifact = await hre.artifacts.readArtifact('MockERC20');
  const mockDeployData = encodeDeployData({ abi: mockArtifact.abi as any, bytecode: mockArtifact.bytecode as `0x${string}`, args: ['Mock', 'MCK'] });
  const mockTxHash: string = await rpc('eth_sendTransaction', [{ from: deployer, data: mockDeployData }]);
  const mockRcpt = await waitForReceipt(mockTxHash);
  const mockAddr = mockRcpt.contractAddress;
  console.log('MockERC20 deployed at:', mockAddr);

  // mint to deployer
  const mintData = encodeFunctionData({ abi: mockArtifact.abi as any, functionName: 'mint', args: [deployer, 1000000n] });
  await rpc('eth_sendTransaction', [{ from: deployer, to: mockAddr, data: mintData }]);

  // --- Deploy Router ---
  const feeRecipient = deployer;
  const defaultTarget = deployer;
  const srcChainId = 1;

  const routerArtifact = await hre.artifacts.readArtifact('Router');
  const routerDeployData = encodeDeployData({ abi: routerArtifact.abi as any, bytecode: routerArtifact.bytecode as `0x${string}`, args: [feeRecipient, defaultTarget, srcChainId] });
  const routerTxHash: string = await rpc('eth_sendTransaction', [{ from: deployer, data: routerDeployData }]);
  const routerRcpt = await waitForReceipt(routerTxHash);
  const routerAddr = routerRcpt.contractAddress;
  console.log('Router deployed at:', routerAddr);

  // approve
  const approveData = encodeFunctionData({ abi: mockArtifact.abi as any, functionName: 'approve', args: [routerAddr, 500000n] });
  await rpc('eth_sendTransaction', [{ from: deployer, to: mockAddr, data: approveData }]);

  // call universalBridgeTransfer
  const ubData = encodeFunctionData({
    abi: routerArtifact.abi as any,
    functionName: 'universalBridgeTransfer',
    args: [mockAddr, 100000n, 50n, 50n, '0x' as `0x${string}`, defaultTarget, 999, 1n],
  });
  const ubTxHash: string = await rpc('eth_sendTransaction', [{ from: deployer, to: routerAddr, data: ubData }]);
  const ubRcpt = await waitForReceipt(ubTxHash);
  console.log('universalBridgeTransfer receipt status:', ubRcpt.status);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});

async function waitForReceipt(hash: string) {
  for (;;) {
    // eslint-disable-next-line no-await-in-loop
    const rcpt = await rpc('eth_getTransactionReceipt', [hash]);
    if (rcpt) return rcpt as any;
    // sleep 200ms
    // eslint-disable-next-line no-await-in-loop
    await new Promise((r) => setTimeout(r, 200));
  }
}

