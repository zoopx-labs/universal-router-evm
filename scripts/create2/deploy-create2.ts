#!/usr/bin/env ts-node
import 'dotenv/config';
import fs from 'fs';
import path from 'path';
import CHAINS from './chains.ts';
import { loadOrCreateMnemonic, deriveAccount } from './wallet.ts';
import { createWalletClient, createPublicClient, formatEther, parseEther } from 'viem';
import { privateKeyToAccount } from 'viem/accounts';
import { resolveEnvPlaceholders } from './env.ts';
import { computeCreate2Address, precomputeFactoryFromEOA } from './addresses.ts';
import { makeCreationCode } from './bytecode.ts';
import { httpWithRateLimit } from './transport.ts';
import { Interface } from 'ethers';

const secret = process.env.DEPLOYER_PRIVATE_KEY || loadOrCreateMnemonic();
const account = deriveAccount(secret);
const priv = account.privateKey || '';

async function deployCreate2OnChain(chain: any, saltHex: string, artifactPath: string, constructorArgsJson?: string) {
  const rpc = resolveEnvPlaceholders(process.env[chain.rpcEnv]);
  if (!rpc) {
    console.warn(`${chain.name} RPC not set; skipping`);
    return;
  }
  const client = createWalletClient({ chain: undefined as any, transport: httpWithRateLimit(rpc), account: privateKeyToAccount(priv) });
  const publicClient = createPublicClient({ transport: httpWithRateLimit(rpc) });

  // Skip if insufficient balance (or if balance cannot be read)
  const min = (() => {
    const v = (process.env.DEPLOY_MIN_BAL_ETH ?? '0').trim();
    try { return parseEther(v === '' ? '0' : v); } catch { return 0n; }
  })();
  let bal: bigint | null = null;
  try {
    bal = await (publicClient as any).getBalance({ address: account.address });
  } catch (e: any) {
    console.warn(`${chain.name}: unable to read balance (${e?.message || e}), skip.`);
    return;
  }
  if (bal === null || bal < min) {
    console.log(`${chain.name}: balance ${bal === null ? 'unknown' : formatEther(bal)} ETH < min (${formatEther(min)}), skip.`);
    return;
  }

  const creation = makeCreationCode(artifactPath, constructorArgsJson);
  let persistedFactory = readFactory(chain);
  let factory: string | undefined = undefined;
  if (persistedFactory) {
    factory = persistedFactory;
  } else {
    // attempt to compute factory using the deployer nonce fetched from chain; this is safer than assuming nonce=0
    try {
      const rawNonce = await (publicClient as any).getTransactionCount({ address: account.address });
      const nonceBig = BigInt(rawNonce ?? 0n);
      // precompute using actual nonce
      factory = precomputeFactoryFromEOA(account.address, nonceBig);
      console.warn(`${chain.name}: no persisted factory found; computed precompute using nonce ${nonceBig}: ${factory}`);
    } catch (e: any) {
      console.warn(`${chain.name}: unable to read nonce to precompute factory (${e?.message || e}); aborting deploy on this chain.`);
      return;
    }
  }
  const expected = computeCreate2Address(factory, saltHex, creation);
  console.log(chain.name, 'factory:', factory, 'expected target:', expected);

  // check if target already exists
  try {
    const code = await (publicClient as any).getBytecode({ address: expected });
    if (code && code !== '0x') {
      console.log(`Target already deployed on ${chain.name} at ${expected}, skipping.`);
      return;
    }
  } catch (e) {
    console.warn('unable to query chain for bytecode, proceeding');
  }

  // verify factory exists on-chain before calling
  try {
    const facCode = await (publicClient as any).getBytecode({ address: factory });
    if (!facCode || facCode === '0x') {
      console.error(`${chain.name}: factory contract not present at ${factory}; cannot call deploy, aborting.`);
      return;
    }
  } catch (e: any) {
    console.warn(`${chain.name}: unable to verify factory bytecode (${e?.message || e}); proceeding but this may fail.`);
  }

  // encode factory.deploy(bytes32,bytes)
  const factoryAbi = ['function deploy(bytes32 salt, bytes creationCode) payable returns (address)'];
  const iface = new Interface(factoryAbi);
  const data = iface.encodeFunctionData('deploy', [saltHex, creation]);
  try {
    const fallbackGas = 2_000_000n;
    let txHash: string;
    try {
      const sent = await (client as any).sendTransaction({ to: factory, data, value: 0n });
      txHash = (sent.hash ?? sent) as string;
    } catch (e: any) {
      console.warn(`${chain.name}: sendTransaction failed (${e?.shortMessage || e?.message || e}); retrying with explicit gas`);
      const sent2 = await (client as any).sendTransaction({ to: factory, data, value: 0n, gas: fallbackGas });
      txHash = (sent2.hash ?? sent2) as string;
    }
    console.log('sent deploy tx:', txHash);
    try {
      const rc = await (publicClient as any).waitForTransactionReceipt({ hash: txHash });
      console.log(`${chain.name}: receipt status ${rc?.status}`);
    } catch (e: any) {
      console.warn(`${chain.name}: wait for receipt failed (${e?.message || e})`);
    }
  } catch (e: any) {
    console.error(`${chain.name}: CREATE2 deploy failed: ${e?.shortMessage || e?.message || e}`);
  }
}

async function main() {
  const salt = process.env.SALT_HEX;
  const artifact = process.env.ROUTER_ARTIFACT || 'out/Router.sol/Router.json';
  if (!salt) throw new Error('SALT_HEX required');
  for (const c of CHAINS) {
    try {
      await deployCreate2OnChain(c as any, salt, artifact, process.env.CONSTRUCTOR_ARGS_JSON);
    } catch (e: any) {
      console.error(`Unhandled error on ${c.name}: ${e?.message || e}`);
    }
  }
}

main().catch(e=>{console.error(e); process.exit(1);});

function factoriesPath() {
  return path.resolve('scripts/create2/state/factories.json');
}

function readFactory(chain: any): string | undefined {
  try {
    const p = factoriesPath();
    if (!fs.existsSync(p)) return undefined;
    const m = JSON.parse(fs.readFileSync(p, 'utf8')) as Record<string, string>;
    return m[String(chain.chainId || chain.name)];
  } catch { return undefined; }
}
