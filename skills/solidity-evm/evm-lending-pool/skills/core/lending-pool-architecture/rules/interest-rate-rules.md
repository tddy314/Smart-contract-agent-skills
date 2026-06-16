# Interest Rate Rules

## Scope

Read this file when implementing or reviewing utilization, rate curves, interest accrual, reserve factor logic, or protocol reserve accounting.

## Rules

- Accrue interest before borrow, repay, liquidity withdrawal, liquidation, and health checks that depend on debt.
- If `totalBorrows == 0`, do not create synthetic debt through accrual.
- If available liquidity is zero and borrows are positive, treat utilization as 100% in a controlled way.
- Bound `baseRateBps`, `slope1Bps`, `slope2Bps`, `optimalUtilizationBps`, and `reserveFactorBps`.
- Ensure protocol fees come only from accrued interest, not principal.
- Update `protocolReserves[token]` atomically with interest accrual.
- Keep rounding behavior deterministic and test it explicitly.
- Emit events when rate config or reserve-factor config changes.
