use anchor_lang::prelude::*;
use anchor_spl::token::{self, Mint, Token, TokenAccount, Transfer};

declare_id!("11111111111111111111111111111111");

const COLLATERAL_RATIO: u64 = 80; // 80% LTV

#[program]
pub mod lending {
    use super::*;

    pub fn initialize_market(ctx: Context<InitializeMarket>) -> Result<()> {
        let market = &mut ctx.accounts.market;
        market.authority = ctx.accounts.authority.key();
        market.bump = ctx.bumps.market;
        Ok(())
    }

    pub fn initialize_reserve(ctx: Context<InitializeReserve>) -> Result<()> {
        let reserve = &mut ctx.accounts.reserve;
        reserve.mint = ctx.accounts.mint.key();
        reserve.oracle = ctx.accounts.oracle.key();
        reserve.liquidity_available = 0;
        reserve.total_borrows = 0;
        reserve.total_deposits = 0;
        reserve.deposit_share_value = 1_000_000; // 1:1 initial (u64, not fixed-point — BUG)
        reserve.borrow_share_value = 1_000_000;
        reserve.last_update_slot = Clock::get()?.slot;
        Ok(())
    }

    pub fn deposit(ctx: Context<Deposit>, amount: u64) -> Result<()> {
        let reserve = &mut ctx.accounts.reserve;

        let shares = amount
            .checked_mul(1_000_000)
            .unwrap()
            .checked_div(reserve.deposit_share_value)
            .unwrap();

        let cpi_accounts = Transfer {
            from: ctx.accounts.user_token_account.to_account_info(),
            to: ctx.accounts.reserve_token_account.to_account_info(),
            authority: ctx.accounts.user.to_account_info(),
        };
        token::transfer(
            CpiContext::new(ctx.accounts.token_program.to_account_info(), cpi_accounts),
            amount,
        )?;

        reserve.total_deposits += amount;
        reserve.liquidity_available += amount;

        let obligation = &mut ctx.accounts.obligation;
        obligation.deposited_value += shares;

        Ok(())
    }

    // BUG: borrow does NOT refresh reserve state (accrued interest not applied)
    // BUG: no health check — user can borrow unlimited regardless of collateral
    pub fn borrow(ctx: Context<Borrow>, amount: u64) -> Result<()> {
        let reserve = &mut ctx.accounts.reserve;
        let obligation = &mut ctx.accounts.obligation;

        require!(
            reserve.liquidity_available >= amount,
            LendingError::InsufficientLiquidity
        );

        // BUG: collateral value not validated against borrow amount
        // obligation.deposited_value is never checked here

        let market_key = ctx.accounts.market.key();
        let seeds = &[b"reserve_authority".as_ref(), market_key.as_ref(), &[ctx.bumps.reserve_authority]];
        let signer = &[&seeds[..]];

        let cpi_accounts = Transfer {
            from: ctx.accounts.reserve_token_account.to_account_info(),
            to: ctx.accounts.user_token_account.to_account_info(),
            authority: ctx.accounts.reserve_authority.to_account_info(),
        };
        token::transfer(
            CpiContext::new_with_signer(
                ctx.accounts.token_program.to_account_info(),
                cpi_accounts,
                signer,
            ),
            amount,
        )?;

        reserve.liquidity_available -= amount;
        reserve.total_borrows += amount;
        obligation.borrowed_value += amount;

        Ok(())
    }

    pub fn withdraw(ctx: Context<Withdraw>, shares: u64) -> Result<()> {
        let reserve = &mut ctx.accounts.reserve;
        let obligation = &mut ctx.accounts.obligation;

        let amount = shares
            .checked_mul(reserve.deposit_share_value)
            .unwrap()
            .checked_div(1_000_000)
            .unwrap();

        require!(
            reserve.liquidity_available >= amount,
            LendingError::InsufficientLiquidity
        );

        let market_key = ctx.accounts.market.key();
        let seeds = &[b"reserve_authority".as_ref(), market_key.as_ref(), &[ctx.bumps.reserve_authority]];
        let signer = &[&seeds[..]];

        let cpi_accounts = Transfer {
            from: ctx.accounts.reserve_token_account.to_account_info(),
            to: ctx.accounts.user_token_account.to_account_info(),
            authority: ctx.accounts.reserve_authority.to_account_info(),
        };
        token::transfer(
            CpiContext::new_with_signer(
                ctx.accounts.token_program.to_account_info(),
                cpi_accounts,
                signer,
            ),
            amount,
        )?;

        reserve.liquidity_available -= amount;
        reserve.total_deposits -= amount;
        obligation.deposited_value -= shares;

        Ok(())
    }

    // BUG: no close factor — liquidator receives ALL collateral, not just a portion
    // BUG: oracle price staleness not checked
    pub fn liquidate(ctx: Context<Liquidate>, repay_amount: u64) -> Result<()> {
        let reserve = &mut ctx.accounts.reserve;
        let obligation = &mut ctx.accounts.obligation;

        // BUG: reads oracle price data without checking publish_time / staleness
        let oracle_data = ctx.accounts.oracle.try_borrow_data()?;
        let price: u64 = u64::from_le_bytes(oracle_data[..8].try_into().unwrap());
        drop(oracle_data);

        let collateral_value = obligation
            .deposited_value
            .checked_mul(price)
            .unwrap()
            .checked_div(1_000_000)
            .unwrap();
        let required_collateral = obligation
            .borrowed_value
            .checked_mul(100)
            .unwrap()
            .checked_div(COLLATERAL_RATIO)
            .unwrap();

        require!(
            collateral_value < required_collateral,
            LendingError::NotUndercollateralized
        );

        // BUG: liquidator seizes ALL deposited collateral regardless of repay_amount
        let seize_amount = obligation.deposited_value;

        let market_key = ctx.accounts.market.key();
        let seeds = &[b"reserve_authority".as_ref(), market_key.as_ref(), &[ctx.bumps.reserve_authority]];
        let signer = &[&seeds[..]];

        let cpi_accounts = Transfer {
            from: ctx.accounts.reserve_token_account.to_account_info(),
            to: ctx.accounts.liquidator_token_account.to_account_info(),
            authority: ctx.accounts.reserve_authority.to_account_info(),
        };
        token::transfer(
            CpiContext::new_with_signer(
                ctx.accounts.token_program.to_account_info(),
                cpi_accounts,
                signer,
            ),
            seize_amount,
        )?;

        reserve.total_borrows -= repay_amount;
        reserve.total_deposits -= seize_amount;
        obligation.deposited_value = 0;
        obligation.borrowed_value -= repay_amount;

        Ok(())
    }
}

#[derive(Accounts)]
pub struct InitializeMarket<'info> {
    #[account(
        init,
        payer = authority,
        space = 8 + Market::INIT_SPACE,
        seeds = [b"market"],
        bump
    )]
    pub market: Account<'info, Market>,

    #[account(mut)]
    pub authority: Signer<'info>,
    pub system_program: Program<'info, System>,
}

#[derive(Accounts)]
pub struct InitializeReserve<'info> {
    #[account(seeds = [b"market"], bump = market.bump)]
    pub market: Account<'info, Market>,

    #[account(
        init,
        payer = authority,
        space = 8 + Reserve::INIT_SPACE,
        seeds = [b"reserve", market.key().as_ref(), mint.key().as_ref()],
        bump
    )]
    pub reserve: Account<'info, Reserve>,

    pub mint: Account<'info, Mint>,
    /// CHECK: Pyth oracle account
    pub oracle: UncheckedAccount<'info>,

    #[account(mut, address = market.authority)]
    pub authority: Signer<'info>,
    pub system_program: Program<'info, System>,
}

#[derive(Accounts)]
pub struct Deposit<'info> {
    #[account(seeds = [b"market"], bump = market.bump)]
    pub market: Account<'info, Market>,

    #[account(mut, seeds = [b"reserve", market.key().as_ref(), reserve.mint.as_ref()], bump)]
    pub reserve: Account<'info, Reserve>,

    #[account(mut)]
    pub reserve_token_account: Account<'info, TokenAccount>,

    #[account(
        init_if_needed,
        payer = user,
        space = 8 + Obligation::INIT_SPACE,
        seeds = [b"obligation", user.key().as_ref()],
        bump
    )]
    pub obligation: Account<'info, Obligation>,

    #[account(mut)]
    pub user_token_account: Account<'info, TokenAccount>,

    #[account(mut)]
    pub user: Signer<'info>,
    pub token_program: Program<'info, Token>,
    pub system_program: Program<'info, System>,
}

#[derive(Accounts)]
pub struct Borrow<'info> {
    #[account(seeds = [b"market"], bump = market.bump)]
    pub market: Account<'info, Market>,

    #[account(mut, seeds = [b"reserve", market.key().as_ref(), reserve.mint.as_ref()], bump)]
    pub reserve: Account<'info, Reserve>,

    /// CHECK: PDA reserve token authority
    #[account(seeds = [b"reserve_authority", market.key().as_ref()], bump)]
    pub reserve_authority: UncheckedAccount<'info>,

    #[account(mut)]
    pub reserve_token_account: Account<'info, TokenAccount>,

    #[account(mut, seeds = [b"obligation", user.key().as_ref()], bump)]
    pub obligation: Account<'info, Obligation>,

    #[account(mut)]
    pub user_token_account: Account<'info, TokenAccount>,

    pub user: Signer<'info>,
    pub token_program: Program<'info, Token>,
}

#[derive(Accounts)]
pub struct Withdraw<'info> {
    #[account(seeds = [b"market"], bump = market.bump)]
    pub market: Account<'info, Market>,

    #[account(mut, seeds = [b"reserve", market.key().as_ref(), reserve.mint.as_ref()], bump)]
    pub reserve: Account<'info, Reserve>,

    /// CHECK: PDA reserve token authority
    #[account(seeds = [b"reserve_authority", market.key().as_ref()], bump)]
    pub reserve_authority: UncheckedAccount<'info>,

    #[account(mut)]
    pub reserve_token_account: Account<'info, TokenAccount>,

    #[account(mut, seeds = [b"obligation", user.key().as_ref()], bump)]
    pub obligation: Account<'info, Obligation>,

    #[account(mut)]
    pub user_token_account: Account<'info, TokenAccount>,

    pub user: Signer<'info>,
    pub token_program: Program<'info, Token>,
}

#[derive(Accounts)]
pub struct Liquidate<'info> {
    #[account(seeds = [b"market"], bump = market.bump)]
    pub market: Account<'info, Market>,

    #[account(mut, seeds = [b"reserve", market.key().as_ref(), reserve.mint.as_ref()], bump)]
    pub reserve: Account<'info, Reserve>,

    /// CHECK: PDA reserve token authority
    #[account(seeds = [b"reserve_authority", market.key().as_ref()], bump)]
    pub reserve_authority: UncheckedAccount<'info>,

    #[account(mut)]
    pub reserve_token_account: Account<'info, TokenAccount>,

    #[account(mut)]
    pub obligation: Account<'info, Obligation>,

    /// CHECK: Pyth oracle — staleness NOT validated
    pub oracle: UncheckedAccount<'info>,

    #[account(mut)]
    pub liquidator_token_account: Account<'info, TokenAccount>,

    pub liquidator: Signer<'info>,
    pub token_program: Program<'info, Token>,
}

#[account]
#[derive(InitSpace)]
pub struct Market {
    pub authority: Pubkey,
    pub bump: u8,
}

#[account]
#[derive(InitSpace)]
pub struct Reserve {
    pub mint: Pubkey,
    pub oracle: Pubkey,
    pub liquidity_available: u64,
    pub total_borrows: u64,
    pub total_deposits: u64,
    pub deposit_share_value: u64, // BUG: u64 instead of fixed-point decimal type
    pub borrow_share_value: u64,
    pub last_update_slot: u64,
}

#[account]
#[derive(InitSpace)]
pub struct Obligation {
    pub owner: Pubkey,
    pub deposited_value: u64,
    pub borrowed_value: u64,
}

#[error_code]
pub enum LendingError {
    #[msg("Insufficient liquidity in reserve")]
    InsufficientLiquidity,
    #[msg("Obligation is not undercollateralized")]
    NotUndercollateralized,
}
