# Risk Rules

## Scope

Read this file when implementing or reviewing collateral policy, health factor, or reserve risk configuration.

## Rules

- Revert if a user tries to borrow without enough collateral capacity.
- Revert if a collateral-reducing withdraw would push health factor below the required threshold.
- Count only collateral-enabled supplied assets toward collateral value.
- Use one consistent valuation path for total collateral, total debt, available borrow, and health factor.
- Bound LTV, liquidation threshold, liquidation bonus, reserve factor, borrow caps, and supply caps.
- Emit events for risk-parameter changes.
