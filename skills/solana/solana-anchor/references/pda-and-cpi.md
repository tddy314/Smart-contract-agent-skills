# PDA and CPI Patterns

## Table of Contents

- PDA derivation and bump storage
- PDA-signed CPI and signer-seed nesting
- CPI to Anchor programs (declare_program!)
- CPI to native and SPL programs
- reload after CPI
- Token transfer helper module

---

## PDA derivation and bump storage

A PDA is derived from seeds plus a bump that pushes the result off the ed25519 curve. `find_program_address` returns the canonical bump (the highest valid one). Store it.

```rust
// at init, capture the bump Anchor already computed
offer.bump = context.bumps.offer;

// store seed constants centrally
pub const RESERVE_SEED: &[u8] = b"reserve";
pub const OBLIGATION_SEED: &[u8] = b"obligation";
```

On later calls validate with `bump = account.bump` rather than `bump` alone. Re-deriving with bare `bump` recomputes `find_program_address` (more compute) and, in hand-rolled checks, can let a caller supply a non-canonical bump for a different valid address.

In a test, derive the PDA the same way the program does:

```rust
let (reserve_pda, _bump) = Pubkey::find_program_address(
    &[RESERVE_SEED, market.as_ref(), mint.as_ref()],
    &program_id,
);
```

## PDA-signed CPI and signer-seed nesting

When a PDA owns a vault or mint authority, it authorizes a CPI by signing with its seeds plus stored bump.

```rust
let market_key = ctx.accounts.lending_market.key();
let mint_key = ctx.accounts.liquidity_mint.key();
let reserve = ctx.accounts.reserve.load()?;

let signer_seeds: &[&[&[u8]]] = &[&[
    RESERVE_SEED,
    market_key.as_ref(),
    mint_key.as_ref(),
    &[reserve.bump_seed],
]];

let cpi_context = CpiContext::new_with_signer(
    ctx.accounts.token_program.to_account_info(),
    TransferChecked {
        from: ctx.accounts.reserve_liquidity_supply.to_account_info(),
        mint: ctx.accounts.liquidity_mint.to_account_info(),
        to: ctx.accounts.user_liquidity_ata.to_account_info(),
        authority: ctx.accounts.reserve.to_account_info(),
    },
    signer_seeds,
);
transfer_checked(cpi_context, amount, ctx.accounts.liquidity_mint.decimals)?;
```

**The nesting is the trap.** `new_with_signer` takes `&[&[&[u8]]]`:

- innermost `&[u8]` - one seed
- middle `&[&[u8]]` - all seeds for one signer
- outer `&[&[&[u8]]]` - a list of signers (usually one)

A helper that accepts `authority_signer_seeds: &[&[u8]]` (one signer's seeds) must wrap it as `&[authority_signer_seeds]` at the call site. A helper that already accepts `&[&[&[u8]]]` is pre-wrapped. Mixing these up produces a runtime "Could not create program address with signer seeds" error, not a compile error - so read the helper signature before calling. The team's `token_transfer.rs` and `spl_token.rs` helpers differ on this exact point: `mint(... seeds: &[&[u8]])` wraps internally, `burn_with_signer(... seeds: &[&[&[u8]]])` expects it pre-wrapped.

## CPI to Anchor programs (declare_program!)

Prefer generating typed bindings from the callee's IDL over hand-copying discriminators or account orders.

```rust
declare_program!(lever);              // reads idls/lever.json, generates the lever module
use lever::cpi::accounts::SwitchPower;
use lever::cpi::switch_power;
use lever::program::Lever;

pub fn pull_lever(context: Context<PullLever>, name: String) -> Result<()> {
    let cpi_context = CpiContext::new(
        context.accounts.lever_program.to_account_info(),
        SwitchPower { power: context.accounts.power.to_account_info() },
    );
    switch_power(cpi_context, name)
}

#[derive(Accounts)]
pub struct PullLever<'info> {
    #[account(mut)]
    pub power: Account<'info, PowerStatus>,
    pub lever_program: Program<'info, Lever>,   // program ID validated by type
}
```

Avoid hardcoding instruction discriminators as byte arrays. If you must reference one, derive it from the IDL rather than pasting the literal.

## CPI to native and SPL programs

System transfer with a PDA payer:

```rust
let signer_seeds: &[&[&[u8]]] = &[&[b"rent_vault", &[context.bumps.rent_vault]]];
create_account(
    CpiContext::new(system_program, CreateAccount { from, to })
        .with_signer(signer_seeds),
    lamports, space, owner,
);
```

For fixed external programs invoked by raw `invoke_signed` (e.g. a stake pool), pin the program and every external account by `address = CONST` against hardcoded constants, so no fake pool can be substituted.

## reload after CPI

A CPI that changes a token account does not update Anchor's in-memory copy. Reading `.amount` after the CPI without reloading gives the pre-CPI value.

```rust
token_interface::transfer_checked(cpi_context, amount, decimals)?;
ctx.accounts.vault.reload()?;                 // refresh from account data
let new_balance = ctx.accounts.vault.amount;  // now correct
```

This matters especially with Token Extensions, where transfer fees mean the amount received is not the amount sent - always reload and read the actual delta rather than assuming.

## Token transfer helper module

Centralize CPI token movements so signer-seed handling lives in one reviewed place. Representative helpers:

```rust
// PDA-signed transfer (vault -> user)
pub fn token_transfer_with_signer<'info>(
    from: AccountInfo<'info>,
    authority: AccountInfo<'info>,
    to: AccountInfo<'info>,
    token_program: &Program<'info, Token>,
    signer_seeds: &[&[&[u8]]],   // pre-wrapped
    amount: u64,
) -> Result<()> {
    let cpi_context = CpiContext::new_with_signer(
        token_program.to_account_info(),
        token::Transfer { from, to, authority },
        signer_seeds,
    );
    token::transfer(cpi_context, amount)
}

// user-signed transfer (user -> vault)
pub fn token_transfer_user<'info>(
    from: AccountInfo<'info>,
    authority: &Signer<'info>,
    to: AccountInfo<'info>,
    token_program: &Program<'info, Token>,
    amount: u64,
) -> Result<()> {
    let cpi_context = CpiContext::new(
        token_program.to_account_info(),
        token::Transfer { from, to, authority: authority.to_account_info() },
    );
    token::transfer(cpi_context, amount)
}
```

Prefer the `transfer_checked` / `TransferChecked` variants (with mint + decimals) over the plain `transfer` shown in older helpers - the checked form catches wrong-mint and wrong-decimals bugs. When extending these helpers, migrate to checked transfers rather than copying the deprecated form.
