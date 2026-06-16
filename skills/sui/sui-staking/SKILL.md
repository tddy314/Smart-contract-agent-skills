---
name: sui-staking
description: >
  Architecture and implementation patterns for Sui staking and liquid-staking protocols: validator pools, LST mint/redeem,
  TreasuryCap-controlled stake certificates, epoch refresh, exchange-rate rewards, inactive validator migration, delayed
  withdrawals, staking rewards, validator rewards, epoch rewards, and staking fees. Use whenever a Sui task involves stake,
  unstake, redeem, liquid staking, validator pools, LSTs, epoch reward accounting, or checkpointed staking accounting.
  ALWAYS use with `sui-move` and `sui-defi-math`.
---

# Sui Staking

This skill captures Sui liquid-staking and staking-accounting patterns from Navi Volo and Suilend liquid-staking references. The recurring failures are stale epoch/exchange-rate state, wrong TreasuryCap/capability flow, incorrect mint/redeem rounding, skipped inactive-validator migration, and treating redeem as the mirror image of stake.

---

## When to Use

- Native SUI staking wrappers or validator-pool management
- Liquid staking token (LST) mint/redeem flows
- Stake, unstake, request-withdraw, complete-withdraw, claim, or reward functions
- Validator activation/deactivation, inactive stake migration, epoch refresh, or storage pruning
- Staking fees, exchange-rate rewards, cert/receipt objects, or TreasuryCap mint/burn
- Staking inside a strategy vault or wrapper

**Do not use** for generic rewards or incentives that are not tied to staking, validator pools, LST exchange rates, epoch staking rewards, or stake/unstake lifecycle. Use `sui-lending` for lending incentives and `sui-vault` for strategy-wrapper rewards.

---

## Identify the Staking Model First

### 1. Liquid staking protocol

Users deposit SUI, the protocol stakes with validators, and users receive an LST or certificate. Rewards usually appear as an improving exchange rate, not as a separate reward transfer.

### 2. Validator-pool manager

The protocol allocates stake across validators and periodically refreshes active/inactive state. Epoch changes are first-class behavior.

### 3. Token staking with explicit rewards

Users stake a token and accrue separate rewards through an accumulator, checkpoint, or reward-debt model.

### 4. Strategy-integrated staking

A vault/wrapper stakes on behalf of pooled users. Load `sui-vault` too.

Do not reason about all staking as one shape. Liquid-staking rewards are exchange-rate based; token-staking rewards are often accumulator based.

---

## Core Objects and Capabilities

Expect some combination of:

- shared `Storage`, `StakePool`, `ValidatorPool`, `LSTInfo`, or registry object;
- `AdminCap` for config and fee changes;
- `OperatorCap` for validator operations, refresh, or routing;
- `TreasuryCap<LST>` for mint/burn of the liquid staking token;
- validator records and inactive stake records;
- fee config / reward buckets;
- request or receipt objects for delayed redeem.

Trace exactly where `TreasuryCap` lives. If LST mint/burn can happen without the intended cap path, the protocol is broken.

---

## Refresh and Epoch Discipline

Before mint, redeem, claim, rebalance, or validator mutation:

1. Refresh current epoch from trusted Sui system/clock data as the repo does.
2. Reconcile active and inactive validator stake.
3. Update exchange rate / total SUI / total LST supply accounting.
4. Apply pending fees or rewards.
5. Then mutate user or pool state.

Refresh should usually be idempotent within an epoch. Tests should cover "refresh twice" behavior.

---

## Mint and Redeem Math

Liquid staking core:

```text
minted_lst = deposit_sui * total_lst_supply / total_underlying_sui
redeemed_sui = burned_lst * total_underlying_sui / total_lst_supply
```

Default rounding:

- mint LST: round down;
- redeem SUI: round down unless using ceil to burn enough LST for exact-withdraw semantics;
- fees: round down unless protocol docs say otherwise.

Guard:

- first depositor / zero supply;
- zero mint for nonzero deposit;
- redeem amount greater than available liquid stake;
- stale exchange rate;
- fee rate bounds;
- min stake / min available thresholds.

---

## Stake and Unstake Are Not Symmetric

Stake may mint LST immediately. Unstake can mean:

- immediate redeem from liquid buffer;
- request now, complete after epoch/cooldown;
- validator deactivation then later withdrawal;
- burn LST and receive a claim/receipt;
- redeem only after inactive stake migrates back to liquidity.

For every unstake path, ask:

- what stops earning rewards immediately?
- what object proves future claim rights?
- can the request be cancelled or transferred?
- what happens if liquidity is insufficient?
- how are fees and exchange-rate changes handled during the wait?

---

## Repository Inspection

Locate:

- stake pool / storage / validator pool objects;
- exchange-rate calculation and total underlying accounting;
- `TreasuryCap` storage and all mint/burn call sites;
- epoch refresh and inactive-validator migration logic;
- min stake / min available / fee constants;
- claim/redeem request objects or hot-potato receipts;
- tests for epoch rollover, inactive migration, rounding, and stale refresh.

Source examples: Navi `volo_liquid_staking/sources/{stake_pool,validator_pool,cert,fee_config}.move`; Suilend `liquid-staking/contracts/sources/{liquid_staking,storage,registry,fees}.move`.

---

## Common Mistakes to Avoid

- Minting/redeeming against stale exchange-rate state.
- Treating unstake as immediate when the protocol uses epoch/cooldown semantics.
- Leaking `TreasuryCap` or allowing mint/burn through the wrong capability path.
- Forgetting inactive-validator migration or validator pruning.
- Rounding LST shares in a way that over-issues ownership.
- Mixing fee/reward buckets with user principal.
- Not testing refresh idempotence and edge epochs.

---

## Final Response Expectations

For staking work, state:

- staking model used;
- cap path for `AdminCap`, `OperatorCap`, and `TreasuryCap`;
- refresh/epoch ordering;
- mint/redeem formula and rounding;
- unstake lifecycle;
- validator/inactive stake migration behavior;
- fee/reward bucket handling.

---

## Reference Files

- `references/liquid-staking-lifecycle.md` - LST objects, epoch refresh, mint/redeem, validator migration

---

## Rules

1. Identify whether rewards are exchange-rate based or explicit reward-debt based.
2. Refresh epoch/exchange-rate state before stake, redeem, claim, or validator changes.
3. Trace `TreasuryCap` and operator/admin caps end-to-end.
4. Treat unstake/redeem as its own lifecycle, not stake in reverse.
5. Keep principal, rewards, fees, and inactive stake separately accountable.
