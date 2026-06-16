# Liquidation Math

Self-contained patterns. Adapt names to the host repo. This file is the math; `solana-lending` covers the protocol assembly and the handler.

## Table of Contents

- Health and LTV
- When liquidation triggers
- The liquidation bonus
- How much can be liquidated
- Capping against available collateral
- Partial vs full liquidation and dust
- The post-liquidation health check

---

## Health and LTV

An obligation holds collateral worth `collateral_value` and owes debt worth `borrowed_value`, both in a common quote unit (usually USD as a fixed-point value). Loan-to-value is:

```
ltv = borrowed_value / collateral_value
```

Each collateral asset carries two configured thresholds, expressed against the value it backs:

- `loan_to_value_pct` - the most you may borrow against it (the borrow gate).
- `liquidation_threshold_pct` - the point past which the position is unhealthy and liquidatable.

The gap between them is the safety buffer. A position opened at the borrow limit is not immediately liquidatable; it becomes liquidatable only after price movement or accrued interest pushes `ltv` up to the liquidation threshold. Compute both weighted across all the obligation's collateral, not per-asset in isolation.

```
allowed_borrow_value   = Σ (collateral_value_i * loan_to_value_pct_i)
unhealthy_borrow_value = Σ (collateral_value_i * liquidation_threshold_pct_i)
```

A position is healthy while `borrowed_value <= unhealthy_borrow_value`.

---

## When liquidation triggers

```rust
let user_ltv = obligation.loan_to_value();          // borrowed_value / collateral_value
let unhealthy_ltv = obligation.unhealthy_loan_to_value();
require!(user_ltv >= unhealthy_ltv, LendingError::CannotLiquidateHealthyObligation);
```

All inputs must be fresh: refresh every reserve the obligation touches, then refresh the obligation, then evaluate health. Liquidating on stale prices or stale interest is the classic way liquidations go wrong in both directions - seizing from a healthy position or missing a genuinely underwater one.

---

## The liquidation bonus

The liquidator repays the borrower's debt and receives collateral worth slightly more - the bonus is the incentive. It scales with how unhealthy the position is, so deeper insolvency draws faster liquidation:

```
unhealthy_factor = user_ltv - max_allowed_ltv
bonus = max(reserve_configured_bonus, unhealthy_factor)
```

Near bad-debt territory (`ltv` approaching or exceeding 1.0), the position cannot fully cover debt plus bonus, so the bonus is bounded by a separate `bad_debt_liquidation_bonus` and by the distance to `ltv = 1`:

```rust
fn liquidation_bonus(
    collateral_cfg: &ReserveConfig,
    debt_cfg: &ReserveConfig,
    max_allowed_ltv: Fraction,
    user_ltv: Fraction,
) -> Fraction {
    let bad_debt_ltv = Fraction::ONE;

    if user_ltv >= Fraction::from_num_ratio(99u64, 100u64) {
        // near or past insolvency: use the capped bad-debt bonus
        let bad_debt_bonus_bps = collateral_cfg
            .bad_debt_liquidation_bonus_bps
            .min(debt_cfg.bad_debt_liquidation_bonus_bps);
        let bad_debt_bonus = Fraction::from_bps(bad_debt_bonus_bps);
        if user_ltv < bad_debt_ltv {
            let diff_to_bad_debt = bad_debt_ltv - user_ltv;
            return bad_debt_bonus.max(diff_to_bad_debt);
        }
        return bad_debt_bonus;
    }

    let unhealthy_factor = user_ltv - max_allowed_ltv;
    Fraction::from_bps(collateral_cfg.liquidation_bonus_bps).max(unhealthy_factor)
}
```

Take the minimum of the two reserves' bad-debt bonuses so neither side's config alone sets a bonus the other cannot sustain.

---

## How much can be liquidated

Start from the liquidator's requested repay amount, capped at the actual borrowed amount, and convert to a value including the bonus:

```rust
let debt_to_liquidate = requested.min(borrowed_amount);
let liquidation_ratio = debt_to_liquidate / borrowed_amount;

let bonus_multiplier = Fraction::ONE + liquidation_bonus_rate;
let liquidation_value_with_bonus = borrowed_value * liquidation_ratio * bonus_multiplier;
let liquidation_value_no_bonus  = borrowed_value * liquidation_ratio;
```

`settle_amount` is how much debt is cleared, `repay_amount` is what the liquidator transfers in (round up so the protocol is never short), `withdraw_amount` is the collateral seized (round down).

---

## Capping against available collateral

The seized value cannot exceed the collateral actually deposited. Compare the bonus-inclusive liquidation value to the collateral value and branch:

```rust
match liquidation_value_with_bonus.cmp(&collateral_value) {
    Ordering::Greater => {
        // Not enough collateral to pay full debt+bonus: scale the repay down to what the
        // collateral can cover, seize all of it.
        let repay_ratio = collateral_value / liquidation_value_with_bonus;
        let settle = debt_to_liquidate * repay_ratio;
        let repay = settle.to_ceil();                 // round up: liquidator pays in
        let withdraw = collateral.deposited_amount;    // all of it
        (settle, repay, withdraw)
    }
    Ordering::Equal => {
        let settle = debt_to_liquidate;
        (settle, settle.to_ceil(), collateral.deposited_amount)
    }
    Ordering::Less => {
        // Collateral more than covers it: seize the proportional slice.
        let settle = debt_to_liquidate;
        let withdraw_pct = liquidation_value_with_bonus / collateral_value;
        let withdraw = (Fraction::from_num(collateral.deposited_amount) * withdraw_pct).to_floor();
        (settle, settle.to_ceil(), withdraw)
    }
}
```

The rounding split is deliberate: `repay` (token in) ceils, `withdraw` (token out) floors. Both round in the protocol's favor.

---

## Partial vs full liquidation and dust

Liquidations are usually partial - a liquidator clears part of the debt and seizes part of the collateral. But tiny remainders cause problems: a position left with sub-unit debt or collateral may become impossible to liquidate or close, because the proportional seize floors to zero.

Two guards:

- A minimum net value below which the position is treated as fully liquidatable in one shot, so it cannot be whittled into permanent dust.
- A dust floor on the seize amount: when the position is below the minimum-value threshold and the computed withdraw rounds below one base unit, seize at least one unit rather than zero.

```rust
let below_min_value = liquidation_value_with_bonus < market.min_net_value_in_obligation;
let withdraw = if below_min_value && withdraw_amount_f < DUST_LAMPORT_THRESHOLD {
    DUST_LAMPORT_THRESHOLD
} else {
    withdraw_amount_f.to_floor()
};
```

---

## The post-liquidation health check

After a partial liquidation, the position should be healthier (lower LTV), not worse. For a liquidation large enough to matter, verify it does not push the obligation further past its allowed borrow value:

```rust
let new_allowed_borrow = obligation.allowed_borrow_value
    - liquidation_value_with_bonus * collateral_ltv;
let new_borrowed_value = obligation.borrowed_value - liquidation_value_no_bonus;

if new_allowed_borrow - market.min_net_value > new_borrowed_value {
    // liquidation would over-correct, leaving the position worse against its limits
    return err!(LendingError::LiquidationValueExceedsCollateralValue);
}
```

This catches a mis-parameterized bonus or threshold that would let a liquidation seize more than the unhealthiness justifies. Tests should cover: healthy position rejected, exactly-at-threshold behavior, partial liquidation reduces LTV, near-bad-debt bonus capping, and the dust path on a tiny position.
