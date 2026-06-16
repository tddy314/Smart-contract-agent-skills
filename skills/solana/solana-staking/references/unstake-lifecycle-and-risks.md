# Unstake Lifecycle and Risks

Self-contained patterns. Adapt names to the host repo.

## Table of Contents

- Four unstake shapes
- Cooldowns, tickets, and delayed claims
- Native deactivate and withdraw
- Swap-based unstake
- Slashing, concentration, and liquidity mismatch
- Testing focus

---

## Four unstake shapes

Unstake is not one thing. A staking protocol must make its unstake model explicit.

**Immediate redeem.** Burn or surrender the staking receipt/LST and receive the underlying asset immediately at the current exchange rate.

**Request + cooldown.** User requests unstake now, but the underlying is only claimable after a waiting period. The request itself is state.

**Deactivate + withdraw.** Native stake semantics: deactivate now, wait through epoch-based cooldown, withdraw later.

**Swap-based exit.** The program sells the LST in a market route and returns proceeds. This adds slippage and route-validation risk and is not the same as redeeming at the protocol's exchange rate.

Document which one the program uses before writing any logic.

---

## Cooldowns, tickets, and delayed claims

If unstake is delayed, the request itself is state. Common shapes are a pending request or an unbonding ticket:

```rust
pub struct PendingUnstake {
    pub owner: Pubkey,
    pub amount: u64,
    pub claimable_at_ts: u64,
}

pub struct UnbondingTicket {
    pub owner: Pubkey,
    pub amount: u64,
    pub created_at_ts: u64,
    pub redeemable_at_ts: u64,
}
```

The follow-up handler checks time/epoch eligibility before releasing assets. The protocol also has to define whether:

- requested stake stops earning rewards immediately;
- a pending request can be cancelled;
- multiple requests queue, aggregate, or are rejected;
- full completion closes the user stake account.

Those are protocol rules, not implementation details.

---

## Native deactivate and withdraw

If the protocol wraps native stake accounts, unstake follows the native Stake Program lifecycle:

1. `Deactivate` the stake;
2. wait for epoch-based deactivation to complete;
3. `Withdraw` once the stake is inactive and lockup rules allow it.

Do not compress these into a pretend instant "unstake" if the underlying semantics are delayed. Any wrapper should expose the delay honestly in state and in the user flow.

---

## Swap-based unstake

If unstake goes through a market swap, treat it like any other external trading integration:

- constrain the swap program ID;
- constrain the pool or route to an allow-list;
- require a user- or config-provided minimum-out / threshold;
- validate post-swap balances with `reload()`;
- surface slippage as a security and UX consideration.

Do not describe a market-swap unstake as if it were a deterministic redeem at protocol NAV.

---

## Slashing, concentration, and liquidity mismatch

Staking has risks vaults and lending pools do not:

- **slash risk** - delegated stake can lose value;
- **validator concentration** - routing all stake to one validator or one pool centralizes risk;
- **liquidity mismatch** - the pool token may be liquid while the underlying redeem path is delayed;
- **operator routing risk** - a managed wrapper can route to the wrong validator/pool if allow-lists are weak.

Even if the program cannot eliminate these, the skill should force the agent to surface them in the final report and in any threat model.

---

## Testing focus

For staking work, the highest-signal tests are:

- correct pool/program/account pinning;
- unauthorized caller cannot route to a different pool or validator;
- stake increases the expected LST or receipt balance;
- unstake path respects cooldown, epoch-delay, or minimum-out logic;
- reward checkpoint or reward-debt update happens before stake amount changes;
- delayed claim or claim-record logic prevents replay/double-claim;
- float-free math round-trips correctly under integer/fixed-point conversion.
