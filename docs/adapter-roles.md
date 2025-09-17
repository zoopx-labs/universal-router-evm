# Adapter Roles & Finalization

The router now uses a multi-adapter allowlist enforced via `AccessControl` instead of a single adapter address.

## Rationale
A single mutable `adapter` bottleneck concentrates risk (key compromise / upgrade race). A role-based allowlist:
- Enables parallel adapters (e.g., CCTP, Superchain, LP Vault) without redeploying the router.
- Allows rapid freeze of a compromised adapter (`freezeAdapter`) while others continue operating.
- Preserves storage layout by retaining (but deprecating) the legacy `adapter` slot.

## Roles
- `DEFAULT_ADMIN_ROLE`: Granted to the deploy-time admin in the constructor. Can add/remove/freeze adapters.
- `ADAPTER_ROLE`: Entities permitted to call `finalizeMessage` on the destination chain.

## Adapter Lifecycle
```solidity
addAdapter(address a);      // grant ADAPTER_ROLE
removeAdapter(address a);   // revoke ADAPTER_ROLE
freezeAdapter(address a, bool frozen); // toggle per-adapter emergency freeze
```
Frozen adapters still have the role but calls gated by `onlyAdapter` revert with `AdapterFrozenErr`.

## Gating
```solidity
modifier onlyAdapter() {
    if (!hasRole(ADAPTER_ROLE, _msgSender())) revert NotAdapter();
    if (frozenAdapter[_msgSender()]) revert AdapterFrozenErr();
    _;
}
```
`finalizeMessage` is the only path using this modifier; all other source‑leg flows remain permissionless (user or signed intent driven).

## Replay & Fees (Unchanged)
- Replay mapping: `usedMessages[messageHash]` still guards `finalizeMessage`.
- Destination fee distribution: protocolShare + lpShare + relayerFee extracted from the forwarded `amount`, with remainder to the vault.
- Event telemetry (`FeeApplied`) unchanged; `messageHash` is the indexing key.

## Hashing & BridgeID
No human-readable BridgeID is stored on-chain. The backend derives a display BridgeID from `messageHash` (e.g., formatting first bytes) and records per-leg tx hashes keyed by `messageHash`.

Source-leg events emit `payloadHash` + `messageHash` + `globalRouteId`. Destination-leg event (`FeeApplied`) emits `messageHash`.

## Migration Notes
- Legacy `adapter` variable retained for layout but ignored for authorization; scripts may optionally still set it for backward analytics compatibility.
- Deployment scripts should call `addAdapter` (or multiple via comma-separated env) post-deploy.
- Freezing does not clear role membership; design allows quick thaw without re-granting.

## Operational Playbook
1. Add new adapter: `addAdapter(newAdapter)`; monitor logs for `AdapterAdded`.
2. Emergency compromise: `freezeAdapter(adapter, true)`; confirm `AdapterFrozen` event.
3. Full removal (post incident / retirement): `removeAdapter(adapter)`; historical events remain indexable.
4. Unfreeze: `freezeAdapter(adapter, false)`.

## Security Considerations
- Keep the admin key in a secure multisig where possible; role admin = DEFAULT_ADMIN_ROLE.
- Consider monitoring automation watching for unexpected `AdapterFrozen(true)` emits or sudden `removeAdapter` churn.
- Separate adapters by purpose—e.g., one per backplane—to minimize blast radius if frozen.

## Testing
Dedicated Foundry tests:
- `AdapterAllowlist.t.sol` — add/remove/freeze/replay unaffected.
- `Replay.t.sol` — explicit finalize replay guard.
- `TargetAllowlist.t.sol` — target enforcement.
- `EventsHashes.t.sol` — smoke for hash emission path.
Existing core tests already exercise intent, approve-then-call, and residue invariants.

## Future Extensions
- Per-adapter fee multipliers (append-only storage) if divergent economics required.
- Optional adapter “quarantine” grace period before new adapter becomes active.
- Hashing library usage inline once integrated end-to-end (currently provided as utility at `contracts/lib/Hashing.sol`).
