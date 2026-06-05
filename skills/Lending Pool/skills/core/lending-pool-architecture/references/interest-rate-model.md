# Interest Rate Model

## Scope

Read this file when implementing or changing utilization, borrow rate curves, interest accrual, reserve factor, or protocol reserves.

## Rate Config

Use a utilization-based variable rate curve per reserve.

```solidity
struct InterestRateConfig {
    uint256 baseRateBps;
    uint256 slope1Bps;
    uint256 slope2Bps;
    uint256 optimalUtilizationBps;
}
```

Utilization:

```text
utilization = totalBorrows / (availableLiquidity + totalBorrows)
```

Borrow rate:

```text
if utilization <= optimalUtilization:
    borrowRate = baseRate + utilization * slope1 / optimalUtilization
else:
    borrowRate = baseRate + slope1
               + (utilization - optimalUtilization) * slope2
                 / (1 - optimalUtilization)
```

Supplier yield:

```text
supplyRate = borrowRate * utilization * (1 - reserveFactor)
```

Protocol fee:

```text
protocolFee = interestAccrued * reserveFactorBps / 10000
protocolReserves[token] += protocolFee
```

Rules:

- Accrue interest before borrow, repay, withdraw liquidity, liquidation, and health checks that depend on debt.
- If `totalBorrows == 0`, utilization and interest accrual should not create debt.
- If available liquidity is zero and total borrows are positive, utilization is 100%.
- Bound rate config values to avoid impossible or explosive rates.
- Keep interest math deterministic and test rounding direction.

## Fee Model

The default platform fee is a reserve factor taken from accrued borrower interest.

```text
interestAccrued = newTotalBorrows - oldTotalBorrows
protocolFee = interestAccrued * reserveFactorBps / 10000
supplierYield = interestAccrued - protocolFee
```

Rules:

- Do not charge fees on collateral deposits by default.
- Do not charge fees on principal by default.
- Store fee as `protocolReserves[token]`.
- Allow treasury to withdraw only protocol reserves.
- Do not count protocol reserves as supplier claim.
- Emit events when protocol reserves accrue and when they are withdrawn.
