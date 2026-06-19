# Protocol Logic Checklist

Use this checklist before chain-specific checks. It catches business-logic bugs that can exist on any smart contract platform.

## State Machine Logic

Map every user-visible flow as states and transitions.

Check:

- each action is only allowed in the correct state;
- terminal states cannot be used again;
- pause, cancel, close, dispute, claim, liquidate, and emergency states do not conflict;
- partial completion cannot leave the system in a state that breaks later actions;
- retry behavior is intentional after failed, reverted, aborted, or partially settled steps;
- state transitions emit or expose enough information for off-chain systems when relevant.

Bug patterns:

- claim remains possible after withdrawal;
- request can be finalized twice;
- cancellation and completion both remain valid;
- pause blocks normal users but accidentally blocks required recovery;
- migration marks new state without disabling old state.

## Accounting Logic

Trace every global total and per-user value together.

Check:

- user balances sum to global totals where that invariant should hold;
- deposits increase the right totals and withdrawals decrease them;
- fees, rewards, debt, collateral, shares, reserves, and insurance are not double-counted;
- accounting updates happen on every path, including early return, error handling, cancel, liquidation, and emergency exit;
- rounding direction is intentional for minting shares, burning shares, repaying debt, claiming rewards, and charging fees;
- dust cannot be accumulated or repeatedly extracted into meaningful value.

Bug patterns:

- `totalDeposits` decreases but user balance does not;
- rewards are accrued twice when stake and unstake happen in the same period;
- fee is charged on gross amount in one path and net amount in another;
- shares are minted using stale total assets;
- debt index updates globally but not per position.

## Business-Rule Bypass

List every rule the protocol claims to enforce.

Check:

- minimums, maximums, caps, utilization limits, and per-user limits apply to every entry point;
- allowlists, denylists, market-enable flags, and pause flags cover alternate paths;
- cooldowns, lockups, deadlines, timelocks, dispute windows, and grace periods cannot be skipped;
- helper, internal, admin, router, batch, callback, or migration functions cannot bypass user-facing checks unexpectedly;
- changing config cannot invalidate existing user positions unless that is explicitly allowed.

Bug patterns:

- deposit cap applies to `deposit` but not `depositFor`;
- pause blocks `borrow` but not `borrowFromCollateral`;
- whitelist is checked on mint but not transfer or redeem;
- cooldown applies to normal withdraw but not emergency withdraw;
- admin lowers max LTV and instantly makes healthy users liquidatable without intended grace.

## Order of Operations

For every value-moving action, write the intended order.

Check:

- refresh/checkpoint/accrue happens before reading rates, prices, rewards, debts, shares, or limits;
- validation happens before mutation when invalid actions must leave no state changes;
- state is updated before external calls when reentrancy or callbacks matter;
- assets move only after all required checks pass;
- events describe the final committed state, not a stale intermediate state;
- failure after asset movement cannot leave accounting inconsistent.

Bug patterns:

- transfer happens before recording debt;
- rewards are computed before checkpointing elapsed time;
- oracle freshness is checked after borrow amount is accepted;
- shares are burned before verifying enough liquidity exists;
- external strategy call sees stale vault accounting.

## Multi-Step Flow Consistency

Review complete flows, not only single functions.

Check:

- deposit -> withdraw;
- stake -> claim -> unstake;
- borrow -> repay -> withdraw collateral;
- borrow -> become unhealthy -> liquidate;
- request withdraw -> finalize withdraw -> claim;
- flash borrow -> repay/settle;
- bridge/send -> receive/finalize;
- migrate old position -> use new position;
- admin config change -> user action before and after change.

For each flow, ask:

- what state must carry from one step to the next?
- what can change between steps?
- who can interfere between steps?
- can the second step be called without the first?
- can the first step be replayed after the second?
- what happens if the middle step is skipped, delayed, or front-run?

## Invariant Checks

Identify protocol-level truths that should hold across all valid actions.

Common invariants:

- assets are greater than or equal to liabilities;
- total shares correspond to total assets under the exchange-rate formula;
- sum of user balances equals global total, minus explicitly tracked fees or reserves;
- collateral value and debt value use compatible units and prices;
- a user cannot claim more rewards than accrued;
- debt cannot become negative;
- utilization cannot exceed the intended maximum unless insolvency is explicitly modeled;
- caps cannot be exceeded by splitting actions across accounts or transactions;
- ownership or capability cannot be duplicated.

If an invariant is intentionally not strict, document the reason and the compensating control.

## Adversarial Scenarios

Assume users choose timing and transaction shape to maximize advantage.

Check:

- splitting one action into many small actions;
- batching multiple actions in one transaction;
- acting in the same block, slot, checkpoint, or epoch as another user;
- acting immediately before or after admin config changes;
- acting immediately before or after oracle/rate/exchange-rate updates;
- front-running or back-running when the chain execution model allows it;
- using multiple accounts to bypass per-user limits;
- using tiny amounts, max amounts, zero amounts, and exact-boundary amounts;
- repeatedly entering and exiting to farm rounding, rewards, or fees.

## Reporting Rule

When this checklist finds an issue, report the broken rule and the exact flow.

Good:

```text
Finding:
- Component: withdraw request lifecycle
- Description: A finalized request is not marked consumed, so the same request can be finalized again.
- Scenario: user requestWithdraw -> finalizeWithdraw -> finalizeWithdraw again
- Broken invariant: each withdraw request settles at most once
```

Bad:

```text
Possible state bug around withdrawals.
```
