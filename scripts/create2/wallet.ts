import fs from 'fs';
import path from 'path';
import { Wallet } from 'ethers';

// Return either a private key (if provided) or derive from mnemonic.
// We intentionally keep the returned shape minimal: { address, privateKey }
export function loadOrCreateMnemonic(envName = 'DEPLOYER_MNEMONIC') {
  // If env var already set, use it.
  const env = process.env[envName];
  if (env && env.length > 10) return env.trim();

  // Attempt to load a project-local .env file from a few likely locations to avoid generating a new mnemonic
  const scriptDir = (typeof __dirname !== 'undefined') ? __dirname : path.dirname(new URL(import.meta.url).pathname);
  const candidates = [
    path.resolve(process.cwd(), '.env'),
    path.resolve(scriptDir, '..', '..', '.env'),
  ];
  for (const dotenvPath of candidates) {
    try {
      if (!fs.existsSync(dotenvPath)) continue;
      try {
        const dotenv = require('dotenv');
        dotenv.config({ path: dotenvPath });
      } catch (e) {
        const raw = fs.readFileSync(dotenvPath, 'utf8');
        for (const line of raw.split(/\r?\n/)) {
          const m = line.match(/^\s*([A-Za-z0-9_]+)\s*=\s*(.*)\s*$/);
          if (m) {
            const k = m[1];
            let v = m[2] || '';
            if ((v.startsWith('"') && v.endsWith('"')) || (v.startsWith("'") && v.endsWith("'"))) {
              v = v.slice(1, -1);
            }
            // overwrite to ensure quoted values are applied
            process.env[k] = v;
          }
        }
      }
      // if loaded one file, break
      break;
    } catch (e) {
      // ignore and try next
    }
  }

  const env2 = process.env[envName];
  if (env2 && env2.length > 10) return env2.trim();

  const rnd = Wallet.createRandom();
  const mn = (rnd as any).mnemonic?.phrase;
  if (!mn) throw new Error('unable to generate mnemonic');
  console.warn('No DEPLOYER_MNEMONIC provided. Generated one (save it somewhere):');
  console.warn(mn);
  try {
    fs.writeFileSync('.deployer-mnemonic', mn, { flag: 'wx' });
    console.warn('Wrote .deployer-mnemonic to local folder (NOT checked into git).');
  } catch (e) {
    // ignore if exists
  }
  return mn;
}

export function deriveAccount(secret: string) {
  // If the user passed a raw private key (0x...), use it directly. Otherwise treat as mnemonic.
  if (secret.startsWith('0x') && secret.length === 66) {
    const w = new Wallet(secret);
    return { address: w.address, privateKey: secret };
  }
  // treat as mnemonic
  // ethers v6 exposes fromPhrase helper in Wallet
  // use fromPhrase when available
  const w = (Wallet as any).fromPhrase ? (Wallet as any).fromPhrase(secret) : new Wallet(secret);
  return { address: w.address, privateKey: w.privateKey };
}
