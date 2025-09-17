# ZoopXRouterV1 (MVP)

This branch provides a minimal router snapshot intended for a tightly scoped MVP rollout limited to CCTP-based transfers.

Scope and constraints
- CCTP-only: Transactions must route exclusively through the designated CCTP adapter/handler.
- Single target: Only one fixed adapter address should be used as the target.
- Zero fees at source: Protocol and relayer fees MUST be set to 0 for all transactions.
- Token constraints: Use canonical USDC only; avoid fee-on-transfer or non-standard ERC-20s.
- Simple payloads: Only the payloads required by the CCTP adapter; no EOAs as targets.
- Limited exposure: Keep volume, assets, and chains narrowly scoped for this MVP.

Operational guidance
- Enforce invariants off-chain: The service submitting transactions must verify target address, token, and zero fees before sending.
- Monitoring: Track router and adapter balances, and alert on any unexpected residual balances or approval anomalies.
- Emergency process: Be prepared to halt submissions rapidly if any invariant is violated.

Migration plan
- This MVP is a stepping stone toward the hardened router (V2) on the main branch, which adds role-based adapter gating, replay protections, canonical hashing, fee delegation, permit flows, and richer telemetry.

Notes
- Contract code in this branch reflects the historical snapshot used for MVP scoping; do not extend functionality in this branch. Any enhancements belong in V2.
