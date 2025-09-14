#!/usr/bin/env ts-node
import 'dotenv/config';
import fs from 'fs';
import path from 'path';
import CHAINS from './chains.ts';
import { loadOrCreateMnemonic, deriveAccount } from './wallet.ts';
import { createPublicClient, formatEther, parseEther } from 'viem';
import { resolveEnvPlaceholders } from './env.ts';
import { httpWithRateLimit } from './transport.ts';
import { precomputeFactoryFromEOA, computeCreate2Address } from './addresses.ts';
import { makeCreationCode } from './bytecode.ts';

const secret = process.env.DEPLOYER_PRIVATE_KEY || loadOrCreateMnemonic();
const acct = deriveAccount(secret);
if (!acct || !acct.address) {
  console.error('unable to derive account');
  process.exit(1);
}

function factoriesPath() { return path.resolve('scripts/create2/state/factories.json'); }
function readFactories(): Record<string,string> { try { const p = factoriesPath(); if (!fs.existsSync(p)) return {}; return JSON.parse(fs.readFileSync(p,'utf8')); } catch { return {}; } }

async function checkChain(c:any, saltHex: string, artifactPath: string) {
  const rpc = resolveEnvPlaceholders(process.env[c.rpcEnv]);
  if (!rpc) return { name: c.name, ok: false, reason: 'rpc missing' };
  const publicClient = createPublicClient({ transport: httpWithRateLimit(rpc) });
  // balance
  let bal: bigint | null = null;
  try { bal = await (publicClient as any).getBalance({ address: acct.address }); } catch (e:any) { return { name: c.name, ok: false, reason: 'balance error: '+(e?.message||e) }; }
  // persisted factory
  const m = readFactories();
  const persisted = m[String(c.chainId || c.name)];
  // compute expected factory using on-chain nonce if possible
  let expectedFactory = precomputeFactoryFromEOA(acct.address);
  try {
    const rawNonce = await (publicClient as any).getTransactionCount({ address: acct.address });
    expectedFactory = precomputeFactoryFromEOA(acct.address, BigInt(rawNonce ?? 0n));
  } catch {}
  // creation code
  let creation = '';
  try { creation = makeCreationCode(artifactPath, process.env.CONSTRUCTOR_ARGS_JSON); } catch (e:any) { creation = 'err:'+ (e?.message||e); }
  const target = creation && creation.startsWith('0x') ? computeCreate2Address(persisted || expectedFactory, saltHex, creation) : 'n/a';

  // check bytecodes
  let factoryCode = null as string|null;
  try { factoryCode = await (publicClient as any).getBytecode({ address: persisted || expectedFactory }); } catch {}
  let targetCode = null as string|null;
  try { if (target !== 'n/a') targetCode = await (publicClient as any).getBytecode({ address: target }); } catch {}

  return {
    name: c.name,
    chainId: c.chainId,
    rpc: rpc,
    balance: bal === null ? 'unknown' : formatEther(bal),
    persistedFactory: persisted || null,
    expectedFactory,
    factoryCode: factoryCode || null,
    target,
    targetCode: targetCode || null,
  };
}

async function main(){
  const salt = process.env.SALT_HEX;
  const artifact = process.env.ROUTER_ARTIFACT || 'out/Router.sol/Router.json';
  if (!salt) { console.error('SALT_HEX required'); process.exit(1); }
  const rows = [] as any[];
  for(const c of CHAINS){
    try{
      const r = await checkChain(c as any, salt, artifact);
      rows.push(r);
    }catch(e:any){ rows.push({ name: c.name, error: e?.message||e }); }
  }
  console.log('Readiness report:');
  for(const r of rows){
    console.log('---');
    console.log(r.name, 'chainId', r.chainId);
    if (r.reason) { console.log('SKIP:', r.reason); continue; }
    console.log('RPC:', r.rpc);
    console.log('Balance:', r.balance);
    console.log('PersistedFactory:', r.persistedFactory);
    console.log('ExpectedFactory:', r.expectedFactory);
    console.log('FactoryCodePresent:', r.factoryCode && r.factoryCode !== '0x');
    console.log('Target:', r.target);
    console.log('TargetCodePresent:', r.targetCode && r.targetCode !== '0x');
  }
}

main().catch(e=>{ console.error(e); process.exit(1); });
