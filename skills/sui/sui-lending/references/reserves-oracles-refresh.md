# Sui Lending Reserve, Oracle, and Refresh Reference

## Reserve model

A Sui lending reserve commonly tracks:

- asset type and reserve ID;
- available liquidity / balance bucket;
- total borrowed amount;
- cumulative borrow/deposit indexes;
- fees and unclaimed rewards;
- oracle configuration;
- last update timestamp, epoch, or version;
- caps and risk parameters.

## Obligation/account model

User state may be address-owned or represented by account objects. Per-asset balances are often stored by dynamic fields.

Check:

- dynamic-field key type is unique and has `copy, drop, store`;
- field access checks existence before borrow/remove;
- remove paths clean up empty positions;
- account object used by the caller actually belongs to or is authorized by that caller.

## Oracle acceptance

For each price:

1. Match feed ID to reserve config.
2. Check timestamp freshness using `Clock`.
3. Check confidence ratio.
4. Normalize decimals/exponent.
5. Return `None` or abort on invalid data.
6. Use conservative values for risk checks.

## Refresh ordering

```text
load clock/oracle → validate price → compound reserve indexes → update cached state → perform deposit/borrow/withdraw/repay/liquidate
```

Do not update user position first and then refresh; it lets the user act against stale rates.

## Test focus

- stale oracle rejected;
- high confidence rejected;
- wrong feed rejected;
- refresh once per epoch/no-op behavior;
- borrow after interest accrual updates debt;
- withdraw after price move fails when unhealthy;
- liquidation respects close factor and bonus;
- flash-loan receipt cannot be dropped/reused/wrongly settled.
