# Test Plan

## Scope

Read this file when writing or reviewing tests for lending pool accounting, risk checks, liquidation, and admin controls.

## Invariants

Every implementation and test plan must cover the applicable invariants:

- User cannot borrow more than borrow power.
- User cannot withdraw collateral if remaining collateral does not cover total debt.
- `supplyFromCollateral` cannot move collateral into liquidity if remaining collateral does not cover total debt.
- Liquidation can occur only when total debt exceeds liquidation power.
- Liquidator cannot repay more than borrower debt for the selected token.
- Liquidator cannot seize more collateral than the borrower owns.
- Liquidation bonus cannot bypass collateral balance caps.
- Chainlink price must not be zero, negative, stale, missing, or incomplete.
- Price and token decimals must be normalized consistently.
- Interest must accrue before borrow, repay, withdraw liquidity, liquidation, and debt-dependent health checks.
- Protocol fees must come only from accrued interest.
- Protocol reserves must not be counted as supplier claim.
- Supplier shares cannot withdraw more than available liquidity.
- Borrowing must reduce available liquidity.
- Repayment must increase available liquidity.
- Pausing borrow must not block repay.
- Admin rescue cannot remove accounted collateral, supplier liquidity, borrower repayment liquidity, or protocol reserves beyond the recorded reserve amount.
- `ltvBps <= liquidationThresholdBps <= 10000`.
- Reserve factor, liquidation bonus, rate slopes, borrow caps, and supply caps must be bounded.

## Minimum Test Coverage

At minimum, write tests for:

- Collateral deposit and withdrawal.
- Withdrawal rejection when borrow power would be exceeded.
- Liquidity supply and share accounting.
- Liquidity withdrawal with enough available liquidity.
- Liquidity withdrawal rejection when pool liquidity is unavailable.
- Supply from collateral with healthy remaining position.
- Supply from collateral rejection when remaining collateral cannot cover debt.
- Borrow success within borrow power.
- Borrow rejection above borrow power.
- Repay partial and full debt.
- Interest accrual and borrow index changes.
- Supplier yield after borrower interest accrues.
- Protocol reserve fee accrual and withdrawal.
- Liquidation rejection for healthy borrower.
- Liquidation success for unhealthy borrower.
- Liquidation seize amount with oracle prices and bonus.
- Oracle stale, zero, missing, and decimal normalization cases.
- Admin config bounds.
- Pause behavior, especially repay while borrow is paused.
- Rescue restrictions for accounted assets.
