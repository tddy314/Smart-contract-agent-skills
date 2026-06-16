# Liquidation

## Scope

Read this file when implementing or changing liquidation conditions, repay limits, seized collateral math, or close-factor policy.

## Liquidation Flow

The borrower is liquidatable when:

```text
totalDebtUSD > liquidationPowerUSD
```

Liquidation flow:

```text
liquidator repays debtToken for borrower
pool reduces borrower debt
pool calculates seized collateral value
pool transfers selected collateral token to liquidator
```

Seized collateral:

```text
repaidDebtValueUSD = repayAmount * debtTokenPriceUSD
seizedCollateralValueUSD =
  repaidDebtValueUSD * (10000 + liquidationBonusBps[collateralToken]) / 10000
seizedCollateralAmount =
  seizedCollateralValueUSD / collateralTokenPriceUSD
```

Rules:

- Liquidation must revert if the borrower is healthy.
- Liquidator may repay any debt token the borrower owes.
- Liquidator may seize any collateral token the borrower owns.
- Do not repay more than the borrower's actual debt for the selected debt token.
- Do not seize more collateral than the borrower owns.
- Apply a close factor if the design requires partial liquidation limits.
- Emit liquidation events with borrower, liquidator, debt token, repay amount, collateral token, and seized amount.

## External Function

```solidity
function liquidate(
    address borrower,
    address debtToken,
    uint256 repayAmount,
    address collateralToken
) external returns (uint256 repaid, uint256 seizedCollateral);
```

Required behavior:

- Revert if borrower is healthy.
- Revert if repay amount is zero.
- Accrue the selected debt reserve and any other reserves needed for total debt calculation.
- Revert if borrower has no selected debt.
- Revert if borrower has no selected collateral.
- Repay at most borrower debt for the selected debt token.
- Transfer debt token from liquidator to pool.
- Reduce borrower debt.
- Calculate seized collateral with oracle price and liquidation bonus.
- Revert if collateral to seize is zero.
- Cap seized collateral to borrower collateral balance or reduce repay amount consistently.
- Transfer seized collateral to liquidator.
- Emit `Liquidated`.
