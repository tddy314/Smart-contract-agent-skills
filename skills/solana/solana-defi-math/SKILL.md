---
name: solana-defi-math
description: >
  Fixed-point and integer math patterns for Solana DeFi programs - interest accrual,
  exchange rates, share/collateral accounting, utilization curves, liquidation math,
  fee proration, and rounding discipline. Use whenever a Solana/Anchor task involves
  financial calculation: interest, yield, shares vs assets, collateral exchange rates,
  borrow-rate curves, liquidation amounts, or any value that moves tokens or persists
  in account state. ALWAYS use this skill when reviewing or writing math that affects
  balances, even if the user only says "calculate", "rate", "accrue", "shares", or
  "rounding". Pairs with solana-anchor (host patterns), solana-lending, and solana-vault.
---

# Solana DeFi Math

This skill encodes how to do financial math correctly in Solana programs. The recurring failures in DeFi math are not exotic - they are floats, silent overflow, wrong rounding direction, and stale accounting. Each leaks value or breaks determinism. This skill exists to make the safe pattern the default one.

`solana-anchor` owns the host program patterns (accounts, CPI, tokens). This skill owns the numbers. Load `solana-lending` or `solana-vault` for protocol-shaped assemblies of these primitives.

---

## When to Use

- Interest or yield accrual over time (slots, seconds)
- Exchange rates between two units (liquidity ↔ collateral, assets ↔ shares)
- Share accounting (deposit/withdraw proportional ownership)
- Utilization-based rate curves
- Liquidation amount and bonus math
- Fee calculation (management, performance, protocol take)
- Any rounding decision on a value that moves tokens or persists in state

**Do not use** for non-financial integer work (counters, indices, lengths) or off-chain display formatting where precision loss is cosmetic.

---

## The Four Rules

These are the failure modes, in order of how often they cause losses.

### 1. No floats. Ever. In financial paths.

`f32`/`f64` are banned for amounts, shares, rates, prices, and any value that affects token movement or persisted state - including instruction parameters and intermediate calculations.

Why it matters: float addition is non-associative, so `(a + b) + c != a + (b + c)` in general. Two users depositing the same amount in different orders can end up with different recorded balances. Borsh serialization of floats is not guaranteed identical across platforms. None of this is acceptable when the number controls who owns what.

If you encounter float financial code (a `total_lending_sol: f64` field, a `withdraw_amount: f64` parameter), do not extend it. Flag it as a SECURITY-REVIEW item and propose the integer/fixed-point replacement. This is a real pattern in the wild and it is always a defect.

### 2. Every operation is checked.

Set `overflow-checks = true` in the release profile (`[profile.release]` in the workspace `Cargo.toml`) so arithmetic traps instead of wrapping. But still prefer explicit `checked_*` in handler logic so the failure surfaces as a clean custom error, not a panic:

```rust
let new_debt = principal
    .checked_add(interest)
    .ok_or(LendingError::MathOverflow)?;
```

Multiplication is where overflow hides. `u64 * u64` overflows above ~1.8e19; with token amounts in base units plus a scaled rate, you reach that fast. Widen to `u128` (or `U256`) for the intermediate product, then narrow back with a checked conversion.

### 3. Rounding always favors the protocol.

Every division has a rounding direction, and the wrong one leaks value. The rule: round so the user never gets more than they are owed and never owes less than they should.

- Minting shares/collateral **to** a user on deposit: round **down**.
- Computing the liquidity a user must deposit for a given collateral: round **up**.
- Computing what a borrower must repay: round **up**.
- Computing what a withdrawer receives: round **down**.

A pair of conversions that must round in opposite directions (deposit vs withdraw) is the classic place a rounding bug becomes a slow drain. Provide both a floor and a ceil variant of each conversion and pick deliberately at each call site.

### 4. Stale accounting is a bug, not a lag.

Time-dependent values (accrued interest, cumulative rate, market value) must be refreshed to the current slot/timestamp **before** they are read for a decision. A borrow check against yesterday's debt under-counts what is owed.

Encode freshness in the data and enforce it. Stamp accounts with the slot they were last updated, mark them stale after any mutation, and require freshness before any value-moving action. See `references/staleness-and-accrual.md` for the `LastUpdate` pattern and the refresh-before-act sequence.

---

## Choosing a Numeric Representation

Pick the simplest representation that holds the required precision.

**Scaled integers (`u64`/`u128`).** A value times a fixed scale (e.g. `10^6` or `10^9`). Good for share accounting and simple ratios. Cheap. The whole protocol must agree on the scale, and you must track it mentally at every operation - this is the main hazard.

**Fixed-point (`Fraction`, e.g. `U68F60`).** A type from the `fixed` crate carrying its scale in the type. Best for rates, exchange rates, and anything multiplied/divided repeatedly. The scale is implicit and correct by construction, which removes the main hazard of manual scaled integers. Use this for interest math and curves.

**Basis points / percent as inputs.** Config values arrive as integers: bps (`/10_000`) or percent (`/100`). Convert to your working type at the boundary. Name the constant: `FULL_BPS = 10_000`.

**Big-integer intermediates (`U256`).** When a fixed-point multiply would overflow `u128` in its intermediate, widen to `U256` for the product and divide back down. Necessary for `value * ratio` where both are large scaled numbers.

Rules of thumb: rates and exchange rates → fixed-point. Share/asset accounting → scaled `u128`. Anything multiplied then divided by large scaled operands → `U256` intermediate. Details and a fixed-point helper API in `references/fixed-point.md`.

---

## Core Formulas

These are the building blocks. Each links to a worked, self-contained implementation.

### Exchange rate (two-unit conversion)

A reserve holds liquidity and issues collateral tokens (cTokens) representing a share of it. The exchange rate is `total_liquidity / collateral_supply`, and it grows as interest accrues - that growth is how depositors earn yield.

```
collateral_minted = liquidity_deposited / exchange_rate     (round down to user)
liquidity_returned = collateral_burned  * exchange_rate      (round down to user)
```

First deposit into an empty reserve uses a 1:1 rate. After that, the rate reflects accrued interest. The inverse conversions (how much liquidity for N collateral) round **up** so the reserve is never short. Worked code with floor/ceil variants: `references/shares-and-exchange-rate.md`.

### Share accounting (proportional ownership)

A vault holds a pool of value; each depositor owns shares. The invariant is `user_shares / total_shares == user_value / total_value`.

```
shares_minted = deposit_amount * total_shares / total_value   (round down)   # pool non-empty
shares_minted = deposit_amount                                                # pool empty (1:1)
assets_out    = shares_burned  * total_value  / total_shares   (round down)
```

Do the multiply before the divide, in `u128`, to preserve precision. The empty-pool branch and the first-depositor inflation concern are covered in `references/shares-and-exchange-rate.md`.

### Utilization and borrow rate

Utilization drives the interest rate:

```
utilization = total_borrows / total_supply
```

The borrow rate is a function of utilization, typically a piecewise-linear curve: low and flat below an optimal utilization, steep above it, to push the pool back toward a target. Supply rate is derived from borrow rate:

```
supply_rate = utilization * borrow_rate * (1 - reserve_factor)
```

The curve representation, segment interpolation, and validation rules are in `references/interest-rate-curves.md`.

### Interest accrual (compounding)

Interest compounds per slot. The exact form is `principal * (1 + rate_per_slot)^slots_elapsed`, but integer `pow` over many slots overflows and exact fixed-point `pow` is expensive. The production pattern is a Taylor approximation of the compound factor for the elapsed slots, with exact shortcuts for very small slot counts. A cumulative borrow-rate index lets per-obligation debt be updated lazily without touching every account each slot.

Full derivation, the approximation, and the cumulative-index pattern: `references/staleness-and-accrual.md`.

### Liquidation math

When an obligation's loan-to-value crosses the unhealthy threshold, a liquidator repays debt and seizes collateral plus a bonus. The moving parts:

```
ltv = borrowed_value / collateral_value
liquidation triggers when ltv >= unhealthy_ltv_threshold
seized = repaid_value * (1 + liquidation_bonus)        # capped at available collateral
```

The bonus scales with how unhealthy the position is and is capped near bad-debt territory. Partial vs full liquidation, dust thresholds, and the bonus curve are protocol policy - see `solana-lending` and `references/liquidation-math.md`.

### Fee proration

A management fee charged at deposit is prorated to the fraction of the fee period remaining, so a depositor who joins late in the period pays proportionally less:

```
time_remaining = period_end - now
fee = amount * fee_rate_per_period * time_remaining / period_length
```

A performance fee is charged only on profit at withdrawal:

```
fee = if withdraw_value > deposited_value
      { (withdraw_value - deposited_value) * performance_fee_rate }
      else { 0 }
```

Worked examples and the fee-rate scaling (per-`10^6`, percent) in `references/fees.md`.

---

## Workflow for a Math Change

1. **Identify the units and scale of every input.** Base token units? Bps? A scaled fraction? Write it down. Most math bugs are unit mismatches.
2. **Pick the representation** (scaled int / fixed-point / U256 intermediate) using the rules above.
3. **Write the formula with explicit rounding** at each division. State which direction and why, in a comment, at the call site.
4. **Widen intermediates** so the multiply cannot overflow before the divide.
5. **Refresh time-dependent inputs** to the current slot before reading them.
6. **Test the boundaries** (see below), not just a mid-range happy path.

---

## Testing Math

Hand test design to `smart-contract-testing`, but these are the math-specific cases that catch real bugs:

- **Rounding direction:** a deposit-then-immediate-withdraw must not return more than was put in (round-trip ≤ identity). This single test catches most rounding-direction errors.
- **Empty-pool / first-depositor:** first deposit, and the share-inflation edge where a tiny first deposit could skew the rate.
- **Overflow boundary:** maximum plausible amounts times maximum rate - prove the intermediate widens correctly.
- **Zero and dust:** zero amount rejected; sub-unit results handled by an explicit dust rule, not silent truncation to zero.
- **Accrual over time:** interest after N slots matches the expected compound factor; accruing in one step equals accruing in several steps over the same span (within the approximation's tolerance).
- **Monotonicity:** the exchange rate never decreases across an accrual; utilization stays in `[0, 1]`.

---

## Common Mistakes to Avoid

- `f64`/`f32` anywhere in a financial path - the single most common and most serious.
- Dividing before multiplying, throwing away precision.
- Multiplying two scaled `u64`s without widening - silent overflow (or a release-mode panic) under large inputs.
- The same rounding direction for both deposit and withdraw conversions - a slow drain.
- Reading interest, debt, or market value without refreshing to the current slot first.
- Mixing scales (bps vs percent vs raw fraction) in one expression.
- Magic numbers - `10_000`, `1_000_000` with no name or rationale.
- Truncating a sub-unit result to zero with no dust handling, letting tiny positions become un-liquidatable or un-closeable.

---

## Reference Files

- `references/fixed-point.md` - representations, the `Fraction` helper API, bps/percent conversion, `U256` intermediates
- `references/shares-and-exchange-rate.md` - exchange-rate and share-accounting math with floor/ceil variants and the empty-pool branch
- `references/interest-rate-curves.md` - utilization, piecewise-linear borrow-rate curve, supply rate, curve validation
- `references/staleness-and-accrual.md` - `LastUpdate` freshness pattern, compound-interest approximation, cumulative-rate index
- `references/liquidation-math.md` - LTV, health, liquidation amounts, bonus curve, dust and partial-liquidation policy
- `references/fees.md` - management-fee proration, performance fee on profit, fee-rate scaling

---

## Rules

1. Never use floats in a financial path; flag existing float math as SECURITY-REVIEW.
2. Check every arithmetic operation; widen intermediates before they overflow.
3. State the rounding direction at every division, and round in the protocol's favor.
4. Provide floor and ceil variants for conversions that run in both directions.
5. Refresh time-dependent values to the current slot before reading them.
6. Track the unit and scale of every operand; never mix scales.
7. Name every numeric constant.
8. Test boundaries - round-trip, empty pool, overflow, dust, accrual-over-time.
