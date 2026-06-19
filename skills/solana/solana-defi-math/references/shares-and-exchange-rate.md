# Shares and Exchange Rates

Self-contained patterns. Adapt names to the host repo.

## Table of Contents

- The two conversions and why they differ
- Exchange rate (liquidity ↔ collateral)
- Floor and ceil variants
- Share accounting (assets ↔ shares)
- The empty-pool branch
- First-depositor inflation
- Round-trip safety

---

## The two conversions and why they differ

Both an exchange-rate reserve and a share-vault answer the same question in two directions:

- How much of unit B do I get for N of unit A? (deposit)
- How much of unit A do I get back for M of unit B? (withdraw)

The rate connecting them grows over time (interest, fees, yield). The danger is not the rate itself but the rounding: if both directions round the same way, repeated deposit/withdraw cycles either leak value to users or trap it in the pool. Each direction must round in the protocol's favor.

---

## Exchange rate (liquidity ↔ collateral)

A reserve holds `total_liquidity` and has issued `collateral_supply` cTokens. The exchange rate is liquidity per collateral:

```
exchange_rate = total_liquidity / collateral_supply
```

It starts at 1.0 for an empty reserve and rises as interest accrues into `total_liquidity` while `collateral_supply` stays fixed. That rise is depositor yield.

```rust
pub struct CollateralExchangeRate(Fraction);

impl CollateralExchangeRate {
    pub fn new(total_liquidity: Fraction, collateral_supply: u128) -> Self {
        if collateral_supply == 0 {
            return Self(Fraction::ONE); // empty reserve: 1:1
        }
        Self(total_liquidity / Fraction::from_num(collateral_supply))
    }
}
```

---

## Floor and ceil variants

Provide both directions explicitly. On deposit, the user receives collateral - round **down** so the reserve is never short. To compute the liquidity required to back a given collateral amount, round **up**.

```rust
impl CollateralExchangeRate {
    // Liquidity a user receives when burning `collateral` cTokens. Round DOWN (to user).
    pub fn collateral_to_liquidity(&self, collateral: u64) -> u64 {
        (Fraction::from_num(collateral) * self.0).to_floor()
    }

    // Collateral minted for `liquidity` deposited. Round DOWN (to user).
    pub fn liquidity_to_collateral(&self, liquidity: u64) -> u64 {
        (Fraction::from_num(liquidity) / self.0).to_floor()
    }

    // Liquidity REQUIRED to back `collateral`. Round UP (protocol not short).
    // Use a U256 intermediate; collateral * scaled_rate can exceed u128.
    pub fn collateral_to_liquidity_ceil(&self, collateral: u64) -> u64 {
        let rate_bits = self.0.to_bits();
        let numerator = U256::from(collateral).checked_mul(U256::from(rate_bits)).unwrap();
        let one = U256::from(Fraction::ONE.to_bits());
        let ceil = numerator.checked_add(one - 1).unwrap() / one;
        u128::try_from(ceil).unwrap().try_into().unwrap()
    }
}
```

The pairing that matters: deposit uses `liquidity_to_collateral` (floor), and any path that must reserve liquidity for collateral uses `collateral_to_liquidity_ceil`. Mismatched rounding here is the classic slow drain.

---

## Share accounting (assets ↔ shares)

A vault holds `total_assets` of value and has minted `total_shares`. Ownership is proportional: `user_shares / total_shares == user_assets / total_assets`.

```rust
// Shares minted for a deposit. Multiply BEFORE divide, in u128, round DOWN.
fn assets_to_shares(deposit: u64, total_shares: u128, total_assets: u128) -> Result<u128> {
    if total_shares == 0 || total_assets == 0 {
        return Ok(deposit as u128); // empty pool: 1:1
    }
    (deposit as u128)
        .checked_mul(total_shares)
        .and_then(|n| n.checked_div(total_assets))
        .ok_or(VaultError::MathOverflow.into())
}

// Assets returned for burning shares. Round DOWN (to user).
fn shares_to_assets(shares: u128, total_shares: u128, total_assets: u128) -> Result<u64> {
    if total_shares == 0 {
        return Ok(0);
    }
    let assets = shares
        .checked_mul(total_assets)
        .and_then(|n| n.checked_div(total_shares))
        .ok_or(VaultError::MathOverflow)?;
    u64::try_from(assets).map_err(|_| VaultError::MathOverflow.into())
}
```

The `checked_mul` before `checked_div` is not stylistic: dividing first throws away the fractional part and systematically under-mints. The `u128` widening keeps `deposit * total_shares` from overflowing.

---

## The empty-pool branch

Every share/exchange conversion needs an explicit empty-pool case. With `total_shares == 0` there is no ratio to apply, so the first deposit defines the unit: shares minted equal assets deposited (1:1). Forgetting this branch gives a divide-by-zero or a nonsensical rate on the first deposit.

---

## First-depositor inflation

A known attack on naive share vaults: the first depositor mints 1 share for 1 wei, then transfers a large amount of the underlying asset directly into the vault (not through deposit). Now 1 share is worth a lot, and a second depositor's `deposit * total_shares / total_assets` rounds down to zero shares - their deposit is captured by the attacker.

Mitigations, in rough order of preference:

- Seed the pool at initialization with a minimum liquidity that is burned (locked forever), so `total_shares` is never tiny.
- Track `total_assets` as an internal accounting figure updated only by deposits/withdrawals/accrual, so a raw token transfer into the vault does not move the rate.
- Require a minimum first deposit.

The internal-accounting approach is the most robust: if the rate is computed from a tracked figure rather than the vault's live token balance, donating tokens to the vault changes nothing.

---

## Round-trip safety

The single most valuable test: deposit `X`, immediately withdraw all resulting shares, assert you get back **at most** `X` (never more). With correct down-rounding on both legs, the user loses at most rounding dust and the pool never pays out more than it took in. If a round-trip ever returns more than the input, a rounding direction is wrong and the pool is drainable.
