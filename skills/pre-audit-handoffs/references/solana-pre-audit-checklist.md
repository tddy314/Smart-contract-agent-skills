# Solana Pre-Audit Checklist

Use for Anchor programs, Rust onchain code, PDA authority, token accounts, CPIs, LiteSVM or TypeScript tests, and Solana DeFi protocols.

## Scope and Build

- Inspect `Anchor.toml`, `Cargo.toml`, `programs/`, `tests/`, IDL generation, and deployment scripts.
- Identify program IDs, upgrade authority assumptions, feature flags, and test validator setup.
- Identify account size, zero-copy, realloc, and close behavior.

## Account Validation

- Check every account has the correct owner, mutability, signer requirement, and address constraint.
- Check PDA seeds and bump are validated against the expected program.
- Check attacker-supplied accounts cannot substitute market, reserve, vault, oracle, mint, authority, or token account.
- Check duplicate mutable accounts cannot alias in a harmful way.
- Check account close sends lamports to the intended recipient and cannot close twice.

## Authority and Signers

- Map user signer, admin signer, PDA authority, mint authority, freeze authority, vault authority, and CPI signer seeds.
- Check signer seeds match the PDA used as authority.
- Check admin/operator/keeper/liquidator roles are separated.
- Check authority rotation and emergency powers are documented as trust assumptions.

## Token Accounts and Mints

- Check token account owner, mint, delegate, close authority, and token program.
- Check Token-2022 extensions if used.
- Check decimals and amount units.
- Check transfer, mint, burn, freeze, thaw, and close instructions use the intended authority.
- Check associated token account assumptions are enforced or documented.

## CPI Safety

- Check CPI program IDs cannot be redirected.
- Check CPI accounts match the expected protocol and token program.
- Check signer seeds are only used for intended instructions.
- Check external protocol failure behavior.
- Check reentrancy-like callback assumptions where applicable.

## Accounting and Math

- Use checked arithmetic.
- Check rounding direction for shares, interest, collateral, liquidation, rewards, and fees.
- Check stale slot, stale price, stale reserve, stale obligation, and stale accumulator behavior.
- Check first-depositor, empty-pool, zero-liquidity, max-utilization, and tiny-amount branches.

## Lifecycle and State Machines

- Check initialize can run once and writes all required fields.
- Check deposit, withdraw, borrow, repay, liquidate, claim, stake, unstake, harvest, rebalance, pause, and close transitions.
- Check terminal states cannot be reused.
- Check refresh-before-act is enforced where lending, oracle, interest, or rewards depend on freshness.

## Test Gaps to Flag

- Wrong signer fails.
- Wrong PDA seeds or bump fail.
- Malicious account substitution fails.
- Wrong mint or token account fails.
- CPI redirection fails.
- Stale oracle/reserve/obligation fails.
- Asset conservation or solvency invariants are tested.
