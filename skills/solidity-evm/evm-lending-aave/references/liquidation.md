# Aave Liquidation

Use this skill when the task is specifically about `liquidationCall`, unhealthy-account handling, or collateral seizure logic.

## Responsibilities

Liquidation should:

- only trigger for unhealthy accounts
- repay borrower debt under protocol rules
- seize collateral using the configured liquidation bonus
- preserve reserve and user accounting consistency

## Implementation Rules

- Revert if the borrower is healthy.
- Revert if the selected debt reserve has no borrower debt.
- Revert if the selected collateral reserve has no borrower collateral.
- Do not repay more than the borrower actually owes.
- Do not seize more collateral than the borrower owns.
- Use the same valuation path as account-data checks.
- Emit liquidation events with borrower, liquidator, debt asset, repaid amount, collateral asset, and seized amount.

## Read Next

- For health factor and oracle policy:
  Read [oracle-and-risk.md](oracle-and-risk.md)
- For user-facing pool integration:
  Read [pool.md](pool.md)
