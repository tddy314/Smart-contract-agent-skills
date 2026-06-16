# Account Validation Catalog

Most Anchor exploits are account-substitution attacks: the program's logic is correct, but it ran on accounts the attacker chose. Each constraint below closes a specific substitution. When writing or reviewing a handler, walk this list against the `#[derive(Accounts)]` struct.

## Table of Contents

- Account types and what they check
- Signer and authority
- PDA seeds and bump
- Token account mint and authority
- CPI target program
- Cross-referenced accounts
- remaining_accounts
- init, init_if_needed, close
- Duplicate mutable accounts
- Worked example

---

## Account types and what they check

- `Signer<'info>` - the account signed the transaction. No ownership/type check.
- `Account<'info, T>` - deserializes `T`, checks the account is owned by this program and the 8-byte discriminator matches.
- `InterfaceAccount<'info, TokenAccount>` / `Mint` - like `Account` but accepts either the Classic Token Program or Token Extensions. Use this for token accounts and mints unless the repo deliberately pins one program.
- `AccountLoader<'info, T>` - zero-copy account; access via `.load()?` / `.load_mut()?`. Used for large or array-heavy state.
- `Program<'info, T>` - validates the account is the program with `T`'s ID. Use for CPI targets.
- `SystemAccount<'info>` - owned by the System Program.
- `UncheckedAccount<'info>` / `AccountInfo<'info>` - no checks at all. Every use must be justified and the account constrained another way (`address = ...`, or seeds). Treat an unconstrained `UncheckedAccount` as a red flag.

## Signer and authority

A signer constraint proves who signed, not who is allowed. For privileged actions, bind the signer to stored authority.

```rust
#[account(mut)]
pub authority: Signer<'info>,

#[account(
    mut,
    seeds = [CONFIG_SEED],
    bump = config.bump,
    has_one = authority,   // config.authority must equal authority.key()
)]
pub config: Account<'info, Config>,
```

`has_one = authority` checks `config.authority == authority.key()`. Equivalent inline form: `constraint = signer.key() == config.authority @ MyError::Unauthorized`. Without this, any signer can invoke an admin instruction.

For an operator role (bot, liquidator, agent) bound to a config field:

```rust
#[account(constraint = bot_server.key() == config.vault_bot_server @ MyError::Unauthorized)]
pub bot_server: Signer<'info>,
```

Take authority as an init argument or from the signer. Do not hardcode a deployer pubkey (`address = pubkey!("99Tx...")`) in `initialize` - it makes the program non-reusable.

## PDA seeds and bump

Seeds must uniquely and completely identify the account. Store the bump at init and reuse it.

```rust
// init
#[account(
    init, payer = user,
    space = 8 + Offer::INIT_SPACE,
    seeds = [b"offer", maker.key().as_ref(), id.to_le_bytes().as_ref()],
    bump,
)]
pub offer: Account<'info, Offer>,
// ...later store it: offer.bump = context.bumps.offer;

// subsequent calls - use the stored canonical bump
#[account(
    mut,
    has_one = maker,
    seeds = [b"offer", maker.key().as_ref(), offer.id.to_le_bytes().as_ref()],
    bump = offer.bump,
)]
pub offer: Account<'info, Offer>,
```

Using `bump = offer.bump` pins the canonical bump (saves compute and prevents an attacker from supplying a different valid bump for a non-canonical address). Expose instruction args in seeds with `#[instruction(id: u64)]` on the accounts struct.

## Token account mint and authority

A token account argument with no mint/authority constraint can be any token account the attacker controls.

```rust
#[account(
    mut,
    associated_token::mint = liquidity_mint,
    associated_token::authority = reserve,
    associated_token::token_program = token_program,
)]
pub reserve_liquidity_supply: InterfaceAccount<'info, TokenAccount>,
```

- `mint = ...` - without it, an attacker passes a token account for a worthless mint and drains the real one.
- `authority = ...` - ties the account to its expected owner (a user, or a PDA).
- For arbitrary (non-ATA) token accounts use `token::mint` / `token::authority`.

## CPI target program

```rust
// Anchor program account: ID validated by the type
pub token_program: Interface<'info, TokenInterface>,
pub clmm_program: Program<'info, RaydiumClmm>,

// raw CPI to a fixed external program: pin the address
#[account(address = spl_stake_pool::id())]
pub stake_pool_program: UncheckedAccount<'info>,
```

Without this, a CPI can be redirected to an attacker program that mimics the expected interface.

## Cross-referenced accounts

When several accounts must be consistent with one loaded account (a pool and its config/vaults/observation), constrain the dependents against the loaded state instead of trusting the caller to pass a matching set.

```rust
#[account(constraint = allowed_pools.contains(&pool_state.key()))]
pub pool_state: AccountLoader<'info, PoolState>,

#[account(address = pool_state.load()?.amm_config)]
pub amm_config: Account<'info, AmmConfig>,

#[account(constraint = token_vault_0.key() == pool_state.load()?.token_vault_0)]
pub token_vault_0: InterfaceAccount<'info, TokenAccount>,
```

This prevents an attacker from passing a real pool but mismatched vaults.

## remaining_accounts

`ctx.remaining_accounts` is a raw, unvalidated slice. Anchor does no checks. Before using it:

- Validate the length against an expected count, returning a custom error.
- Validate the order - if positions correspond to stored entries, check each pubkey against the expected value (`InvalidReserveAccountOrder`-style error).
- Deserialize with discriminator checks (a helper that verifies `data[..8] == T::DISCRIMINATOR` before `try_deserialize`).

```rust
require!(
    ctx.remaining_accounts.len() == expected_count,
    MyError::InvalidRemainingAccountLength
);
for (account, expected) in ctx.remaining_accounts.iter().zip(expected_pubkeys) {
    require_keys_eq!(account.key(), expected, MyError::InvalidAccountOrder);
}
```

## init, init_if_needed, close

- `init` - creates the account; fails if it already exists. Set `space` from `8 + T::INIT_SPACE` (discriminator + `#[derive(InitSpace)]`).
- `init_if_needed` - creates only if missing. Safe for user PDAs the user re-enters. Dangerous on any account where re-running would reset security-relevant state (authority, balances, flags). Requires the `init-if-needed` feature; use sparingly.
- `close = recipient` - zeroes the account and sends rent to `recipient`. Always pair with `has_one`/seeds so only the rightful owner can close. To close an SPL token account, CPI `close_account` with the PDA signer.

## Duplicate mutable accounts

If a handler takes two accounts it assumes are distinct (e.g. `from` and `to`), an attacker may pass the same account for both. Where the logic depends on distinctness, enforce it: `constraint = from.key() != to.key()`.

## Worked example

A borrow handler from a lending program, annotated:

```rust
#[derive(Accounts)]
pub struct BorrowLiquidity<'info> {
    #[account(mut)]
    pub user: Signer<'info>,                                  // who pays/receives

    #[account(
        mut,
        seeds = [OBLIGATION_SEED, lending_market.key().as_ref(), user.key().as_ref()],
        bump,
    )]
    pub obligation: AccountLoader<'info, Obligation>,         // tied to this user + market

    #[account(seeds = [LENDING_MARKET_SEED, &lending_market.load()?.name], bump)]
    pub lending_market: AccountLoader<'info, LendingMarket>,

    #[account(
        mut,
        seeds = [RESERVE_SEED, lending_market.key().as_ref(), liquidity_mint.key().as_ref()],
        bump,
    )]
    pub reserve: AccountLoader<'info, Reserve>,               // tied to market + mint

    #[account(
        address = reserve.load()?.liquidity.mint_pubkey,     // mint pinned to reserve state
        mint::token_program = liquidity_token_program,
    )]
    pub liquidity_mint: InterfaceAccount<'info, Mint>,

    #[account(
        mut,
        associated_token::mint = liquidity_mint,
        associated_token::authority = reserve,                // vault owned by reserve PDA
    )]
    pub reserve_liquidity_supply: InterfaceAccount<'info, TokenAccount>,

    #[account(
        mut,
        associated_token::mint = liquidity_mint,
        associated_token::authority = user,                   // destination owned by user
    )]
    pub user_liquidity_ata: InterfaceAccount<'info, TokenAccount>,

    pub liquidity_token_program: Interface<'info, TokenInterface>,
}
```

Every account is anchored to something already trusted: the user signs; the obligation and reserve are PDAs derived from the market and mint; the mint is pinned to the reserve's stored value; both token accounts are tied to that mint and to the correct authority. There is no account the attacker can freely choose.
