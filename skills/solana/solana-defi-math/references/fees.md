# Fee Math

Self-contained patterns. Adapt names to the host repo. Covers the three fee types in the team's vault and lending programs: management (prorated, at deposit and at collection), performance (on profit, at withdrawal), and protocol take (on accrued interest).

## Table of Contents

- Fee-rate scaling
- Management fee, prorated at deposit
- Management fee at periodic collection
- Performance fee on profit
- Protocol take on interest
- Initialization and timing pitfalls

---

## Fee-rate scaling

Fee rates arrive as integers and must be converted at the boundary, never inlined as magic numbers. Two scales are common; pick one per field and document it:

```rust
// per-million: e.g. 1_000 means 0.1% (1_000 / 1_000_000)
pub const FEE_DENOMINATOR_PPM: u64 = 1_000_000;

// percent: e.g. 20 means 20% (20 / 100)
pub const PERCENT_DENOMINATOR: u64 = 100;
```

The team's programs use per-million for the monthly management fee and a direct percent for the performance fee. They are different scales in the same program - a real source of confusion. Name them distinctly (`monthly_management_fee` documented as per-`10^6`, `performance_fee_percent` documented as a percent) and convert each with its own denominator.

---

## Management fee, prorated at deposit

A flat monthly fee taken in full from every deposit would overcharge someone who deposits a day before the period rolls over. The fix is to prorate to the fraction of the current period remaining:

```
period_length = 30 days (in seconds)
time_remaining = period_end - now
fee = amount * fee_rate_per_period * time_remaining / period_length
```

```rust
const SECONDS_PER_MONTH: u64 = 2_592_000; // 30 * 86_400

// End of the current period, rounded up to the next boundary.
let period_end = (now / SECONDS_PER_MONTH + 1) * SECONDS_PER_MONTH;
let time_remaining = period_end - now;

// fee = amount * (rate / 1_000_000) * (time_remaining / period_length)
// Do the multiplies first, in u128, then the divides. Round down (toward the user).
let fee = (deposit_amount as u128)
    .checked_mul(monthly_management_fee as u128).unwrap()
    .checked_mul(time_remaining as u128).unwrap()
    .checked_div(FEE_DENOMINATOR_PPM as u128).unwrap()
    .checked_div(SECONDS_PER_MONTH as u128).unwrap() as u64;
```

A depositor joining at the start of a period pays nearly the full monthly fee; one joining near the end pays nearly nothing, and will pay again next period. The fee transfers to the fee wallet immediately at deposit.

---

## Management fee at periodic collection

Separately, a recurring fee is skimmed from assets under management once per period. It is gated by a timer that advances by exactly one period each collection, so it cannot be called repeatedly to drain the vault:

```rust
require!(now >= config.next_fee_collection_time, VaultError::FeeNotDue);

let fee = (assets_under_management as u128)
    .checked_mul(monthly_management_fee as u128).unwrap()
    .checked_div(FEE_DENOMINATOR_PPM as u128).unwrap() as u64;

// Advance the timer by one full period (not "now + period"), so collection cadence
// stays aligned to fixed boundaries even if a collection is late.
config.next_fee_collection_time = config
    .next_fee_collection_time
    .checked_add(SECONDS_PER_MONTH).unwrap();
```

Two pitfalls, both observed in real code:

- **Advancing to `now + period` instead of `previous + period`** lets cadence drift later on every late collection. Advance from the previous scheduled time.
- **Forgetting to initialize the timer** leaves `next_fee_collection_time == 0`, so the first collection is callable from genesis and the gate is meaningless. Set it at `initialize` to `now + SECONDS_PER_MONTH` (see below).

---

## Performance fee on profit

Charged only on gains, only at withdrawal. No profit, no fee - never charge on returned principal:

```rust
let performance_fee = if withdraw_value > deposited_value {
    (withdraw_value - deposited_value)
        .checked_mul(performance_fee_percent).unwrap()
        .checked_div(PERCENT_DENOMINATOR).unwrap()
} else {
    0
};
```

`deposited_value` is the cost basis recorded when the user deposited. Compare like units: if `deposited_value` is in SOL, `withdraw_value` must be the SOL-denominated proceeds, after any swaps and after unwrapping. The fee is taken from the proceeds before they reach the user.

When proceeds come back as wrapped SOL, the usual sequence is: transfer wrapped SOL to the user's account, close that account to unwrap into native SOL, then collect the fee in native SOL. The user signs the transaction, so the fee transfer is authorized as part of the same flow.

---

## Protocol take on interest

In a lending reserve, the protocol keeps a slice of the interest borrowers pay. It applies to the newly accrued interest each accrual, not to principal:

```rust
// During compound_interest, after computing net new debt for this accrual:
let net_new_debt = new_total_debt - previous_total_debt;
let protocol_fee = net_new_debt * protocol_take_rate;   // take_rate as a Fraction
accumulated_protocol_fees += protocol_fee;
```

This accumulates in a fee field on the reserve and is withdrawn by the protocol authority separately. Because it is computed inside accrual on the net new debt, it never double-counts across accruals. See `staleness-and-accrual.md` for where this sits in the compound-interest step.

---

## Initialization and timing pitfalls

- Initialize every timer field. `next_fee_collection_time = now + SECONDS_PER_MONTH` at `initialize`. A zero-defaulted timer disables the gate it was meant to enforce.
- Prorated deposit fee and periodic collection are two different mechanisms; a program may use both. Do not let them double-charge the same value in the same period - the deposit fee covers the depositor's entry, the collection fee covers assets sitting under management.
- Performance fee compares against a stored cost basis. If a user deposits twice, decide deliberately whether the basis is a weighted average or per-tranche; a single `deposited_amount` field implicitly chooses weighted average and resets the high-water mark on each deposit.
- All fee math rounds down (in the user's favor on what they keep is the wrong frame here - round so the protocol does not over-collect; for fees that means round the fee down). State the direction at the call site.
