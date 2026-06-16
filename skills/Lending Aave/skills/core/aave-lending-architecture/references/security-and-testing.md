# Security And Testing

## Scope

Read this file when implementing invariants, trust boundaries, and contract tests for Aave-style lending logic.

## Security Invariants

- Reserve state must remain isolated per asset.
- `aToken` supply and withdraw must stay consistent with underlying reserve liquidity.
- Debt accounting must stay consistent with borrow and repay operations.
- Health factor checks must gate borrow and collateral-reducing withdraw paths.
- Liquidation must not be allowed for healthy accounts.
- Reserve factor must not consume principal.
- Admin updates must not bypass bounds on risk parameters.
- Rescue logic must not remove assets backing supplier claims or debt settlement.

## Minimum Contract Test Coverage

- supply and withdraw accounting
- collateral enablement and disablement
- borrow and repay accounting
- health factor checks
- liquidation eligibility and seize math
- rate-strategy transitions across utilization levels
- stale or invalid oracle data handling
- pause, freeze, and admin update behavior
