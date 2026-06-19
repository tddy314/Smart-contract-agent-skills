use anchor_lang::prelude::*;
use anchor_spl::token::{self, Mint, MintTo, Token, TokenAccount, Burn};

declare_id!("11111111111111111111111111111111");

#[program]
pub mod staking {
    use super::*;

    pub fn initialize(ctx: Context<Initialize>, bump: u8) -> Result<()> {
        let pool = &mut ctx.accounts.stake_pool;
        pool.msol_mint = ctx.accounts.msol_mint.key();
        pool.total_sol = 0;
        pool.msol_supply = 0;
        pool.epoch = 0;
        pool.admin = ctx.accounts.admin.key();
        pool.bump = bump;
        Ok(())
    }

    // BUG: no minimum deposit amount enforced
    pub fn deposit_sol(ctx: Context<DepositSol>, sol_amount: u64) -> Result<()> {
        let pool = &mut ctx.accounts.stake_pool;

        // BUG: rounding direction unspecified — could favor user over protocol
        // BUG: divide-by-zero if total_sol == 0 on first deposit
        let msol_amount = sol_amount
            .checked_mul(pool.msol_supply)
            .unwrap()
            .checked_div(pool.total_sol)
            .unwrap();

        anchor_lang::system_program::transfer(
            CpiContext::new(
                ctx.accounts.system_program.to_account_info(),
                anchor_lang::system_program::Transfer {
                    from: ctx.accounts.user.to_account_info(),
                    to: ctx.accounts.sol_reserve.to_account_info(),
                },
            ),
            sol_amount,
        )?;

        pool.total_sol += sol_amount;
        pool.msol_supply += msol_amount;

        let pool_key = pool.key();
        let seeds = &[b"stake_pool".as_ref(), &[pool.bump]];
        let signer = &[&seeds[..]];

        let cpi_accounts = MintTo {
            mint: ctx.accounts.msol_mint.to_account_info(),
            to: ctx.accounts.user_msol_account.to_account_info(),
            authority: ctx.accounts.stake_pool.to_account_info(),
        };
        token::mint_to(
            CpiContext::new_with_signer(
                ctx.accounts.token_program.to_account_info(),
                cpi_accounts,
                signer,
            ),
            msol_amount,
        )?;

        let _ = pool_key;
        Ok(())
    }

    // BUG: no minimum withdraw amount enforced
    pub fn request_unstake(ctx: Context<RequestUnstake>, msol_amount: u64) -> Result<()> {
        let pool = &mut ctx.accounts.stake_pool;

        let sol_amount = msol_amount
            .checked_mul(pool.total_sol)
            .unwrap()
            .checked_div(pool.msol_supply)
            .unwrap();

        let seeds = &[b"stake_pool".as_ref(), &[pool.bump]];
        let signer = &[&seeds[..]];

        let cpi_accounts = Burn {
            mint: ctx.accounts.msol_mint.to_account_info(),
            from: ctx.accounts.user_msol_account.to_account_info(),
            authority: ctx.accounts.user.to_account_info(),
        };
        token::burn(
            CpiContext::new_with_signer(
                ctx.accounts.token_program.to_account_info(),
                cpi_accounts,
                signer,
            ),
            msol_amount,
        )?;

        let ticket = &mut ctx.accounts.user_ticket;
        ticket.beneficiary = ctx.accounts.user.key();
        ticket.lamports_amount = sol_amount;
        ticket.created_epoch = pool.epoch;

        pool.total_sol -= sol_amount;
        pool.msol_supply -= msol_amount;

        Ok(())
    }

    // BUG: does NOT check that enough epochs have passed before releasing SOL
    pub fn claim_unstake(ctx: Context<ClaimUnstake>) -> Result<()> {
        let ticket = &ctx.accounts.user_ticket;
        let pool = &ctx.accounts.stake_pool;

        // BUG: should be `pool.epoch > ticket.created_epoch + 1` or similar delay
        // This check is completely missing — any ticket can be claimed immediately
        let _ = pool.epoch;
        let _ = ticket.created_epoch;

        let amount = ticket.lamports_amount;

        **ctx.accounts.sol_reserve.try_borrow_mut_lamports()? -= amount;
        **ctx.accounts.user.try_borrow_mut_lamports()? += amount;

        Ok(())
    }

    // BUG: no caller validation — anyone can call refresh_epoch
    // BUG: no check if already refreshed this epoch — call twice, get double rewards
    pub fn refresh_epoch(ctx: Context<RefreshEpoch>, rewards_lamports: u64) -> Result<()> {
        let pool = &mut ctx.accounts.stake_pool;
        let clock = Clock::get()?;

        // BUG: pool.epoch should be compared to clock.epoch before updating
        // Missing: require!(clock.epoch > pool.epoch, StakingError::AlreadyRefreshed);

        pool.total_sol += rewards_lamports;
        pool.epoch = clock.epoch;

        Ok(())
    }
}

#[derive(Accounts)]
pub struct Initialize<'info> {
    #[account(
        init,
        payer = admin,
        space = 8 + StakePool::INIT_SPACE,
        seeds = [b"stake_pool"],
        bump
    )]
    pub stake_pool: Account<'info, StakePool>,

    #[account(
        init,
        payer = admin,
        mint::decimals = 9,
        mint::authority = stake_pool,
    )]
    pub msol_mint: Account<'info, Mint>,

    /// CHECK: SOL reserve PDA to hold staked lamports
    #[account(
        mut,
        seeds = [b"sol_reserve"],
        bump
    )]
    pub sol_reserve: UncheckedAccount<'info>,

    #[account(mut)]
    pub admin: Signer<'info>,
    pub token_program: Program<'info, Token>,
    pub system_program: Program<'info, System>,
    pub rent: Sysvar<'info, Rent>,
}

#[derive(Accounts)]
pub struct DepositSol<'info> {
    #[account(
        mut,
        seeds = [b"stake_pool"],
        bump = stake_pool.bump
    )]
    pub stake_pool: Account<'info, StakePool>,

    #[account(mut, address = stake_pool.msol_mint)]
    pub msol_mint: Account<'info, Mint>,

    /// CHECK: SOL reserve
    #[account(mut, seeds = [b"sol_reserve"], bump)]
    pub sol_reserve: UncheckedAccount<'info>,

    #[account(mut)]
    pub user_msol_account: Account<'info, TokenAccount>,

    #[account(mut)]
    pub user: Signer<'info>,
    pub token_program: Program<'info, Token>,
    pub system_program: Program<'info, System>,
}

#[derive(Accounts)]
pub struct RequestUnstake<'info> {
    #[account(
        mut,
        seeds = [b"stake_pool"],
        bump = stake_pool.bump
    )]
    pub stake_pool: Account<'info, StakePool>,

    #[account(mut, address = stake_pool.msol_mint)]
    pub msol_mint: Account<'info, Mint>,

    #[account(
        init,
        payer = user,
        space = 8 + UserTicket::INIT_SPACE,
        seeds = [b"ticket", user.key().as_ref(), &stake_pool.epoch.to_le_bytes()],
        bump
    )]
    pub user_ticket: Account<'info, UserTicket>,

    #[account(mut)]
    pub user_msol_account: Account<'info, TokenAccount>,

    #[account(mut)]
    pub user: Signer<'info>,
    pub token_program: Program<'info, Token>,
    pub system_program: Program<'info, System>,
}

// BUG: no has_one = beneficiary check — anyone can claim another user's ticket
#[derive(Accounts)]
pub struct ClaimUnstake<'info> {
    #[account(seeds = [b"stake_pool"], bump = stake_pool.bump)]
    pub stake_pool: Account<'info, StakePool>,

    #[account(
        mut,
        close = user,
        seeds = [b"ticket", user.key().as_ref(), &user_ticket.created_epoch.to_le_bytes()],
        bump
    )]
    pub user_ticket: Account<'info, UserTicket>,

    /// CHECK: SOL reserve
    #[account(mut, seeds = [b"sol_reserve"], bump)]
    pub sol_reserve: UncheckedAccount<'info>,

    #[account(mut)]
    pub user: Signer<'info>,
    pub system_program: Program<'info, System>,
}

#[derive(Accounts)]
pub struct RefreshEpoch<'info> {
    // BUG: no authority constraint — anyone can call this
    #[account(mut, seeds = [b"stake_pool"], bump = stake_pool.bump)]
    pub stake_pool: Account<'info, StakePool>,

    /// CHECK: SOL reserve
    #[account(mut, seeds = [b"sol_reserve"], bump)]
    pub sol_reserve: UncheckedAccount<'info>,

    // BUG: no signer constraint on admin — permissionless refresh
    pub caller: Signer<'info>,
    pub system_program: Program<'info, System>,
}

#[account]
#[derive(InitSpace)]
pub struct StakePool {
    pub msol_mint: Pubkey,
    pub total_sol: u64,
    pub msol_supply: u64,
    pub epoch: u64,
    pub admin: Pubkey,
    pub bump: u8,
}

#[account]
#[derive(InitSpace)]
pub struct UserTicket {
    pub beneficiary: Pubkey,
    pub lamports_amount: u64,
    pub created_epoch: u64,
}

#[error_code]
pub enum StakingError {
    #[msg("Epoch not yet completed")]
    EpochNotCompleted,
    #[msg("Already refreshed this epoch")]
    AlreadyRefreshed,
}
