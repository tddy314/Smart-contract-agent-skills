use anchor_lang::prelude::*;
use anchor_spl::token::{self, Mint, Token, TokenAccount, Transfer};

declare_id!("11111111111111111111111111111111");

#[program]
pub mod vault {
    use super::*;

    pub fn initialize(ctx: Context<Initialize>) -> Result<()> {
        let vault = &mut ctx.accounts.vault;
        vault.authority = ctx.accounts.authority.key();
        vault.mint = ctx.accounts.mint.key();
        vault.total_shares = 0;
        vault.total_assets = 0;
        vault.bump = ctx.bumps.vault;
        Ok(())
    }

    pub fn deposit(ctx: Context<Deposit>, amount: u64) -> Result<()> {
        let vault = &mut ctx.accounts.vault;
        let user_position = &mut ctx.accounts.user_position;

        // BUG: divide by zero when total_shares == 0 (first depositor edge case)
        // BUG: uses floating point — precision loss and non-determinism
        let shares_to_mint = (amount as f64 * vault.total_shares as f64
            / vault.total_assets as f64) as u64;

        // BUG: uses transfer instead of transfer_checked (no decimal validation)
        let cpi_accounts = Transfer {
            from: ctx.accounts.user_token_account.to_account_info(),
            to: ctx.accounts.vault_token_account.to_account_info(),
            authority: ctx.accounts.user.to_account_info(),
        };
        let cpi_ctx = CpiContext::new(ctx.accounts.token_program.to_account_info(), cpi_accounts);
        token::transfer(cpi_ctx, amount)?;

        // BUG: no reload() after CPI — vault_token_account balance is stale

        vault.total_assets += amount;
        vault.total_shares += shares_to_mint;
        user_position.shares += shares_to_mint;

        Ok(())
    }

    pub fn withdraw(ctx: Context<Withdraw>, shares: u64) -> Result<()> {
        let vault = &mut ctx.accounts.vault;
        let user_position = &mut ctx.accounts.user_position;

        require!(user_position.shares >= shares, VaultError::InsufficientShares);

        let assets_to_return = shares * vault.total_assets / vault.total_shares;

        let seeds = &[b"vault".as_ref(), vault.mint.as_ref(), &[vault.bump]];
        let signer = &[&seeds[..]];

        // BUG: uses transfer instead of transfer_checked
        let cpi_accounts = Transfer {
            from: ctx.accounts.vault_token_account.to_account_info(),
            to: ctx.accounts.user_token_account.to_account_info(),
            authority: ctx.accounts.vault_authority.to_account_info(),
        };
        let cpi_ctx = CpiContext::new_with_signer(
            ctx.accounts.token_program.to_account_info(),
            cpi_accounts,
            signer,
        );
        token::transfer(cpi_ctx, assets_to_return)?;

        vault.total_assets -= assets_to_return;
        vault.total_shares -= shares;
        user_position.shares -= shares;

        Ok(())
    }
}

#[derive(Accounts)]
pub struct Initialize<'info> {
    #[account(
        init,
        payer = authority,
        space = 8 + Vault::INIT_SPACE,
        seeds = [b"vault", mint.key().as_ref()],
        bump
    )]
    pub vault: Account<'info, Vault>,

    /// CHECK: PDA that acts as vault token authority
    #[account(
        seeds = [b"vault_authority", vault.key().as_ref()],
        bump
    )]
    pub vault_authority: UncheckedAccount<'info>,

    #[account(
        init,
        payer = authority,
        token::mint = mint,
        token::authority = vault_authority,
    )]
    pub vault_token_account: Account<'info, TokenAccount>,

    pub mint: Account<'info, Mint>,

    #[account(mut)]
    pub authority: Signer<'info>,

    pub token_program: Program<'info, Token>,
    pub system_program: Program<'info, System>,
    pub rent: Sysvar<'info, Rent>,
}

#[derive(Accounts)]
pub struct Deposit<'info> {
    #[account(
        mut,
        seeds = [b"vault", vault.mint.as_ref()],
        bump = vault.bump,
    )]
    pub vault: Account<'info, Vault>,

    /// CHECK: PDA vault authority
    #[account(
        seeds = [b"vault_authority", vault.key().as_ref()],
        bump
    )]
    pub vault_authority: UncheckedAccount<'info>,

    #[account(
        mut,
        token::mint = vault.mint,
        token::authority = vault_authority,
    )]
    pub vault_token_account: Account<'info, TokenAccount>,

    #[account(
        init_if_needed,
        payer = user,
        space = 8 + UserPosition::INIT_SPACE,
        seeds = [b"position", vault.key().as_ref(), user.key().as_ref()],
        bump
    )]
    pub user_position: Account<'info, UserPosition>,

    #[account(mut, token::mint = vault.mint)]
    pub user_token_account: Account<'info, TokenAccount>,

    #[account(mut)]
    pub user: Signer<'info>,

    pub token_program: Program<'info, Token>,
    pub system_program: Program<'info, System>,
}

// BUG: missing has_one = owner constraint — any signer can withdraw another user's funds
#[derive(Accounts)]
pub struct Withdraw<'info> {
    #[account(
        mut,
        seeds = [b"vault", vault.mint.as_ref()],
        bump = vault.bump,
    )]
    pub vault: Account<'info, Vault>,

    /// CHECK: PDA vault authority
    #[account(
        seeds = [b"vault_authority", vault.key().as_ref()],
        bump
    )]
    pub vault_authority: UncheckedAccount<'info>,

    #[account(
        mut,
        token::mint = vault.mint,
        token::authority = vault_authority,
    )]
    pub vault_token_account: Account<'info, TokenAccount>,

    #[account(
        mut,
        seeds = [b"position", vault.key().as_ref(), user_position.owner.as_ref()],
        bump
    )]
    pub user_position: Account<'info, UserPosition>,

    #[account(mut, token::mint = vault.mint)]
    pub user_token_account: Account<'info, TokenAccount>,

    pub user: Signer<'info>,

    pub token_program: Program<'info, Token>,
}

#[account]
#[derive(InitSpace)]
pub struct Vault {
    pub authority: Pubkey,
    pub mint: Pubkey,
    pub total_shares: u64,
    pub total_assets: u64,
    pub bump: u8,
}

#[account]
#[derive(InitSpace)]
pub struct UserPosition {
    pub owner: Pubkey,
    pub shares: u64,
}

#[error_code]
pub enum VaultError {
    #[msg("Insufficient shares to withdraw")]
    InsufficientShares,
}
