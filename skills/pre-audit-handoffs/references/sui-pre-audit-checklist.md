# Sui Pre-Audit Checklist

Use for Sui Move packages, shared objects, capabilities, Coin/Balance flows, dynamic fields, liquid staking, lending, vaults, and strategy wrappers.

## Package and Scope

- Inspect `Move.toml`, `Published.toml`, `Move.lock`, `sources/`, and `tests/`.
- Identify package edition, dependencies, published IDs, and upgrade capability assumptions.
- Identify public APIs that cannot easily change after publish.

## Object and Capability Flow

- Map every object with `key`: owner, shared/frozen/wrapped status, transfer path, and deletion path.
- Identify every capability: `AdminCap`, `OperatorCap`, `TreasuryCap`, `UpgradeCap`, or protocol-specific cap.
- Check who receives each cap during `init`.
- Check whether a cap can be transferred, wrapped, borrowed, returned, or destroyed.
- Check wrong-owner and wrong-cap paths in multi-transaction scenarios.

## Coin and Balance Flow

- Trace `Coin<T>` entering public APIs and conversion into `Balance<T>`.
- Keep principal, rewards, fees, reserves, insurance, and unclaimed balances separate unless the protocol intentionally commingles them.
- Check split, join, mint, burn, and returned change paths.
- Check zero-value coin handling follows repo convention.
- Check `TreasuryCap<T>` cannot leak or be used without the intended authority.

## Shared Objects and Dynamic Fields

- Check shared object entry points use valid state assumptions.
- Prefer immutable borrows when mutation is not needed.
- Check dynamic field existence before borrow/remove.
- Check parent object deletion removes all child fields first.
- Check dynamic field keys cannot mix data across markets, reserves, wrappers, or users.

## Freshness and Accounting

- Check oracle price, confidence, epoch, exchange rate, accumulator, reserve, debt, reward, and share state is refreshed before value-moving mutations.
- Check same-epoch and cross-epoch behavior.
- Check rate changes checkpoint existing accrual before mutating config.
- Check stale state cannot be used for borrow, redeem, liquidate, withdraw, harvest, or rebalance.

## Hot-Potato Receipts and Borrowed Authority

- Check receipt structs have no `drop`, `copy`, or `store` unless intentionally safe.
- Bind receipts to exact wrapper, object, action, sender, cap, and value when relevant.
- Check receipts cannot be replayed, settled twice, settled against the wrong object, or abandoned with borrowed authority.
- Check relayer/operator powers are separate from admin powers.

## Public API and PTB Composability

- Check `public` functions return objects/coins when composability matters.
- Use `entry` wrappers only for convenience.
- Check APIs do not transfer to `ctx.sender()` when the caller needs PTB composition.
- Check `public_transfer` is not used when custom transfer rules are required.

## Test Gaps to Flag

- Capability holder succeeds and non-holder fails.
- Wrong owner fails across transactions.
- Shared object take/return behavior is tested.
- Dynamic field cleanup is tested.
- Stale oracle, stale epoch, stale rate, and stale accumulator cases fail safely.
- Receipt replay/drop/wrong-wrapper cases are tested.
