#!/usr/bin/env ts-node
import fs from 'fs';
import path from 'path';
import dotenv from 'dotenv';
import { http, createPublicClient } from 'viem';
import { Interface } from 'ethers';

// Load env from evm-thin-router/.env if present (for optional SELECT_RPCS, etc.)
const envPath = path.resolve(process.cwd(), 'evm-thin-router', '.env');
if (fs.existsSync(envPath)) dotenv.config({ path: envPath });
else dotenv.config();

function resolveVar(raw?: string): string | undefined {
  if (!raw) return undefined;
  let s = raw.replace(/\$\{([A-Z0-9_]+)\}/g, (_m, name) => process.env[name] ?? '');
  s = s.replace(/\s+/g, '');
  if ((s.startsWith('"') && s.endsWith('"')) || (s.startsWith("'") && s.endsWith("'"))) s = s.slice(1, -1);
  if (s === '') return undefined;
  return s;
}

function outPath() {
  return path.resolve('scripts/deployments/router-deploys.json');
}
function readOut(): Record<string, any> {
  try {
    const p = outPath();
    if (!fs.existsSync(p)) return {};
    return JSON.parse(fs.readFileSync(p, 'utf8'));
  } catch {
    return {};
  }
}
function writeOut(m: Record<string, any>) {
  const p = outPath();
  const d = path.dirname(p);
  if (!fs.existsSync(d)) fs.mkdirSync(d, { recursive: true });
  fs.writeFileSync(p, JSON.stringify(m, null, 2));
}

async function verifyOne(key: string, entry: any) {
  const rpc: string | undefined = entry?.rpc;
  const addr: string | undefined = entry?.address;
  if (!rpc || !addr) {
    console.log(key, '-> missing rpc or address; skip');
    return;
  }

  const publicClient = createPublicClient({ transport: http(rpc) });
  // Prepare ABI iface for getters
  const iface = new Interface([
    'function admin() view returns (address)',
    'function feeRecipient() view returns (address)',
    'function defaultTarget() view returns (address)',
    'function SRC_CHAIN_ID() view returns (uint16)'
  ]);
  const data = {
    admin: iface.encodeFunctionData('admin', []),
    feeRecipient: iface.encodeFunctionData('feeRecipient', []),
    defaultTarget: iface.encodeFunctionData('defaultTarget', []),
    SRC_CHAIN_ID: iface.encodeFunctionData('SRC_CHAIN_ID', []),
  } as const;

  const normalize = (v: any): string | null => {
    if (!v) return null;
    if (typeof v === 'string') return v as string;
    if (typeof v === 'object' && v.data) return v.data as string;
    return null;
  };

  try {
    const [aRaw, fRaw, dRaw, sRaw] = await Promise.all([
      (publicClient as any).call({ to: addr, data: data.admin }),
      (publicClient as any).call({ to: addr, data: data.feeRecipient }),
      (publicClient as any).call({ to: addr, data: data.defaultTarget }),
      (publicClient as any).call({ to: addr, data: data.SRC_CHAIN_ID }),
    ]);
    const aHex = normalize(aRaw);
    const fHex = normalize(fRaw);
    const dHex = normalize(dRaw);
    const sHex = normalize(sRaw);

    if (!aHex || !fHex || !dHex || !sHex) {
      console.warn(key, 'getter call returned empty or malformed data', { aRaw, fRaw, dRaw, sRaw });
      return;
    }

    const admin = iface.decodeFunctionResult('admin', aHex)[0] as string;
    const feeRecipient = iface.decodeFunctionResult('feeRecipient', fHex)[0] as string;
    const defaultTarget = iface.decodeFunctionResult('defaultTarget', dHex)[0] as string;
    const SRC_CHAIN_ID = Number(iface.decodeFunctionResult('SRC_CHAIN_ID', sHex)[0]);

    console.log(key, '→', addr, { admin, feeRecipient, defaultTarget, SRC_CHAIN_ID });

    const stored = readOut();
    stored[key] = { ...(stored[key] || {}), getters: { admin, feeRecipient, defaultTarget, SRC_CHAIN_ID } };
    writeOut(stored);
  } catch (e: any) {
    console.warn(key, 'getter verification failed:', e?.message || e);
  }
}

(async () => {
  const only = (resolveVar(process.env.SELECT_RPCS) || '').trim();
  const filter = only ? new Set(only.split(',').map(s => s.trim()).filter(Boolean)) : null;
  const all = readOut();
  const keys = Object.keys(all);
  if (keys.length === 0) {
    console.error('No entries in', outPath());
    process.exit(1);
  }
  for (const key of keys) {
    if (filter && !filter.has(key)) continue;
    await verifyOne(key, all[key]);
  }
  console.log('verify done');
})();
