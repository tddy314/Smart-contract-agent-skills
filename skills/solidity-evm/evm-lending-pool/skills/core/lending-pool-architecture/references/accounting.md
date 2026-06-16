# Accounting

## Scope

Read this file when implementing or changing reserve accounting, scaled debt, supply shares, collateral balances, or collateral-to-liquidity movement.

## Token Roles

Each token can be enabled independently as collateral, borrow/liquidity, or both.

Collateral config is global by collateral token:

```solidity
struct CollateralConfig {
    uint256 ltvBps;
    uint256 liquidationThresholdBps;
    uint256 liquidationBonusBps;
    bool enabled;
}
```

Reserve config is global by borrow/liquidity token:

```solidity
struct ReserveConfig {
    bool borrowEnabled;
    bool supplyEnabled;
    uint256 reserveFactorBps;
    uint256 borrowCap;
    uint256 supplyCap;
}
```

Rules:

- `ltvBps <= liquidationThresholdBps`.
- `liquidationThresholdBps <= 10000`.
- `reserveFactorBps` must have a documented maximum cap.
- `liquidationBonusBps` must have a documented maximum cap.
- A token can be collateral without being borrowable.
- A token can be borrowable without being accepted as collateral.
- A token can be both collateral and borrowable.

## Reserve State

Each borrow/liquidity token has its own reserve state.

```solidity
struct ReserveState {
    uint256 totalSupplyShares;
    uint256 totalBorrowsScaled;
    uint256 availableLiquidity;
    uint256 borrowIndex;
    uint256 lastAccrualTimestamp;
    uint256 protocolReserves;
}
```

Use `RAY = 1e27` precision for indexes.

Debt:

```text
actualDebt = scaledDebt * borrowIndex / 1e27
```

Total borrows:

```text
totalBorrows = totalBorrowsScaled * borrowIndex / 1e27
```

Liquidity supplier claim:

```text
totalLiquidityAssets = availableLiquidity + totalBorrows - protocolReserves
supplierClaim = supplyShares * totalLiquidityAssets / totalSupplyShares
```

Rules:

- `protocolReserves` must not be counted as supplier claim.
- Supplier shares cannot redeem more than available liquidity.
- Borrowing reduces `availableLiquidity`.
- Repayment increases `availableLiquidity`.
- Interest accrual increases borrower debt.
- Protocol fee is taken only from accrued interest, never from principal.

## User State

Track user state by token:

```solidity
mapping(address user => mapping(address token => uint256 amount)) collateralBalance;
mapping(address user => mapping(address token => uint256 shares)) supplyShares;
mapping(address user => mapping(address token => uint256 scaledDebt)) borrowDebt;
```

Rules:

- Collateral balances are not supplier shares unless explicitly moved through `supplyFromCollateral`.
- Liquidity supply shares are not collateral by default.
- User debt must be accrued before health checks that depend on debt value.
- A user's total debt is the sum of actual debt across every borrowed token, converted to USD.

## Collateral To Liquidity

`supplyFromCollateral` moves an already-deposited collateral asset into the supplier accounting bucket for the same token.

Rules:

- The token must be both collateral enabled and supply enabled.
- The user must have enough collateral balance.
- The pool must accrue reserve interest before minting supplier shares.
- The pool must accrue debt needed for the health check.
- The move must revert if remaining collateral no longer covers total debt.
- No external token transfer should happen during the move because the token is already held by the pool.
