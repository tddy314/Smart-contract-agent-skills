# Function Spec

## Scope

Read this file when implementing or reviewing the external API, function-level checks, or admin controls.

## User Functions

### depositCollateral

```solidity
function depositCollateral(address token, uint256 amount) external;
```

Required behavior:

- Revert if token is not enabled as collateral.
- Revert if amount is zero.
- Transfer token from user to pool.
- Increase `collateralBalance[user][token]`.
- Emit `CollateralDeposited`.

### withdrawCollateral

```solidity
function withdrawCollateral(address token, uint256 amount) external;
```

Required behavior:

- Revert if amount is zero.
- Revert if user collateral balance is insufficient.
- Accrue debt reserves needed for health calculation.
- Simulate collateral balance after withdrawal.
- Revert if remaining collateral cannot cover total debt by borrow power.
- Decrease collateral balance.
- Transfer token to user.
- Emit `CollateralWithdrawn`.

### supplyLiquidity

```solidity
function supplyLiquidity(address token, uint256 amount) external;
```

Required behavior:

- Revert if token is not supply enabled.
- Revert if amount is zero.
- Accrue reserve interest.
- Enforce supply cap if configured.
- Transfer token from user to pool.
- Increase available liquidity.
- Mint or credit reserve-specific supply shares.
- Emit `LiquiditySupplied`.

### withdrawLiquidity

```solidity
function withdrawLiquidity(address token, uint256 shares) external;
```

Required behavior:

- Revert if shares are zero.
- Accrue reserve interest.
- Convert shares to underlying claim.
- Revert if available liquidity is insufficient.
- Burn or reduce user supply shares.
- Decrease available liquidity.
- Transfer token to user.
- Emit `LiquidityWithdrawn`.

### supplyFromCollateral

```solidity
function supplyFromCollateral(address token, uint256 amount) external;
```

Required behavior:

- Revert if token is not collateral enabled.
- Revert if token is not supply enabled.
- Revert if amount is zero.
- Revert if user collateral balance is insufficient.
- Accrue reserve interest.
- Accrue debt reserves needed for health calculation.
- Simulate collateral balance after movement.
- Revert if remaining collateral cannot cover total debt by borrow power.
- Decrease collateral balance.
- Credit supply shares for the same token.
- Do not perform an external token transfer because the token is already held by the pool.
- Emit `CollateralSuppliedToLiquidity`.

### borrow

```solidity
function borrow(address token, uint256 amount) external;
```

Required behavior:

- Revert if token is not borrow enabled.
- Revert if amount is zero.
- Accrue reserve interest.
- Enforce borrow cap if configured.
- Revert if available liquidity is insufficient.
- Calculate total debt after borrow.
- Revert if total debt after borrow exceeds borrow power.
- Increase user scaled debt.
- Increase reserve scaled borrows.
- Decrease available liquidity.
- Transfer token to borrower.
- Emit `Borrowed`.

### repay

```solidity
function repay(address token, uint256 amount) external returns (uint256 repaid);
```

Required behavior:

- Revert if amount is zero.
- Accrue reserve interest.
- Calculate actual user debt.
- Repay at most the actual debt.
- Transfer repaid amount from user to pool.
- Reduce user scaled debt.
- Reduce reserve scaled borrows.
- Increase available liquidity.
- Emit `Repaid`.

## Admin Controls

Administrative functions may include:

- Add or update collateral config.
- Add or update reserve config.
- Add or update interest rate config.
- Set Chainlink feed for a token.
- Set stale price threshold.
- Pause deposit, withdraw, supply, borrow, repay, or liquidation flows.
- Withdraw protocol reserves to treasury.
- Rescue non-accounted tokens.

Rules:

- Every admin action must emit an event.
- Config updates must validate bounds.
- Live config changes must not make existing accounting insolvent.
- Pausing borrow must not block repay.
- Pausing supply must not block liquidity withdrawal when withdrawal is technically safe.
- Rescue must not remove tokens backing collateral balances, supplier claims, outstanding borrows, or protocol reserve accounting.
