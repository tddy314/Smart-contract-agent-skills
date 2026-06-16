---
name: threat-model
description: >
  Makes the agent analyze smart contract design logic before implementation, review, deployment,
  or handoff. This skill produces a neutral analysis of the design — what it does, how it works,
  what depends on what, and what the possible outcomes are. The agent examines the plan and
  reports findings without biasing toward finding problems. ALWAYS use this skill for any smart
  contract task involving features, permissions, asset movement, oracle integration, cross-contract
  calls, migrations, or deployment. Works for both existing repos and new/blank projects.
---

# Design Analysis

Before implementing smart contract changes, the agent examines the design logic and reports findings. This is a neutral analysis — the agent follows the logic and reports what it finds, not a hunt for bugs.

The goal is understanding: what does this design do, how does it work, and what are the possible outcomes. Some findings may be risks. Some may be good properties. Some may be open questions. Report all of them.

After the neutral flow analysis, force a chain-specific risk pass. Do not stay generic.

---

## When to Use

- Feature design
- Contract implementation
- Protocol refactors
- Permission changes
- Asset movement
- Oracle integration
- Cross-contract calls
- CPI / IBC / bridge logic
- Migration
- Deployment preparation

This applies to existing repos and new/blank projects. For existing repos, analyze the current code. For new projects, analyze the plan.

---

## How It Works

The agent has already inspected the repo (if it exists) and completed the interactive plan. Now the agent examines the design logic and reports findings.

### Approach

Follow the logic through the system. For each component, ask: what does this do, what affects it, what does it affect, and what happens in each case.

Do not start with "what could go wrong." Start with "how does this work."

```
Agent thinking:
- updateRewardRate() writes to reward_config.reward_rate
- reward_config.reward_rate is read by calculateRewards()
- calculateRewards() determines user payouts
- So updateRewardRate() affects user payouts
- The function requires AdminCap
- AdminCap is a transferable object
- If AdminCap is transferred, the new holder can call updateRewardRate()
- This is a design property — not good or bad, just a finding
```

### Output Format

```
Design summary:
<What the change does — 2-3 sentences>

Components touched:
- <function/module/account> — <what it does, what it reads, what it writes>

Flow:
<How the change works end-to-end: entry point → logic → state changes → effects>

Properties:
- <Design property 1 — e.g., "Only AdminCap holder can update rate">
- <Design property 2 — e.g., "Rate change takes effect immediately">
- <Design property 3 — e.g., "No upper bound on rate">

Dependencies:
- <What depends on what — e.g., "calculateRewards() depends on reward_config.reward_rate">

Possible outcomes:
- <Outcome 1: what happens in the normal case>
- <Outcome 2: what happens if admin sets rate to 0>
- <Outcome 3: what happens if AdminCap is transferred>

Open questions:
- <Anything the agent is unsure about or needs the user to decide>
```

### Checklist

Examine each of these aspects. Only include those that are relevant — skip if not applicable.

- Who can call this? What do they need to hold or prove?
- What state changes? What reads that state?
- What assets move? From where to where?
- What external systems are involved? What happens if they fail or behave unexpectedly?
- What depends on timing? What if things happen in an unexpected order?
- What is the admin/operator trusted to do? What can they not do?
- What happens on migration or upgrade?
- What is not enforced? What is left to trust?

For each relevant aspect, report what you find — whether it's a strength, a limitation, or an open question.

### Chain-Specific Risk Pass

Always run the matching checklist after the neutral flow analysis.

#### EVM / Solidity

Check explicitly for:

- access control mistakes and role confusion;
- broken or missing state-transition guards;
- stuck funds or unclaimable refunds;
- reentrancy or unsafe external-call ordering;
- withdrawal-vs-push-payment implications;
- timeout / deadline / `block.timestamp` edge behavior;
- accounting drift, rounding, or wrong-recipient payout paths;
- event compatibility when off-chain systems depend on them.

#### Sui Move

Check explicitly for:

- capability misuse or unintended capability transfer;
- object ownership mistakes across transactions;
- principal/reward/fee commingling in balances;
- incorrect coin / balance split-join-transfer flow;
- stale accumulator, checkpoint, rate, or debt updates;
- shared-object entry points that rely on invalid state assumptions;
- missing cleanup / return paths for borrowed or shared test objects;
- assumptions about who can hold, move, or wrap the governing object.

### User Review

After producing the analysis, present it to the user with:

> "Design analysis complete. Review and flag anything that needs adjustment."

**If the user flags something:** Revise the affected section and re-present.

**If the user approves:** Proceed to the code gate in the core workflow.

---

## Example

**Task:** "Add admin function to update reward rate."

**Agent:**

```
Design summary:
Adds an admin-callable function to update the reward rate stored in
reward_config. The new rate affects future reward calculations.

Components touched:
- updateRewardRate(uint256 newRate) — new function, writes reward_config.reward_rate
- reward_config.reward_rate — existing state, read by calculateRewards()
- AdminCap — existing capability, required to call updateRewardRate()

Flow:
1. Admin calls updateRewardRate(newRate) holding AdminCap
2. Function checks AdminCap presence
3. Function checks newRate <= max_reward_rate (new constraint)
4. Function writes newRate to reward_config.reward_rate
5. Function emits RewardRateUpdated event
6. Next call to calculateRewards() uses the new rate

Properties:
- Only AdminCap holder can update rate
- Rate is capped at max_reward_rate
- Rate change takes effect immediately
- Event is emitted for off-chain monitoring

Dependencies:
- calculateRewards() reads reward_config.reward_rate — affected by any change
- AdminCap is transferable — whoever holds it can update rate

Possible outcomes:
- Admin sets rate within bounds: rate updates, users earn new rate
- Admin sets rate above max: transaction reverts
- Admin sets rate to 0: users earn nothing (valid but may be unintended)
- AdminCap is transferred: new holder gains rate-update ability
- Non-holder calls: transaction reverts

Open questions:
- Should there be a minimum rate to prevent zero-reward scenarios?
- Should rate changes have a delay before taking effect?

Chain-specific findings:
- Sui capability path is explicit: whoever controls AdminCap controls rate changes
- If accrued rewards are not checkpointed before changing the rate, future reward math may overpay or underpay
- Because reward logic is time-sensitive, same-checkpoint and cross-checkpoint behavior should be reviewed explicitly
```

**User:** "No floor, no delay. Looks good."

**Agent:** Proceeds to code gate.

---

## Rules

1. Follow the logic before making judgments.
2. Report findings neutrally — strengths, limitations, and open questions.
3. Do not manufacture problems to appear thorough.
4. Do not claim the code is audited, secure, or production-safe.
5. If unsure about a finding, present it as an open question.
6. The user decides what is acceptable — the agent reports, the user judges.
