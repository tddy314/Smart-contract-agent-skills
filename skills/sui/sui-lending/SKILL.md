---
name: sui-lending
description: >
  Architecture and implementation patterns for Sui lending protocols: reserves, obligations, deposits, borrows,
  repayments, withdrawals, liquidations, flash loans, oracle-backed collateral values, interest accrual, reward indexes,
  and dynamic-field account state. Use whenever a Sui task touches lending markets, NAVI/Suilend-style reserves,
  LTV/health factor, collateral, debt, price oracles, liquidation, flash-loan receipts, or reserve refresh. ALWAYS use
  with `sui-move` and `sui-defi-math` for Sui lending work.
---

# Sui Lending

This skill captures the Sui-specific shape of lending markets from Navi and Suilend references. The recurring failure modes are stale reserve/oracle state, wrong dynamic-field account relationships, unsafe price fallback, rounding mistakes in shares/debt, and hot-potato receipts that can be forged or not returned.

`sui-move` owns object/capability discipline. `sui-defi-math` owns decimal, interest, oracle, and rounding math. This skill owns lending protocol shape and sequencing.

---

## When to Use

- Reserve, market, obligation, lending account, or collateral object work
- Deposit, withdraw, borrow, repay, liquidate, claim-fee, claim-reward, flash-loan functions
- Oracle-backed collateral/debt value, LTV, health factor, borrow limits, liquidation threshold
- Interest compounding, reward indexes, borrow/deposit rates, utilization curves
- Dynamic-field account balances or per-asset state
- Pyth/Switchboard/Supra oracle integration used by a lending market

**Do not use** for a pure staking pool with no collateral/debt model (use `sui-staking`), a strategy wrapper with no borrow/debt accounting (use `sui-vault`), or generic Sui object work with no reserve/obligation/oracle risk model (use `sui-move`).

---

## Identify the Lending Model First

Before coding, identify:

- **Market / global object** - owns admin config, reserves, risk settings, or registry.
- **Reserve object** - one per asset; tracks liquidity, collateral supply, borrowed amount, indexes, fees, and oracle config.
- **Obligation / account object** - per user or per account; tracks deposits/collateral and borrows, often by dynamic fields.
- **Oracle object(s)** - Pyth/Switchboard/Supra adapters, price identifiers, confidence and staleness settings.
- **Receipt / hot potato objects** - flash-loan or wrapper borrow receipts that must be returned in the same PTB.

Do not assume an EVM-style mapping. In Sui, the object graph and dynamic fields are the lending state.

---

## Refresh Before Act

Every value-moving lending action should work against fresh state.

Before deposit/withdraw/borrow/repay/liquidate/claim/flash-loan settlement:

1. Refresh oracle price if needed.
2. Refresh/compound reserve interest and indexes.
3. Recompute or validate collateral/debt values.
4. Then mutate user balances, reserve liquidity, or debt.

If the repo has explicit `refresh`, `compound_interest`, `update_index`, `stale`, or epoch fields, preserve their ordering. A function that mutates debt before refreshing debt indexes is suspect.

---

## Oracle Safety

Lending protocols should not silently accept bad prices.

Checklist:

- Staleness bound uses `Clock` or an equivalent trusted timestamp.
- Confidence ratio is within configured threshold.
- Price IDs map to the reserve's configured asset.
- Fallback behavior is explicit: reject action, return `None`, or use a secondary oracle by design.
- Collateral value is conservative: do not overstate collateral; do not understate debt.

Tests should cover stale price, high confidence interval, missing price, wrong price feed, and decimal conversion boundaries.

---

## Reserve and Obligation Invariants

Track these invariants through every operation:

- Reserve liquidity plus outstanding borrows plus fees/rewards matches accounting expectations.
- User collateral/debt dynamic fields match the assets enabled in the obligation/account.
- Withdraw cannot violate LTV/health-factor requirements after refresh.
- Borrow cannot exceed reserve liquidity, borrow caps, or user collateral capacity.
- Repay decreases both user debt and reserve borrowed accounting consistently.
- Liquidation improves account health and respects close factor / liquidation bonus limits.
- Fees and rewards accrue into separate buckets and are claimable only under protocol liquidity rules.

---

## Flash Loan and Hot-Potato Receipts

If the protocol uses a flash-loan receipt:

- The receipt should have no `store`, `copy`, or `drop` abilities unless the design justifies it.
- It must encode or bind the reserve/market ID, asset type, loan amount, fee, and borrower/initiator when needed.
- Settlement must verify the exact receipt matches the outstanding loan.
- The reserve must end with principal plus fee restored.
- No path should allow a receipt to be dropped, duplicated, reused, or settled against a different reserve.

---

## Repository Inspection

For a lending repo, locate:

- reserve modules and fields for liquidity, borrowed amount, indexes, fee buckets, last update time;
- obligation/account modules and dynamic-field keys;
- price oracle adapters and staleness/confidence constants;
- interest-rate calculation modules;
- liquidation functions and formulas;
- flash-loan receipt definitions and return functions;
- test files for price failure, liquidation, account state, refresh, and flash loan.

Source examples: Navi `lending_core/sources/{reserve,logic,lending,account,calculator,flash_loan,validation}.move`; Suilend `contracts/suilend/sources/{reserve,lending_market,obligation,oracles,staker,decimal}.move`.

---

## Common Mistakes to Avoid

- Mutating deposit/borrow state before reserve interest is refreshed.
- Using stale or high-confidence oracle prices for collateral checks.
- Failing open when an oracle returns `None`.
- Mixing asset dynamic fields from one obligation/account with another.
- Rounding collateral value optimistically or debt value pessimistically.
- Allowing withdraw before health factor is recomputed.
- Flash-loan receipt can be dropped, replayed, or settled against the wrong object.
- Claiming fees/rewards from principal liquidity without checking availability.

---

## Final Response Expectations

For lending work, the final report must address:

- refresh ordering for reserve/oracle/accrual;
- oracle staleness/confidence handling;
- reserve and obligation/account invariants touched;
- rounding direction for shares/debt/collateral/liquidation math;
- capability/admin/operator boundary;
- flash-loan/receipt safety if applicable.

---

## Reference Files

- `references/reserves-oracles-refresh.md` - reserve model, oracle safety, refresh ordering, flash-loan receipts

---

## Rules

1. Refresh reserve and oracle state before value-moving lending actions.
2. Treat bad oracle data as a hard branch, not a default zero or stale value.
3. Keep reserve, obligation/account, and dynamic-field relationships explicit.
4. Use conservative rounding for collateral/debt/liquidation math.
5. Bind hot-potato receipts to the exact reserve/market/action they settle.
