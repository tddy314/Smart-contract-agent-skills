# Smart Contract Agent Skills

A collection of agent skills for working on smart contract codebases. Each skill is a
self-contained folder with a `SKILL.md` and optional `references/`, written for an
LLM agent that can read them on demand.

Skills cover the full workflow (inspect, plan, threat-model, implement, test, report,
hand off) plus chain-specific implementation patterns for **Solidity/EVM**, **Sui Move**,
and **Anchor/Solana**.

## Layout

```
skills/
├── smart-contract-core/        master workflow — always load first
├── pre-coding-plan/            interactive planning interview
├── threat-model/               neutral design analysis + chain-specific risk pass
├── smart-contract-testing/     test quality (invariants, edge cases, failure paths)
├── pr-workflow/                commits, PR summaries, reviewer handoff
├── evals/                      eval prompts/cases (evals.json)
│
├── solidity-evm/
│   ├── evm-lending-aave/       Aave-style lending system (Hardhat + reserve architecture)
│   ├── evm-lending-pool/       single-pool Solidity lending protocol
│   └── evm-staking-vault/      staking / yield vaults + ERC-4626
│
├── solana/
│   ├── solana-anchor/          Anchor host patterns (accounts, PDAs, CPIs, zero-copy)
│   ├── solana-defi-math/       fixed-point math, interest, shares, liquidation
│   ├── solana-lending/         reserve/obligation/refresh-before-act
│   ├── solana-staking/         native stake, LSTs, restaking, epoch rewards
│   └── solana-vault/           share accounting, authority model, external CPI
│
└── sui/
    ├── sui-move/               Sui Move base — object model, caps, Move 2024
    ├── sui-defi-math/          fixed-point, shares, oracle decimals on Sui
    ├── sui-lending/            reserves, oracles, refresh, liquidation
    ├── sui-staking/            liquid staking, LST mint/redeem, epoch refresh
    └── sui-vault/              strategy wrappers, hot-potato receipts
```

## How skills are loaded

Most skills start with `ALWAYS use this skill for ...` in their frontmatter description.
The intended pattern:

1. **`smart-contract-core`** is the entry point for every task. Load it first.
2. It tells the agent to call **`pre-coding-plan`** (interactive) and
   **`threat-model`** (one-shot) at the right points.
3. The agent then picks a chain base skill:
   - EVM / Solidity → `solidity-evm/<matching skill>` (start with the
     domain skill closest to the task)
   - Solana / Anchor → `solana/solana-anchor` (always), plus
     `solana-defi-math` when balances move
   - Sui Move → `sui/sui-move` (always), plus a `sui-*-*` domain skill
4. **`smart-contract-testing`** is loaded whenever behavior, permissions, or
   state transitions change.
5. **`pre-audit-handoffs`** is loaded when preparing a project for internal
   pre-audit review or external auditor handoff.
6. **`pr-workflow`** runs at the end, when packaging the work for a human reviewer.

## Shared workflow skills

| Skill | Purpose |
|---|---|
| [`smart-contract-core`](skills/smart-contract-core/SKILL.md) | Master workflow. Inspect → plan → threat-model → code gate → implement → test → report. |
| [`pre-coding-plan`](skills/pre-coding-plan/SKILL.md) | Interactive interview. Agent proposes understanding, user validates before any code. |
| [`threat-model`](skills/threat-model/SKILL.md) | Neutral design analysis followed by a chain-specific risk pass (EVM and Sui checklists). |
| [`smart-contract-testing`](skills/smart-contract-testing/SKILL.md) | Pushes past happy-path tests — invariants, failure paths, framework edge cases. |
| [`pre-audit-handoffs`](skills/pre-audit-handoffs/SKILL.md) | Self-audit, finding classification, test gaps, and reviewer-ready audit handoff. |
| [`pr-workflow`](skills/pr-workflow/SKILL.md) | Conventional commit titles, focused change summaries, reviewer-facing handoff. |
| [`evals`](skills/evals/evals.json) | Eval prompts and assertions used to test the skills. |

## Chain base skills

| Chain | Skill | Notes |
|---|---|---|
| EVM / Solidity | `solidity-evm/evm-lending-aave` | Aave-style reserve architecture, aToken/debt-token accounting, liquidation. |
| EVM / Solidity | `solidity-evm/evm-lending-pool` | Single-pool lending, multi-collateral, Chainlink oracles. |
| EVM / Solidity | `solidity-evm/evm-staking-vault` | Staking / yield vaults, router, ERC-4626, rewards and fees. |
| Solana | `solana/solana-anchor` | Account validation, PDAs, CPIs, zero-copy, upgrades. **Always load for Anchor.** |
| Solana | `solana/solana-defi-math` | Fixed-point, interest accrual, shares, liquidation math. **Load when balances move.** |
| Solana | `solana/solana-lending` | Three-account lending model, refresh-before-act, liquidation. |
| Solana | `solana/solana-staking` | Native stake, LSTs, restaking, epoch rewards, cooldown. |
| Solana | `solana/solana-vault` | Share accounting, authority model, safe external CPI. |
| Sui Move | `sui/sui-move` | Object model, caps, Move 2024, testing commands. **Always load for Sui.** |
| Sui Move | `sui/sui-defi-math` | Fixed-point, shares, oracle decimals on Sui. **Load when balances move.** |
| Sui Move | `sui/sui-lending` | Reserve/obligation patterns, refresh, liquidation, flash loans. |
| Sui Move | `sui/sui-staking` | Liquid staking, LST mint/redeem, validator pools, epoch refresh. |
| Sui Move | `sui/sui-vault` | Strategy wrappers, hot-potato receipts, operator flows. |

## How a skill is structured

Each skill folder follows the same shape:

```
skill-name/
├── SKILL.md           # frontmatter (name, description) + body
└── references/        # optional — supporting docs the body links to
```

The `description` in frontmatter is what an agent uses to decide whether to load the
skill, so it is written as "Use when ..." and lists the trigger keywords the agent
should recognize in the user's request.

`references/` files are detail-deep dives. The main `SKILL.md` body is intentionally
compact and only links to references for the long material (math, account layouts,
checklists, etc.).

## Conventions

- **kebab-case** for skill folder names
- **kebab-case** for the `name` field in frontmatter (matches the folder name)
- **`description`** starts with `Use when ...` and includes the trigger keywords the
  agent should match
- **No code in this repo** — these are instructions and references, not runnable code
- **Chain base skill is always loaded first** for its chain, before any domain skill
- **Domain skills pair with their math skill** whenever balances or rates change

## Branches

- `main` — public skill collection (legacy EVM packages, Title-Case layout)
- `ahng` — restructured branch: skills normalized to one-`SKILL.md`-per-skill with
  flat `references/`; EVM skills remapped under `solidity-evm/` with kebab-case
  names; Sui suite added
