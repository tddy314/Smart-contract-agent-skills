# Interest And Oracle

## Scope

Read this file when implementing or changing reserve utilization, interest accrual, debt indexes, or oracle policy.

## Interest Accrual

Use reserve indexes for accrual.

Typical components:

- liquidity index
- variable borrow index
- current liquidity rate
- current variable borrow rate
- last update timestamp

Rules:

- Accrue before borrow, repay, withdraw, liquidation, and account-data checks that depend on debt or liquidity.
- Keep index math deterministic and test rounding explicitly.
- Apply reserve factor only to accrued interest, not principal.

## Interest Rate Strategy

Use reserve-specific utilization-based rate logic.

Typical dimensions:

- base rate
- optimal utilization
- slope1
- slope2

## Oracle Policy

Use an external oracle system, typically Chainlink-backed, to normalize values to a common base unit.

Rules:

- Revert if the price is missing, stale, zero, negative, or incomplete.
- Use one consistent valuation path for collateral, debt, health factor, and liquidation.
- Bound stale-price configuration and emit events when it changes.
