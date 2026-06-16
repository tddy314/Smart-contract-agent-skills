---
name: sui-vault
description: >
  Architecture and implementation patterns for Sui strategy vaults and wrappers: pooled deposits, share accounting,
  managed rebalancing, relayer/operator authority, wrapped caps, hot-potato borrow receipts, strategy allow-lists,
  external protocol integration, fees, and emergency migration. Use whenever a Sui task involves vaults, strategies,
  wrappers, rebalancing, deposits/withdrawals, pooled shares, relayers, borrowed authority, or Suilend-style strategy
  wrappers. ALWAYS use with `sui-move` and `sui-defi-math`.
---

# Sui Vault

This skill captures Sui strategy-vault and wrapper patterns from Suilend strategy-wrapper contracts and related lending/liquid-staking references. The recurring failures are weak share accounting, operator/relayer authority drift, unbounded external strategy calls, and hot-potato receipt flows that fail to force borrowed authority or funds to return.

---

## When to Use

- Pooled-deposit vaults with shares, receipts, or proportional ownership
- Strategy wrappers that route funds into lending, liquid staking, CLMMs, or other protocols
- Operator, bot, relayer, or manager rebalancing flows
- Wrapped capability patterns or temporary borrowed authority
- Hot-potato receipts for borrow/return, flash execution, or migration
- Management/performance fees or strategy allow-lists

**Do not use** for a lending market's core reserve/obligation logic (use `sui-lending`), a standalone liquid-staking protocol without pooled strategy shares/wrapping (use `sui-staking`), or pure math-only changes (use `sui-defi-math`).

---

## Identify the Vault Shape

### 1. Pooled share vault

Users deposit assets and receive shares representing `user_shares / total_shares` of the vault.

### 2. Strategy wrapper

The contract wraps access to another protocol and may temporarily lend a capability or object to a relayer under a receipt that must be returned.

### 3. Managed strategy position

An operator rebalances funds between allowed strategies while users retain pro-rata claims.

Do not treat wrappers as plain admin helpers. A wrapper that can move pooled funds is part of the protocol's security boundary.

---

## Object and Authority Model

Expect:

- shared vault/wrapper state object;
- `AdminCap` for config/migration/emergency changes;
- `OperatorCap` or `RelayerCap` for bounded strategy actions;
- wrapped external cap or market authority;
- per-user position or share object;
- internal `Balance<T>` buckets for idle assets, deployed assets accounting, rewards, and fees;
- hot-potato receipt for temporary borrows.

Authority rules:

- Admin can configure; operator/relayer can execute within bounds.
- Operator must not be able to change fees, redirect withdrawals, or add arbitrary strategy targets.
- Wrapped caps must only be borrowed through functions that issue a receipt and require return.
- Emergency migration must be cap-gated and evented.

---

## Share Accounting

The core invariant:

```text
user_shares / total_shares == user_claim_value / total_vault_value
```

Deposit:

```text
minted_shares = deposit_value * total_shares / total_vault_value
```

Withdraw:

```text
withdraw_value = burned_shares * total_vault_value / total_shares
```

Use `sui-defi-math` for scaling and rounding. Preserve strategy value accounting: idle balance + deployed position value + claimable rewards - fees/debt.

---

## Hot-Potato / Receipt Pattern

For temporary borrowed authority or funds:

- Receipt should be no-ability or at least non-`store`, non-`copy`, non-`drop` unless justified.
- Receipt binds wrapper ID, borrower/sender, borrowed object/cap ID, amount/value, and nonce/version if needed.
- Borrow function records outstanding state and returns the receipt.
- Return function verifies receipt fields and clears outstanding state.
- Tests prove double-borrow, wrong sender, wrong wrapper, wrong amount, and missing return fail.

This pattern is visible in strategy wrappers that temporarily expose a wrapped cap or borrow authority for a bounded action.

---

## Strategy and External Protocol Discipline

For any strategy action:

- Target protocol/market/pool must be fixed, allow-listed, or cross-checked against loaded config.
- Refresh strategy value before minting/burning shares or collecting fees.
- Validate post-action balances and receipt outcomes.
- Keep slippage/min-out limits as explicit primitive args with bounds.
- Emit events for deposits, withdrawals, rebalances, fee claims, migrations, and emergency actions.

Sui has no CPI in the Solana sense, but a PTB can compose calls across packages. The wrapper still needs to constrain what objects/caps it exposes and what states it accepts back.

---

## Fees

- Management fee: usually time/value based; require initialized timestamp/epoch and max bounds.
- Performance fee: charge on profit only; requires cost basis or high-water mark.
- Withdrawal fee: clearly separate fee bucket from principal and rewards.

Fee extraction should not make user withdrawals insolvent. Round fee extraction conservatively and event it.

---

## Repository Inspection

Locate:

- vault/wrapper state structs and share fields;
- wrapped cap or authority storage;
- borrow/return receipt types;
- relayer/operator checks;
- strategy allow-list or fixed target checks;
- value computation for deployed strategy positions;
- fee computation and claim paths;
- tests for borrow/return, migration, unauthorized relayer/admin, rounding, deposit/withdraw, and emergency paths.

Source examples: Suilend `contracts/strategy_wrapper/sources/strategy_wrapper.move` and tests; Suilend `contracts/suilend/sources/staker.move`; Suilend liquid-staking storage/redeem paths.

---

## Common Mistakes to Avoid

- Minting shares from stale total value.
- Letting operator/relayer change config or redirect funds.
- A receipt that can be dropped, copied, stored, reused, or returned to the wrong wrapper.
- Strategy action accepts arbitrary target objects without an allow-list or cross-check.
- Performance fee charged on principal rather than profit.
- No post-action balance validation.
- Emergency migration lacks events or cap gating.

---

## Final Response Expectations

For vault work, state:

- vault shape and share invariant;
- authority split: admin vs operator/relayer/user;
- wrapped cap / receipt safety if present;
- refresh/value computation before share mint/burn;
- strategy target constraints;
- fee basis and rounding;
- post-action validation and tests.

---

## Reference Files

- `references/strategy-wrapper-hot-potato.md` - wrapper authority, receipts, share accounting, strategy constraints

---

## Rules

1. Preserve proportional share invariants with integer math.
2. Refresh strategy value before deposits, withdrawals, fees, and rebalances.
3. Separate admin, operator/relayer, and user powers.
4. Bind hot-potato receipts to exact wrapper/action/sender/value.
5. Allow-list or cross-check external strategy targets.
6. Validate post-action balances and emit events for state changes.
