# Security And Testing

## Scope

Read this file when implementing invariants, trust boundaries, or tests for vault routing, share accounting, rewards, and fee safety.

For a fuller evaluation workflow, including agent A/B testing with and without this skill, also read [architecture-skill-evaluation.md](architecture-skill-evaluation.md).

## Security Invariants

Every architecture document must include the applicable invariants before implementation.

- Router only routes to active registered vaults.
- Router must not keep principal after a completed user operation.
- Router must not mint or burn protocol vault shares directly.
- Router vault metadata must match the protocol vault's actual underlying asset.
- Each protocol vault accounts only for its own assets and protocol position.
- Shares from vault A cannot redeem assets from vault B.
- Yield or loss in one vault cannot change another vault's share price.
- `totalAssets()` must not include projected or unclaimable value.
- `maxWithdraw()` and `maxRedeem()` must respect real protocol liquidity.
- Async withdrawal requests cannot be claimed more than once.
- Pausing deposits should not block safe principal withdrawal unless technically required.
- Rescue functions cannot remove assets backing user principal or claimable withdrawals.
- Harvesting and fee collection must not reduce assets backing user shares except through explicitly documented fee logic.

## Security Checks

Apply these implementation-level checks when writing or reviewing contracts:

- Use `SafeERC20` for every ERC20 transfer.
- Add reentrancy protection to deposit, withdraw, redeem, request, claim, harvest, and rescue paths when external calls or token transfers are involved.
- Validate zero-address sensitive inputs such as treasury, reward router, external protocol dependency, or registry target addresses.
- Bound fee basis points, capability flags, and admin config writes.
- Emit events for every privileged state change.
- Ensure pause controls do not accidentally lock technically safe principal withdrawal.
- Ensure rescue paths cannot remove assets that back user shares, pending claims, or principal.
- Ensure router and vault state transitions remain consistent even if an external protocol call reverts.

## Test Plan

At minimum, write tests for:

- Router registry and vault activation checks.
- Deposit routing and asset validation.
- Instant withdrawal capability enforcement.
- Async request and claim flow enforcement.
- Share isolation between protocol vaults.
- `totalAssets()` accounting with idle assets and protocol position value.
- Reward harvest-and-compound effects on share price.
- Fee behavior for any enabled platform fee.
- Rescue restrictions.
- Pause behavior that still preserves technically safe principal withdrawal.

Use a contract-testing baseline such as the referenced `testing-patterns.md` workflow when choosing unit, invariant, and fuzz patterns.
