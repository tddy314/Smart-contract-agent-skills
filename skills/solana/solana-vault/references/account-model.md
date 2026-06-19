# Vault Account Model

Self-contained patterns. Adapt names to the host repo. Every financial field is an integer - no `f64`, ever.

## Table of Contents

- Config (singleton)
- VaultInfo
- UserInfo
- PDA seeds
- The integer-only discipline

---

## Config (singleton)

Global configuration and authority. Holds no per-user state and no tokens.

```rust
#[account]
pub struct Config {
    pub authority: Pubkey,          // admin - highest privilege, prefer a multisig
    pub operator: Pubkey,           // bot/agent that executes the strategy
    pub fee_wallet: Pubkey,         // where fees are sent
    pub allowed_pools: Vec<Pubkey>, // strategies/pools the operator may use (cap the length)
    pub management_fee_per_1e6: u64,    // e.g. 1_000 = 0.1% per period
    pub performance_fee_percent: u64,   // e.g. 20 = 20% of profit
    pub next_fee_collection_time: u64,  // MUST be initialized (see fees discipline)
}
```

`allowed_pools` is a bounded `Vec` - fix its maximum and size the account for it. An unbounded list is a rent and a reallocation problem.

Take `authority` and `operator` from instruction arguments at init. Do not bake a pubkey into the program:

```rust
// WRONG - non-redeployable, one-deployment-only:
#[account(address = pubkey!("99Txx..."))]
pub authority: Signer<'info>,

// RIGHT - authority supplied at init, stored in config:
pub fn initialize(ctx: Context<Initialize>, operator: Pubkey, fee_wallet: Pubkey, /* ... */) -> Result<()> {
    let config = &mut ctx.accounts.config;
    config.authority = ctx.accounts.authority.key(); // the signer who initialized
    config.operator = operator;
    config.fee_wallet = fee_wallet;
    config.next_fee_collection_time = Clock::get()?.unix_timestamp as u64 + FEE_PERIOD;
    Ok(())
}
```

---

## VaultInfo

Per-vault (or per-strategy-position) state: the strategy identity, the aggregate position in integer share units, the lock, and reserve balances held between operations.

```rust
#[account]
pub struct VaultInfo {
    pub bump: u8,
    pub pool: Pubkey,           // current strategy/pool this vault is deployed into
    pub total_shares: u128,     // INTEGER share units - the denominator of every ownership calc
    pub is_locked: bool,        // multi-step-operation guard
    pub reserve_amount: u64,    // tokens held in the vault between operations
}
```

`total_shares` is the value most often mis-typed as `f64` in real vaults. It must be an integer. The whole ownership model is `user_shares / total_shares`; if this is a float, the model is non-deterministic.

Do not leave abandoned fields. A `pub total_sol_fee: u64 // abandon` wastes space and confuses readers - remove it and migrate the account.

---

## UserInfo

Per-user position: integer shares and the cost basis for performance fees. PDA-derived from the user key so it cannot be forged or shared.

```rust
#[account]
pub struct UserInfo {
    pub share: u128,            // INTEGER - this user's share balance
    pub deposited_amount: u64,  // cost basis in token units, for performance-fee calculation
    pub reserve_amount: u64,    // tokens credited to the user awaiting claim
}
```

`deposited_amount` is what makes a performance-fee-on-profit-only calculation possible: at withdraw you compare the value returned against what they put in.

Create with `init_if_needed` so users do not need a separate account-creation step - re-initialization is harmless here because the PDA is per-user and the fields start at zero:

```rust
#[account(
    init_if_needed,
    payer = user,
    space = 8 + UserInfo::INIT_SPACE,
    seeds = [USER_INFO_SEED, user.key().as_ref()],
    bump,
)]
pub user_info: Account<'info, UserInfo>,
```

---

## PDA seeds

Name seeds clearly; user accounts include the user key so each user gets a distinct PDA.

```rust
pub const CONFIG_SEED: &[u8]     = b"config";
pub const VAULT_INFO_SEED: &[u8] = b"vault_info";
pub const USER_INFO_SEED: &[u8]  = b"user_info"; // + user.key()
```

Watch for typos in constant names (a real repo shipped `USER_INF0_SEED` with a zero). The byte string is what matters functionally, but a wrong name misleads every future reader.

The vault PDA (derived from `VAULT_INFO_SEED`) is the authority that signs CPI to move tokens out of vault-owned token accounts. Store its bump and reuse it for signing.

---

## The integer-only discipline

A checklist for any vault account:

- No field is `f32` or `f64`. Shares, totals, reserves, fees - all integers.
- Share fields are `u128` (room for a large scaled supply); token amounts are `u64` (native token unit range).
- A `bump: u8` is stored for any account whose PDA signs CPI.
- `allowed_pools` (or equivalent) is a length-bounded `Vec`.
- No abandoned/placeholder fields.
- The fee-collection timer field exists and is set at init.

If an existing vault violates the no-float rule, that is a finding: flag it as SECURITY-REVIEW, do not extend it, and propose the `u128` share representation from `solana-defi-math/references/shares-and-exchange-rate.md`.
