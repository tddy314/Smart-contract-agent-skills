---
name: solana-vault
description: >
  Architecture and implementation patterns for Solana yield/strategy vaults built with Anchor -
  proportional share accounting, the admin/operator/user authority model, the lock state machine,
  management and performance fees, and safe CPI into external protocols (staking pools, CLMMs,
  lending markets). Use whenever a task involves a Solana vault that pools user deposits and
  deploys them into a strategy: share/unit accounting, deposit/withdraw, rebalancing by a bot or
  agent, fee collection, or wrapping an external DeFi protocol. ALWAYS use this skill for vault
  work even if the user only says "vault", "shares", "strategy", "rebalance", "bot", "deposit
  pool", or "yield". Pairs with solana-anchor (host patterns) and solana-defi-math (share/fee math).
---

# Solana Vault

This skill encodes how a Solana strategy vault is structured: users deposit a token, receive a proportional claim on a pooled position, and an operator deploys the pool into an external yield source. The recurring vault failures are share-accounting precision (especially floats), authority confusion between admin and operator, and unguarded CPI into external protocols. This skill makes the safe shape the default.

`solana-anchor` owns account validation and CPI mechanics. `solana-defi-math` owns the share and fee math. This skill owns the vault shape: the accounts, the three-role authority model, the lock discipline, and how external protocols are wrapped safely.

---

## When to Use

- Implementing or modifying a vault that pools deposits and deploys them into a strategy
- Share / unit accounting for proportional ownership
- Deposit and withdraw flows where users get a claim on a pooled position
- Operator-driven rebalancing (a bot or agent moving funds between strategies)
- Management and performance fee logic
- Wrapping an external protocol (liquid staking, CLMM/AMM, lending) via CPI

**Do not use** for a lending market with per-user debt (use `solana-lending`), or for a program with no pooled-ownership concept.

---

## The Core Idea: Shares Over a Pool

A vault holds a pool of value and issues shares. Every depositor owns `user_shares / total_shares` of the pool. The entire correctness of a vault rests on one invariant:

```
user_shares / total_shares == user_value / total_value
```

Everything else - deposits, withdrawals, fees, rebalancing - must preserve this. A deposit mints shares proportional to value added; a withdrawal burns shares proportional to value removed; the operator moving funds between strategies changes neither anyone's shares nor the invariant.

**Shares must be integers (`u64`/`u128`), never floats.** This is the single most important rule in this skill, and it is the most common real-world vault defect. See the next section.

---

## The Float Defect (read this first)

Vaults in the wild store share accounting as `f64` - fields like `total_lending_sol: f64` or `deposited_lending_sol: f64`, or instruction parameters like `withdraw_amount: f64`. **This is always a defect.** When you see it, do not extend it; flag it as a SECURITY-REVIEW finding and propose the integer replacement.

Why it is unacceptable in share accounting specifically:

- Float addition is non-associative. Two users depositing the same amount in different orders accumulate different recorded balances. The ownership invariant silently breaks.
- Errors compound over many deposits and withdrawals. A vault that runs for months drifts.
- A user's claim `deposited / total` computed in float is non-deterministic across instruction orderings - different validators replaying can disagree at the bit level.
- Borsh-serialized floats are not guaranteed bit-identical across platforms.

The fix is always the same: store shares as scaled `u128`, do the proportional math as `deposit * total_shares / total_value` with a `u128` (or `U256`) intermediate, and round in the vault's favor. The math is in `solana-defi-math/references/shares-and-exchange-rate.md`. A float parameter at the instruction boundary (`withdraw_amount: f64`) is doubly bad: clients pass it as a JS `number`, losing precision before the program even runs. Take share amounts as integer `u128`.

---

## The Account Model

A vault is typically three account types.

**Config** (singleton). Owns: the admin authority, the operator (bot/agent) pubkey, the fee wallet, the allow-list of external pools/strategies the operator may use, and the fee parameters (management fee rate, performance fee rate, fee-collection timer). It does not hold per-user state or tokens.

**VaultInfo** (one per vault, or per strategy position). Owns: the current strategy/pool identity, the aggregate position size in **integer share units** (`total_shares: u128`), the lock flag, and any reserve token balances held between operations. This is where the float defect usually appears - keep every value here an integer.

**UserInfo** (one per user). Owns: the user's **integer** share balance (`share: u128`) and the cost basis needed for performance-fee calculation (the amount they deposited, in token units). PDA-derived from the user's key so it is unforgeable.

Tokens live in vault-owned token accounts (PDAs), never in the info accounts. The info accounts are accounting records; the vault PDA is the authority that signs CPI to move the real tokens.

Layouts, PDA seeds, and the integer-only discipline: `references/account-model.md`.

---

## The Three-Role Authority Model

Vaults separate three privilege levels. Keep them distinct, and make the operator key configurable, not hardcoded.

**Admin (authority).** Initializes the vault, updates config, sets fees, and may have an emergency withdraw. Checked with `has_one = authority` or `address = config.authority`. The highest privilege; should be a multisig in production.

**Operator (bot / agent).** Executes the strategy - rebalances, opens/closes positions, swaps, moves funds between allow-listed pools. Checked against `config.operator` (named `vault_bot_server`, `ai_agent`, etc. in various repos - pick one name and use it consistently). The operator can move pooled funds but must not be able to change config, change fees, or redirect funds outside the allow-list or to itself.

**User.** Deposits and withdraws their own position. No signer constraint beyond being the transaction signer; the `UserInfo` PDA ties actions to their key.

Two disciplines that matter:

- **Take authority as an argument or from the signer at init - never hardcode a deployer pubkey.** A program with `address = pubkey!("99Txx...")` baked into `initialize` cannot be redeployed by anyone else. It is a reusability defect and a sign the program was written for one deployment only.
- **Validate the operator's powers are bounded.** The operator moving funds is normal; the operator moving funds to an arbitrary destination, or into a pool not on the allow-list, is not. Every operator action must check the target against `config.allowed_pools`.

Authority structs and the allow-list check: `references/authority-and-lifecycle.md`.

---

## The Lock State Machine

Multi-step strategy operations (deposit-then-stake, decrease-liquidity-then-swap) span CPIs and must not interleave with other users' operations. A boolean lock on `VaultInfo` enforces this:

- A multi-step flow sets `is_locked = true` at entry and clears it at completion.
- User-facing operations refuse to run while locked.

This is the vault's reentrancy guard and its consistency guard. It prevents a user deposit from landing in the middle of a rebalance and seeing a half-updated pool. When reviewing a vault, confirm every operation that leaves the pool in a transient state takes the lock, and that there is no path that sets the lock without clearing it (a stuck lock bricks the vault).

---

## External Protocol CPI

A vault's whole job is deploying funds into an external protocol - a liquid-staking pool, a CLMM, a lending market. This is the largest attack surface. The discipline:

- **Constrain the external program's identity.** `Program<'info, T>` validates the program ID; for raw `invoke_signed`, assert `address = expected_program::id()`. An unconstrained program account means the operator (or an attacker who reaches the handler) can redirect the CPI to a malicious program.
- **Hardcode fixed external accounts as named constants.** For a fixed integration (a specific staking pool), pin every account - pool, withdraw authority, reserve, fee account - to a constant pubkey. This eliminates fake-pool substitution.
- **Allow-list dynamic targets.** When the pool is chosen at runtime (the operator picks among several), gate it: `require!(config.allowed_pools.contains(&pool.key()))`. Never accept an arbitrary pool.
- **Cross-reference derived accounts from loaded state.** When accounts must be consistent with a pool (its config, its vaults), tie them: `address = pool_state.load()?.amm_config`, `constraint = token_vault.key() == pool_state.load()?.token_vault_0`. This prevents a caller from mixing accounts from different pools.
- **`reload()` after every CPI before reading balances.** The whole point of a strategy CPI is that balances change; the in-memory copy is stale until reloaded.
- **Validate the post-CPI outcome.** After deploying funds, check the expected amount actually moved (e.g. at least N% of reserve was deployed). A CPI that silently does less than asked should be caught, not assumed successful.

Patterns for staking pools, CLMMs, and the cross-reference discipline: `references/external-cpi.md`.

---

## Fees

Two fee types, both common in vaults.

**Management fee** - charged on assets, prorated to time. Taken at deposit (prorated to the fraction of the fee period remaining, so late depositors pay less) and/or collected periodically by the admin on a timer. The timer must be initialized - a fee-collection timestamp left at zero means collection is callable from genesis, defeating the time gate. Confirm `initialize` sets it.

**Performance fee** - charged on profit only, at withdrawal:

```
fee = if withdraw_value > deposited_value
      { (withdraw_value - deposited_value) * performance_fee_rate }
      else { 0 }
```

No profit, no fee. This requires `UserInfo` to store the cost basis (what they put in). Fee-rate scaling (per-`10^6`, percent), proration math, and the timer discipline: `solana-defi-math/references/fees.md` and `references/authority-and-lifecycle.md`.

---

## Repository Inspection

On a vault repo, additionally to the `solana-anchor` inspection, locate:

- The three account types (config / vault info / user info) and **check whether any financial field is `f64`** - if so, that is an immediate finding.
- The share-accounting math: where shares are minted on deposit and burned on withdraw, and the rounding direction on each.
- The authority model: admin vs operator, and whether the operator key is configurable or hardcoded.
- The lock flag and every operation that sets/clears it - look for a path that can leave it stuck.
- Every external CPI: how the program and accounts are constrained, and whether dynamic pools are allow-listed.
- The fee logic and whether the fee-collection timer is initialized.
- Dead code: commented-out handlers, abandoned fields, hardcoded dev paths in tests - flag for deletion.

---

## Common Mistakes to Avoid

- `f64` for shares, totals, or any financial field or instruction parameter - the defining vault defect.
- Share math that divides before multiplying, or multiplies two large values without a `u128`/`U256` intermediate.
- Same rounding direction for deposit (mint shares) and withdraw (burn shares) - round shares to the user *down* in both directions so the vault never over-issues or over-pays.
- Hardcoded deployer pubkey in `initialize`, making the program non-redeployable.
- An operator that can change config/fees, or move funds to an unconstrained destination or non-allow-listed pool.
- Unconstrained external program account in a CPI (program substitution).
- Reading a balance after a CPI without `reload()`.
- A lock that can be set without a guaranteed clear path (stuck-lock brick), or operations that should take the lock but do not.
- Fee-collection timer left uninitialized (collectable from genesis).
- Performance fee charged on principal, not just profit, because cost basis is not tracked.
- Leaving commented-out handlers, abandoned state fields, or hardcoded local paths in shipped code.

---

## Final Response Expectations

Follow `smart-contract-core`'s report. For vault work, the security section must address:

- Share accounting: integer representation confirmed (no floats), and the rounding direction on deposit and withdraw.
- Authority: admin vs operator boundary, operator powers bounded, authority not hardcoded.
- Lock: which operations take it and that it is always cleared.
- External CPI: how each external program and its accounts are constrained, and how dynamic pools are allow-listed.
- Fees: timer initialized, performance fee on profit only.

Name the actual handlers and fields; confirm they exist before naming them. If you found a float financial field or a hardcoded authority, surface it prominently as a finding.

---

## Reference Files

- `references/account-model.md` - config/vault-info/user-info layouts, integer-only share fields, PDA seeds
- `references/authority-and-lifecycle.md` - three-role authority, lock state machine, deposit/withdraw/rebalance flow, fee timing
- `references/external-cpi.md` - constraining external programs and accounts, allow-lists, cross-referencing, post-CPI validation

For the math: `solana-defi-math/references/shares-and-exchange-rate.md` (share accounting) and `fees.md` (fee proration).

---

## Rules

1. Shares and all financial state are integers; treat any `f64` as a SECURITY-REVIEW finding.
2. Preserve `user_shares / total_shares == user_value / total_value` across every operation.
3. Round shares to the user down on both deposit and withdraw; multiply before dividing with a widened intermediate.
4. Separate admin and operator privileges; bound operator powers to allow-listed targets.
5. Never hardcode the deployer/authority; take it from config or the signer.
6. Take the lock for any multi-step flow and guarantee it is always cleared.
7. Constrain every external program and its accounts; allow-list dynamic pools.
8. `reload()` after CPI and validate the post-CPI outcome.
9. Initialize fee timers; charge performance fees on profit only.
