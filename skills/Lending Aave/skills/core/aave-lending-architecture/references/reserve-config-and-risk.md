# Reserve Config And Risk

## Scope

Read this file when implementing or changing reserve configuration, collateral policy, account data, or health-factor logic.

## Reserve Risk Model

Each reserve should define:

- LTV
- liquidation threshold
- liquidation bonus
- reserve factor
- borrow cap
- supply cap
- active, paused, or frozen flags

## Account Data

Health factor should be based on total collateral value and total debt value.

Typical structure:

```text
totalCollateralBase
totalDebtBase
availableBorrowsBase
currentLiquidationThreshold
ltv
healthFactor
```

Rules:

- Only collateral-enabled supplied assets contribute to collateral value.
- Debt value must include all active debts across reserves.
- Borrow must revert if resulting health factor falls below the required threshold.
- Withdraw must revert if resulting health factor falls below the required threshold.
- Liquidation eligibility must use the same underlying valuation path as borrow checks.
