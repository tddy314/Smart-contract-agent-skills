# Vault External Protocol CPI

Self-contained patterns. Adapt names to the host repo. A vault's job is deploying funds into an external protocol - this is the largest attack surface, so every account and program in the CPI must be constrained.

## Table of Contents

- The threat
- Constraining the external program
- Fixed integrations: hardcoded constants
- Dynamic targets: allow-lists
- Cross-referencing derived accounts
- PDA-signed CPI
- reload() and post-CPI validation

---

## The threat

A CPI hands control and accounts to another program. If the vault does not constrain which program runs and which accounts it touches, an attacker (or a compromised/buggy operator path) can:

- redirect the CPI to a malicious program that drains the vault's token accounts,
- substitute a fake pool whose "deposit" simply transfers funds away,
- mix accounts from two different pools so the math is computed against one and tokens move from another.

Every constraint below closes one of these.

---

## Constraining the external program

The program account itself must be pinned. Anchor's typed `Program<'info, T>` validates the program ID for you:

```rust
pub stake_pool_program: Program<'info, SplStakePool>,
```

For raw `invoke_signed` where there is no typed wrapper, assert the address explicitly:

```rust
#[account(address = spl_stake_pool::id())]
pub stake_pool_program: AccountInfo<'info>,
```

An unconstrained `AccountInfo` program account is the single most dangerous omission in a vault - it is direct program substitution.

---

## Fixed integrations: hardcoded constants

When the vault integrates one specific external protocol (a particular liquid-staking pool), pin every account it needs to a named constant. This eliminates fake-pool substitution entirely - there is no runtime choice to attack.

```rust
pub const JITO_STAKE_POOL: Pubkey = pubkey!("Jito...");
pub const JITO_STAKE_POOL_WITHDRAW_AUTHORITY: Pubkey = pubkey!("...");
pub const JITO_STAKE_POOL_RESERVE: Pubkey = pubkey!("...");
pub const JITO_STAKE_POOL_FEE_ACCOUNT: Pubkey = pubkey!("...");

#[derive(Accounts)]
pub struct DeployToJito<'info> {
    #[account(mut, address = JITO_STAKE_POOL)]
    pub stake_pool: AccountInfo<'info>,
    #[account(address = JITO_STAKE_POOL_WITHDRAW_AUTHORITY)]
    pub withdraw_authority: AccountInfo<'info>,
    #[account(mut, address = JITO_STAKE_POOL_RESERVE)]
    pub reserve: AccountInfo<'info>,
    #[account(mut, address = JITO_STAKE_POOL_FEE_ACCOUNT)]
    pub fee_account: AccountInfo<'info>,
    // ...
}
```

Comment each constant with what it is and where it came from (the protocol's published addresses), so a reviewer can verify them.

---

## Dynamic targets: allow-lists

When the operator chooses among several pools at runtime, you cannot hardcode - but you must still gate. Check the chosen pool against the admin-maintained allow-list:

```rust
#[account(
    constraint = config.allowed_pools.contains(&pool_state.key()) @ VaultError::PoolNotAllowed,
)]
pub pool_state: AccountLoader<'info, PoolState>,
```

The allow-list is admin-controlled config, not operator-controlled. The operator picks *within* a set the admin approved; it cannot add to that set.

---

## Cross-referencing derived accounts

Even with the right pool, the satellite accounts (the pool's config, its token vaults, its observation account) must be the ones that actually belong to that pool - not accounts from a different pool that would make the math lie. Tie them to the loaded pool state:

```rust
#[account(address = pool_state.load()?.amm_config)]
pub amm_config: AccountInfo<'info>,

#[account(mut, address = pool_state.load()?.observation_key)]
pub observation_state: AccountInfo<'info>,

#[account(
    mut,
    constraint = token_vault_0.key() == pool_state.load()?.token_vault_0 @ VaultError::WrongVault,
)]
pub token_vault_0: InterfaceAccount<'info, TokenAccount>,
```

For external PDAs (a CLMM's position or tick arrays), validate them with the external program's seeds via `seeds::program`:

```rust
#[account(
    seeds = [POSITION_SEED, pool_state.key().as_ref()],
    bump,
    seeds::program = clmm_program.key(),
)]
pub position: AccountInfo<'info>,
```

This proves the account is the real PDA the external program expects, derived under the external program's ID.

---

## PDA-signed CPI

The vault PDA is the authority over the vault's token accounts, so it signs the CPI. Pass its seeds (including the stored bump) as signer seeds:

```rust
let vault_bump = ctx.accounts.vault_info.bump;
let signer_seeds: &[&[&[u8]]] = &[&[VAULT_INFO_SEED, &[vault_bump]]];

let cpi_context = CpiContext::new_with_signer(
    ctx.accounts.stake_pool_program.to_account_info(),
    stake_pool_cpi_accounts,
    signer_seeds,
);
deposit_sol(cpi_context, amount)?;
```

Mind the `&[&[&[u8]]]` nesting - see `solana-anchor/references/pda-and-cpi.md`.

---

## reload() and post-CPI validation

After a CPI changes balances, the in-memory copies are stale. Reload before reading, and verify the operation actually did what was asked.

```rust
// Before CPI: snapshot what we expect to change.
let before = ctx.accounts.vault_token_account.amount;

// ... CPI that should deploy `amount` ...

ctx.accounts.vault_token_account.reload()?;
let after = ctx.accounts.vault_token_account.amount;

// Validate the outcome - do not assume the CPI fully succeeded.
let deployed = before.checked_sub(after).ok_or(VaultError::MathOverflow)?;
require!(
    deployed >= amount.checked_mul(95).unwrap() / 100, // e.g. at least 95% deployed
    VaultError::IncompleteDeployment
);
```

A CPI that silently deploys less than requested (a partial fill, a pool at capacity) should be caught here, not assumed successful - otherwise the vault's share math counts value that was never actually deployed.
