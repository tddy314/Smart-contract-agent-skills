# Liquidation Rules

## Scope

Read this file when implementing or reviewing liquidation eligibility, repay limits, seized collateral math, or close-factor behavior.

## Rules

- Revert if the borrower is still healthy.
- Revert if the selected debt token has no outstanding borrower debt.
- Revert if the selected collateral token has no borrower balance.
- Revert on zero repay amount.
- Do not repay more than the borrower actually owes for the selected debt token.
- Do not seize more collateral than the borrower owns.
- Use oracle pricing and liquidation bonus in one consistent formula.
- If collateral balance is insufficient, reduce repay consistently or revert; do not silently create bad accounting.
- If a close factor exists, enforce it before state mutation.
- Emit liquidation events with borrower, liquidator, debt token, repaid amount, collateral token, and seized collateral.
