# Staleness and Interest Accrual

Self-contained patterns. Adapt names to the host repo.

## Table of Contents

- The freshness problem
- The LastUpdate pattern
- Refresh-before-act
- Compound interest, exactly
- The approximation used in production
- The cumulative-rate index
- Per-obligation lazy accrual

---

## The freshness problem

Interest, market value, and any time-dependent quantity drift continuously, but onchain state only changes when a transaction touches it. If a handler reads `borrowed_amount` and decides whether a borrow is safe without first applying the interest that accrued since the last update, it is deciding on stale, under-counted debt. That is not a rounding lag - it is a correctness hole that lets a position borrow against value it no longer has.

The fix is structural: make staleness a property the data carries, and refuse to act on stale data.

---

## The LastUpdate pattern

Stamp each time-dependent account with the slot it was last refreshed and an explicit stale flag:

```rust
#[derive(Clone, Copy)]
pub struct LastUpdate {
    pub slot: u64,
    pub stale: u8, // 1 = must refresh before use, 0 = fresh this slot
    pub _padding: [u8; 7],
}

impl LastUpdate {
    pub fn new(slot: u64) -> Self {
        Self { slot, stale: 1, _padding: [0; 7] } // born stale: must be refreshed before first use
    }
    pub fn update_slot(&mut self, slot: u64) {
        self.slot = slot;
        self.stale = 0;
    }
    pub fn mark_stale(&mut self) {
        self.stale = 1;
    }
    pub fn is_fresh(&self, slot: u64) -> bool {
        self.stale == 0 && self.slot == slot
    }
    pub fn slots_elapsed(&self, slot: u64) -> Result<u64> {
        slot.checked_sub(self.slot).ok_or(LendingError::MathOverflow.into())
    }
}
```

Two non-obvious choices matter. Accounts are born stale, so a freshly created account cannot be used in a value decision until it has been refreshed once. And freshness requires the *same slot* - being refreshed last slot is not good enough, because anything could have changed since.

---

## Refresh-before-act

Any mutation marks the account stale; any value-moving action requires freshness in the current slot. The two halves enforce each other:

```rust
// At the start of any value-moving handler:
require!(reserve.last_update.is_fresh(clock.slot), LendingError::NeedToRefreshReserve);
require!(obligation.last_update.is_fresh(clock.slot), LendingError::NeedToRefreshObligation);

// ... do the work ...

// After mutating, mark stale so the next action in the same transaction must refresh:
reserve.last_update.mark_stale();
```

This makes it physically impossible to chain two state-changing actions on the same reserve without an intervening refresh: the first marks it stale, the second's freshness check fails. A multi-reserve protocol therefore enforces a transaction layout of `refresh_reserve(each) -> refresh_obligation -> action`. Tests should assert that two actions in one transaction without a refresh between them abort with the refresh error - that negative test is what proves the invariant holds.

---

## Compound interest, exactly

Debt compounds each slot at the per-slot rate:

```
new_debt = principal * (1 + rate_per_slot) ^ slots_elapsed
rate_per_slot = annual_rate / SLOTS_PER_YEAR
```

The exact computation is a problem onchain. Integer `pow` over tens of thousands of slots overflows immediately. Exact fixed-point exponentiation by squaring is possible but costs compute and still risks intermediate overflow. So production code approximates the compound *factor* `(1 + x)^n` where `x` is tiny.

---

## The approximation used in production

For very small slot counts, compute the factor exactly (cheap, and avoids approximation error where it would be most visible). Above a small threshold, use a truncated binomial/Taylor expansion of `(1 + x)^n`:

```
(1 + x)^n ≈ 1 + n·x + n(n-1)/2 · x² + n(n-1)(n-2)/6 · x³
```

```rust
fn compound_factor(rate_per_slot: Fraction, slots: u64) -> Fraction {
    let one = Fraction::ONE;
    match slots {
        0 => one,
        1 => one + rate_per_slot,
        2 => (one + rate_per_slot) * (one + rate_per_slot),
        // small exact cases ...
        n => {
            let x = rate_per_slot;
            let n_f = Fraction::from_num(n);
            let term1 = n_f * x;
            // n(n-1)/2 · x²  - divide the integer binomial coefficients first
            let c2 = Fraction::from_num(n * (n - 1) / 2);
            let term2 = c2 * x * x;
            let c3 = Fraction::from_num(n * (n - 1) * (n - 2) / 6);
            let term3 = c3 * x * x * x;
            one + term1 + term2 + term3
        }
    }
}
```

Because `x = annual_rate / SLOTS_PER_YEAR` is on the order of `1e-8`, the fourth-order term is negligible and three terms hold ample precision. The approximation always slightly *under*-estimates the true compound factor, which errs in the borrower's favor by a hair - an acceptable and auditable direction. Document that this is an approximation and why; do not let a future reader mistake it for an exact formula.

---

## The cumulative-rate index

Touching every borrower's account each slot is impossible. Instead maintain one global, monotonically increasing index per reserve - the cumulative borrow rate - and store on each obligation the index value at its last interaction. A borrower's current debt is then a single multiply:

```
current_debt = stored_debt * (current_cumulative_rate / stored_cumulative_rate)
```

On each reserve refresh, advance the index by the compound factor for the elapsed slots:

```rust
// reserve refresh
let factor = compound_factor(rate_per_slot, slots_elapsed);
reserve.cumulative_borrow_rate = reserve.cumulative_borrow_rate * factor;
reserve.borrowed_amount = reserve.borrowed_amount * factor; // pool total accrues too
```

The index only ever grows, so the ratio `current / stored` is always `>= 1` and debt only increases between repayments. Storing the index as a big fixed-point value (`U256`-backed) keeps precision over the protocol's lifetime.

---

## Per-obligation lazy accrual

When an obligation is refreshed, bring each of its borrows up to date using the ratio of indices, then restamp it:

```rust
// obligation refresh, per borrow position
let ratio = reserve.cumulative_borrow_rate / borrow.cumulative_borrow_rate_snapshot;
borrow.borrowed_amount = borrow.borrowed_amount * ratio;
borrow.cumulative_borrow_rate_snapshot = reserve.cumulative_borrow_rate;
```

This way interest is correct on read without ever iterating over all positions. The cost is moved to the moment each position is actually used, which is exactly when correctness matters. The reserve must be fresh before the obligation reads its index - hence the `refresh_reserve -> refresh_obligation` ordering.
