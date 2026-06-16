# Oracle And Pricing

## Scope

Read this file when implementing or changing Chainlink integration, price normalization, borrow power checks, collateral config interpretation, or health checks.

## Oracle Policy

Use Chainlink price feeds through a dedicated oracle wrapper, such as `ChainlinkPriceOracle`.

Every token value must be normalized to USD with `1e18` precision.

Oracle checks:

- Feed exists for the token.
- Returned price is greater than zero.
- `updatedAt` is not stale.
- Round data is complete.
- Feed decimals are normalized.
- Token decimals are normalized.

Rules:

- Revert if a feed is missing, stale, zero, negative, or incomplete.
- Do not rely on manipulable spot prices.
- Do not hardcode USDC as exactly 1 USD unless that design is explicitly required and documented.
- Use the same price normalization path for collateral value, debt value, borrow power, liquidation, and seized collateral calculations.

## Borrow Power

Borrow power is based on all collateral deposited by the user.

```text
collateralValueUSD[token] = collateralAmount[token] * tokenPriceUSD

borrowPowerUSD =
  sum(collateralValueUSD[token] * ltvBps[token] / 10000)

totalDebtUSD =
  sum(actualDebt[token] * debtTokenPriceUSD)
```

Borrow and collateral withdrawal are allowed only when:

```text
totalDebtUSDAfter <= borrowPowerUSDAfter
```

Rules:

- Calculate borrow power after simulating the requested operation.
- Borrowing must accrue the debt reserve before checking debt and utilization.
- Withdrawing collateral must accrue all debt reserves needed for an accurate total debt value.
- If the user has no debt, collateral withdrawal can skip borrow power checks after balance validation.

## Liquidation Power

Liquidation uses liquidation threshold, not LTV.

```text
liquidationPowerUSD =
  sum(collateralValueUSD[token] * liquidationThresholdBps[token] / 10000)
```

The user is liquidatable when:

```text
totalDebtUSD > liquidationPowerUSD
```
