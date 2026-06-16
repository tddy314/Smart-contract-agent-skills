# Interest Rate Curves

Self-contained patterns. Adapt names to the host repo.

## Table of Contents

- Utilization
- Why a curve
- Piecewise-linear borrow-rate curve
- Segment interpolation
- Curve validation
- Supply rate

---

## Utilization

Utilization is the fraction of supplied liquidity currently borrowed:

```
utilization = total_borrows / total_supply
```

where `total_supply = available_liquidity + total_borrows`. It lives in `[0, 1]`. It is the single input to the borrow rate: as more of the pool is lent out, borrowing costs more, which both compensates suppliers for reduced liquidity and pushes utilization back down.

```rust
fn utilization(total_borrows: Fraction, available: u64) -> Fraction {
    let supply = total_borrows + Fraction::from_num(available);
    if supply == Fraction::ZERO {
        return Fraction::ZERO; // empty reserve
    }
    let u = total_borrows / supply;
    if u > Fraction::ONE { Fraction::ONE } else { u } // clamp defensively
}
```

Clamp to `1.0`. Rounding in the accrual path can momentarily produce borrows slightly above supply; the curve must not be handed an out-of-range input.

---

## Why a curve

A flat rate cannot both keep borrowing cheap when liquidity is plentiful and protect the pool from being fully drained. The standard solution is a curve that is gentle below a target ("optimal") utilization and steep above it, so the marginal cost of pushing utilization toward 100% rises sharply and suppliers are always able to withdraw.

---

## Piecewise-linear borrow-rate curve

Represent the curve as an ordered set of points `(utilization, rate)`, both in basis points, and linearly interpolate between them. A fixed-size array keeps it zero-copy friendly:

```rust
#[derive(Clone, Copy)]
pub struct CurvePoint {
    pub utilization_bps: u32, // 0 .. 10_000
    pub rate_bps: u32,
}

pub struct BorrowRateCurve {
    pub points: [CurvePoint; 11], // up to 11 points; unused slots repeat the last
}
```

A two-point curve is a single line; a three-point curve `(0, base), (optimal, optimal_rate), (10000, max_rate)` is the classic two-slope model. Eleven points allow a finely shaped curve without arbitrary-length storage.

---

## Segment interpolation

To evaluate the rate at a given utilization, find the segment whose endpoints bracket it and interpolate linearly:

```rust
impl BorrowRateCurve {
    pub fn borrow_rate(&self, utilization: Fraction) -> Result<Fraction> {
        let u_bps: u32 = (utilization * 10_000u128).to_floor();

        // Find the bracketing segment.
        let (start, end) = self.points
            .windows(2)
            .map(|w| (w[0], w[1]))
            .find(|(s, e)| u_bps >= s.utilization_bps && u_bps <= e.utilization_bps)
            .ok_or(LendingError::InvalidUtilization)?;

        // Exact hits on a point need no interpolation.
        if u_bps == start.utilization_bps {
            return Ok(Fraction::from_bps(start.rate_bps));
        }
        if u_bps == end.utilization_bps {
            return Ok(Fraction::from_bps(end.rate_bps));
        }

        // Linear interpolation within the segment:
        // rate = start_rate + (u - start_u) * (end_rate - start_rate) / (end_u - start_u)
        let slope_num = (end.rate_bps - start.rate_bps) as u128;
        let slope_den = (end.utilization_bps - start.utilization_bps) as u128;
        let offset = utilization - Fraction::from_bps(start.utilization_bps);
        let rise = offset * slope_num / slope_den;
        Ok(Fraction::from_bps(start.rate_bps) + rise)
    }
}
```

Because the differences `end - start` are pre-checked positive at construction (see validation), the subtractions here cannot underflow.

---

## Curve validation

A malformed curve is a config-time foot-gun that becomes a runtime abort or a mispriced loan. Validate at the boundary, when the curve is set:

- First point must be at utilization `0`.
- Last point must be at utilization `10_000` (100%).
- Utilization must be strictly increasing across points (so segments are well-formed and the bracketing search is unambiguous).
- Rate must be non-decreasing (a curve where borrowing gets cheaper as the pool drains is almost always a mistake).

```rust
impl BorrowRateCurve {
    pub fn validate(&self) -> Result<()> {
        require!(self.points[0].utilization_bps == 0, LendingError::InvalidCurve);
        let last = self.points.len() - 1;
        require!(self.points[last].utilization_bps == 10_000, LendingError::InvalidCurve);
        for w in self.points.windows(2) {
            // utilization strictly increasing until it saturates at 10_000
            require!(
                w[1].utilization_bps > w[0].utilization_bps
                    || w[0].utilization_bps == 10_000,
                LendingError::InvalidCurve
            );
            require!(w[1].rate_bps >= w[0].rate_bps, LendingError::InvalidCurve);
        }
        Ok(())
    }
}
```

---

## Supply rate

Suppliers earn the borrow interest, scaled by how much of the pool is actually lent (utilization) and net of the protocol's cut (the reserve factor):

```
supply_rate = utilization * borrow_rate * (1 - reserve_factor)
```

```rust
fn supply_rate(utilization: Fraction, borrow_rate: Fraction, reserve_factor: Fraction) -> Fraction {
    utilization * borrow_rate * (Fraction::ONE - reserve_factor)
}
```

The supply rate is always below the borrow rate: idle liquidity earns nothing and the reserve factor is skimmed for the protocol. This spread is the protocol's revenue model and a sanity check - if your computed supply rate ever exceeds the borrow rate, the math is wrong.
