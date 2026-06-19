# Staking Account and CPI Model

Self-contained patterns. Adapt names to the host repo.

## Table of Contents

- Native stake-account actors
- Standalone staking protocol accounts
- Fixed stake-pool integrations
- Dynamic integrations
- Two-hop restaking
- PDA signer model
- Post-CPI verification

---

## Native stake-account actors

If a protocol touches the native Stake Program, keep these actors distinct:

- **stake authority** - can delegate, deactivate, split, merge in the ways the native program allows;
- **withdraw authority** - can withdraw inactive stake and change withdrawer authority;
- **lockup / custodian** - can gate early withdrawal depending on lockup rules;
- **vote account / validator** - the validator the stake is delegated to.

If your wrapper or staking protocol abstracts these away, that is fine, but the abstraction still has to preserve the underlying separation of powers. Do not model all of them as a single "admin".

---

## Standalone staking protocol accounts

The generic shape for a full staking protocol is:

```rust
#[account]
pub struct Config {
    pub authority: Pubkey,
    pub pending_authority: Option<Pubkey>,
    pub reward_admin: Option<Pubkey>,
    pub token_mint: Pubkey,
    pub reward_vault: Pubkey,
    pub is_paused: bool,
}

#[account]
pub struct StakingPool {
    pub total_staked: u128,
    pub reward_per_share_scaled: u128,
    pub cooldown_seconds: u64,
    pub min_stake_amount: u64,
}

#[account]
pub struct UserStake {
    pub owner: Pubkey,
    pub staked_amount: u64,
    pub reward_debt_scaled: u128,
    pub pending_rewards: u64,
}
```

Variants the refs show:

- `ValidatorStake` accounts for per-validator totals;
- `SolStakerStake` accounts coupling a user to native SOL stake;
- `RewardsEpoch` and `ClaimRecord` accounts for merkle-epoch reward claims;
- `UnbondingTicket` / `PendingUnstake` accounts for delayed-redemption staking.

The exact names differ, but the functional roles repeat.

---

## Fixed stake-pool integrations

For a known pool (for example a specific liquid staking pool), pin every required external account to a constant.

```rust
pub const JITO_POOL: Pubkey = pubkey!("...");
pub const JITO_WITHDRAW_AUTHORITY: Pubkey = pubkey!("...");
pub const JITO_RESERVE_ACCOUNT: Pubkey = pubkey!("...");
pub const JITO_FEE_ACCOUNT: Pubkey = pubkey!("...");
pub const JITO_SOL_MINT: Pubkey = pubkey!("...");

#[derive(Accounts)]
pub struct StakeWithPool<'info> {
    #[account(mut, address = JITO_POOL)]
    pub stake_pool: AccountInfo<'info>,
    #[account(address = JITO_WITHDRAW_AUTHORITY)]
    pub stake_pool_withdraw_authority: AccountInfo<'info>,
    #[account(mut, address = JITO_RESERVE_ACCOUNT)]
    pub stake_pool_reserve_account: AccountInfo<'info>,
    #[account(mut, address = JITO_FEE_ACCOUNT)]
    pub stake_pool_fee_account: AccountInfo<'info>,
    #[account(mut, address = JITO_SOL_MINT)]
    pub pool_mint: InterfaceAccount<'info, Mint>,
}
```

The point is to make fake-pool substitution impossible.

---

## Dynamic integrations

If the pool is chosen at runtime, gate it with an allow-list held in config and cross-check any derivative accounts against the pool state.

```rust
#[account(
    constraint = config.allowed_pools.contains(&pool.key()) @ StakingError::PoolNotAllowed,
)]
pub pool: AccountInfo<'info>,
```

The allow-list must be admin-controlled, not operator-controlled.

---

## Two-hop restaking

Some integrations are two-step: deposit SOL into a stake pool and receive an LST, then CPI into a restaking program with that LST. Model them as two independent constrained CPIs:

1. fixed or allow-listed stake-pool CPI;
2. fixed or allow-listed restaking CPI.

Do not treat the full restake flow as one trusted blob. Each hop has its own accounts, authority, and post-balance checks.

---

## PDA signer model

If the program or vault PDA owns the token account receiving the LST, that PDA signs the CPI:

```rust
let signer_seeds: &[&[&[u8]]] = &[&[VAULT_INFO_SEED, &[vault_info.bump]]];

solana_program::program::invoke_signed(
    &deposit_sol(/* ... */),
    &[/* external + local accounts */],
    signer_seeds,
)?;
```

The signer should only be used for accounts the PDA actually owns. Do not reuse the same PDA as an all-purpose signer across unrelated authorities.

---

## Post-CPI verification

After staking or redeeming, reload the token account and validate the actual balance delta. Do not assume the external protocol delivered the expected amount.

```rust
let before = vault_lst_ata.amount;
// CPI stake/redeem
vault_lst_ata.reload()?;
let after = vault_lst_ata.amount;
require!(after > before, StakingError::NoStakeTokensReceived);
```

For redeem/unstake, the verification may be on SOL/WSOL or on the intermediate token balance depending on the path.
