---
name: solana-anchor
description: >
  Chain-specific implementation skill for Solana Anchor programs (Rust onchain code,
  TypeScript/LiteSVM tests, Anchor.toml). Use whenever a task touches Anchor programs,
  account validation, PDAs, CPIs, SPL/Token-Extensions integrations, zero-copy accounts,
  or program upgrades. ALWAYS use this skill for Solana/Anchor work even if the user does
  not say "Anchor" - recognize it from `Anchor.toml`, `declare_id!`, `#[program]`,
  `#[derive(Accounts)]`, or a `programs/` directory. For DeFi math (fixed-point, interest,
  shares) also load `solana-defi-math`; for lending protocols load `solana-lending`; for
  vaults load `solana-vault`.
---

# Solana Anchor

This skill teaches the agent how to work safely and consistently in Solana Anchor repositories. It encodes the account-validation discipline, PDA/CPI patterns, token handling, and project conventions used across the team's production programs.

`smart-contract-core` owns the overall workflow (inspect, plan, threat-model, implement, report). This skill provides the Solana-specific checklists and patterns at each step. When the task involves financial math, share accounting, or protocol-specific logic, load the companion skills named in the frontmatter.

---

## When to Use

- Anchor program implementation or modification
- Solana account validation and constraint design
- PDA derivation, seeds, and bump handling
- CPI to other programs (system, token, or third-party)
- SPL Token and Token Extensions integration
- Zero-copy accounts (`AccountLoader`)
- Anchor tests (TypeScript or Rust/LiteSVM)
- Program upgrades and migration

**Do not use** for non-Solana chains, or for pure client-side TypeScript that does not touch program accounts (a plain web frontend with no transaction building).

---

## The One Rule That Matters Most

**Most Anchor bugs are account-validation bugs, not business-logic bugs.**

A program is a pure function over the accounts it is handed. If you validate the wrong accounts, correct business logic operates on attacker-controlled data. Before reviewing or writing any handler logic, review the `#[derive(Accounts)]` struct and convince yourself that every account is constrained so that only the intended account can be passed.

When reviewing a handler, read the accounts struct first and the logic second.

---

## Terminology

Solana is not Ethereum. Use the right words - they shape how you reason.

- Programs, not "smart contracts". Transaction fees, not "gas". No mempool.
- "Instruction handlers" for the Rust functions; "instructions" for the data passed to them.
- "Token Extensions Program" (not "Token 2022"), "Classic Token Program" for the older one.
- Write "onchain" and "offchain" as single words, never hyphenated.
- A mint is the account controlling supply; a token is the asset. In economic prose say "token A", reserve "mint account" for the technical account argument.

Full conventions: see `references/conventions.md`.

---

## Repository Inspection

Before coding, inspect:

- `Anchor.toml` - Anchor version, cluster, test runner, program IDs
- `Cargo.toml` (workspace and program) - `anchor-lang`/`anchor-spl` versions, `overflow-checks`, math crates (`fixed`, `uint`), third-party CPI deps
- `programs/<name>/src/lib.rs` - program ID, instruction list, dispatch style
- `src/instructions/` or `src/handlers/` - handler organization
- `src/state/` or `src/states/` - account layouts, zero-copy vs plain
- `src/constants/` and any `seeds.rs` - PDA seed constants
- `src/errors/` - error enum
- `tests/` - test framework (LiteSVM/`cargo test` vs TypeScript/mocha) and existing patterns
- `migrations/` - deployment scripts

Identify before planning: which token program (Classic vs Extensions vs both via `TokenInterface`), zero-copy vs plain accounts, the PDA map (every seed and signer), and which external programs are called via CPI.

---

## Project Structure

The team's programs use a layered structure. Match whatever the repo already does; for new programs, prefer this:

```
programs/<name>/src/
  lib.rs                 # declare_id!, #[program] dispatcher - thin wrappers only
  errors/ (or errors.rs) # #[error_code] enum
  constants/             # PDA seeds, magic numbers as named constants
  state/                 # account structs
  instructions/          # one file per handler, grouped by role
    admin/
    user/
    <operator>/          # e.g. bot_server, liquidator, ai_agent
  utils.rs               # shared CPI helpers (token transfer, etc.)
```

**`lib.rs` carries no business logic.** Each entry is a thin wrapper that delegates:

```rust
pub fn borrow_liquidity(context: Context<BorrowLiquidity>, amount: u64) -> Result<()> {
    borrow_liquidity::process(context, amount)
}
```

Group handlers by role (`admin/`, `user/`, operator). The directory layout becomes the authorization map - a reviewer can see the privilege boundary from the file tree.

---

## Account Validation Checklist

For every handler, verify each account is constrained. Reason about what an attacker could substitute if a constraint is missing.

- **Signer** - is the right party required to sign? `Signer<'info>`, or `constraint = signer.key() == config.authority`.
- **Owner / authority** - for privileged actions, is the signer checked against stored authority? Use `has_one = authority` or `address = config.authority`.
- **PDA seeds and bump** - are seeds correct and complete? Prefer storing the bump in the account and using `bump = account.bump` on later calls (canonical bump, saves compute, avoids re-derivation).
- **`mut`** - is every account that gets written marked `mut`? Is anything `mut` that should not be?
- **Account type** - `Account` (deserializes + checks owner + discriminator), `InterfaceAccount` (token-program-agnostic), `AccountLoader` (zero-copy), `UncheckedAccount` (no checks - must justify and constrain by `address`/seeds).
- **Token account mint** - `associated_token::mint` / `token::mint` ties the token account to the expected mint. Missing this lets an attacker pass a token account for a different mint.
- **Token account authority** - `associated_token::authority` / `token::authority` ties it to the expected owner.
- **CPI target program** - is the program account constrained? `Program<'info, T>` validates the program ID; for raw CPI use `address = expected::id()`.
- **Cross-referenced accounts** - when accounts must be consistent with a loaded account (e.g. a pool's config/vaults), constrain them: `address = pool_state.load()?.amm_config`.
- **`remaining_accounts`** - never trusted. Validate length, order, and each pubkey against expected values before use.
- **Duplicate mutable accounts** - can the same account be passed twice where the logic assumes two distinct accounts?
- **`init_if_needed`** - only on accounts where re-initialization is harmless (user PDAs). Never on accounts where re-init resets security-relevant state.
- **`close`** - `close = recipient` returns rent and zeroes the account. Confirm only the rightful owner can trigger it (`has_one`).

Deep dive with code examples: `references/account-validation.md`.

---

## PDA and CPI Patterns

**Storing the bump.** Store `bump: u8` in the account at init (`bump: context.bumps.<account>`), then validate with `bump = account.bump` afterward. This pins the canonical bump and avoids recomputation.

**PDA-signed CPI.** A PDA signs by passing its seeds (including the stored bump) as signer seeds:

```rust
let signer_seeds: &[&[&[u8]]] = &[&[
    RESERVE_SEED, market_key.as_ref(), mint_key.as_ref(), &[reserve.bump_seed],
]];
let cpi_context = CpiContext::new_with_signer(token_program, accounts, signer_seeds);
```

Watch the nesting: `CpiContext::new_with_signer` wants `&[&[&[u8]]]`. Helper functions that build the inner slice and wrap it differ by one level - read the signature before calling (this is a common source of "could not create program address" errors).

**CPI to other Anchor programs.** Prefer `declare_program!(other)` to generate typed CPI bindings from the IDL, then `other::cpi::method(cpi_context, args)`. Avoid copying discriminators or account orders by hand.

**`reload()` after CPI.** After a CPI changes a token account (transfer, mint, burn), call `account.reload()?` before reading its `amount` - the in-memory copy is stale otherwise.

**`Box` large accounts** (`Box<Account<'info, T>>`) to keep them off the stack and avoid stack-overflow build errors.

Deep dive: `references/pda-and-cpi.md`.

---

## Token Handling

- Use `transfer_checked` (not the deprecated `transfer`) for token movements - it validates mint and decimals, which catches wrong-mint and wrong-decimals bugs. The checked variants need the mint account and `decimals`.
- Prefer `InterfaceAccount<'info, TokenAccount>` and `Interface<'info, TokenInterface>` so the program works with both the Classic Token Program and Token Extensions. Pin a token account to its program with `token::token_program` / `associated_token::token_program` where the repo distinguishes them.
- Centralize CPI token movements in a `utils.rs` / `token_transfer.rs` helper module rather than inlining `CpiContext` construction in every handler. The team's programs do this - it keeps signer-seed handling in one reviewed place.
- Token Extensions can carry transfer fees, transfer hooks, and other extensions. When a mint may have extensions, do not assume the amount received equals the amount sent - read the balance via `reload()`.

---

## Arithmetic Safety

Onchain financial math must be exact and deterministic.

- **Never use `f32`/`f64` for amounts, shares, rates, or any value that affects token movement or persisted state.** Floats are non-deterministic across rounding paths, compound error over many operations, and serialize inconsistently. This applies to instruction parameters, account fields, and intermediate math. If you find float financial code, flag it as a SECURITY-REVIEW item rather than extending it. Use scaled integers (`u64`/`u128`) or fixed-point (see `solana-defi-math`).
- Set `overflow-checks = true` in the release profile so arithmetic overflow traps instead of wrapping. Even with it on, prefer explicit `checked_add`/`checked_mul`/`checked_sub` returning a custom error in handler logic, so the failure is a clean program error rather than a panic.
- Be explicit about rounding direction. Round in the protocol's favor: when minting shares/collateral to a user round down, when computing what they must repay round up. Mismatched rounding is a value-leak bug.
- Avoid magic numbers. Give constants names (`FULL_BPS = 10_000`) or derive values from the IDL rather than hardcoding.

---

## Common Commands

```bash
anchor build
anchor test                 # builds, starts validator, deploys, runs configured suite
anchor test --skip-build
anchor test --skip-deploy
cargo test                  # Rust/LiteSVM tests
cargo clippy
cargo fmt
```

For test design, defer to `smart-contract-testing`. Solana-specific priorities: wrong-signer rejection, wrong-PDA/bump rejection, attacker-supplied account rejection, CPI cannot be redirected, duplicate-mutable-account rejection, token mint/authority validation.

LiteSVM (`cargo test`) is the lighter, faster harness used by the official examples; TypeScript/mocha via `anchor test` is the other common style. Follow the repo's existing choice.

---

## Common Mistakes to Avoid

- Reviewing handler logic before the accounts struct - validation bugs hide in constraints, not logic.
- Missing signer constraint, or checking a signer that is not bound to stored authority.
- Weak or incomplete PDA seeds; re-deriving the bump instead of using the stored canonical bump.
- Trusting `remaining_accounts` without validating length, order, and pubkeys.
- Missing token mint or token authority constraints on token accounts.
- CPI to an unconstrained program account (program substitution).
- Reading a token account `amount` after a CPI without `reload()`.
- `init_if_needed` on an account where re-init resets security state.
- `f64`/`f32` anywhere in financial math or state.
- Wrapping signer seeds at the wrong nesting level for `new_with_signer`.
- Leaving commented-out instruction handlers or dead account fields in shipped code - delete them.
- Hardcoding a deployer pubkey in `initialize`, which makes the program non-reusable. Take authority as an argument or from the signer.
- Open-ended dependency ranges or unpinned git CPI deps - pin them and comment why.

---

## Final Response Expectations

Follow `smart-contract-core`'s report format. For Anchor work, make sure the report's security section explicitly addresses:

- Which accounts are validated by what constraint (the privilege boundary)
- PDA seeds and signer authority for any PDA-signed CPI
- Token mint/authority validation for any token movement
- Which external programs are called via CPI and how their identity is enforced
- Arithmetic: overflow handling and rounding direction for value-moving math

Name the actual instruction handlers and account fields in prose. Before naming an identifier, confirm it exists in the source.

---

## Reference Files

- `references/conventions.md` - terminology, naming, documentation, and financial-writing conventions (house style)
- `references/account-validation.md` - the constraint catalog with code examples and the attack each prevents
- `references/pda-and-cpi.md` - PDA derivation, bump storage, PDA-signed CPI, `declare_program!`, signer-seed nesting

---

## Rules

1. Read the `#[derive(Accounts)]` struct before the handler logic.
2. Constrain every account; for each, know what an attacker could substitute.
3. Store and reuse the canonical PDA bump.
4. Never trust `remaining_accounts` - validate length, order, and pubkeys.
5. Use `transfer_checked` and validate token mint and authority.
6. Constrain every CPI target program's identity.
7. `reload()` token accounts after CPI before reading balances.
8. Never use floats in financial math or state; flag existing float code for review.
9. Keep `lib.rs` thin; put logic in role-grouped handler files.
10. Delete dead code; pin dependency versions with a reason.
