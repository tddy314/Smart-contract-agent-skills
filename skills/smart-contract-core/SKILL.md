---
name: smart-contract-core
description: >
  Defines the master workflow for any smart contract task — feature implementation, bug fixing,
  refactoring, test writing, deployment scripts, migrations, or protocol logic. This skill
  orchestrates inspection, planning, threat modeling, implementation, and reporting. ALWAYS use
  this skill for any smart contract task, even if the user doesn't explicitly ask for planning
  or risk assessment. Covers Solidity/EVM, Sui Move, Anchor/Solana, and CosmWasm.
---

# Smart Contract Core

This is the base skill for all smart contract tasks. It defines how the agent should work before coding, while coding, and after finishing.

Other skills (`pre-coding-plan`, `threat-model`, chain-specific skills) are loaded alongside this one. This skill owns the workflow. The others provide checklists at the right moments.

---

## When to Use

Use this skill when the task involves any of the following:

- Feature implementation
- Bug fixing
- Refactoring
- Smart contract tests
- Deployment scripts
- Migration scripts
- Protocol logic
- Review preparation

**Do not use** for cosmetic changes (typo fixes, comment updates, README edits, variable renames that don't affect logic).

---

## Workflow

Follow this sequence. Each step is mandatory unless marked optional.

### Step 1: Inspect the Repository

Before anything else, understand the codebase.

**If existing repo:**
- Read `contracts/`, `src/`, `sources/`, `programs/` (whichever exists)
- Read config files: `foundry.toml`, `hardhat.config.*`, `Move.toml`, `Anchor.toml`, `Cargo.toml`
- Read `tests/`, `test/`
- Read `README.md`
- Identify: chain, framework, project structure, access control model, existing patterns
- Identify the contract model before planning:
  - EVM: roles, state machine, asset flow, external calls, time-based behavior
  - Sui: objects, capabilities, ownership model, coin/balance flow, checkpointed accounting

**If new repo:**
- Check for any scaffold (config files, package manifests)
- If none found, note "fresh project" and proceed
- Ask the user about intended chain/framework if not clear

### Step 2: Plan (Interactive)

Use the `pre-coding-plan` skill. This is an interactive interview — the agent proposes understanding, the user validates or corrects. Do not proceed until the user confirms the plan.

### Step 3: Threat Model (One-Shot)

Use the `threat-model` skill. Produce a risk analysis based on the confirmed plan. Present it to the user for review. If the user flags something incorrect, revise. Otherwise proceed.

### Step 4: Code Gate

Before writing any code, ask:

> "Plan confirmed, threats reviewed. Ready to implement?"

Wait for explicit user confirmation. The user may want to revise the plan or threat model at this point.

### Step 5: Implement

Write the code. Follow these rules:

- Follow existing repo patterns before creating new ones
- Do not make unrelated refactors
- Do not change public APIs unless required
- Do not touch secrets, private keys, production RPCs, deployment keys, or live config without explicit instruction
- List assumptions clearly as you go

Apply the branch that matches the repo:

- EVM / Solidity:
  - preserve or explicitly revise the state machine
  - keep access control and event behavior intentional
  - keep asset flow easy to trace end-to-end
  - prefer checks-effects-interactions around external calls
  - treat withdrawal/refund paths and timeout semantics as first-class logic, not edge cases
- Sui Move:
  - preserve explicit object ownership and transfer semantics
  - trace capability creation, storage, transfer, and use
  - keep principal, rewards, fees, and other balances economically separated unless commingling is explicitly intended
  - update checkpointed accounting before mutating rates, debts, totals, or balances when the design depends on elapsed time
  - treat multi-transaction object evolution as core behavior, not a secondary concern

### Step 6: Test

**If existing repo:** Run existing tests (`forge test`, `sui move test`, `anchor test`, `cargo test`, etc.). Report pass/fail.

**If new repo:** Skip testing for now. Note "no tests in repo" in the report.

Do not write new tests in this phase. Testing quality is handled by the `smart-contract-testing` skill.

### Step 7: Report

Produce a condensed final report. Do not repeat the full plan or threat model — summarize the key points.

```
Summary:
<What was done and why — 2-3 sentences>

Files changed:
- <file path> — <what changed>

Tests run:
<command> — <pass/fail count, or "none in repo">

Assumptions:
- <key assumptions from planning>

Security considerations:
- <key risks from threat model>

Remaining risks:
- <anything flagged but not addressed>

Human review focus:
- <where to focus review attention>
```

---

## Rules

1. Always inspect before coding.
2. Always plan before implementing.
3. Always assess threats before coding.
4. Always ask for confirmation before writing code.
5. Always produce a final report.
6. Never assume the user's intent — ask.
7. Never trust the repo blindly — existing code may have bugs.
8. Never touch production infrastructure without explicit instruction.
9. For EVM, reason in terms of roles, state transitions, value transfer, and time.
10. For Sui, reason in terms of objects, capabilities, ownership, and balance flow.
