<div align="center">
  <img src="assets/zoopx.png" alt="ZoopX" height="92" />
  <h1>Universal Router (EVM)</h1>
  <p>Lightweight, secure, and chain-agnostic router for multi-chain bridging via intents, superchains, CCTP, and liquidity vaults.</p>
</div>

## Overview

ZoopX Universal Router is a minimal, auditable EVM contract paired with an off-chain coordinator that assembles intents into safe token movements across chains. It supports three bridging backplanes:

- Superchains and L2 ecosystems (e.g., OP Stack, Arbitrum Orbit, Linea) via native bridge adapters.
- CCTP-supported chains via Circle’s Cross-Chain Transfer Protocol (canonical USDC burn/mint).
- Liquidity Pool Vault-based bridging for any EVM chain using hub-and-spoke vaults and fast relayers.

This repo contains the on-chain Router, Foundry/Hardhat tooling, and scripts for deploy, sign, and smoke tests.

## Key Properties

- Stateless router: pulls tokens, takes fee, and calls partner/vault adapters; no stateful liquidity in the router.
- EIP-712 intents: users sign intents; the router can execute with signature variants (permit/DAI permit supported).
- SafeERC20 and ReentrancyGuard; conservative error handling; target allowlist can be enforced by admin.
- Deterministic deployments supported via Create2 factory when needed.

## Architecture

High-level components:

- Universal Router (this repo):
  - Accepts intent structs, performs pull-transfer, optional fee, and invokes a target adapter (bridge/vault/partner).
  - Enforces an optional target allowlist and admin-configurable fee recipient.
  - defaultTarget is immutable and set to zero; backends must pass an explicit adapter target.

Adapters:
- Superchain Adapter(s): use canonical L1/L2 bridge interfaces per ecosystem (e.g., Optimism, Arbitrum, Base, Linea).
- CCTP Adapter: burns USDC on source chain and triggers mint on destination via Circle attestation flow.
- LP Vault Adapter: locks tokens in chain-local vault, mints claim tickets, and relayers/liquidity managers fulfill on dest chain from shared liquidity.

Off-chain Coordinator/Backend:
- Receives requests (API), quotes routes, assembles calldata for the router + adapter, and submits transactions.
- Handles replay protection, fee calculation, per-chain gas overrides, and monitoring/settlement.

```text
User Wallet  --(signed intent)-->  Coordinator  --(tx)-->  Universal Router  --(call)-->  Adapter
                                                                        |                 | 
                                                                        |                 +--> Bridge (native / CCTP / Vault)
                                                                        +--> Fee skim     
```

## Bridging Flows

### 1) Superchains & L2 Ecosystems

Use the ecosystem’s canonical bridge contracts. The adapter normalizes to a single interface, taking:
- token, amount, destinationChainId, recipient, and optional metadata.

Flow:
1. Router pulls tokens using SafeERC20 (supports permit variants).
2. Router calls SuperchainAdapter.bridge(token, amount, dstChainId, recipient, data).
3. Adapter invokes L1/L2 standard bridge (e.g., OptimismPortal/L2StandardBridge, Arbitrum Inbox/Outbox, Base bridge, Linea bridge).
4. Message is finalized per ecosystem rules; tokens are minted/released to recipient on destination.

Security & ops:
- Allowlist adapters to reduce target surface area.
- Per-chain gas and fee overrides are supported by deployment scripts.

### 2) CCTP (USDC Canonical Burn/Mint)

For CCTP-enabled chains, prefer canonical USDC bridging:

Flow:
1. Router pulls USDC from the user.
2. Router calls CCTPAdapter.burnAndSend(usdc, amount, dstDomain, recipient, nonce, extraData).
3. Circle attestation is fetched off-chain; destination chain adapter mints USDC to recipient.

Notes:
- Eliminates liquidity fragmentation for USDC.
- Requires monitoring attestation finality and retry logic in the backend.

### 3) Liquidity Pool Vault (LPV)

For chains without native or CCTP coverage, LPV provides fast bridging via shared liquidity.

Flow:
1. Router pulls tokens and calls VaultAdapter.lockAndIssue(vault, token, amount, dstChainId, recipient, quoteId).
2. Relayers fulfill on destination by releasing from destination vault liquidity.
3. Periodic rebalancing/settlement between vaults (off-chain coordination) maintains liquidity health.

Benefits:
- Fast finality independent of canonical bridge times.
- Extensible to any EVM chain with vault coverage.

Risks & mitigations:
- Liquidity risk: mitigate via caps, per-asset buffers, and on-chain vault accounting.
- Relayer risk: use multiple relayers and slashing/escrow for misbehavior.

## Data Contracts

- Intents (EIP-712): include token, amount, target adapter, destination info, and deadlines/salts to prevent replay.
- Getters: admin(), feeRecipient(), defaultTarget() = 0x0, SRC_CHAIN_ID() immutable per chain.
- Admin controls: setAdmin/propose+accept, setFeeRecipient, setAllowedTarget, setEnforceTargetAllowlist.

## Status & Deployments

See `deployment.md` for a live matrix of networks and addresses. The deploy tooling supports:
- DEFAULT_TARGET (per-chain) — normalized to zero by default.
- SELECT_RPCS filter to target subsets.
- Per-chain gas limit/maxFee/maxPriority overrides.
- Post-deploy ABI verification and JSON update.

## Quick Start

Prereqs: Node.js 18+, pnpm, Foundry.

Install deps:
```bash
pnpm install
```

Build & test:
```bash
pnpm build
pnpm test
```

Deploy (env-driven):
```bash
# Example (deploy to all RPC_* with zero defaultTarget)
DEFAULT_TARGET=0x0 pnpm ts-node --esm scripts/deploy-router-all.ts
```

Verify getters against recorded deployments:
```bash
pnpm ts-node --esm scripts/verify-getters.ts
```

## Security

- ReentrancyGuard on state-mutating entrypoints that transfer tokens.
- SafeERC20 for all token interactions.
- Optional target allowlist recommended in production.
- Compile with evmVersion=paris to avoid PUSH0 mismatches on some L2s.

Audits
- Static analysis via Slither (config in repo). External audits recommended before mainnet.

## Contributing

PRs welcome. Please:
- Keep contracts small and auditable.
- Add tests for new adapters or flows.
- Run lints and unit tests before submitting.

## License

MIT

## Additional Documentation

- Adapter Roles & Finalization: `docs/adapter-roles.md`

## Centralized Fee Settlement (Current Mode)

The router skims both `protocolFee` and `relayerFee` on the SOURCE leg (unless `delegateFeeToTarget[target]` is set, in which case the full amount is forwarded and fees are handled by the target/vault). The destination `finalizeMessage` call does NOT perform any distribution; it simply forwards the bridged `amount` and ECHOs the fee values in the `FeeApplied` event for audit correlation. A future DAO-governed contract can replace the simple EOA `feeRecipient` without altering the message hashing schema.

Implications:
- No double counting: destination side will never move fee tokens again.
- Relayer compensation presently occurs off-chain (the relayer = operator controlling `feeRecipient`).
- Upgrading to on-chain splits later will not break existing `messageHash` correlation if implemented as a new function or with append-only storage.

## Hashing Parity

Canonical `messageHash` is produced on-chain by `Hashing.messageHash(uint64 srcChainId, address srcAdapter, address recipient, address asset, uint256 amount, bytes32 payloadHash, uint64 nonce, uint64 dstChainId)` with packed encoding (`abi.encodePacked`) of each field in that exact order. A JavaScript parity test (`test-js/HashingParity.spec.ts`) mirrors this to ensure off-chain indexers derive identical hashes for BridgeID correlation.
