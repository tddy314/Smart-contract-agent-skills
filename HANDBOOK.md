# Smart Contract Agent Skills — Usage Handbook

A practical guide for your team on how to use these skills effectively with any LLM agent or CLI.

---

## What This Is

A collection of 19 agent skills that guide an LLM through the full smart contract development lifecycle:

**Inspect → Plan → Threat Model → Code Gate → Implement → Test → Report**

Covering three chains: **Solidity/EVM**, **Solana/Anchor**, and **Sui Move**.

These are not runnable code — they are instruction sets and reference docs that tell an agent *how* to approach smart contract work correctly.

---

## Quick Start

### 1. Load the Skills

Point your agent at the `skills/` directory. The loading order matters:

```
1. smart-contract-core          ← always load first (master orchestrator)
2. Chain base skill             ← solana-anchor, sui-move, or evm-*
3. Domain skill (if applicable) ← lending, staking, vault, defi-math
4. smart-contract-testing       ← when behavior/permissions/state changes
5. pre-audit-handoffs           ← when preparing for audit
6. pr-workflow                  ← when packaging work for review
```

### 2. Give Your Prompt

Just describe your task naturally. The agent matches your prompt to the right skills based on keywords.

### 3. Follow the Workflow

The agent should walk you through the steps. Your job is to **validate** at each checkpoint — especially the planning interview and code gate.

---

## Skill Map

### Workflow Skills (chain-agnostic)

| Skill | When It Activates | What It Does |
|-------|-------------------|--------------|
| **smart-contract-core** | Every task | Orchestrates the full workflow. Entry point. |
| **pre-coding-plan** | Before implementation | Interactive interview — agent proposes, you validate. |
| **threat-model** | Before implementation | Neutral design analysis + chain-specific risk pass. |
| **smart-contract-testing** | When code changes behavior | Pushes past happy-path: invariants, failure paths, fuzz, replay. |
| **pre-audit-handoffs** | Before sending to auditors | Self-audit, severity classification, structured handoff package. |
| **pr-workflow** | When packaging a PR | Conventional commits, reviewer-oriented summaries, risk callouts. |

### Solana Skills

| Skill | When to Use |
|-------|-------------|
| **solana-anchor** | Any Anchor program work. Always load for Solana. |
| **solana-defi-math** | When balances, rates, or shares are involved. |
| **solana-lending** | Lending protocols (reserve/obligation/refresh). |
| **solana-staking** | Staking, liquid staking, restaking, epoch rewards. |
| **solana-vault** | Strategy vaults with share accounting. |

### EVM/Solidity Skills

| Skill | When to Use |
|-------|-------------|
| **evm-lending-aave** | Aave-style multi-reserve lending systems. |
| **evm-lending-pool** | Single-pool lending with Chainlink oracles. |
| **evm-staking-vault** | ERC-4626 vaults, staking, yield strategies. |

### Sui Move Skills

| Skill | When to Use |
|-------|-------------|
| **sui-move** | Any Sui Move work. Always load for Sui. |
| **sui-defi-math** | When balances, rates, or shares are involved. |
| **sui-lending** | Lending protocols (reserve/obligation/refresh). |
| **sui-staking** | Liquid staking, LST mint/redeem, epoch refresh. |
| **sui-vault** | Strategy wrappers, hot-potato receipt patterns. |

---

## How the Workflow Actually Works

Here's what should happen when you give the agent a task:

### Step 1: Inspect

The agent reads your repo — structure, dependencies, existing code, tests. It should do this **before** proposing anything.

**What you see:** The agent reading files, not asking you to describe the codebase.

**Red flag:** Agent starts coding or suggesting architecture without reading the repo first.

### Step 2: Plan (pre-coding-plan)

The agent proposes its understanding of your task — field by field:

- **Feature**: What's being built/changed
- **Actors**: Who interacts with this
- **Permissions**: Who can do what
- **State**: What data changes
- **Assets at risk**: What can be lost
- **Invariants**: What must always be true
- **Test plan**: What to verify

**Your job:** Validate each field. Correct what's wrong. Add what's missing.

**Red flag:** Agent asks you open-ended questions ("what should the permissions be?") instead of proposing and asking you to confirm.

### Step 3: Threat Model

The agent analyzes the design neutrally — tracing logic flow, reporting properties and dependencies. Then runs a chain-specific risk pass.

**What you see:** A structured analysis, not a list of scary-sounding vulnerabilities.

**Red flag:** Agent manufactures threats or jumps to solutions before finishing the analysis.

### Step 4: Code Gate

The agent asks: "Ready to implement?"

**Your job:** Say yes or redirect. This is your last checkpoint before code gets written.

**Red flag:** Agent starts writing code without asking.

### Step 5: Implement

The agent writes code using chain-specific patterns from the loaded skills.

**What you see:** Code that follows the conventions in the skill references (Anchor constraints, Sui capabilities, EVM patterns).

### Step 6: Test

The agent runs or writes tests using the correct framework:

| Chain | Test Framework |
|-------|----------------|
| Solana | LiteSVM, Mollusk |
| EVM | Foundry (forge test) |
| Sui | sui move test |

### Step 7: Report

A condensed summary:

- What changed (files, functions)
- Tests run and results
- Assumptions made
- Security considerations
- Remaining risks
- Where a human reviewer should focus

---

## Prompt Tips

### Be Specific About the Chain and Framework

```
Bad:  "Add a deposit function"
Good: "Add a deposit function to the Solana vault program in programs/vault/src/lib.rs using Anchor"
```

### Name the Domain When Applicable

The agent picks domain skills based on keywords. Help it:

```
"lending" / "borrow" / "liquidation"  → loads lending skill
"staking" / "unstake" / "rewards"     → loads staking skill
"vault" / "shares" / "strategy"       → loads vault skill
"exchange rate" / "interest" / "math" → loads defi-math skill
```

### Tell It When You're NOT Ready to Code

If you just want analysis:

```
"Before I implement this, what could go wrong?"
"Analyze the design risks — don't write code yet."
"I want a threat model, not an implementation."
```

### Tell It When You Want the Full Workflow

```
"Walk me through the full workflow: plan, threat model, implement, test, report."
```

### Tell It When You Want Just One Step

```
"Just write the tests — the code is already done."
"Just prepare the audit handoff — code and tests are complete."
"Just generate the PR summary."
```

---

## Skill Composition Rules

Skills are designed to layer. The agent should load them in combination:

| Task | Skills Loaded |
|------|---------------|
| New Anchor lending feature | core + anchor + defi-math + lending + testing |
| Bug fix in Sui staking | core + sui-move + staking + (defi-math if rates involved) |
| ERC-4626 vault from scratch | core + evm-staking-vault + testing |
| Audit prep for Solana program | core + anchor + pre-audit-handoffs |
| PR for Sui vault change | core + sui-move + sui-vault + pr-workflow |

**Rules:**
- Chain base skill (anchor, sui-move) is **always** loaded first for its chain
- Domain skills (lending, staking, vault) **pair with their math skill** when balances or rates change
- `smart-contract-core` is the entry point for **every** task
- `smart-contract-testing` is loaded whenever behavior, permissions, or state transitions change

---

## What These Skills Cannot Do

| Limitation | Why |
|------------|-----|
| Deploy contracts | Skills are instructions, not infrastructure. You deploy. |
| Access on-chain state | No RPC connections. Agent works with local code. |
| Replace a professional audit | Self-audit catches common issues; auditors catch subtle ones. |
| Run tests without a local toolchain | You need Foundry/Anchor CLI/Sui CLI installed. |
| Handle non-smart-contract code | These skills are scoped to on-chain programs and their direct integrations. |

---

## Common Mistakes

### 1. Skipping the Planning Interview

The agent should propose and you validate. If you just say "build it" and rubber-stamp the plan, you'll miss design issues that are cheap to fix now and expensive to fix later.

### 2. Ignoring the Code Gate

If the agent asks "Ready to implement?" and you immediately say yes without reading the threat model, you're skipping the safety net.

### 3. Loading the Wrong Domain Skill

If you're building a vault but the agent loaded the lending skill, the patterns won't match. Check that the right skills are active.

### 4. Not Pairing Math Skills

When balances, exchange rates, or interest calculations are involved, the math skill (defi-math) must be loaded alongside the domain skill. Without it, the agent may use naive math patterns.

### 5. Testing Only Happy Paths

The testing skill exists to push past "deposit works." It should generate: permission failures, boundary values, replay attacks, invariant checks, and fuzz targets.

---

## Folder Structure Reference

```
skills/
├── smart-contract-core/        ← always load first
├── pre-coding-plan/            ← interactive planning
├── threat-model/               ← design risk analysis
├── smart-contract-testing/     ← test quality enforcement
├── pre-audit-handoffs/         ← audit preparation
├── pr-workflow/                ← commit/PR standards
├── evals/                      ← eval cases (evals.json)
│
├── solidity-evm/
│   ├── evm-lending-aave/       ← Aave-style lending
│   ├── evm-lending-pool/       ← single-pool lending
│   └── evm-staking-vault/      ← ERC-4626 vaults
│
├── solana/
│   ├── solana-anchor/          ← Anchor base (always load)
│   ├── solana-defi-math/       ← math (load when balances move)
│   ├── solana-lending/         ← lending protocols
│   ├── solana-staking/         ← staking / LSTs
│   └── solana-vault/           ← strategy vaults
│
└── sui/
    ├── sui-move/               ← Sui base (always load)
    ├── sui-defi-math/          ← math (load when balances move)
    ├── sui-lending/            ← lending protocols
    ├── sui-staking/            ← liquid staking
    └── sui-vault/              ← strategy wrappers

test-fixtures/                   ← realistic contracts with intentional bugs
├── solidity-staking/            ← Synthetix StakingRewards (Foundry)
├── solidity-lending/            ← Aave v3 simplified (Foundry)
├── solidity-vault/              ← ERC-4626 + strategy router (Foundry)
├── solana-vault/                ← MarginFi-style share accounting (Anchor)
├── solana-lending/              ← MarginFi/Solend reserve model (Anchor)
├── solana-staking/              ← Marinade-style LST (Anchor)
├── sui-lending/                 ← Scallop-style reserve/obligation (Move)
├── sui-staking/                 ← LST mint/redeem + epoch refresh (Move)
└── sui-vault/                   ← Hot-potato receipt vault (Move)
```

Each skill folder:
```
skill-name/
├── SKILL.md           ← main instructions (compact)
└── references/        ← deep-dive docs linked from SKILL.md
```

---

*Last updated: 2026-06-19*
