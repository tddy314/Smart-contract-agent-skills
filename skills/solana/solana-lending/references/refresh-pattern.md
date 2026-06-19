# The Refresh-Before-Act Pattern

Self-contained patterns. Adapt names to the host repo.

## Table of Contents

- The invariant
- Staleness fields
- refresh_reserve
- refresh_obligation
- remaining_accounts validation
- Marking stale after mutation
- The transaction the client must build

---

## The invariant

Every state-changing action (deposit, borrow, repay, withdraw, liquidate) must be preceded, in the same transaction, by a refresh of every reserve and the obligation it touches. The refresh accrues interest and pulls current prices so the decision uses live data, never a stale slot.

The discipline is made self-enforcing by encoding freshness in the accounts: a mutating handler leaves the reserves it touched stale, so a second value-moving action in the same transaction sees a stale reserve and aborts. This makes same-transaction manipulation (act twice on one reserve before interest/price catches up) physically impossible.

---

## Staleness fields

Each reserve and obligation carries a `LastUpdate`:

```rust
#[zero_copy]
#[repr(C)]
pub struct LastUpdate {
    pub slot: u64,
    pub stale: u8,        // 1 = stale, 0 = fresh
    pub _padding: [u8; 7],
}

impl LastUpdate {
    pub fn new(slot: u64) -> Self {
        Self { slot, stale: 1, _padding: [0; 7] } // born stale
    }
    pub fn update_slot(&mut self, slot: u64) {
        self.slot = slot;
        self.stale = 0;
    }
    pub fn mark_stale(&mut self) {
        self.stale = 1;
    }
    pub fn is_fresh(&self, slot: u64) -> bool {
        self.slot == slot && self.stale == 0
    }
}
```

Freshness is "same slot AND not marked stale". A new account is born stale so it cannot be used before its first refresh.

---

## refresh_reserve

Accrues interest, pulls the current price, stamps fresh. The oracle account is pinned to the reserve.

```rust
#[derive(Accounts)]
pub struct RefreshReserve<'info> {
    #[account(mut)]
    pub reserve: AccountLoader<'info, Reserve>,

    #[account(
        seeds = [LENDING_MARKET_SEED, &lending_market.load()?.name],
        bump,
    )]
    pub lending_market: AccountLoader<'info, LendingMarket>,

    /// CHECK: pinned to the reserve's stored oracle pubkey
    #[account(address = reserve.load()?.oracle_pubkey @ LendingError::InvalidOracle)]
    pub oracle: UncheckedAccount<'info>,
}

pub fn process(ctx: Context<RefreshReserve>) -> Result<()> {
    let clock = Clock::get()?;
    let price_sf = read_and_validate_price(&ctx.accounts.oracle)?; // staleness + sanity inside
    let reserve = &mut ctx.accounts.reserve.load_mut()?;

    reserve.accrue_interest(clock.slot)?;          // compound since last update
    reserve.liquidity.market_price_sf = price_sf;  // fixed-point bits
    reserve.last_update.update_slot(clock.slot);   // now fresh for this slot
    Ok(())
}
```

After this runs, `reserve.last_update.is_fresh(clock.slot)` is true.

---

## refresh_obligation

Reads every reserve the obligation touches (via `remaining_accounts`), requires each fresh, recomputes the obligation's aggregate values, stamps it fresh. Needs the `'info` lifetime on the context to borrow `remaining_accounts`.

```rust
pub fn process<'info>(
    ctx: Context<'_, '_, 'info, 'info, RefreshObligation<'info>>,
) -> Result<()> {
    let clock = Clock::get()?;
    let obligation = &mut ctx.accounts.obligation.load_mut()?;

    let deposit_count = obligation.active_deposits_count();
    let borrow_count = obligation.active_borrows_count();
    require!(
        ctx.remaining_accounts.len() == deposit_count + borrow_count,
        LendingError::InvalidRemainingAccountLength
    );

    let mut total_deposited_value = Fraction::ZERO;
    let mut total_allowed_borrow_value = Fraction::ZERO;
    let mut total_unhealthy_value = Fraction::ZERO;
    let mut total_borrowed_value = Fraction::ZERO;

    // Deposits first, in stored order.
    for (i, deposit) in obligation.active_deposits().enumerate() {
        let reserve_ai = &ctx.remaining_accounts[i];
        require_keys_eq!(
            reserve_ai.key(), deposit.deposit_reserve,
            LendingError::InvalidReserveAccountOrder
        );
        let reserve = AccountLoader::<Reserve>::try_from(reserve_ai)?.load()?;
        require!(reserve.last_update.is_fresh(clock.slot), LendingError::NeedToRefreshReserve);

        let value = reserve.collateral_market_value(deposit.deposited_amount)?;
        total_deposited_value += value;
        total_allowed_borrow_value += value * Fraction::from_percent(reserve.config.loan_to_value_pct);
        total_unhealthy_value += value * Fraction::from_percent(reserve.config.liquidation_threshold_pct);
    }

    // Borrows next, in stored order.
    for (j, borrow) in obligation.active_borrows().enumerate() {
        let reserve_ai = &ctx.remaining_accounts[deposit_count + j];
        require_keys_eq!(
            reserve_ai.key(), borrow.borrow_reserve,
            LendingError::InvalidReserveAccountOrder
        );
        let reserve = AccountLoader::<Reserve>::try_from(reserve_ai)?.load()?;
        require!(reserve.last_update.is_fresh(clock.slot), LendingError::NeedToRefreshReserve);

        // Accrue this borrow to the reserve's current cumulative rate, then value it.
        let accrued = borrow.accrue_to(reserve.liquidity.cumulative_borrow_rate())?;
        total_borrowed_value += reserve.debt_market_value(accrued)?;
    }

    obligation.deposited_value_sf = total_deposited_value.to_bits();
    obligation.allowed_borrow_value_sf = total_allowed_borrow_value.to_bits();
    obligation.unhealthy_borrow_value_sf = total_unhealthy_value.to_bits();
    obligation.borrowed_assets_market_value_sf = total_borrowed_value.to_bits();
    obligation.last_update.update_slot(clock.slot);
    Ok(())
}
```

---

## remaining_accounts validation

`remaining_accounts` is attacker-controlled. Three checks, all mandatory:

1. **Length** equals active deposits + active borrows. Wrong length aborts.
2. **Order** matches the obligation's stored positions: deposits first in their stored order, then borrows in theirs.
3. **Identity** - each passed pubkey equals the `deposit_reserve` / `borrow_reserve` stored on the position.

Skipping any of these lets a caller feed a reserve that is not actually part of the obligation, or feed them in an order that mismatches the value math. The order requirement is why the client must build `remaining_accounts` deliberately, not from an unordered map.

---

## Marking stale after mutation

The other half of the invariant. Every handler that changes a reserve's liquidity or an obligation's positions marks the reserve stale at the end:

```rust
// at the tail of deposit / borrow / repay / withdraw / liquidate
reserve.last_update.mark_stale();
```

This is what makes a second action on the same reserve in the same transaction impossible without re-refreshing. If you add a new mutating handler and forget this line, you have opened a same-transaction manipulation hole - it is the easiest invariant to break by omission.

---

## The transaction the client must build

```
refresh_reserve(reserve_A)
refresh_reserve(reserve_B)        # one per reserve the obligation touches
refresh_obligation               # remaining_accounts = [reserve_A, reserve_B], deposit-then-borrow order
<action: deposit | borrow | repay | withdraw | liquidate>
```

If two actions are needed on the same reserve, each needs its own refresh sequence - they cannot share one because the first action marks the reserve stale.

The freshness primitive and the interest-accrual math behind `accrue_interest`: `solana-defi-math/references/staleness-and-accrual.md`.
