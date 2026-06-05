# Interest And Oracle Rules

## Scope

Read this file when implementing or reviewing index accrual, rate strategy, or oracle-backed valuation.

## Rules

- Accrue indexes before borrow, repay, withdraw, liquidation, and account-data checks that depend on debt or liquidity.
- Do not create synthetic debt when no real borrow exposure exists.
- Bound rate-strategy inputs such as base rate, optimal utilization, slope1, and slope2.
- Revert if the oracle answer is missing, stale, zero, negative, or incomplete.
- Normalize decimals consistently across all valuation paths.
- Emit events when oracle configuration or rate-strategy configuration changes.
