# Fixed-Point and Integer Representations

Self-contained patterns. Adapt names to the host repo.

## Table of Contents

- Why fixed-point
- Scaled integers
- The Fraction type (fixed-point)
- Basis points and percent
- U256 intermediates
- Choosing between them

---

## Why fixed-point

Onchain math needs exactness and determinism. Floats give neither. The two safe tools are scaled integers (you track the scale) and fixed-point types (the type tracks the scale). Fixed-point is preferred for anything multiplied and divided repeatedly, because the scale cannot drift.

---

## Scaled integers

A value stored as `value * SCALE`, with `SCALE` a power of ten the whole protocol agrees on.

```rust
pub const SCALE: u128 = 1_000_000_000; // 10^9, one "unit" of precision

// Store 1.5 as 1_500_000_000
let stored: u128 = 3 * SCALE / 2;

// Multiply two scaled numbers: divide back out one scale factor.
let product = a.checked_mul(b).unwrap() / SCALE;

// Divide two scaled numbers: multiply in one scale factor first.
let quotient = a.checked_mul(SCALE).unwrap() / b;
```

The hazard is entirely on you: every multiply gains a scale factor that must be divided out, every divide loses one that must be multiplied in. Mistracking the scale silently changes results by powers of ten. Use scaled integers for simple, shallow math (share accounting); reach for fixed-point when the expressions get deep.

---

## The Fraction type (fixed-point)

The `fixed` crate gives types like `U68F60` - 68 integer bits, 60 fractional bits - that carry their scale in the type. Wrap it so the protocol has one name for "a rate or ratio":

```rust
pub use fixed::types::U68F60 as Fraction;

// Construction
let one = Fraction::ONE;
let from_int = Fraction::from_num(5u64);          // 5.0
let from_ratio = Fraction::from_num(3) / 4;       // 0.75

// Arithmetic is ordinary operators; the type keeps the scale correct.
let rate = base_rate + utilization * slope;

// Persisting: store the raw bits (a u128) in the account, reconstruct on read.
let bits: u128 = rate.to_bits();          // store this
let restored = Fraction::from_bits(bits); // read this
```

A common convention is a `_sf` suffix ("scaled fraction") on account fields holding `Fraction::to_bits()` values, so a reader knows the `u128` is a fixed-point payload, not a raw amount.

A small extension trait keeps conversions readable and explicit about rounding:

```rust
pub trait FractionExtra {
    fn from_bps<T: Into<u128>>(bps: T) -> Self; // bps / 10_000
    fn from_percent<T: Into<u128>>(pct: T) -> Self; // pct / 100
    fn to_floor<D>(&self) -> D; // truncate toward zero
    fn to_ceil<D>(&self) -> D;  // round up
    fn to_round<D>(&self) -> D; // nearest
}
```

The point of `to_floor` / `to_ceil` being separate, named methods is that the rounding direction becomes a visible decision at the call site rather than an accident of which conversion you reached for.

---

## Basis points and percent

Config values arrive as integers. Convert at the boundary, never mid-expression.

```rust
pub const FULL_BPS: u128 = 10_000; // 100% in basis points

// bps -> fraction
let ltv = Fraction::from_bps(7_500u128); // 0.75

// percent -> fraction
let take_rate = Fraction::from_percent(20u128); // 0.20

// fraction -> bps (for events/logging), rounding chosen explicitly
let bps: u64 = (rate * FULL_BPS).round().to_num();
```

Never write `value * 7500 / 10000` inline - name it, convert once, and keep the rest of the expression in one unit.

---

## U256 intermediates

A fixed-point multiply `a * b` forms an intermediate of roughly `a_bits * b_bits`, which can exceed `u128` even when the final result fits. Widen the intermediate to `U256`, then narrow back:

```rust
// full_mul_int_ratio: (self * numerator / denominator) without overflowing the product
fn mul_ratio_wide(value: Fraction, numerator: u128, denominator: u128) -> Fraction {
    let wide = U256::from(value.to_bits())
        .checked_mul(U256::from(numerator)).unwrap()
        .checked_div(U256::from(denominator)).unwrap();
    let narrowed: u128 = wide.try_into().expect("result exceeds Fraction range");
    Fraction::from_bits(narrowed)
}

// ceil variant: add (denominator - 1) before dividing
fn mul_ratio_wide_ceil(value: Fraction, numerator: u128, denominator: u128) -> Fraction {
    let wide = U256::from(value.to_bits())
        .checked_mul(U256::from(numerator)).unwrap()
        .checked_add(U256::from(denominator - 1)).unwrap()
        .checked_div(U256::from(denominator)).unwrap();
    Fraction::from_bits(wide.try_into().expect("overflow"))
}
```

Use `U256` intermediates for `value * ratio` where both operands are large scaled numbers - market-value calculations, large balances times a rate.

---

## Choosing between them

- Rate, exchange rate, utilization, any repeatedly multiplied/divided ratio → **Fraction (fixed-point)**.
- Share/asset accounting, simple proportional splits → **scaled `u128`**.
- A multiply of two large scaled operands that then gets divided → keep it fixed-point but compute the product through a **`U256` intermediate**.
- Config inputs → bps/percent integers, converted to `Fraction` at the boundary.

Never floats.
