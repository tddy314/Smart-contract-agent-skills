# Lending Account Model

Self-contained patterns. Adapt names to the host repo.

## Table of Contents

- The three account types
- Market layout
- Reserve layout
- Obligation layout
- Zero-copy considerations
- PDA seeds

---

## The three account types

A lending protocol separates global config, per-asset state, and per-user state into three account types. The separation is what keeps the protocol auditable: each piece of state has exactly one owner.

- **Market** - singleton, global config and authority.
- **Reserve** - one per lendable asset, holds the pool and risk parameters.
- **Obligation** - one per user per market, the user's deposits and borrows.

Tokens never live in the obligation. They live in reserve-owned vault accounts (PDAs). The obligation is an accounting record.

---

## Market layout

The market is the root of authority and global policy. It holds no per-asset or per-user data.

```rust
#[account(zero_copy)]
#[repr(C)]
pub struct LendingMarket {
    pub market_name: [u8; 32],              // also used as a PDA seed
    pub authority: Pubkey,                   // admin
    pub min_net_value_in_obligation_sf: u128, // dust threshold (scaled fraction)
    pub global_allowed_borrow_value: u64,
    pub bump_seed: u8,
    pub is_paused: u8,                       // 0 = active, 1 = paused
    pub _padding: [u8; N],
}
```

`is_paused` is a global circuit breaker - handlers check it and abort when set. `min_net_value_in_obligation_sf` is the threshold below which a position is forced into full liquidation so it cannot become un-liquidatable dust.

---

## Reserve layout

The reserve is the per-asset heart of the protocol. Group its state by responsibility: liquidity, config, collateral, and freshness.

```rust
#[account(zero_copy)]
#[repr(C)]
pub struct Reserve {
    pub liquidity: ReserveLiquidity,
    pub config: ReserveConfig,
    pub collateral: ReserveCollateral,
    pub market: Pubkey,
    pub oracle_pubkey: Pubkey,    // pinned at init, validated every refresh
    pub last_update: LastUpdate,  // freshness (slot + stale flag)
    pub bump_seed: u8,
    pub _padding: [u8; N],
}

pub struct ReserveLiquidity {
    pub mint_pubkey: Pubkey,
    pub mint_decimals: u64,
    pub available_amount: u64,            // raw liquidity in the vault
    pub borrowed_amount_sf: u128,         // total borrowed (scaled fraction)
    pub cumulative_borrow_rate_bsf: BigFractionBytes, // the interest index
    pub accumulated_protocol_fees_sf: u128,
    pub market_price_sf: u128,            // last oracle price (scaled fraction)
    pub market_price_last_updated_ts: u64,
}

pub struct ReserveConfig {
    pub borrow_rate_curve: BorrowRateCurve,
    pub deposit_limit: u64,
    pub borrow_limit: u64,
    pub max_age_price_seconds: u64,
    pub loan_to_value_pct: u8,            // borrow ceiling driver
    pub liquidation_threshold_pct: u8,    // liquidation trigger driver (> LTV)
    pub liquidation_bonus_bps: u16,
    pub bad_debt_liquidation_bonus_bps: u16,
    pub protocol_take_rate_pct: u8,       // protocol's cut of interest
    pub is_paused: u8,
    pub _padding: [u8; N],
}

pub struct ReserveCollateral {
    pub mint_pubkey: Pubkey,              // the cToken mint
    pub mint_total_supply: u64,           // total cTokens issued
}
```

The `_sf` suffix marks fields holding a fixed-point `Fraction::to_bits()` payload (see `solana-defi-math/references/fixed-point.md`). `cumulative_borrow_rate_bsf` is the interest index that lets per-obligation debt update lazily (see `staleness-and-accrual.md`).

The collateral exchange rate is derived, not stored: `total_liquidity / mint_total_supply`. It grows as interest accrues into `borrowed_amount_sf`.

---

## Obligation layout

The obligation records one user's positions. Fixed-size arrays cap how many distinct reserves a user can touch, which bounds the account size and the refresh cost.

```rust
#[account(zero_copy)]
#[repr(C)]
pub struct Obligation {
    pub owner: Pubkey,
    pub market: Pubkey,
    pub deposits: [ObligationCollateral; 8],  // collateral positions
    pub borrows: [ObligationLiquidity; 5],    // debt positions
    pub deposited_value_sf: u128,             // cached aggregates, set at refresh
    pub borrowed_assets_market_value_sf: u128,
    pub allowed_borrow_value_sf: u128,        // borrow ceiling
    pub unhealthy_borrow_value_sf: u128,      // liquidation trigger
    pub last_update: LastUpdate,
}

pub struct ObligationCollateral {
    pub deposit_reserve: Pubkey,   // Pubkey::default() = empty slot
    pub deposited_amount: u64,     // in cTokens
    pub market_value_sf: u128,
}

pub struct ObligationLiquidity {
    pub borrow_reserve: Pubkey,    // Pubkey::default() = empty slot
    pub borrowed_amount_sf: u128,
    pub cumulative_borrow_rate_bsf: BigFractionBytes, // index at last accrual
    pub market_value_sf: u128,
}
```

Empty slots use `Pubkey::default()` as a sentinel. A helper like `is_active()` checks `reserve != Pubkey::default()`. The cached aggregate `_sf` values are only valid immediately after a refresh in the same slot - that is exactly why the refresh-before-act invariant exists.

Each borrow stores the `cumulative_borrow_rate_bsf` at its last accrual. Interest owed is computed by the ratio of the reserve's current index to the borrow's stored index (see `staleness-and-accrual.md`).

---

## Zero-copy considerations

These accounts are large and hold fixed-size arrays, so they use `#[account(zero_copy)]` + `#[repr(C)]` and are accessed via `AccountLoader`:

```rust
pub obligation: AccountLoader<'info, Obligation>,

// read
let obligation = ctx.accounts.obligation.load()?;
// write
let mut obligation = ctx.accounts.obligation.load_mut()?;
```

Rules that come with zero-copy:

- `#[repr(C)]` is required for a stable layout; explicit `_padding` keeps alignment predictable.
- No `Vec` or other heap types in a zero-copy struct - that is why positions are fixed-size arrays, not vectors. A dynamic list (e.g. a price group) must be a separate plain `#[account]`.
- Drop a `load_mut()` borrow (`drop(reserve);`) before you need the account info again for a CPI in the same handler.
- Size the account as `8 + size_of::<T>()` (discriminator + struct).

---

## PDA seeds

Name every seed as a constant. A representative set:

```rust
pub const MARKET_SEED: &[u8] = b"lending_market";
pub const RESERVE_SEED: &[u8] = b"reserve";
pub const RESERVE_COLLATERAL_MINT_SEED: &[u8] = b"reserve_collateral_mint";
pub const OBLIGATION_SEED: &[u8] = b"obligation";
```

Typical derivations:

```
market      = [MARKET_SEED, market_name]
reserve     = [RESERVE_SEED, market.key(), liquidity_mint.key()]
ctoken_mint = [RESERVE_COLLATERAL_MINT_SEED, reserve.key()]
obligation  = [OBLIGATION_SEED, market.key(), owner.key()]
```

The reserve is the authority over its liquidity vault and cToken mint, so it signs vault transfers and mints with its seeds plus stored `bump_seed` (see `solana-anchor/references/pda-and-cpi.md`).
