#!/usr/bin/env ts-node
import fs from 'fs';
import path from 'path';
import dotenv from 'dotenv';
import { Wallet } from 'ethers';
import { createPublicClient, http, formatEther } from 'viem';

// Load project .env explicitly
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

// Derive deployer address
const priv = process.env.DEPLOYER_PRIVATE_KEY?.trim() || '';
const mn = process.env.DEPLOYER_MNEMONIC?.trim() || '';
let address: string | null = null;
if (priv && priv.length >= 10) {
  try { address = (new Wallet(priv)).address; } catch (e) { /* ignore */ }
}
if (!address && mn && mn.length > 10) {
  try { address = (Wallet.fromPhrase ? Wallet.fromPhrase(mn) : new Wallet(mn)).address; } catch (e) { /* ignore */ }
}
if (!address) {
  console.error('No DEPLOYER_PRIVATE_KEY or DEPLOYER_MNEMONIC found in env; please set one in evm-thin-router/.env or your shell.');
  process.exit(1);
}

// Collect RPC_* entries from process.env
const rpcKeys = Object.keys(process.env).filter(k => k.startsWith('RPC_'));
if (rpcKeys.length === 0) {
  console.error('No RPC_* entries found in env');
  process.exit(1);
}

(async () => {
  console.log('Deployer address:', address);
  for (const k of rpcKeys) {
    const raw = process.env[k];
    const rpc = resolve(raw);
    if (!rpc) {
      console.log(k, ': (empty)');
      continue;
    }
    try {
      const client = createPublicClient({ transport: http(rpc) });
      const bal = await (client as any).getBalance({ address });
      console.log(k.padEnd(25), rpc.padEnd(60), formatEther(bal));
    } catch (e: any) {
      console.log(k.padEnd(25), rpc.padEnd(60), 'ERROR:', e?.message || String(e));
    }
  }
})();
