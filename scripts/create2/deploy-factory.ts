#!/usr/bin/env ts-node
import 'dotenv/config';
import fs from 'fs';
import path from 'path';
import CHAINS from './chains.ts';
import { loadOrCreateMnemonic, deriveAccount } from './wallet.ts';
import { createWalletClient, createPublicClient, formatEther, parseEther } from 'viem';
import { privateKeyToAccount } from 'viem/accounts';
import { precomputeFactoryFromEOA } from './addresses.ts';
import { resolveEnvPlaceholders } from './env.ts';
import { httpWithRateLimit } from './transport.ts';

type Hex = `0x${string}`;

function asHex(x: string): Hex { return (x.startsWith('0x') ? x : ('0x' + x)) as Hex; }

function tryReadFactoryArtifact(): Hex | null {
  const artifactPath = path.resolve('out/Create2Factory.sol/Create2Factory.json');
  if (!fs.existsSync(artifactPath)) return null;
  const art = JSON.parse(fs.readFileSync(artifactPath, 'utf8'));
  const bc = (typeof art.bytecode === 'string' ? art.bytecode : art.bytecode?.object) || art.evm?.bytecode?.object;
  return bc ? asHex(String(bc)) : null;
}

async function compileFactoryWithSolc(): Promise<Hex> {
  // Lazy-load solc to avoid hard dependency when artifact exists
  const mod: any = await import('solc');
  const solc: any = mod?.default ?? mod;
  // try common locations: script-local, repo root, workspace relative
  const scriptDir = (typeof __dirname !== 'undefined') ? __dirname : path.dirname(new URL(import.meta.url).pathname);
  const candidates = [
    path.resolve('contracts/utils/Create2Factory.sol'),
    path.resolve('evm-thin-router/contracts/utils/Create2Factory.sol'),
    path.resolve(scriptDir, '..', '..', 'contracts', 'utils', 'Create2Factory.sol')
  ];
  let sourcePath = candidates.find((p) => fs.existsSync(p));
  if (!sourcePath) sourcePath = path.resolve('contracts/utils/Create2Factory.sol');
  const source = fs.readFileSync(sourcePath, 'utf8');
  const input = {
    language: 'Solidity',
    sources: { 'Create2Factory.sol': { content: source } },
    settings: {
      optimizer: { enabled: true, runs: 200 },
      outputSelection: { '*': { '*': ['evm.bytecode.object'] } }
    }
  } as any;
  const output = JSON.parse(solc.compile(JSON.stringify(input)));
  const errors = output.errors?.filter((e: any) => e.severity === 'error');
  if (errors && errors.length) {
    throw new Error('solc compile error: ' + errors.map((e: any) => e.formattedMessage || e.message).join('\n'));
  }
  const bytecode = output.contracts['Create2Factory.sol']['Create2Factory'].evm.bytecode.object as string;
  if (!bytecode) throw new Error('solc produced no bytecode for Create2Factory');
  return asHex(bytecode);
}

const secret = process.env.DEPLOYER_PRIVATE_KEY || loadOrCreateMnemonic();
const acct = deriveAccount(secret);
if (!acct || !acct.privateKey) {
  console.error('unable to derive private key from secret');
  process.exit(1);
}

async function deployFactoryOnChain(chain: any) {
  const rpc = resolveEnvPlaceholders(process.env[chain.rpcEnv]);
  if (!rpc) {
    console.warn(`${chain.name} RPC not set; skipping.`);
    return;
  }
  const client = createWalletClient({ transport: httpWithRateLimit(rpc), account: privateKeyToAccount(acct.privateKey) as any, chain: undefined as any });
  const publicClient = createPublicClient({ transport: httpWithRateLimit(rpc) });

  // Skip if insufficient balance (or if balance cannot be read)
  const min = (() => {
    const v = (process.env.DEPLOY_MIN_BAL_ETH ?? '0').trim();
    try { return parseEther(v === '' ? '0' : v); } catch { return 0n; }
  })();
  let bal: bigint | null = null;
  try {
    bal = await (publicClient as any).getBalance({ address: acct.address });
  } catch (e: any) {
    console.warn(`${chain.name}: unable to read balance (${e?.message || e}), skip.`);
    return;
  }
  if (bal === null || bal < min) {
    console.log(`${chain.name}: balance ${bal === null ? 'unknown' : formatEther(bal)} ETH < min (${formatEther(min)}), skip.`);
    return;
  }

  // Load or compile factory creation bytecode
  let bytecode: Hex | null = tryReadFactoryArtifact();
  if (!bytecode) {
    try {
      bytecode = await compileFactoryWithSolc();
    } catch (e: any) {
      console.error('unable to load or compile Create2Factory bytecode:', e?.message || e);
      return;
    }
  }

  // attempt to compute expected factory using current nonce for better accuracy
  let expectedFactory = precomputeFactoryFromEOA(acct.address);
  try {
    const rawNonce = await (publicClient as any).getTransactionCount({ address: acct.address });
    const nonceBig = BigInt(rawNonce ?? 0n);
    expectedFactory = precomputeFactoryFromEOA(acct.address, nonceBig);
    console.log(`${chain.name}: computed expected factory ${expectedFactory} using nonce ${nonceBig}`);
  } catch (e: any) {
    console.warn(`${chain.name}: unable to read nonce, falling back to default precompute: ${expectedFactory}`);
  }

  // check if already deployed
  try {
    const code = await (publicClient as any).getBytecode({ address: expectedFactory });
    if (code && code !== '0x') {
      console.log(`Factory already deployed on ${chain.name} at ${expectedFactory}, skipping.`);
      return;
    }
  } catch (e) {
    console.warn('unable to query chain for bytecode, proceeding with deploy attempt');
  }

  console.log(`Sending deployment tx to ${chain.name} using RPC ${rpc}`);
  try {
    // Some RPCs fail on estimateGas for contract creation; provide a conservative fallback gas.
    const fallbackGas = 1_200_000n;
    let txHash: string;
    try {
      const sent = await (client as any).sendTransaction({ data: bytecode, value: 0n });
      txHash = (sent.hash ?? sent) as string;
    } catch (e: any) {
      // Retry with explicit gas to bypass estimateGas quirks.
      console.warn(`${chain.name}: sendTransaction failed (${e?.shortMessage || e?.message || e}); retrying with explicit gas`);
      const sent2 = await (client as any).sendTransaction({ data: bytecode, value: 0n, gas: fallbackGas });
      txHash = (sent2.hash ?? sent2) as string;
    }
    console.log('sent tx hash:', txHash);
    try {
      const receipt = await (publicClient as any).waitForTransactionReceipt({ hash: txHash });
      const deployedAt = receipt?.contractAddress as string | undefined;
      if (deployedAt && deployedAt !== '0x0000000000000000000000000000000000000000') {
        console.log(`${chain.name}: factory deployed at ${deployedAt}`);
        persistFactoryAddress(chain, deployedAt);
      } else {
        // attempt to verify by reading bytecode at expectedFactory and persist if present
        try {
          const code = await (publicClient as any).getBytecode({ address: expectedFactory });
          if (code && code !== '0x') {
            console.log(`${chain.name}: bytecode present at expected factory ${expectedFactory}, persisting.`);
            persistFactoryAddress(chain, expectedFactory);
          } else {
            console.warn(`${chain.name}: receipt had no contractAddress and no code at expectedFactory; manual verify needed.`);
          }
        } catch (e: any) {
          console.warn(`${chain.name}: unable to query bytecode after receipt (${e?.message || e}); manual verify needed.`);
        }
      }
    } catch (e: any) {
      console.warn(`${chain.name}: wait for receipt failed (${e?.message || e}), attempting to verify by bytecode at expected address.`);
      try {
        const code = await (publicClient as any).getBytecode({ address: expectedFactory });
        if (code && code !== '0x') {
          console.log(`${chain.name}: bytecode present at ${expectedFactory}, persisting.`);
          persistFactoryAddress(chain, expectedFactory);
        } else {
          console.warn(`${chain.name}: no bytecode at expectedFactory; manual verification needed.`);
        }
      } catch (e2: any) {
        console.warn(`${chain.name}: unable to query bytecode (${e2?.message || e2}); manual verify needed.`);
      }
    }
  } catch (e: any) {
    console.error(`${chain.name}: factory deploy failed: ${e?.shortMessage || e?.message || e}`);
  }
}

async function main() {
  for (const c of CHAINS) {
    try {
      await deployFactoryOnChain(c as any);
    } catch (e: any) {
      console.error(`Unhandled error on ${c.name}: ${e?.message || e}`);
    }
  }
}

main().catch((e)=>{ console.error(e); process.exit(1); });

// --- helpers to persist factory address mapping ---
function factoriesPath() {
  return path.resolve('scripts/create2/state/factories.json');
}

function readFactories(): Record<string, string> {
  try {
    const p = factoriesPath();
    if (!fs.existsSync(p)) return {};
    return JSON.parse(fs.readFileSync(p, 'utf8')) as Record<string, string>;
  } catch { return {}; }
}

function persistFactoryAddress(chain: any, address: string) {
  const p = factoriesPath();
  const dir = path.dirname(p);
  if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });
  const data = readFactories();
  data[String(chain.chainId || chain.name)] = address;
  fs.writeFileSync(p, JSON.stringify(data, null, 2));
}
