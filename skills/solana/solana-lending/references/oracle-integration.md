# Oracle Integration

Self-contained patterns. Adapt names to the host repo. The disciplines here apply whether the price source is a Pyth/Switchboard feed or a protocol-maintained price account - the failure modes are the same.

## Table of Contents

- The four oracle disciplines
- Pinning the oracle per reserve
- Staleness
- Sanity checks
- Decimal and exponent conversion
- A protocol-maintained price account

---

## The four oracle disciplines

A lending protocol values every position through an oracle. If the oracle can be spoofed, frozen, or misread, the protocol misvalues collateral and debt - which means it can be drained. Four disciplines, all mandatory:

1. **Pin** the oracle account per reserve so a caller cannot substitute one.
2. **Reject stale** prices past a max-age window.
3. **Validate** the price is sane (no NaN/zero/negative/absurd, confidence bounded).
4. **Convert** to the protocol's fixed-point type at the boundary, handling exponent and decimals, never via float.

---

## Pinning the oracle per reserve

Store the expected oracle pubkey in the reserve at init. Validate it on every refresh. An unconstrained oracle account is the single most dangerous hole in a lending protocol.

```rust
#[derive(Accounts)]
pub struct RefreshReserve<'info> {
    #[account(mut)]
    pub reserve: AccountLoader<'info, Reserve>,

    #[account(seeds = [LENDING_MARKET_SEED, &lending_market.load()?.name], bump)]
    pub lending_market: AccountLoader<'info, LendingMarket>,

    /// CHECK: validated against the pubkey stored in the reserve at init.
    #[account(address = reserve.load()?.oracle_pubkey @ LendingError::InvalidOracle)]
    pub oracle: UncheckedAccount<'info>,
}
```

The `address = reserve.load()?.oracle_pubkey` constraint is what makes price-spoofing impossible: the only oracle that passes is the one pinned at reserve creation.

---

## Staleness

A price has a publish time. If it is older than the reserve's max-age window, abort - do not value positions at a dead price. A frozen feed must halt valuation, not silently freeze the protocol at the last price.

```rust
let now = Clock::get()?.unix_timestamp;
require!(
    price_publish_time.checked_add(reserve.config.max_age_price_seconds as i64)
        .ok_or(LendingError::MathOverflow)? >= now,
    LendingError::PriceTooStale
);
```

Pick `max_age_price_seconds` per asset: volatile assets need a tighter window. Document the choice.

---

## Sanity checks

Reject prices that cannot be real before they enter the math:

```rust
require!(price > 0, LendingError::InvalidPrice);           // zero/negative is never valid
require!(price < MAX_SANE_PRICE, LendingError::InvalidPrice); // guard absurd magnitudes

// If the feed provides a confidence interval, bound it: reject when confidence is a
// large fraction of price (a wide band means the feed is unsure).
let confidence_ratio = confidence_scaled / price_scaled;
require!(confidence_ratio <= MAX_CONFIDENCE_RATIO, LendingError::PriceConfidenceTooWide);
```

For a feed using IEEE floats at its API boundary (some do), check `is_nan()` / `is_infinite()` before converting, then convert immediately to fixed-point - do not let a float propagate into protocol math.

---

## Decimal and exponent conversion

Oracle feeds publish a price plus an exponent (e.g. price `12345`, expo `-3` means `12.345`). Tokens have their own decimals. To get a comparable value you must reconcile both. Convert to the protocol's `Fraction` at the boundary.

```rust
// price_raw * 10^expo  -> a Fraction
fn oracle_price_to_fraction(price_raw: u64, expo: i32) -> Result<Fraction> {
    let base = Fraction::from_num(price_raw);
    let scaled = if expo >= 0 {
        base.checked_mul(Fraction::from_num(ten_pow(expo as usize)))
    } else {
        base.checked_div(Fraction::from_num(ten_pow((-expo) as usize)))
    }.ok_or(LendingError::MathOverflow)?;
    Ok(scaled)
}
```

When valuing an amount of a token, divide out the token's decimal factor (its `mint_factor = 10^decimals`) so that two assets with different decimals are valued in the same unit:

```rust
// market value = price * amount / 10^token_decimals
let value = price_fraction
    .checked_mul(Fraction::from_num(amount))
    .ok_or(LendingError::MathOverflow)?
    / Fraction::from_num(mint_factor);
```

Store the resulting market price as a scaled fraction (`market_price_sf = price_fraction.to_bits()`), never as a float.

---

## A protocol-maintained price account

Some protocols keep their own price account, updated offchain by a keeper, instead of reading a feed directly. The same four disciplines apply, plus two:

- **The price account is still pinned per reserve** (same `address =` constraint) and **its discriminator is validated** - confirm the account really is the expected type before deserializing, so a look-alike account cannot be passed.
- **The update authority is constrained** - only the keeper may write prices, and the write path stamps a fresh timestamp that the staleness check reads.

A protocol-maintained price account concentrates trust in the keeper. That is a documented trust assumption, not a "trustless" design - describe it honestly (see `solana-anchor/references/conventions.md` on financial-writing claims). The staleness window is the protection against a dead or compromised keeper: if updates stop, valuation halts.
