---
name: sui-defi-math
description: >
  Sui Move DeFi math skill for fixed-point decimals, shares, exchange rates, interest accrual, fees, oracle prices,
  and Coin/Balance accounting. Use whenever a Sui task involves deposits, withdrawals, mint/redeem ratios, lending
  rates, liquidation math, staking exchange rates, strategy-vault shares, Pyth/Switchboard/Supra price conversion,
  or any financial arithmetic. ALWAYS use this skill for Sui financial math even when the user only says "shares",
  "rate", "fee", "oracle", "LTV", "reward", "basis points", "decimal", or "rounding".
---

# Sui DeFi Math

This skill encodes the math discipline used by Sui DeFi contracts: integer-only arithmetic, explicit decimal scaling, predictable rounding, and careful `Coin<T>` / `Balance<T>` accounting. It draws on Navi lending/staking, Suilend reserves/oracles/liquid staking, and MystenLabs Move conventions.

`sui-move` owns object/capability structure. This skill owns numerical correctness.

---

## When to Use

- Share, receipt, cToken, LST, or LP-token mint/redeem math
- Exchange rates, utilization rates, interest curves, reward accumulators, APR/APY-like values
- Lending collateral value, borrow value, LTV, liquidation threshold, close factor, liquidation bonus
- Oracle price normalization across token decimals
- Management/performance fees, spread, borrow fees, protocol fees, reward fees
- Staking rewards, epoch rewards, pending reward debt, claimable balances
- Any use of `Decimal`, `ray_math`, `safe_math`, `u128`, `u256`, basis points, or scaled integers

**Do not use** for non-financial arithmetic, general Move syntax, frontend price formatting, or protocol design that does not affect persisted value, token movement, shares, debt, rewards, fees, or oracle-backed decisions.

---

## Core Rules

1. Use integers and scaled decimals only. Move has no `f64`, but imprecise integer scaling can still leak value.
2. Widen before multiply. Use `u128` or a repo-provided decimal type before multiplying large `u64` values.
3. Define the rounding direction before coding.
4. Keep economic buckets separate: principal, reserve liquidity, rewards, fees, insurance, pending withdraws, and unclaimed balances.
5. Refresh stale rates, prices, or accumulators before using them for value-moving actions.
6. Treat zero supply, zero liquidity, and dust outputs as explicit branches.

---

## Coin and Balance Accounting

Prefer this model:

- Function entry receives `Coin<T>` from users.
- Convert to `Balance<T>` for internal accounting (`payment.into_balance()`).
- Join into the correct reserve/reward/fee bucket.
- Split from a bucket for withdrawals or fees.
- Convert back with `coin::from_balance(balance, ctx)` at the API boundary.

Checklist for every asset-moving function:

- What exact bucket receives the incoming value?
- Is the amount before/after measured by `coin.value()` or `balance.value()` at the right moment?
- Are zero-value coins/balances returned, destroyed, or forbidden consistently?
- Are rewards and fees claimable only if liquidity exists?
- Are events emitted with enough before/after information to reconcile offchain?

---

## Share and Exchange-Rate Math

Common formulas:

```text
initial shares = deposit_amount
minted_shares = deposit_amount * total_shares / total_value
redeem_value = burned_shares * total_value / total_shares
exchange_rate = total_underlying / total_shares
```

Rounding defaults:

- Minting shares to a depositor: round down so the pool does not over-issue ownership.
- Redeeming underlying to a withdrawer: round down unless protocol docs deliberately use ceil to protect complete withdrawal semantics.
- Burning shares required for a target withdrawal: round up so the user burns enough shares.
- Extracting protocol fees/rewards: usually round down to avoid over-draining user principal.

Guard:

- zero `total_shares` / first depositor;
- zero `total_value` with nonzero shares (insolvent/corrupt state);
- minted shares equals zero for a nonzero deposit (dust attack / donation);
- redeem output equals zero for nonzero shares;
- exchange-rate update before mint/redeem.

---

## Oracle Math

For price-based logic, normalize all values to a single decimal convention before comparing.

Oracle acceptance checklist:

- Price timestamp is fresh relative to `Clock`.
- Confidence interval / confidence ratio is below the configured threshold.
- Exponent/decimals are handled correctly.
- Negative, zero, or missing prices are rejected or returned as `Option::none()`.
- Callers decide explicit fallback behavior instead of silently using stale values.

If an oracle module returns `Option<Price>`, propagate that uncertainty; do not unwrap blindly in lending/liquidation code.

---

## Accrual and Refresh Ordering

Many Sui protocols separate stale getters from mutating actions. Before deposit, withdraw, borrow, repay, claim, rebalance, mint, or redeem:

1. Refresh oracle prices or exchange rates.
2. Compound interest / rewards into accumulators.
3. Update per-reserve/per-pool indexes.
4. Then mutate user positions, shares, debts, or balances.

If refresh is epoch-based, make it idempotent for the same epoch.

---

## Final Response Expectations

When reporting on Sui financial math, state:

- scaling representation and widened intermediate type;
- rounding direction for each value-moving formula;
- where refresh/checkpoint happens before state mutation;
- how oracle staleness/confidence is handled;
- which balances represent principal, rewards, fees, and reserves;
- any dust or zero-supply edge cases.

---

## Reference Files

- `references/fixed-point-and-rounding.md` - rounding, scaling, shares, oracles, refresh ordering

Source anchors: Navi `lending_core/sources/ray_math.move`, `safe_math.move`, `calculator.move`, `incentive*.move`; Suilend `decimal.move`, `reserve.move`, `oracles.move`, `staker.move`; Suilend liquid-staking `liquid_staking.move`, `storage.move`.

---

## Rules

1. Widen before multiply and define scale units explicitly.
2. Never divide before multiplying when preserving precision matters.
3. Round in the protocol's intended favor and document it.
4. Refresh rates/prices/accrual before value-moving mutations.
5. Keep `Coin<T>` at boundaries and `Balance<T>` in internal buckets.
6. Treat oracle uncertainty as a first-class branch.
