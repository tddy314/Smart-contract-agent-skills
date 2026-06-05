# Accounting Rules

## Scope

Read this file when implementing or reviewing reserve accounting, scaled debt, supplier shares, collateral balances, or collateral-to-liquidity movement.

## Rules

- Revert if a token is used in the wrong role for the requested operation.
- Keep collateral balances, supplier shares, and debt accounting as separate buckets.
- Do not treat collateral as supplier liquidity unless the user explicitly calls `supplyFromCollateral`.
- Do not count `protocolReserves` as supplier claim.
- Do not allow supplier share redemption above available liquidity.
- Keep `availableLiquidity`, `totalBorrowsScaled`, and user shares or debt updates consistent within one state transition.
- Recompute or accrue dependent reserve state before minting or burning supplier shares.
- Ensure `supplyFromCollateral` cannot reduce effective collateral below the level needed to cover debt.
- Revert if any accounting path would underflow or silently zero-out meaningful state through rounding.
- Emit events for collateral movements, supplier share changes, and debt changes.
