# Lending Lifecycle Handlers

Self-contained patterns. Adapt names to the host repo. Each handler assumes the refresh sequence already ran in the same transaction (see `refresh-pattern.md`).

## Table of Contents

- Shape of a handler
- Deposit / supply
- Borrow
- Repay
- Withdraw / redeem
- Liquidate
- PDA-signed vault transfers
- Events

---

## Shape of a handler

Every lifecycle handler follows the same skeleton:

1. Load accounts; require obligation and touched reserve(s) fresh for the current slot.
2. Run the math (in `solana-defi-math` terms) to get amounts.
3. Check the relevant invariant (limit, health, ownership).
4. Move tokens via PDA-signed CPI.
5. Update reserve and obligation state.
6. Mark the reserve stale.
7. Emit an event.

The freshness require at the top and the `mark_stale` at the bottom are non-negotiable - they are what make the refresh invariant hold.

---

## Deposit / supply

User supplies liquidity, receives collateral tokens (cTokens), and optionally records them as obligation collateral.

```rust
pub fn process(ctx: Context<DepositReserveLiquidity>, liquidity_amount: u64) -> Result<()> {
    let clock = Clock::get()?;
    require!(liquidity_amount > 0, LendingError::InvalidAmount);

    let reserve = &mut ctx.accounts.reserve.load_mut()?;
    require!(reserve.last_update.is_fresh(clock.slot), LendingError::NeedToRefreshReserve);
    require!(reserve.config.is_paused == 0, LendingError::ReservePaused);

    // cTokens minted = liquidity / exchange_rate, rounded DOWN to the user.
    let exchange_rate = reserve.collateral_exchange_rate()?;
    let collateral_amount = exchange_rate.liquidity_to_collateral(liquidity_amount)?;

    // Enforce the reserve deposit limit on the new total.
    let new_total = reserve.liquidity.total_supply()?.checked_add(liquidity_amount.into())
        .ok_or(LendingError::MathOverflow)?;
    require!(new_total <= reserve.config.deposit_limit.into(), LendingError::DepositLimitExceeded);

    reserve.liquidity.deposit(liquidity_amount)?;
    reserve.collateral.mint(collateral_amount)?;

    // user -> reserve vault (user signs; no PDA needed for the inbound transfer)
    transfer_checked_from_user(
        &ctx.accounts.token_program,
        &ctx.accounts.user_liquidity_ata,
        &ctx.accounts.liquidity_mint,
        &ctx.accounts.reserve_liquidity_vault,
        &ctx.accounts.user,
        liquidity_amount,
        ctx.accounts.liquidity_mint.decimals,
    )?;

    // reserve PDA mints cTokens to the user (or to the collateral vault if used as collateral)
    mint_collateral_with_signer(/* reserve signer seeds */, collateral_amount)?;

    reserve.last_update.mark_stale();
    emit!(DepositEvent { reserve: ctx.accounts.reserve.key(), liquidity_amount, collateral_amount });
    Ok(())
}
```

Rounding: `liquidity_to_collateral` rounds **down** so the user never gets more cTokens than the liquidity backs.

---

## Borrow

User borrows against deposited collateral. The gate is allowed-borrow-value, computed at refresh.

```rust
pub fn process(ctx: Context<BorrowLiquidity>, borrow_amount: u64) -> Result<()> {
    let clock = Clock::get()?;
    let obligation = &mut ctx.accounts.obligation.load_mut()?;
    let reserve = &mut ctx.accounts.reserve.load_mut()?;

    require!(reserve.last_update.is_fresh(clock.slot), LendingError::NeedToRefreshReserve);
    require!(obligation.last_update.is_fresh(clock.slot), LendingError::NeedToRefreshObligation);

    require!(reserve.liquidity.available_amount >= borrow_amount, LendingError::InsufficientLiquidity);

    // Value the new borrow and check it against remaining allowed borrow value.
    let borrow_value = reserve.debt_market_value(borrow_amount)?;
    let already_borrowed = Fraction::from_bits(obligation.borrowed_assets_market_value_sf);
    let allowed = Fraction::from_bits(obligation.allowed_borrow_value_sf);
    require!(already_borrowed + borrow_value <= allowed, LendingError::BorrowTooLarge);

    // Record debt with the reserve's CURRENT cumulative rate as the interest baseline.
    obligation.add_or_update_borrow(
        ctx.accounts.reserve.key(),
        borrow_amount,
        reserve.liquidity.cumulative_borrow_rate(),
    )?;
    reserve.liquidity.borrow(borrow_amount)?;

    // reserve vault -> user, PDA-signed (the reserve authority is a PDA)
    let market_key = ctx.accounts.lending_market.key();
    let mint_key = ctx.accounts.liquidity_mint.key();
    let signer_seeds: &[&[&[u8]]] = &[&[
        RESERVE_SEED, market_key.as_ref(), mint_key.as_ref(), &[reserve.bump_seed],
    ]];
    transfer_checked_with_signer(
        &ctx.accounts.token_program,
        &ctx.accounts.reserve_liquidity_vault,
        &ctx.accounts.liquidity_mint,
        &ctx.accounts.user_liquidity_ata,
        &ctx.accounts.reserve_authority,
        signer_seeds,
        borrow_amount,
        ctx.accounts.liquidity_mint.decimals,
    )?;

    reserve.last_update.mark_stale();
    emit!(BorrowEvent { obligation: ctx.accounts.obligation.key(), reserve: ctx.accounts.reserve.key(), borrow_amount });
    Ok(())
}
```

The accounts struct for this handler:

```rust
#[derive(Accounts)]
pub struct BorrowLiquidity<'info> {
    #[account(mut)]
    pub user: Signer<'info>,

    #[account(
        mut,
        seeds = [OBLIGATION_SEED, lending_market.key().as_ref(), user.key().as_ref()],
        bump,
    )]
    pub obligation: AccountLoader<'info, Obligation>,

    #[account(seeds = [LENDING_MARKET_SEED, &lending_market.load()?.name], bump)]
    pub lending_market: AccountLoader<'info, LendingMarket>,

    #[account(
        mut,
        seeds = [RESERVE_SEED, lending_market.key().as_ref(), liquidity_mint.key().as_ref()],
        bump,
    )]
    pub reserve: AccountLoader<'info, Reserve>,

    #[account(address = reserve.load()?.liquidity.mint_pubkey)]
    pub liquidity_mint: Box<InterfaceAccount<'info, Mint>>,

    #[account(mut, associated_token::mint = liquidity_mint, associated_token::authority = reserve_authority)]
    pub reserve_liquidity_vault: Box<InterfaceAccount<'info, TokenAccount>>,

    #[account(mut, associated_token::mint = liquidity_mint, associated_token::authority = user)]
    pub user_liquidity_ata: Box<InterfaceAccount<'info, TokenAccount>>,

    /// CHECK: reserve authority PDA, validated by seeds
    pub reserve_authority: UncheckedAccount<'info>,
    pub token_program: Interface<'info, TokenInterface>,
}
```

---

## Repay

User repays debt; round the required amount **up** so the reserve is never short.

```rust
pub fn process(ctx: Context<RepayLiquidity>, repay_amount: u64) -> Result<()> {
    let clock = Clock::get()?;
    let obligation = &mut ctx.accounts.obligation.load_mut()?;
    let reserve = &mut ctx.accounts.reserve.load_mut()?;
    require!(reserve.last_update.is_fresh(clock.slot), LendingError::NeedToRefreshReserve);
    require!(obligation.last_update.is_fresh(clock.slot), LendingError::NeedToRefreshObligation);

    let borrow = obligation.find_borrow_mut(ctx.accounts.reserve.key())?;
    let outstanding = borrow.accrued_debt(reserve.liquidity.cumulative_borrow_rate())?;

    // Cap at outstanding; settlement amount rounds UP.
    let settle = repay_amount.min(outstanding.to_ceil());

    // user -> reserve vault (user signs)
    transfer_checked_from_user(/* ... */, settle, ctx.accounts.liquidity_mint.decimals)?;

    reserve.liquidity.repay(settle)?;
    borrow.repay(settle)?;
    if borrow.is_zero() { obligation.remove_borrow(ctx.accounts.reserve.key())?; }

    reserve.last_update.mark_stale();
    emit!(RepayEvent { obligation: ctx.accounts.obligation.key(), reserve: ctx.accounts.reserve.key(), amount: settle });
    Ok(())
}
```

---

## Withdraw / redeem

User redeems collateral; the post-withdraw obligation must stay healthy.

```rust
pub fn process(ctx: Context<WithdrawCollateral>, collateral_amount: u64) -> Result<()> {
    let clock = Clock::get()?;
    let obligation = &mut ctx.accounts.obligation.load_mut()?;
    let reserve = &mut ctx.accounts.reserve.load_mut()?;
    require!(reserve.last_update.is_fresh(clock.slot), LendingError::NeedToRefreshReserve);
    require!(obligation.last_update.is_fresh(clock.slot), LendingError::NeedToRefreshObligation);

    // Liquidity returned = collateral * exchange_rate, rounded DOWN to the user.
    let exchange_rate = reserve.collateral_exchange_rate()?;
    let liquidity_amount = exchange_rate.collateral_to_liquidity(collateral_amount)?;

    // Health check: removing this collateral must not push borrowed value above allowed value.
    let collateral_value = reserve.collateral_market_value(collateral_amount)?;
    let ltv_pct = Fraction::from_percent(reserve.config.loan_to_value_pct);
    let new_allowed = Fraction::from_bits(obligation.allowed_borrow_value_sf)
        .checked_sub(collateral_value * ltv_pct)
        .ok_or(LendingError::MathOverflow)?;
    let borrowed = Fraction::from_bits(obligation.borrowed_assets_market_value_sf);
    require!(borrowed <= new_allowed, LendingError::WithdrawTooLarge);

    reserve.collateral.burn(collateral_amount)?;
    reserve.liquidity.withdraw(liquidity_amount)?;
    obligation.withdraw_collateral(ctx.accounts.reserve.key(), collateral_amount)?;

    // burn cTokens (PDA), then reserve vault -> user (PDA-signed)
    burn_collateral_with_signer(/* reserve signer seeds */, collateral_amount)?;
    transfer_checked_with_signer(/* reserve vault -> user */, liquidity_amount, ctx.accounts.liquidity_mint.decimals)?;

    reserve.last_update.mark_stale();
    emit!(WithdrawEvent { /* ... */ });
    Ok(())
}
```

---

## Liquidate

The protocol's safety mechanism and the highest-review handler. A liquidator repays some debt and seizes collateral plus a bonus, only when the obligation is unhealthy.

```rust
pub fn process(ctx: Context<Liquidate>, repay_amount: u64) -> Result<()> {
    let clock = Clock::get()?;
    let obligation = &mut ctx.accounts.obligation.load_mut()?;
    let debt_reserve = &mut ctx.accounts.debt_reserve.load_mut()?;
    let collateral_reserve = &mut ctx.accounts.collateral_reserve.load_mut()?;

    require!(debt_reserve.last_update.is_fresh(clock.slot), LendingError::NeedToRefreshReserve);
    require!(collateral_reserve.last_update.is_fresh(clock.slot), LendingError::NeedToRefreshReserve);
    require!(obligation.last_update.is_fresh(clock.slot), LendingError::NeedToRefreshObligation);

    // The position MUST be unhealthy. Reject otherwise.
    let ltv = obligation.loan_to_value();
    let unhealthy = Fraction::from_bits(obligation.unhealthy_borrow_value_sf)
        / Fraction::from_bits(obligation.deposited_value_sf);
    require!(ltv >= unhealthy, LendingError::CannotLiquidateHealthyObligation);

    // Math (see solana-defi-math/references/liquidation-math.md): settle/repay/withdraw + bonus.
    let result = calculate_liquidation(
        collateral_reserve, debt_reserve, repay_amount,
        &ctx.accounts.lending_market.load()?, obligation, /* liquidity, collateral, index */
    )?;

    // liquidator repays debt -> debt reserve vault (liquidator signs)
    transfer_checked_from_user(/* ... */, result.repay_amount, ctx.accounts.debt_mint.decimals)?;
    debt_reserve.liquidity.repay(result.repay_amount)?;
    obligation.repay_borrow(ctx.accounts.debt_reserve.key(), result.settle_amount)?;

    // collateral reserve vault -> liquidator, PDA-signed (the seized collateral + bonus)
    transfer_checked_with_signer(/* collateral vault -> liquidator */, result.withdraw_amount, ctx.accounts.collateral_mint.decimals)?;
    obligation.withdraw_collateral(ctx.accounts.collateral_reserve.key(), result.withdraw_amount)?;

    debt_reserve.last_update.mark_stale();
    collateral_reserve.last_update.mark_stale();
    emit!(LiquidateEvent { /* ... */ });
    Ok(())
}
```

The four things a reviewer checks here, in order:

1. **Account validation** - the debt reserve, collateral reserve, obligation, and the liquidator's token accounts are all constrained; the obligation's positions actually reference these reserves.
2. **Health gate** - a healthy obligation is rejected (`CannotLiquidateHealthyObligation`).
3. **Rounding** - seize and repay amounts round so the protocol and remaining depositors are never shortchanged; the liquidator's bonus is bounded.
4. **Dust** - a position below the minimum-net-value threshold is fully liquidated, not left as un-liquidatable dust.

---

## PDA-signed vault transfers

Inbound transfers (user → vault) are signed by the user. Outbound transfers (vault → user) are signed by the reserve authority PDA. Centralize both in a `token_transfer` helper module so signer-seed handling lives in one reviewed place. The signer seeds for a reserve-authority PDA:

```rust
let signer_seeds: &[&[&[u8]]] = &[&[
    RESERVE_SEED,
    lending_market_key.as_ref(),
    liquidity_mint_key.as_ref(),
    &[reserve.bump_seed],
]];
```

Use `transfer_checked` (mint + decimals) for all liquidity moves. See `solana-anchor/references/pda-and-cpi.md` for the signer-seed nesting hazard.

---

## Events

Emit an event on every state-changing handler so offchain indexers can reconstruct positions and the protocol can be monitored. Include the obligation, the reserve(s), the amounts, and (for liquidation) the bonus. Use `event-cpi` (the `emit_cpi!` macro) if the repo needs events that survive CPI, otherwise `emit!`.
