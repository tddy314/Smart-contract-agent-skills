---
name: solana-lending
description: >
  Architecture and implementation patterns for Solana lending protocols built with Anchor -
  market/reserve/obligation account model, the refresh-before-act sequence, deposit/borrow/
  repay/withdraw/liquidate lifecycle, collateral exchange rates, loan-to-value health, and
  oracle integration. Use whenever a task involves a Solana lending or borrowing protocol:
  reserves, obligations, cTokens/collateral tokens, utilization, liquidation, or a money market.
  ALWAYS use this skill for lending-protocol work even if the user only says "reserve",
  "obligation", "collateral", "borrow", "liquidate", or "money market". Pairs with solana-anchor
  (host patterns) and solana-defi-math (the underlying math).
---

# Solana Lending

This skill encodes how a Solana lending protocol is structured and why. The architecture is not arbitrary - the three-account model and the refresh-before-act discipline exist to make stale-data exploits and same-transaction manipulation physically impossible. Get the structure right and most classes of lending bug cannot occur.

`solana-anchor` owns account validation and CPI. `solana-defi-math` owns the exchange-rate, interest, and liquidation math. This skill owns the protocol shape: which accounts exist, how a transaction is sequenced, and where the invariants live.

---

## When to Use

- Implementing or modifying a lending market, reserve, or obligation
- Deposit (supply), borrow, repay, or withdraw flows
- Collateral exchange rates and cToken accounting
- Loan-to-value health checks and liquidation
- Interest accrual in a lending context
- Oracle price integration for collateral/debt valuation

**Do not use** for a single-asset vault with no borrowing (use `solana-vault`), or for an AMM/DEX (different shape entirely).

---

## The Three-Account Architecture

A lending protocol is three account types with clear ownership of state. Keep these responsibilities separate.

**Market** (one per deployment, a singleton). Global config and authority. Owns: protocol-wide parameters, pause flag, the minimum-net-value threshold for liquidation, the admin authority. It does not hold per-asset or per-user state.

**Reserve** (one per lendable asset - USDC, SOL, etc.). Owns: the asset's liquidity pool, the collateral mint, risk parameters (LTV, liquidation threshold, the borrow-rate curve, deposit/borrow limits), interest state (cumulative borrow rate, accrued protocol fees), and the oracle pubkey for this asset. The reserve is where interest accrues and where the collateral exchange rate lives.

**Obligation** (one per user per market). Owns: the user's deposits (collateral positions across reserves) and borrows (debt positions across reserves), plus cached aggregate values (total deposited value, total borrowed value, allowed borrow value, unhealthy threshold) computed at the last refresh. Fixed-size arrays cap how many distinct reserves a user can touch.

The separation matters: a reserve never knows about individual users; an obligation never holds tokens. Tokens live in reserve-owned vaults (PDAs). The obligation is an accounting record of claims against those vaults.

State layout, field-by-field, with the zero-copy considerations: `references/account-model.md`.

---

## The Refresh-Before-Act Invariant

This is the single most important pattern in the protocol. **Every state-changing action must be preceded, in the same transaction, by a refresh of every reserve and obligation it touches.**

Why: interest accrues every slot and oracle prices move. A borrow checked against stale debt under-counts what is owed; a liquidation checked against a stale price can be wrong in either direction. Refreshing first guarantees decisions use current data.

How it is made self-enforcing - and this is the elegant part - staleness is encoded in the accounts:

1. Each reserve and obligation stores the slot it was last updated and a stale flag.
2. `refresh_reserve` accrues interest, pulls the current oracle price, and stamps the reserve fresh for the current slot.
3. `refresh_obligation` reads every one of the user's reserves (passed as `remaining_accounts`), requires each to be fresh for the current slot, recomputes the obligation's aggregate values, and stamps it fresh.
4. **Any state-changing action marks the reserves it touched stale at the end.**

Because a mutating action leaves reserves stale, you physically cannot chain two value-moving actions on the same reserve in one transaction without an intervening refresh - the second action sees a stale reserve and aborts. This kills a whole category of same-transaction manipulation.

The required transaction layout the client must build:

```
refresh_reserve(reserve_A)
refresh_reserve(reserve_B)        # one per reserve the obligation touches
refresh_obligation               # remaining_accounts = [reserve_A, reserve_B] in deposit-then-borrow order
<action: deposit | borrow | repay | withdraw | liquidate>
```

The order of `remaining_accounts` in `refresh_obligation` is not free - it must match the obligation's stored deposit-then-borrow ordering, and each pubkey is validated against the stored position. Wrong order is a hard error, not a silent miscalculation.

Full sequence, the `remaining_accounts` validation, and the staleness fields: `references/refresh-pattern.md`. The freshness primitive and accrual math: `solana-defi-math/references/staleness-and-accrual.md`.

---

## The Lifecycle

Each user action is a refresh sequence followed by one handler. The handlers and their invariants:

**Deposit / supply.** User supplies liquidity (e.g. USDC) and receives collateral tokens (cTokens) representing a growing share of the pool. cTokens minted = `liquidity / exchange_rate`, rounded down to the user. The deposit increases reserve liquidity and, if used as collateral, records a collateral position in the obligation. Enforce the reserve deposit limit.

**Borrow.** User borrows against deposited collateral. Before transferring, check the new total debt stays within the obligation's allowed borrow value (driven by each collateral's LTV). Borrowed tokens move from the reserve vault to the user via a PDA-signed transfer; the obligation records the debt with the reserve's current cumulative borrow rate as the baseline for future interest.

**Repay.** User repays debt. Compute the exact repayable amount (capped at outstanding debt, with interest accrued via refresh). Tokens move from user to reserve vault; the obligation's debt is reduced. Round the required repayment up so the reserve is never short.

**Withdraw / redeem.** User withdraws collateral. Check the withdrawal keeps the obligation healthy (post-withdraw LTV stays within limits). Burn cTokens, return liquidity rounded down to the user.

**Liquidate.** When an obligation's LTV crosses the unhealthy threshold, a liquidator repays some debt and seizes collateral plus a bonus. This is the protocol's safety mechanism and the most dangerous handler - see below.

Per-handler account structs, the PDA-signed vault transfers, and event emission: `references/lifecycle-handlers.md`.

---

## Health and Liquidation

The health of an obligation is its loan-to-value ratio:

```
ltv = total_borrowed_value / total_collateral_value
```

Two thresholds, both per-reserve and aggregated on the obligation:

- **Allowed borrow value** (from each collateral's `loan_to_value_pct`) - the ceiling for new borrows. A borrow that would exceed it is rejected.
- **Unhealthy threshold** (from `liquidation_threshold_pct`, set higher than LTV) - once crossed, the obligation is liquidatable.

The gap between the two is the buffer that keeps normal positions out of liquidation while prices wobble.

Liquidation seizes `repaid_value * (1 + liquidation_bonus)` of collateral, capped at what the position holds. The bonus scales with how unhealthy the position is and is bounded near bad-debt territory. A minimum-net-value threshold forces full liquidation of dust positions so they do not become un-liquidatable. The full bonus curve, partial-vs-full logic, and dust handling live in `solana-defi-math/references/liquidation-math.md`; the protocol policy and the handler in `references/lifecycle-handlers.md`.

The danger in liquidation handlers: every account must be validated (which obligation, which reserves, the liquidator's token accounts), the position must actually be unhealthy (reject healthy-obligation liquidation), and the math must round so the protocol and remaining depositors are never shortchanged. Treat it as the highest-review-priority handler in the protocol.

---

## Oracles

Collateral and debt are valued in a common unit using prices from an oracle. Whatever the source (a Pyth/Switchboard feed, or a protocol-maintained price account), the same disciplines apply:

- **Pin the oracle per reserve.** Store the expected oracle pubkey in the reserve at init and validate it on every refresh (`constraint = reserve.oracle_pubkey == oracle.key()`). An unconstrained oracle account is a price-spoofing hole.
- **Reject stale prices.** Require the price's publish time to be within a max-age window; abort if older. A frozen oracle must not let the protocol keep valuing positions at a dead price.
- **Validate the price is sane.** Reject NaN/zero/negative and absurd magnitudes. If the feed provides a confidence interval, enforce a maximum confidence-to-price ratio.
- **Convert to the protocol's fixed-point type at the boundary**, accounting for the oracle's exponent and the token's decimals. Store as a scaled fraction, never a float.

Oracle account validation, staleness checks, and decimal/exponent handling: `references/oracle-integration.md`.

---

## Repository Inspection

On a lending repo, additionally to the `solana-anchor` inspection, locate:

- The three account types (names vary: market/lending_market, reserve, obligation).
- The refresh handlers (`refresh_reserve`, `refresh_obligation`) - confirm they exist and that mutating handlers require freshness.
- The exchange-rate and interest code (cumulative borrow rate, `accrue_interest`).
- The liquidation handler and its health check.
- The oracle integration and where the oracle pubkey is pinned.
- The PDA seed constants for market, reserve, collateral mint, and obligation.

If a repo has mutating handlers that do not require a fresh reserve/obligation, that is a finding - flag it as a stale-data risk.

---

## Common Mistakes to Avoid

- A state-changing handler that does not require the reserve and obligation to be fresh for the current slot.
- Forgetting to mark reserves stale after a mutation, breaking the same-transaction-protection invariant.
- `refresh_obligation` that does not validate `remaining_accounts` length, order, and pubkeys against stored positions.
- An unconstrained oracle account, or no staleness/sanity check on the price.
- Allowing liquidation of a healthy obligation, or computing seize amounts with rounding that favors the liquidator over depositors.
- Using the same rounding direction for deposit (mint cTokens) and withdraw (redeem) conversions - a slow drain on the pool.
- Letting a borrow push the obligation past allowed borrow value due to checking against stale aggregates.
- No deposit/borrow limits, allowing a single reserve to grow past risk parameters.
- Dust positions that become un-liquidatable because the seize amount truncates to zero.

---

## Final Response Expectations

Follow `smart-contract-core`'s report. For lending work, the security section must address:

- Refresh discipline: does every touched handler require fresh reserve(s) and obligation, and mark stale after?
- Health math: which threshold gates borrows, which gates liquidation, and the rounding direction on each conversion.
- Oracle: how the oracle pubkey is pinned and how staleness/sanity are enforced.
- Liquidation: how a healthy obligation is rejected and how seize amounts are bounded.

Name the actual handlers and account fields; confirm they exist before naming them.

---

## Reference Files

- `references/account-model.md` - market/reserve/obligation layouts, zero-copy considerations, PDA seeds
- `references/refresh-pattern.md` - the refresh sequence, `remaining_accounts` validation, staleness fields
- `references/lifecycle-handlers.md` - deposit/borrow/repay/withdraw/liquidate handlers with account structs and PDA-signed transfers
- `references/oracle-integration.md` - oracle pinning, staleness, sanity checks, decimal/exponent conversion

For the math underlying all of this: `solana-defi-math/references/` (shares-and-exchange-rate, interest-rate-curves, staleness-and-accrual, liquidation-math).

---

## Rules

1. Keep market, reserve, and obligation responsibilities separate; tokens live in reserve vaults, never in obligations.
2. Require every touched reserve and obligation to be fresh for the current slot before any state-changing action.
3. Mark reserves stale after every mutation - this enforces same-transaction protection.
4. Validate `remaining_accounts` order against the obligation's stored positions.
5. Gate borrows on allowed borrow value; gate liquidation on the unhealthy threshold.
6. Pin the oracle per reserve and reject stale or insane prices.
7. Round every conversion in the protocol's favor; never use the same direction for deposit and withdraw.
8. Reject liquidation of a healthy obligation; bound seize amounts and handle dust.
