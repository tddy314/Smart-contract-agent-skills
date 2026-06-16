---
name: solana-staking
description: >
  Architecture and implementation patterns for Solana staking programs and staking integrations -
  native stake-account flows, stake-pool wrappers, liquid staking, restaking, reward debt and
  checkpoint accounting, epoch-aware rewards, cooldown and unbond flows, and safe CPI into stake
  pools and restaking programs. Use whenever a task involves staking SOL or SPL/Token-2022 tokens,
  validators or stake pools, reward distribution, cooldown/unstake delays, liquid staking tokens
  like jupSOL, JitoSOL, mSOL, or sSOL, or Solayer-style restaking. ALWAYS use this skill for Solana
  staking work even if the user only says "stake", "unstake", "redeem", "claim", "rewards",
  "epoch", "validator", "cooldown", or "liquid staking". Pairs with solana-anchor (host patterns),
  solana-defi-math (reward/share math), and solana-vault when staking sits inside a strategy vault.
---

# Solana Staking

This skill encodes the Solana-specific patterns for staking protocols and staking integrations. It now covers both sides of the space:

- **integration-driven staking** - stake-pool wrappers, liquid staking, and restaking;
- **standalone staking protocols** - your own staking state, reward accounting, cooldown flows, and claim semantics.

The recurring failures are wrong authority wiring, fake-pool substitution, stale exchange-rate assumptions, weak reward checkpointing, and treating unstake as if it were just stake in reverse.

`solana-anchor` owns account validation and CPI mechanics. `solana-defi-math` owns reward/share math. This skill owns the staking shape - what accounts matter, how rewards accrue, and how stake/unstake/claim flows must be sequenced and risk-checked.

---

## When to Use

- Native stake-account or validator-coupled staking work
- Stake-pool wrappers and liquid staking integrations
- Restaking integrations
- SPL / Token-2022 staking pools
- Stake / unstake / request-unstake / redeem / claim-reward handlers
- Reward accounting tied to epochs, checkpoints, snapshots, exchange rates, or reward debt
- Validator, pool, stake authority, or withdraw authority handling
- Staking operations inside a vault or strategy wrapper

**Do not use** for a lending protocol's debt side (use `solana-lending`), or for a pure vault that merely holds an LST without performing staking actions.

---

## Identify the Staking Model First

There are four distinct staking shapes. Identify which one the repo implements before writing any code.

### 1. Native stake-account flow

This is closest to the canonical Solana Stake Program. Stake is delegated to validators through stake accounts with separate stake and withdraw authorities, lockups, and epoch-based activation/deactivation. Unstake means `Deactivate` first, then wait, then `Withdraw`.

### 2. Stake-pool / liquid staking wrapper

A program deposits SOL into an external stake pool, receives a liquid staking token (LST), and later redeems or swaps it back out. The "reward" is not a separate token transfer - it is the improving exchange rate between the LST and SOL, or the value realized on redemption.

### 3. Protocol-level token staking

Users stake a token into your own program and rewards are distributed by reward-per-share, snapshot, checkpoint, or time/epoch logic. This is where reward debt, checkpointing, and pending-unstake state become first-class.

### 4. Restaking wrapper

Usually a two-hop flow: deposit into a stake pool, receive an LST, then CPI into a second restaking program. Each hop has its own accounts, authority, and post-balance checks.

Do not reason about one shape as if it were another. Liquid staking rewards are usually exchange-rate based; token staking rewards are usually accumulator/checkpoint based.

---

## Core Accounts

### Native stake-account / validator-coupled systems

Expect some combination of:

- a global `Config` account;
- one `ValidatorStake`-style account per validator or vote state;
- one `UserStake` / `SolStakerStake`-style account per user position;
- stake authority / withdraw authority / lockup configuration;
- optional slash authority or sync-reward authority.

### Stake-pool / liquid staking wrappers

The important external accounts are usually:

- the stake pool account itself;
- the pool's withdraw authority;
- the pool's reserve stake / reserve account;
- the pool's fee account;
- the pool mint or liquid staking token mint;
- the user's ATA or vault PDA ATA holding the pool token;
- the system and token programs;
- for restaking, the extra vault/pool accounts required by the second protocol.

These are not freeform. In a fixed integration they should be pinned to named constant pubkeys. If they are dynamic, they must be allow-listed and cross-checked against the external pool state.

### Protocol-level token staking

Expect:

- a global config / authority account;
- one staking pool / pool settings account;
- one per-user stake position account;
- vault token accounts holding principal and reward inventory;
- reward accumulator / reward debt / snapshot fields;
- pending-unstake or unbonding-ticket state if unstake is delayed;
- claim records or reward-epoch state if rewards are epoch-based.

Account models and CPI patterns: `references/account-and-cpi-model.md`.

---

## Reward Accounting Models

### Exchange-rate rewards

In stake-pool wrappers and liquid staking, rewards show up as an improving conversion from the pool token back to SOL or stake. The user's principal can stay constant in token units while its redeemable value grows. Reward accounting means reading or deriving the current exchange rate correctly and applying it with integer math.

### Reward debt / snapshot accounting

In token-staking protocols, the strongest generic pattern is reward debt or accumulator checkpoints:

- the pool tracks an accumulator like `reward_per_share` or `acc_reward_per_weighted_share`;
- each user stores a snapshot / reward debt against that accumulator;
- pending reward is computed from the delta between current accumulator and stored snapshot;
- claiming updates the snapshot so claims are frequency-independent.

This is the safest general model for claimable staking rewards because it avoids iterating over all users and makes repeated claims idempotent.

### Time-weighted rewards

Some protocols intentionally weight stake by age to prevent flash-stake reward capture. This may be linear, step-based, or exponential. If the repo uses time-weighted rewards, preserve the maturity model exactly; do not simplify it into flat reward-per-share and assume it is equivalent.

### Epoch or merkle-epoch claims

Some protocols compute rewards offchain and publish an epoch root onchain. Users then claim by proving inclusion, and a per-user claim record prevents double-claiming. This is common when reward computation is expensive or depends on offchain inputs.

Never use floats in any of these models. If a repo computes an exchange rate or a withdraw amount as `f64`, treat that as a defect and replace it with integer/fixed-point math.

Reward timing, checkpointing, reward debt, time-weighting, and epoch claims: `references/rewards-and-epochs.md`.

---

## Stake and Unstake Are Not Symmetric

This is the main mental trap.

Stake is often synchronous - send SOL or tokens, receive an LST or staking receipt immediately.

Unstake is often not. Depending on the protocol it can mean:

- immediate redeem at the pool's current exchange rate;
- `request_unstake` now, then `complete_unstake` after cooldown;
- `deactivate` then later `withdraw` for native stake semantics;
- burning an LST and redeeming after an unbonding period;
- selling the LST in a market swap instead of redeeming at protocol NAV.

So for every `unstake` path, ask:

- what leaves the user's balance immediately?
- what stops earning rewards immediately?
- what becomes claimable later?
- can the request be cancelled?
- does full unstake close the position account?

Cooldowns, unbonding tickets, delayed claims, and redeem-vs-swap tradeoffs: `references/unstake-lifecycle-and-risks.md`.

---

## Native Stake Semantics

If the protocol touches the native Stake Program directly, preserve its semantics instead of inventing your own:

- stake is delegated one validator at a time;
- activation and deactivation are epoch-based, not instant;
- lockup and custodian rules gate withdrawal;
- split and merge operations require compatible state and authority;
- stake authority and withdraw authority are different powers.

When wrapping or managing native stake accounts, your program must respect those lifecycle constraints rather than pretending stake is just another SPL token balance.

---

## External CPI Discipline

The strongest integration evidence in the refs is fixed-address CPI into stake pools and restaking programs. Keep these rules:

- pin the external program's identity (`Program<'info, T>` or `address = ...`);
- for a fixed pool integration, pin every required pool account to named constants;
- for a dynamic integration, gate the chosen pool with an allow-list and cross-check any derived accounts against the loaded pool state;
- use the vault/program PDA as signer only for token accounts it actually owns;
- `reload()` token accounts after CPI before reading balances;
- validate the post-CPI outcome - did the expected number of pool tokens arrive, or did the underlying balance change by the expected amount?

For restaking, treat each hop as its own constrained integration, not as one trusted blob.

---

## Authority Boundaries

Staking protocols often mix several authorities:

- your program's admin authority;
- your program's operator/bot, if it is a managed wrapper;
- external stake-pool manager and withdraw authority;
- native stake authority and withdraw authority;
- reward admin / epoch publisher / slash authority in some protocols;
- the user's own signature.

Do not conflate them. Within your program, the operator may route staking actions but must not replace the allow-list or redirect withdrawals. When wrapping external staking, validate external authorities by address or by the external pool state; do not infer correctness merely because the CPI succeeded.

---

## Repository Inspection

On a staking repo or staking integration, locate:

- which staking model is used (native stake, pool wrapper, token staking, restaking);
- whether rewards come from an exchange rate, reward debt, time-weighting, or epoch claims;
- the external staking protocol(s) used - stake pool, liquid staking, restaking, native stake;
- the exact pool/program accounts pinned as constants, or the allow-list that gates them;
- the unstake path - immediate redeem, request + cooldown, deactivate + withdraw, unbond + redeem, or market swap;
- any epoch / timestamp / checkpoint / reward-debt fields that gate rewards or fee timing;
- any use of `f64` in exchange-rate or withdraw math - flag it immediately;
- tests that cover stake, unstake, cooldown, reward claim, and unauthorized or wrong-pool cases.

If a staking integration reads an exchange rate from a deserialized pool account, verify that account is pinned and that the conversion is integer/fixed-point. If a standalone staking program uses reward accumulators, confirm checkpointing occurs before stake state changes.

---

## Common Mistakes to Avoid

- `f64` for stake, exchange rate, reward accrual, or unstake amount.
- Treating liquid staking rewards like an explicit reward token when they are really an exchange-rate change.
- Treating unstake as the mirror image of stake and forgetting about cooldowns, latency, or swap slippage.
- Missing reward-debt or snapshot updates before stake changes, enabling repeated-claim or timing exploits.
- Unconstrained stake-pool, restaking-program, or swap-route accounts in CPI.
- Hardcoding a deployer/admin pubkey in init instead of taking it from the signer or config.
- Using stale epoch/timestamp state when computing reward or cooldown eligibility.
- Not validating the post-CPI balance change after staking, redeeming, or restaking.
- Leaving validator/pool choice unconstrained, letting an operator route to arbitrary pools.
- Forgetting claim records for epoch/merkle rewards, allowing double-claims.

---

## Final Response Expectations

Follow `smart-contract-core`'s report. For staking work, the security section must address:

- which staking model is used (native stake, pool wrapper, token staking, restaking);
- which reward model is used (exchange-rate, reward debt/snapshot, time-weighted, merkle epoch);
- how the external pool/program identity is constrained;
- what the unstake lifecycle is (immediate, delayed, deactivate+withdraw, swap-based);
- whether any float math exists in reward or unstake paths;
- how reward checkpoints, reward debt, epochs, or timers are updated before stake changes.

Name the actual handlers and fields; confirm they exist before naming them.

---

## Reference Files

- `references/account-and-cpi-model.md` - stake-pool/restaking account sets, native stake actors, fixed-address pinning, CPI flow
- `references/rewards-and-epochs.md` - exchange-rate rewards, reward debt and snapshots, time-weighting, epoch/timer updates, merkle claims
- `references/unstake-lifecycle-and-risks.md` - unstake variants, request/complete flows, cooldowns, slashing/latency/slippage risks, testing focus

For math details: `solana-defi-math/references/shares-and-exchange-rate.md`, `staleness-and-accrual.md`, and `fees.md`.

---

## Rules

1. Identify the staking model first - native stake, pool wrapper, token staking, or restaking.
2. Never use floats in staking math; treat existing float usage as SECURITY-REVIEW.
3. Constrain every external pool/program account; fixed pools should use named constant pubkeys.
4. Treat unstake as its own lifecycle, not the reverse of stake.
5. Checkpoint rewards or reward debt before changing stake, total stake, or reward rate.
6. Validate post-CPI balance changes after every stake/redeem/restake step.
7. Bound operator powers to approved pools and routes only.
8. Respect native stake semantics when wrapping the Stake Program.
