---
name: pre-coding-plan
description: >
  Forces the agent to plan before writing or editing smart contract code. This skill runs an
  interactive interview where the agent proposes understanding and the user validates, ensuring
  the task is fully understood before implementation begins. ALWAYS use this skill for any
  smart contract task involving features, protocol logic, asset movement, permissions, state
  changes, migrations, audit fixes, or complex refactors. Do not skip planning even for
  "simple" tasks — smart contract simplicity is deceptive.
---

# Pre-Coding Plan

Smart contract work should not begin directly from implementation. The agent must first understand the intended behavior, state changes, permissions, and test cases — and confirm that understanding with the user.

This skill is an interactive interview, not a one-shot template. The agent proposes, the user validates or corrects. Continue until the user confirms.

Keep the plan strict and short. The goal is a decision-ready implementation contract, not a long design essay.

---

## When to Use

- New features
- Protocol logic changes
- Asset movement
- Permission changes
- State transition changes
- Migration logic
- Audit fixes
- Complex refactors

---

## How It Works

The agent has already inspected the repository (Step 1 of the core workflow). Now, using that context, the agent interviews the user about the task.

### Interview Format

The agent proposes understanding field by field. The user confirms or corrects.

**Do not ask open-ended questions.** Propose an answer based on the codebase inspection, then ask the user to validate.

```
Agent: "This looks like an admin-only function. Only the AdminCap holder
        can update the reward rate. Correct?"
User: "Yes."

Agent: "No external calls — just a config state write to reward_config.reward_rate. Correct?"
User: "Yes."

Agent: "Should there be a max rate cap to prevent setting it unreasonably high?"
User: "Yes, 1000 basis points."
```

### Fields to Cover

Produce each field as part of the interview. The agent should propose values based on code inspection; the user validates.

```
Feature:
<What the task does — 1-2 sentences>

Actors:
- <Who interacts with this — admin, user, external contract, etc.>

Permissions:
<Who can do what — capability checks, signer validation, access control>

State touched:
- <Which state variables, objects, accounts are read or written>

Assets touched:
- <Which tokens, coins, NFTs, objects move — or "None" if config-only>

External calls:
- <Cross-contract calls, CPI, oracle reads, bridge calls, or "None">

Invariants:
- <What must always be true after this operation>

Failure cases:
- <What should be rejected — unauthorized caller, invalid input, invalid state>

Test plan:
- <Happy path test>
- <Unauthorized caller test>
- <Invalid input test>
- <Boundary value test>
- <etc.>

Assumptions:
- <What the agent assumes to be true — user should confirm or correct>

Code gate:
- Do not code until the user explicitly approves the plan.
```

Always add the chain-specific fields that apply:

### Extra Fields for EVM / Solidity

```
State transitions:
- <Which states can move to which states>

Events:
- <Which events must be emitted, reused, or preserved>

ETH / token flow:
- <Where value comes from, where it goes, and who can trigger movement>

Time assumptions:
- <block.timestamp / timeout / deadline assumptions, or "None">
```

### Extra Fields for Sui Move

```
Capability path:
- <Which capability or object authorizes the action, where it is stored, who can transfer it>

Coin / balance movement:
- <Which Coin<T> / Balance<T> values move or split, and what each balance economically represents>

Reward / accounting checkpoints:
- <What must be updated before mutating rates, totals, debts, or balances, or "None">

Object lifecycle:
- <Which objects are created, shared, transferred, wrapped, frozen, deleted, or stored as dynamic fields>

Oracle / refresh dependencies:
- <Which prices, exchange rates, epochs, indexes, or accumulators must be fresh before the action, or "None">

Receipt / hot-potato path:
- <Any receipt object that must be returned/consumed in the same PTB, or "None">
```

### Termination

The interview ends when the user confirms the full plan. The agent produces the complete plan document and asks:

> "Plan confirmed. Ready for threat assessment?"

The user says yes, and the workflow moves to the threat model.

If the user wants to revise a field mid-interview, update it and continue. Do not restart from scratch.

---

## Example

**Task:** "Add an admin function to update the reward rate."

**Agent (after inspecting the Sui Move repo):**

```
Feature:
Allow admin to update the reward rate in the staking contract.

Actors:
- Admin (holds AdminCap)
- Normal user (interacts with staking, but cannot update rate)

Permissions:
Only AdminCap holder can call updateRewardRate().

State touched:
- reward_config.reward_rate (uint256)

Assets touched:
None. Config-only change.

External calls:
- None.

Invariants:
- reward_rate must not exceed max_reward_rate (1000 basis points)
- Only AdminCap holder can call this function

Capability path:
- AdminCap authorizes the call; ownership is managed externally

Coin / balance movement:
- None. Config-only change.

Reward / accounting checkpoints:
- Existing accrued rewards must be checkpointed before the new rate applies

Failure cases:
- Non-admin caller → revert
- Rate exceeds max → revert

Test plan:
- Admin can update rate within bounds
- Non-admin cannot update rate
- Rate exceeding max is rejected
- Event is emitted on update
- Existing accrual is checkpointed before the new rate applies

Assumptions:
- AdminCap ownership is trusted and managed externally
- Max reward rate is already defined (or should we add it?)

Code gate:
- Do not code until the user explicitly approves the plan.
```

**User:** "Max rate isn't defined yet. Add it. Everything else looks good."

**Agent:** Updates the plan. Confirms again. Proceeds to threat model.
