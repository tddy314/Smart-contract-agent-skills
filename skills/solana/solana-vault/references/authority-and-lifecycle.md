# Vault Authority and Lifecycle

Self-contained patterns. Adapt names to the host repo.

## Table of Contents

- The three roles
- Admin handlers
- Operator handlers and the allow-list
- User handlers (deposit / withdraw)
- The lock state machine
- Fee timing

---

## The three roles

A vault separates three privilege levels. Each handler's accounts struct encodes which role may call it. The directory layout (`admin/`, `operator/` or `bot_server/`, `user/`) becomes the visible authorization map.

| Role | Checked against | May do |
| --- | --- | --- |
| Admin (authority) | `config.authority` | init, configure, set fees, emergency withdraw |
| Operator (bot/agent) | `config.operator` | rebalance, open/close positions, swap, move funds between allow-listed pools |
| User | own signature + `UserInfo` PDA | deposit, withdraw own position |

The boundary that matters: the operator can move pooled funds but must not be able to change config or fees, and must not move funds outside the allow-list or to itself.

---

## Admin handlers

Admin is checked with `has_one` or an `address` constraint against the stored authority. Make config updates use `Option<T>` so only supplied fields change.

```rust
#[derive(Accounts)]
pub struct Configure<'info> {
    #[account(mut, address = config.authority)]
    pub authority: Signer<'info>,

    #[account(mut, seeds = [CONFIG_SEED], bump)]
    pub config: Account<'info, Config>,
}

pub fn configure(
    ctx: Context<Configure>,
    operator: Option<Pubkey>,
    fee_wallet: Option<Pubkey>,
    management_fee_per_1e6: Option<u64>,
    performance_fee_percent: Option<u64>,
) -> Result<()> {
    let config = &mut ctx.accounts.config;
    if let Some(value) = operator { config.operator = value; }
    if let Some(value) = fee_wallet { config.fee_wallet = value; }
    if let Some(value) = management_fee_per_1e6 { config.management_fee_per_1e6 = value; }
    if let Some(value) = performance_fee_percent { config.performance_fee_percent = value; }
    Ok(())
}
```

Note the `config` is seed-derived here. A real anti-pattern is loading config in `configure` as a bare `#[account(mut)]` without seeds while every other handler uses seeds - keep it consistent so the same account is always addressed the same way.

---

## Operator handlers and the allow-list

The operator executes the strategy. Two constraints are mandatory: the signer is the configured operator, and any pool it touches is on the allow-list.

```rust
#[derive(Accounts)]
pub struct Rebalance<'info> {
    #[account(
        constraint = operator.key() == config.operator @ VaultError::Unauthorized,
    )]
    pub operator: Signer<'info>,

    #[account(seeds = [CONFIG_SEED], bump)]
    pub config: Account<'info, Config>,

    #[account(
        mut,
        seeds = [VAULT_INFO_SEED],
        bump = vault_info.bump,
    )]
    pub vault_info: Account<'info, VaultInfo>,

    /// The external pool the operator wants to deploy into.
    #[account(
        constraint = config.allowed_pools.contains(&pool.key()) @ VaultError::PoolNotAllowed,
    )]
    pub pool: AccountInfo<'info>,
}
```

Without the `allowed_pools` check, an operator (or anyone who reaches the handler) can point the vault at an arbitrary pool and drain it through a "legitimate" strategy call. The allow-list is the boundary that makes operator power safe.

An intentional admin fallback is fine - letting `authority` also pass an operator gate (`operator.key() == config.operator || operator.key() == config.authority`) - but document it; it gives admin operational power beyond config.

---

## User handlers (deposit / withdraw)

Users deposit a token and receive integer shares; they withdraw by burning shares. Share math is in `solana-defi-math/references/shares-and-exchange-rate.md`; here is the handler shape.

```rust
pub fn deposit(ctx: Context<Deposit>, amount: u64) -> Result<()> {
    let vault = &mut ctx.accounts.vault_info;
    require!(!vault.is_locked, VaultError::VaultLocked);
    require!(amount > 0, VaultError::ZeroAmount);

    // prorated management fee taken here; see fee timing below and fees.md

    let total_value = current_pool_value(&ctx)?; // value the vault controls, pre-deposit
    let shares = if vault.total_shares == 0 {
        u128::from(amount) // first deposit: 1:1
    } else {
        // multiply before divide, u128 intermediate, round DOWN to the user
        u128::from(amount)
            .checked_mul(vault.total_shares).ok_or(VaultError::MathOverflow)?
            .checked_div(u128::from(total_value)).ok_or(VaultError::MathOverflow)?
    };

    // move tokens in (user -> vault token account), then:
    let user = &mut ctx.accounts.user_info;
    user.share = user.share.checked_add(shares).ok_or(VaultError::MathOverflow)?;
    user.deposited_amount = user.deposited_amount.checked_add(amount).ok_or(VaultError::MathOverflow)?;
    vault.total_shares = vault.total_shares.checked_add(shares).ok_or(VaultError::MathOverflow)?;
    Ok(())
}
```

Withdraw is the mirror: compute `assets_out = shares_burned * total_value / total_shares` rounded **down**, apply the performance fee on any profit, move tokens out via a PDA-signed transfer, decrement `user.share` and `vault.total_shares`. Round shares to the user down in both directions so the vault never over-issues on deposit or over-pays on withdraw.

---

## The lock state machine

Multi-step flows that leave the pool transiently inconsistent must take the lock so user operations cannot interleave.

```rust
// Entry of a multi-step operator flow:
require!(!vault.is_locked, VaultError::VaultLocked);
vault.is_locked = true;
// ... step 1 (e.g. decrease liquidity via CPI) ...
// ... step 2 (e.g. swap via CPI) ...
vault.is_locked = false; // ALWAYS reached on the success path
```

Two failure modes to check for:

- **An operation that should take the lock but does not** - a user deposit landing mid-rebalance sees a half-updated pool and mints the wrong share count.
- **A path that sets the lock without clearing it** - a stuck lock bricks the vault permanently. Every `is_locked = true` needs a guaranteed `is_locked = false` on every path that returns `Ok`. If a flow spans multiple transactions, provide an admin recovery to clear a stuck lock.

The lock is both the reentrancy guard and the consistency guard. Confirm both properties when reviewing.

---

## Fee timing

**Management fee at deposit** is prorated to the remaining fraction of the fee period, so a late depositor pays less. **Periodic collection** by the admin is gated on a timer that must be initialized.

```rust
// The timer MUST be set at init. Left at zero, this check passes from genesis:
require!(
    now >= config.next_fee_collection_time,
    VaultError::FeeNotDue
);
// ... collect fee ...
config.next_fee_collection_time = config
    .next_fee_collection_time
    .checked_add(FEE_PERIOD)
    .ok_or(VaultError::MathOverflow)?;
```

**Performance fee at withdraw** is charged on profit only, using the cost basis stored in `UserInfo`:

```rust
let performance_fee = if withdraw_value > user.deposited_amount {
    (withdraw_value - user.deposited_amount)
        .checked_mul(config.performance_fee_percent).ok_or(VaultError::MathOverflow)?
        / 100
} else {
    0
};
```

Proration math and fee-rate scaling: `solana-defi-math/references/fees.md`.
