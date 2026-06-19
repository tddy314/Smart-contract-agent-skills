---
name: pre-audit-handoffs
description: >
  Use when preparing a smart contract codebase for external audit, internal pre-audit review,
  audit readiness, security handoff, bug hunting before audit, or reviewer-facing protocol
  documentation. This skill makes the agent inspect audit scope, self-audit for bugs,
  classify findings, identify missing tests and invariants, and produce a concise audit
  handoff package with architecture, privileges, asset flows, known risks, assumptions,
  commands run, and recommended reviewer focus. Use for Solidity/EVM, Sui Move,
  Solana/Anchor, and other smart contract systems.
---

# Pre-Audit Handoffs

Prepare a smart contract project for an external auditor or internal security reviewer. The goal is to find obvious bugs before the audit, document what remains risky, and hand off enough context that reviewers can spend time on the sharp edges instead of rediscovering the system from scratch.

This skill is not an audit certification. Never claim the code is secure, audited, production-ready, or free of bugs. Report what was inspected, what was found, what was tested, and what still needs review.

---

## Relationship to Other Skills

Use this skill after basic repository inspection and before final audit delivery.

- Load `smart-contract-core` for the base smart contract workflow.
- Load `threat-model` when the handoff needs design-flow analysis or risk reasoning.
- Load `smart-contract-testing` when identifying or writing missing tests.
- Load the matching chain or domain skill before chain-specific review:
  - Sui: `sui-move`, plus `sui-lending`, `sui-staking`, `sui-vault`, or `sui-defi-math` when relevant
  - Solana: `solana-anchor`, plus `solana-lending`, `solana-staking`, `solana-vault`, or `solana-defi-math` when relevant
  - EVM: the closest `solidity-evm/*` domain skill when relevant

Do not replace external audit with this skill. Use it to make the audit scope cleaner and to surface known problems early.

---

## Workflow

### Step 1: Confirm Audit Scope

Inspect the repository and state the proposed scope before reviewing deeply.

Include:

- in-scope contracts, modules, programs, libraries, scripts, and tests;
- out-of-scope files and why they are excluded;
- chain and framework;
- deployed or expected deployment model;
- upgradeability, migration, or initialization assumptions;
- external dependencies: tokens, oracles, DEXs, bridges, staking systems, CPIs, governance, keepers, relayers.

If scope is unclear, propose a scope from the repo and ask the user to confirm before producing the final handoff.

### Step 2: Build the System Map

Map the system before looking for bugs.

Cover:

- actors: user, admin, owner, guardian, operator, keeper, liquidator, relayer, governance, external protocol;
- privileged powers and how they are authorized;
- assets and economic roles: principal, collateral, debt, shares, rewards, fees, reserves, insurance, escrowed funds;
- state machines: deposits, borrows, repayments, withdrawals, claims, liquidation, staking, cooldown, pause, upgrade, migration;
- external calls and failure behavior;
- time, epoch, checkpoint, oracle, or accrual dependencies;
- invariants that should never break.

Keep the map factual. It should help an auditor understand the system quickly.

### Step 3: Self-Audit for Bugs

Run a bug-finding pass against the mapped system. Prefer concrete findings with evidence over vague warnings.

First load `references/protocol-logic-checklist.md` and run the protocol-logic pass. Then load the relevant chain-specific checklist.

For every suspicious issue, ask:

1. What exact entry point or state transition is involved?
2. Which actor can trigger it?
3. What state, asset, account, object, or external dependency changes?
4. What invariant breaks or what loss/confusion can occur?
5. What code, test, or documentation supports the finding?
6. What would fix or mitigate it?

Do not pad the report with generic checklist items. If a risk is only theoretical or depends on an unknown assumption, mark it as an open question or review focus.

### Step 4: Classify Findings

Use `references/finding-severity.md` when classifying issues.

Each finding must include:

```text
Finding:
- Severity:
- Component:
- Description:
- Impact:
- Scenario:
- Evidence:
- Recommendation:
- Status:
```

Use `Status` values such as:

- `Confirmed`
- `Likely`
- `Needs user confirmation`
- `Test gap`
- `Informational`

### Step 5: Identify Test and Invariant Gaps

Use `smart-contract-testing` for detailed test design.

At minimum, identify whether tests cover:

- unauthorized actors;
- invalid state transitions;
- boundary values and zero/non-zero cases;
- stale oracle, stale rate, stale epoch, or stale accumulator behavior;
- replay, duplicate action, repeated claim, repeated withdrawal, or reused receipt;
- wrong asset, wrong mint, wrong object, wrong account, wrong recipient;
- external call failure or malicious external dependency behavior;
- protocol invariants after multi-step flows.

Mark gaps separately from confirmed bugs. A missing test is not automatically a vulnerability, but it is useful audit handoff material.

### Step 6: Produce the Handoff

Use `references/audit-handoff-template.md` for the final structure.

The handoff must include:

- scope and out-of-scope items;
- architecture summary;
- actors and privileges;
- asset and accounting map;
- external dependencies and trust assumptions;
- self-audit findings;
- test gaps and commands run;
- known limitations;
- recommended auditor focus;
- open questions.

Keep the final handoff reviewer-facing. Do not include long internal reasoning transcripts.

---

## Audit References

Always load:

- `references/protocol-logic-checklist.md` - chain-agnostic protocol logic issues: state machines, accounting, business-rule bypass, ordering, multi-step flows, invariants, adversarial scenarios

Load only the relevant chain checklist:


- `references/evm-pre-audit-checklist.md` - Solidity/EVM issues: access control, reentrancy, ERC20 behavior, oracle pricing, upgradeability, liquidation, withdrawals
- `references/sui-pre-audit-checklist.md` - Sui Move issues: object ownership, capabilities, Coin/Balance flow, dynamic fields, receipts, stale epoch/oracle state
- `references/solana-pre-audit-checklist.md` - Solana/Anchor issues: PDA seeds, signer and owner checks, account substitution, CPI validation, token account validation

---

## Final Output

Use this shape unless the user asks for a different handoff format:

```text
Pre-Audit Handoff:
- Scope:
- Out of scope:
- Protocol summary:
- Architecture map:
- Actors and privileges:
- Assets and accounting:
- External dependencies:
- Self-audit findings:
- Test gaps:
- Commands run:
- Known limitations:
- Recommended auditor focus:
- Open questions:
```

If no confirmed bugs are found, say so clearly and still report test gaps, assumptions, and review focus.

---

## Rules

1. Inspect code and tests before writing the handoff.
2. Separate confirmed findings, likely findings, test gaps, assumptions, and review focus.
3. Prefer evidence-backed findings over generic checklist noise.
4. Always mention privileged roles, asset movement, external dependencies, and upgrade or migration assumptions.
5. Report commands actually run; do not imply tests were run if they were only proposed.
6. Never claim the project is secure, audited, production-ready, or bug-free.
