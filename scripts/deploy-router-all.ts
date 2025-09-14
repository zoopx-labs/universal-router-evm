#!/usr/bin/env ts-node
import fs from 'fs';
import path from 'path';
import dotenv from 'dotenv';
import { Wallet } from 'ethers';
import { http, createPublicClient, createWalletClient, formatEther } from 'viem';
import type { Hex } from 'viem';
import { privateKeyToAccount } from 'viem/accounts';
import { Interface } from 'ethers';
// Minimal artifact loader + creation code builder (inline to avoid deps on scripts folder)
function readArtifact(p: string) {
  const candidate = path.resolve(p);
  if (!fs.existsSync(candidate)) throw new Error('artifact not found: ' + candidate);
  return JSON.parse(fs.readFileSync(candidate, 'utf8'));
}
function makeCreationCode(artifactPath: string, constructorArgsJson?: string) {
  const art = readArtifact(artifactPath);
  const bytecode: unknown =
    (art.bytecode && (typeof art.bytecode === 'string' ? art.bytecode : art.bytecode.object)) ||
    (art.deployedBytecode && (typeof art.deployedBytecode === 'string' ? art.deployedBytecode : art.deployedBytecode.object)) ||
    art.object ||
    art.evm?.bytecode?.object ||
    art.evm?.deployedBytecode?.object;
  if (!bytecode) throw new Error('artifact missing bytecode: ' + artifactPath);
  // ensure we start with the contract creation bytecode
  const bc = (bytecode as string).startsWith('0x') ? (bytecode as string).slice(2) : (bytecode as string);
  let creation = '0x' + bc;
  // if constructor args provided, append their ABI encoding to the creation bytecode
  if (constructorArgsJson && constructorArgsJson !== '{}') {
    const args = JSON.parse(constructorArgsJson);
    const abi = art.abi || [];
    const iface = new Interface(abi as any);
    const values = Array.isArray(args) ? args : Object.values(args);
    const encoded = iface.encodeDeploy(values || []);
    if (encoded && typeof encoded === 'string') {
      const enc = encoded.startsWith('0x') ? encoded.slice(2) : encoded;
      creation = '0x' + bc + enc;
    }
  }
  return creation;
}

// load env
const envPath = path.resolve(process.cwd(), 'evm-thin-router', '.env');
if (fs.existsSync(envPath)) dotenv.config({ path: envPath });
else dotenv.config();

function resolve(raw?: string): string | undefined {
  if (!raw) return undefined;
  let s = raw.replace(/\$\{([A-Z0-9_]+)\}/g, (_m, name) => process.env[name] ?? '');
  s = s.replace(/\s+/g, '');
  if ((s.startsWith('"') && s.endsWith('"')) || (s.startsWith("'") && s.endsWith("'"))) s = s.slice(1, -1);
  if (s === '') return undefined;
  return s;
}

const priv = (process.env.DEPLOYER_PRIVATE_KEY || '').trim();
const mn = (process.env.DEPLOYER_MNEMONIC || '').trim();
let deployerAddr: string;
let deployerPriv: string;
if (priv && priv.length > 10) {
  deployerPriv = priv;
  deployerAddr = (new Wallet(priv)).address;
} else if (mn && mn.length > 10) {
  const w = (Wallet.fromPhrase ? Wallet.fromPhrase(mn) : new Wallet(mn));
  deployerPriv = w.privateKey;
  deployerAddr = w.address;
} else {
  console.error('No deployer key in env. Set DEPLOYER_PRIVATE_KEY or DEPLOYER_MNEMONIC in evm-thin-router/.env');
  process.exit(1);
}

const allRpcKeys = Object.keys(process.env).filter(k => k.startsWith('RPC_'));
const only = (process.env.SELECT_RPCS || '').trim();
const rpcKeys = only ? only.split(',').map(s => s.trim()).filter(Boolean) : allRpcKeys;
if (rpcKeys.length === 0) { console.error('No RPC_* entries in env'); process.exit(1); }

function outPath() { return path.resolve('scripts/deployments/router-deploys.json'); }
function readOut() { try { const p = outPath(); if (!fs.existsSync(p)) return {}; return JSON.parse(fs.readFileSync(p,'utf8')); } catch { return {}; } }
function writeOut(m: Record<string,any>) { const p = outPath(); const d = path.dirname(p); if (!fs.existsSync(d)) fs.mkdirSync(d,{recursive:true}); fs.writeFileSync(p, JSON.stringify(m,null,2)); }

async function deployToRpc(key: string, rawRpc: string) {
  const rpc = resolve(rawRpc);
  if (!rpc) { console.log(key, '-> empty RPC, skip'); return; }
  // no chain skips; deploy to all RPC_* provided

  const publicClient = createPublicClient({ transport: http(rpc) });
  // balance
  let bal: bigint | null = null;
  try { bal = await (publicClient as any).getBalance({ address: deployerAddr }); } catch (e:any) { console.log(key, '-> balance read error:', e?.message||e); return; }
  if (!bal || bal === 0n) { console.log(key, '-> zero balance, skip'); return; }
  console.log(key, 'balance', formatEther(bal));

  // chain id for srcChainId
  let chainIdNum: number = 0;
  try { const cid = await (publicClient as any).getChainId(); chainIdNum = Number(cid); } catch (e:any) { console.log(key, '-> chainId read error:', e?.message||e); }
  const srcChainId = chainIdNum & 0xffff;

  // artifact path - try several likely locations so script works from different CWDs
  const requested = process.env.ROUTER_ARTIFACT || 'out/Router.sol/Router.json';
  const scriptDir = path.dirname(new URL(import.meta.url).pathname);
  const candidates = [
    requested,
    path.resolve(process.cwd(), requested),
    path.resolve(process.cwd(), 'evm-thin-router', requested),
  // hardhat artifact likely under evm-thin-router/artifacts
  path.resolve(process.cwd(), 'evm-thin-router', 'artifacts', 'contracts', 'Router.sol', 'Router.json'),
  path.resolve(scriptDir, '..', 'artifacts', 'contracts', 'Router.sol', 'Router.json'),
    path.resolve(scriptDir, '..', requested),
    path.resolve(scriptDir, '..', '..', requested),
  ];
  let artifact: string | null = null;
  for (const c of candidates) {
    try {
      if (fs.existsSync(c)) { artifact = c; break; }
    } catch {}
  }
  if (!artifact) { console.log(key, '-> artifact not found, tried:', candidates); return; }
  console.log(key, '-> using artifact at', artifact);

  // constructor args: admin, feeRecipient, defaultTarget, srcChainId
  // defaultTarget is immutable in the contract. To support per-chain configuration and
  // the common pattern of always passing a.target from the backend, we:
  // - read an optional per-chain env override: DEFAULT_TARGET__<RPC_KEY>
  // - otherwise read DEFAULT_TARGET
  // - otherwise default to the zero address (forcing callers to pass a.target)
  const perChainDefaultKey = `DEFAULT_TARGET__${key}`;
  let defaultTargetResolved = resolve((process.env as any)[perChainDefaultKey] || process.env.DEFAULT_TARGET || '0x0000000000000000000000000000000000000000') as string;
  // normalize shorthand 0x0 to full 20-byte zero
  if (defaultTargetResolved === '0x0') defaultTargetResolved = '0x0000000000000000000000000000000000000000';
  console.log(key, '-> defaultTarget', defaultTargetResolved);
  const ctorArgs = [deployerAddr, deployerAddr, defaultTargetResolved, srcChainId];
  const creation = makeCreationCode(artifact, JSON.stringify(ctorArgs));

  const deployerPrivHex = (deployerPriv as unknown as Hex);
  const walletClient = createWalletClient({ transport: http(rpc), account: privateKeyToAccount(deployerPrivHex), chain: undefined as any });

  // optional per-chain gas/fee overrides
  const gasKey = `GAS_LIMIT__${key}`;
  const maxFeeKey = `MAX_FEE_PER_GAS__${key}`;
  const maxPrioKey = `MAX_PRIORITY_FEE_PER_GAS__${key}`;
  const gasOverride = resolve((process.env as any)[gasKey] || process.env.GAS_LIMIT || undefined);
  const maxFeeOverride = resolve((process.env as any)[maxFeeKey] || process.env.MAX_FEE_PER_GAS || undefined);
  const maxPrioOverride = resolve((process.env as any)[maxPrioKey] || process.env.MAX_PRIORITY_FEE_PER_GAS || undefined);

  try {
    let txHash: string;
    try {
      const baseTx: any = { data: creation, value: 0n };
      if (gasOverride) { try { baseTx.gas = BigInt(gasOverride); } catch {} }
      if (maxFeeOverride) { try { baseTx.maxFeePerGas = BigInt(maxFeeOverride); } catch {} }
      if (maxPrioOverride) { try { baseTx.maxPriorityFeePerGas = BigInt(maxPrioOverride); } catch {} }
      const sent = await (walletClient as any).sendTransaction(baseTx);
      txHash = (sent.hash ?? sent) as string;
    } catch (e: any) {
      console.warn(key, 'sendTransaction failed, retry with explicit gas', e?.message || e);
      // keep any fee overrides, but ensure we pass a concrete gas value on retry
      const retryTx: any = { data: creation, value: 0n, gas: 2500000n };
      if (maxFeeOverride) { try { retryTx.maxFeePerGas = BigInt(maxFeeOverride); } catch {} }
      if (maxPrioOverride) { try { retryTx.maxPriorityFeePerGas = BigInt(maxPrioOverride); } catch {} }
      const sent2 = await (walletClient as any).sendTransaction(retryTx);
      txHash = (sent2.hash ?? sent2) as string;
    }
    console.log(key, 'sent tx', txHash);
    try {
      const rc = await (publicClient as any).waitForTransactionReceipt({ hash: txHash });
      const addr = rc?.contractAddress as string | undefined;
      if (addr && addr !== '0x0000000000000000000000000000000000000000') {
        console.log(key, 'deployed at', addr);
        const stored = readOut(); stored[key] = { rpc, chainId: chainIdNum, address: addr, tx: txHash }; writeOut(stored);

        // verify getters admin(), feeRecipient(), defaultTarget(), SRC_CHAIN_ID()
        const iface = new Interface([ 'function admin() view returns (address)', 'function feeRecipient() view returns (address)', 'function defaultTarget() view returns (address)', 'function SRC_CHAIN_ID() view returns (uint16)' ]);
        const adminData = iface.encodeFunctionData('admin', []);
        const feeData = iface.encodeFunctionData('feeRecipient', []);
        const defData = iface.encodeFunctionData('defaultTarget', []);
        const srcData = iface.encodeFunctionData('SRC_CHAIN_ID', []);
        try {
          const aRaw = await (publicClient as any).call({ to: addr, data: adminData });
          const fRaw = await (publicClient as any).call({ to: addr, data: feeData });
          const dRaw = await (publicClient as any).call({ to: addr, data: defData });
          const sRaw = await (publicClient as any).call({ to: addr, data: srcData });

          // normalize viem return shapes: could be string (hex) or { data: hex } or { data: null }
          const normalize = (v: any): string | null => {
            if (!v) return null;
            if (typeof v === 'string') return v;
            if (typeof v === 'object' && v.data) return v.data;
            return null;
          };
          const aHex = normalize(aRaw);
          const fHex = normalize(fRaw);
          const dHex = normalize(dRaw);
          const sHex = normalize(sRaw);

          if (!aHex || !fHex || !dHex || !sHex) {
            console.warn(key, 'getter call returned empty data (likely no code at address or call failed). Raw:', { aRaw, fRaw, dRaw, sRaw });
          } else {
            const adminVal = iface.decodeFunctionResult('admin', aHex)[0];
            const feeVal = iface.decodeFunctionResult('feeRecipient', fHex)[0];
            const defVal = iface.decodeFunctionResult('defaultTarget', dHex)[0];
            const sVal = iface.decodeFunctionResult('SRC_CHAIN_ID', sHex)[0];
            console.log(key, 'getters => admin:', adminVal, 'feeRecipient:', feeVal, 'defaultTarget:', defVal, 'SRC_CHAIN_ID:', Number(sVal));
            stored[key].getters = { admin: adminVal, feeRecipient: feeVal, defaultTarget: defVal, SRC_CHAIN_ID: Number(sVal) };
            writeOut(stored);
          }
        } catch (e:any) { console.warn(key, 'getter calls failed', e?.message||e); }
      } else {
        console.warn(key, 'receipt missing contractAddress');
      }
    } catch (e:any) { console.warn(key, 'wait for receipt failed', e?.message||e); }
  } catch (e:any) { console.error(key, 'deploy error', e?.message||e); }
}

(async ()=>{
  for (const k of rpcKeys) {
    try { await deployToRpc(k, process.env[k] || ''); } catch (e:any) { console.error('Unhandled', k, e?.message||e); }
  }
  console.log('done');
})();
