# Test Cases — Smart Contract Agent Skills

Manual test cases for validating each skill. Each case has a prompt you can paste into any agent or CLI, what to look for in the response, and a pass/fail checklist.

---

## How to Use

1. Copy a fixture into a clean working directory (see **Fixture Setup** below)
2. Load the skills into your agent (Claude Code, CLI, or any agent runtime)
3. `cd` into the fixture directory, then paste the **Prompt**
4. Observe the agent's behavior step by step
5. Check each criterion — mark Pass/Fail
6. Notes column is for edge-case observations

**Grading**: A test passes if ALL criteria are met. Partial = Fail with notes.

---

## Fixture Setup

Each test case uses a pre-built contract fixture in `test-fixtures/`. Copy the relevant fixture into a temp directory before testing so the agent has real code to inspect.

```bash
# Example: testing solidity-staking skills
cp -r test-fixtures/solidity-staking /tmp/test-staking
cd /tmp/test-staking
# Now run your agent here
```

### Fixture Inventory

| Fixture | Based On | Chain | Used By |
|---------|----------|-------|---------|
| `test-fixtures/solidity-staking/` | Synthetix StakingRewards | EVM | TC-1.1, TC-4.1, TC-6.1 |
| `test-fixtures/solidity-lending/` | Aave v3 (simplified) | EVM | TC-2.1, TC-5.1, TC-12.1, TC-12.2, TC-13.1, TC-X.3 |
| `test-fixtures/solidity-vault/` | Yearn v3 / ERC-4626 | EVM | TC-3.1, TC-14.1 |
| `test-fixtures/solana-vault/` | MarginFi share accounting | Solana | TC-7.1, TC-7.2, TC-8.1, TC-11.1, TC-X.2 |
| `test-fixtures/solana-lending/` | MarginFi / Solend | Solana | TC-9.1, TC-9.2 |
| `test-fixtures/solana-staking/` | Marinade Finance | Solana | TC-10.1 |
| `test-fixtures/sui-lending/` | Scallop | Sui | TC-2.2, TC-15.2, TC-17.1, TC-17.2, TC-X.1 |
| `test-fixtures/sui-staking/` | Sui LST / Volo | Sui | TC-1.2, TC-4.2, TC-18.1 |
| `test-fixtures/sui-vault/` | Strategy vault + hot-potato | Sui | TC-3.2, TC-15.1, TC-19.1 |

### What's In Each Fixture

Every fixture is a minimal but realistic contract based on a real protocol, with **intentional bugs** embedded. The bugs are what the agent skills should catch. Each fixture includes:

- Source contracts with realistic state, math, and access patterns
- Build config (foundry.toml / Anchor.toml / Move.toml)
- Happy-path-only tests (EVM fixtures) — agents should identify missing test categories

**Do NOT tell the agent about the bugs.** The point is to test whether the skill guides the agent to find them.

---

## 1. smart-contract-core

The master orchestrator. Every task should flow through: Inspect → Plan → Threat Model → Code Gate → Implement → Test → Report.

### TC-1.1: New Feature (Solidity)

**Fixture:** `test-fixtures/solidity-staking/`

**Prompt:**
> Add a withdraw function to the staking contract that lets users unstake their tokens and claim rewards. The contract is in src/Staking.sol using Foundry.

| # | Criterion | Pass/Fail | Notes |
|---|-----------|-----------|-------|
| 1 | Agent inspects repo before proposing anything (reads Staking.sol, foundry.toml, test/) | | |
| 2 | Agent proposes understanding of the feature (actors, permissions, state, assets) and asks user to validate — not open-ended questions | | |
| 3 | Agent produces a design analysis (components, flow, properties, outcomes) | | |
| 4 | Agent asks "Ready to implement?" or equivalent before writing code | | |
| 5 | Agent runs existing tests if present (`forge test`) | | |
| 6 | Agent produces a condensed report: summary, files changed, tests, assumptions, security considerations, remaining risks, human review focus | | |
| 7 | **Bonus**: Agent notices existing bugs in Staking.sol (CEI violation in getReward, missing reentrancy guard, no amount > 0 checks) | | |

### TC-1.2: Bug Fix (Sui Move)

**Fixture:** `test-fixtures/sui-staking/`

**Prompt:**
> There's a bug in the reward calculation — users are getting double rewards when they refresh in the same epoch. Can you fix it? The module is in sources/liquid_staking.move.

| # | Criterion | Pass/Fail | Notes |
|---|-----------|-----------|-------|
| 1 | Agent inspects repo and traces the code before proposing a fix | | |
| 2 | Agent asks about expected behavior before assuming the fix | | |
| 3 | Agent produces a design analysis of the fix (what changes, what stays, outcomes) | | |
| 4 | Agent asks for confirmation before writing code | | |
| 5 | Agent does NOT manufacture extra bugs or over-scope the fix | | |
| 6 | Agent produces condensed report | | |
| 7 | **Bonus**: Agent identifies that refresh_epoch lacks epoch guard and can double-count rewards | | |

### TC-1.3: Greenfield Project (Solidity)

**Fixture:** None — this tests the fresh-repo path.

**Prompt:**
> I want to build a simple escrow contract in Solidity. One party deposits, the other releases or disputes. Help me design and implement it.

| # | Criterion | Pass/Fail | Notes |
|---|-----------|-----------|-------|
| 1 | Agent recognizes it's a new project and handles the fresh-repo path | | |
| 2 | Agent asks about key design decisions (dispute mechanism, timeout, arbiter, fees) | | |
| 3 | Agent produces design analysis even without existing code to inspect | | |
| 4 | Agent asks for confirmation before writing code | | |
| 5 | Agent produces condensed report | | |

---

## 2. pre-coding-plan

Interactive planning interview. Agent proposes understanding field-by-field, user validates.

### TC-2.1: Planning Interview Quality

**Fixture:** `test-fixtures/solidity-lending/`

**Prompt:**
> I want to add a flash loan feature to our lending pool. The pool is in src/LendingPool.sol.

| # | Criterion | Pass/Fail | Notes |
|---|-----------|-----------|-------|
| 1 | Agent proposes (not asks) its understanding of actors, permissions, state transitions, and assets at risk | | |
| 2 | Each field is presented for user validation, not as open-ended questions | | |
| 3 | Agent identifies the correct chain-specific extra fields (EVM: reentrancy, gas, proxy) | | |
| 4 | Agent waits for user validation before proceeding to design/implementation | | |
| 5 | Plan includes a test plan section | | |

### TC-2.2: Planning for Sui Move

**Fixture:** `test-fixtures/sui-lending/`

**Prompt:**
> I need to add a liquidation function to our Sui lending protocol. The reserve is in sources/lending.move.

| # | Criterion | Pass/Fail | Notes |
|---|-----------|-----------|-------|
| 1 | Agent proposes understanding with Sui-specific fields (object model, capabilities, Coin/Balance flow) | | |
| 2 | Agent identifies oracle dependency and refresh ordering | | |
| 3 | Agent does not use EVM-specific terminology (msg.sender, require, etc.) | | |
| 4 | Plan addresses Move 2024 syntax conventions | | |

---

## 3. threat-model

Neutral design analysis + chain-specific risk pass.

### TC-3.1: EVM Threat Model

**Fixture:** `test-fixtures/solidity-vault/`

**Prompt:**
> Before I implement this ERC-4626 vault with a strategy router, what could go wrong? Review src/StrategyVault.sol and analyze the design risks.

| # | Criterion | Pass/Fail | Notes |
|---|-----------|-----------|-------|
| 1 | Agent traces logic flow neutrally (not threat-hunting from the start) | | |
| 2 | Agent reports properties, dependencies, and outcomes | | |
| 3 | Agent runs an EVM-specific risk pass (reentrancy, approval patterns, proxy upgrade, rounding) | | |
| 4 | Analysis separates what is known vs. what needs verification | | |
| 5 | Agent does NOT jump to implementation — stays in analysis mode | | |

### TC-3.2: Sui Threat Model

**Fixture:** `test-fixtures/sui-vault/`

**Prompt:**
> We're adding a hot-potato receipt pattern for strategy rebalancing in our Sui vault. Analyze sources/vault.move for design risks before we change anything.

| # | Criterion | Pass/Fail | Notes |
|---|-----------|-----------|-------|
| 1 | Agent runs a Sui-specific risk pass (object binding, copy/drop/store abuse, capability escalation) | | |
| 2 | Analysis covers receipt replay, wrong wrapper, double borrow | | |
| 3 | Agent separates admin/operator/user authority boundaries | | |
| 4 | Agent maps object flow (which objects move, who owns them, what's consumed) | | |

---

## 4. smart-contract-testing

Test quality enforcement — pushes past happy-path.

### TC-4.1: Test Coverage Push

**Fixture:** `test-fixtures/solidity-staking/`

**Prompt:**
> I have a staking contract with only happy-path tests. Review test/Staking.t.sol and tell me what's missing.

| # | Criterion | Pass/Fail | Notes |
|---|-----------|-----------|-------|
| 1 | Agent identifies missing test categories from the baseline matrix: permissions, boundaries, replay, fuzz, invariants | | |
| 2 | Agent provides concrete test cases for each gap (not just categories) | | |
| 3 | Agent uses the correct test framework conventions (Foundry for Solidity) | | |
| 4 | Agent checks for failure path tests (reverts, error conditions) | | |
| 5 | Agent suggests invariant tests where applicable | | |

### TC-4.2: Sui Move Test Patterns

**Fixture:** `test-fixtures/sui-staking/`

**Prompt:**
> Write comprehensive tests for the liquid staking module in sources/liquid_staking.move. It has mint_lst, redeem_lst, and refresh_epoch functions.

| # | Criterion | Pass/Fail | Notes |
|---|-----------|-----------|-------|
| 1 | Agent uses `test_scenario` patterns (not generic test patterns) | | |
| 2 | Tests cover capability success/failure paths | | |
| 3 | Tests cover object ownership transitions | | |
| 4 | Tests cover epoch boundary edge cases | | |
| 5 | Agent uses `sui move test` or `sui move build` commands | | |

---

## 5. pre-audit-handoffs

Audit preparation workflow.

### TC-5.1: Audit Handoff Preparation

**Fixture:** `test-fixtures/solidity-lending/`

**Prompt:**
> We're sending our lending protocol to an auditor next week. The code is in src/LendingPool.sol. Help me prepare the handoff package.

| # | Criterion | Pass/Fail | Notes |
|---|-----------|-----------|-------|
| 1 | Agent confirms scope (which contracts, which chains) | | |
| 2 | Agent creates a system map (components, interactions, trust boundaries) | | |
| 3 | Agent runs a self-audit and classifies findings by severity | | |
| 4 | Agent identifies test coverage gaps | | |
| 5 | Agent produces a structured handoff document matching the audit template | | |
| 6 | Agent uses the correct chain-specific pre-audit checklist (EVM, Solana, or Sui) | | |

---

## 6. pr-workflow

Commits and PR summaries.

### TC-6.1: PR Summary Generation

**Fixture:** `test-fixtures/solidity-vault/`

**Prompt:**
> I've finished implementing the vault withdrawal logic in src/StrategyVault.sol. Help me prepare the PR.

| # | Criterion | Pass/Fail | Notes |
|---|-----------|-----------|-------|
| 1 | Commit message follows Conventional Commits format | | |
| 2 | PR summary is reviewer-oriented (not author-oriented) | | |
| 3 | PR includes explicit risk callouts for smart contract changes | | |
| 4 | PR separates what changed from why it changed | | |

---

## 7. solana-anchor

Anchor-specific program patterns.

### TC-7.1: Account Validation

**Fixture:** `test-fixtures/solana-vault/`

**Prompt:**
> Review the deposit instruction in programs/vault/src/lib.rs. Check the account validation and fix any issues.

| # | Criterion | Pass/Fail | Notes |
|---|-----------|-----------|-------|
| 1 | Account struct uses proper constraints: `seeds`, `bump`, `has_one`, `mut`, `init` | | |
| 2 | Signer checks are present on the depositor | | |
| 3 | PDA is derived correctly with appropriate seeds | | |
| 4 | Uses `transfer_checked` (not `transfer`) for token operations | | |
| 5 | No floating-point math — uses integer arithmetic | | |
| 6 | Calls `reload()` after any CPI that mutates an account used later | | |

### TC-7.2: CPI Pattern

**Fixture:** `test-fixtures/solana-vault/`

**Prompt:**
> The vault needs to call the token program to transfer tokens. Review the CPI pattern in programs/vault/src/lib.rs and fix any issues.

| # | Criterion | Pass/Fail | Notes |
|---|-----------|-----------|-------|
| 1 | Uses CPI context with proper signer seeds for PDA signing | | |
| 2 | Validates the target program ID | | |
| 3 | Handles the CPI result (doesn't ignore errors) | | |
| 4 | Uses `reload()` on any accounts mutated by the CPI | | |

---

## 8. solana-defi-math

Fixed-point and DeFi math patterns for Solana.

### TC-8.1: Share Accounting

**Fixture:** `test-fixtures/solana-vault/`

**Prompt:**
> Review the share calculation in the deposit function in programs/vault/src/lib.rs. Is the math correct? Explain the rounding.

| # | Criterion | Pass/Fail | Notes |
|---|-----------|-----------|-------|
| 1 | Uses integer-only math (no floats) | | |
| 2 | Exchange rate uses a fixed-point representation with explicit scaling | | |
| 3 | Rounding direction is explicit and correct (round down on deposit = favor vault) | | |
| 4 | Handles the zero-share / first-depositor edge case | | |
| 5 | Explains the shares-over-pool invariant | | |

### TC-8.2: Interest Rate Calculation

**Fixture:** `test-fixtures/solana-lending/`

**Prompt:**
> Review the interest rate and share value accounting in programs/lending/src/lib.rs. Is the math correct for a lending protocol?

| # | Criterion | Pass/Fail | Notes |
|---|-----------|-----------|-------|
| 1 | Uses fixed-point integers for all calculations | | |
| 2 | Handles kink point correctly (two-slope model) | | |
| 3 | Avoids division by zero when utilization is 0% or pool is empty | | |
| 4 | Accrual uses time-weighted calculation (not per-block) | | |
| 5 | Rounding favors the protocol on interest accrual | | |

---

## 9. solana-lending

Lending protocol architecture.

### TC-9.1: Refresh-Before-Act

**Fixture:** `test-fixtures/solana-lending/`

**Prompt:**
> Review the borrow instruction in programs/lending/src/lib.rs. Check if the reserve state is properly refreshed and if the oracle price is validated.

| # | Criterion | Pass/Fail | Notes |
|---|-----------|-----------|-------|
| 1 | Refreshes oracle/reserve/accrual state BEFORE executing the borrow | | |
| 2 | Uses the 3-account model (market, reserve, obligation) | | |
| 3 | Checks borrow limits and collateral ratios after refresh | | |
| 4 | Oracle price includes staleness check | | |
| 5 | Updates obligation state after the borrow | | |

### TC-9.2: Liquidation Flow

**Fixture:** `test-fixtures/solana-lending/`

**Prompt:**
> Review the liquidation instruction in programs/lending/src/lib.rs. A liquidator repays part of an unhealthy obligation and receives discounted collateral. Are there any issues?

| # | Criterion | Pass/Fail | Notes |
|---|-----------|-----------|-------|
| 1 | Refreshes all state before checking health | | |
| 2 | Validates the obligation is actually unhealthy | | |
| 3 | Enforces close factor (max liquidation percentage) | | |
| 4 | Applies liquidation discount/bonus correctly | | |
| 5 | Updates both the repaid liability and seized collateral | | |

---

## 10. solana-staking

Staking and liquid staking patterns.

### TC-10.1: Liquid Staking Design

**Fixture:** `test-fixtures/solana-staking/`

**Prompt:**
> Review the liquid staking program in programs/staking/src/lib.rs. Users deposit SOL, receive mSOL, and can redeem after an unstake period. What's wrong with the design?

| # | Criterion | Pass/Fail | Notes |
|---|-----------|-----------|-------|
| 1 | Identifies the staking model (pool wrapper / token staking) | | |
| 2 | Handles stake/unstake asymmetry (instant stake, delayed unstake) | | |
| 3 | Exchange rate accounting uses epoch-based refresh | | |
| 4 | Reward distribution model is explicit (rebase vs. exchange-rate) | | |
| 5 | Covers the cooldown/deactivation lifecycle | | |

---

## 11. solana-vault

Strategy vault patterns.

### TC-11.1: Vault Share Accounting

**Fixture:** `test-fixtures/solana-vault/`

**Prompt:**
> Review deposit and withdraw in programs/vault/src/lib.rs. This vault delegates funds to external strategies. Check the share accounting, authority model, and CPI safety.

| # | Criterion | Pass/Fail | Notes |
|---|-----------|-----------|-------|
| 1 | Maintains the share-over-pool invariant | | |
| 2 | Detects and handles float defects (idle vs. deployed balance) | | |
| 3 | Authority model separates admin/operator/user roles | | |
| 4 | Lock state machine prevents withdrawals during rebalancing | | |
| 5 | External CPI follows safe constraints (validated program, checked accounts) | | |
| 6 | Fee calculation is explicit and documented | | |

---

## 12. evm-lending-aave

Aave-style lending architecture.

### TC-12.1: Reserve Architecture

**Fixture:** `test-fixtures/solidity-lending/`

**Prompt:**
> Review the supply function in src/LendingPool.sol. Users deposit tokens and receive aTokens. Check the index update logic and reserve state management.

| # | Criterion | Pass/Fail | Notes |
|---|-----------|-----------|-------|
| 1 | Uses reserve-first architecture (reserve config, liquidity index, variable borrow index) | | |
| 2 | Mints aTokens at the correct scaled amount (amount / liquidityIndex) | | |
| 3 | Updates reserve state (liquidity, indexes) before minting | | |
| 4 | Handles the first-deposit edge case | | |
| 5 | Uses the Pool/PoolConfigurator separation | | |

### TC-12.2: Liquidation

**Fixture:** `test-fixtures/solidity-lending/`

**Prompt:**
> Review the liquidate function in src/LendingPool.sol. Check the health factor validation, close factor enforcement, and collateral seizure logic.

| # | Criterion | Pass/Fail | Notes |
|---|-----------|-----------|-------|
| 1 | Updates indexes before health factor calculation | | |
| 2 | Health factor check uses oracle prices | | |
| 3 | Close factor limits the max repayment | | |
| 4 | Liquidation bonus is applied to collateral seizure | | |
| 5 | Burns debt tokens and transfers aTokens correctly | | |

---

## 13. evm-lending-pool

Single-pool lending protocol.

### TC-13.1: Multi-Collateral Lending

**Fixture:** `test-fixtures/solidity-lending/`

**Prompt:**
> Review src/LendingPool.sol. It accepts multiple collateral tokens and uses oracle pricing. Check the oracle integration, decimal handling, and interest rate model.

| # | Criterion | Pass/Fail | Notes |
|---|-----------|-----------|-------|
| 1 | Chainlink oracle integration includes staleness checks | | |
| 2 | Collateral value aggregation handles different decimals | | |
| 3 | Utilization-based interest rate model is implemented | | |
| 4 | Invariant: total deposits >= total borrows per asset | | |
| 5 | Uses Foundry for tests | | |

---

## 14. evm-staking-vault

ERC-4626 staking/yield vaults.

### TC-14.1: ERC-4626 Vault

**Fixture:** `test-fixtures/solidity-vault/`

**Prompt:**
> Review src/StrategyVault.sol. It's an ERC-4626 vault with strategy routing. Check the share math, access controls, withdrawal logic, and rounding conventions.

| # | Criterion | Pass/Fail | Notes |
|---|-----------|-----------|-------|
| 1 | Implements ERC-4626 interface correctly (deposit, mint, withdraw, redeem, preview functions) | | |
| 2 | Router architecture separates vault from strategies | | |
| 3 | Strategy whitelisting with admin controls | | |
| 4 | Withdrawal capability handles illiquid strategies | | |
| 5 | Reward harvesting and fee deduction are explicit | | |
| 6 | Rounding follows ERC-4626 convention (favor vault on deposit, favor user on withdraw — or opposite with justification) | | |

---

## 15. sui-move

Base Sui Move patterns.

### TC-15.1: Object and Capability Model

**Fixture:** `test-fixtures/sui-vault/`

**Prompt:**
> Review sources/vault.move. Check the AdminCap/RelayerCap authorization model and whether entry functions properly gate on capabilities.

| # | Criterion | Pass/Fail | Notes |
|---|-----------|-----------|-------|
| 1 | Uses AdminCap (capability object) for authorization, not address checks | | |
| 2 | Pause flag stored in a shared object, not a global | | |
| 3 | Uses Move 2024 syntax conventions | | |
| 4 | Tests cover both capability success and failure paths | | |
| 5 | Entry functions correctly gate on pause state | | |

### TC-15.2: Coin/Balance Discipline

**Fixture:** `test-fixtures/sui-lending/`

**Prompt:**
> Review sources/lending.move. Check the Coin/Balance handling — are deposits and withdrawals using coin::into_balance and balance::split correctly? Any values dropped silently?

| # | Criterion | Pass/Fail | Notes |
|---|-----------|-----------|-------|
| 1 | Uses `Coin<T>` at entry boundaries and `Balance<T>` internally | | |
| 2 | Fee split uses `coin::split` or `balance::split` correctly | | |
| 3 | Remainder is transferred back to the sender | | |
| 4 | No Coin/Balance values are silently dropped | | |
| 5 | Uses `transfer::public_transfer` for types with `store` | | |

---

## 16. sui-defi-math

Sui DeFi financial math.

### TC-16.1: Fixed-Point Math

**Fixture:** `test-fixtures/sui-lending/`

**Prompt:**
> Review the share value accounting in sources/lending.move. Check the fixed-point math, rounding direction, and oracle price normalization.

| # | Criterion | Pass/Fail | Notes |
|---|-----------|-----------|-------|
| 1 | Uses fixed-point decimal representation (u64 or u128 with explicit scale) | | |
| 2 | Rounding direction is a parameter or explicitly documented | | |
| 3 | Handles zero-supply / first-deposit edge case | | |
| 4 | No floating-point math in Move | | |
| 5 | Oracle price normalization handles different decimal counts | | |

---

## 17. sui-lending

Sui lending protocol patterns.

### TC-17.1: Reserve Refresh and Borrow

**Fixture:** `test-fixtures/sui-lending/`

**Prompt:**
> Review the borrow function in sources/lending.move. Check if the reserve is refreshed before borrow logic, and if the oracle price is validated for staleness.

| # | Criterion | Pass/Fail | Notes |
|---|-----------|-----------|-------|
| 1 | Refreshes reserve (accrual, oracle) before borrow logic | | |
| 2 | Uses the reserve/obligation model with proper object references | | |
| 3 | Oracle safety includes staleness, confidence, and failure handling | | |
| 4 | Uses Sui object model (shared objects, owned objects) correctly | | |
| 5 | Uses dynamic fields for state where appropriate | | |

### TC-17.2: Flash Loan

**Fixture:** `test-fixtures/sui-lending/`

**Prompt:**
> Our lending protocol in sources/lending.move needs a flash loan feature. Add it using a hot-potato receipt pattern.

| # | Criterion | Pass/Fail | Notes |
|---|-----------|-----------|-------|
| 1 | Receipt struct has no `drop`, `copy`, or `store` abilities | | |
| 2 | Receipt binds to the specific pool/reserve and amount | | |
| 3 | Repay function validates receipt fields match | | |
| 4 | Fee is collected on repayment | | |
| 5 | No way to bypass repayment (receipt must be consumed) | | |

---

## 18. sui-staking

Sui liquid staking patterns.

### TC-18.1: LST Mint/Redeem

**Fixture:** `test-fixtures/sui-staking/`

**Prompt:**
> The redeem function in sources/liquid_staking.move sometimes uses a stale exchange rate. Review the epoch refresh flow and fix it.

| # | Criterion | Pass/Fail | Notes |
|---|-----------|-----------|-------|
| 1 | Agent traces the Storage/StakePool/ValidatorPool/TreasuryCap flow | | |
| 2 | Epoch refresh happens before redeem calculation | | |
| 3 | Handles refresh idempotence (refreshing twice in same epoch is safe) | | |
| 4 | LST burn uses TreasuryCap authority correctly | | |
| 5 | Tests cover epoch boundary edge cases and rounding | | |
| 6 | Addresses inactive-validator migration risk | | |

---

## 19. sui-vault

Sui strategy vault/wrapper patterns.

### TC-19.1: Strategy Wrapper with Hot-Potato Receipt

**Fixture:** `test-fixtures/sui-vault/`

**Prompt:**
> Review sources/vault.move. A relayer borrows vault funds via a hot-potato receipt to rebalance strategies. What can go wrong?

| # | Criterion | Pass/Fail | Notes |
|---|-----------|-----------|-------|
| 1 | Analyzes receipt binding (wrong wrapper, wrong sender, wrong cap) | | |
| 2 | Covers double borrow, replay, drop/copy/store abuse risks | | |
| 3 | Separates admin, operator/relayer, and user authorities | | |
| 4 | Maps the full object flow (wrapper state → cap → receipt → return) | | |
| 5 | Considers strategy allow-list or target constraints | | |
| 6 | Checks share/value accounting around rebalance (no value leak) | | |

---

## Cross-Cutting Tests

These test that multiple skills compose correctly through the master workflow.

### TC-X.1: Sui Lending End-to-End

**Fixture:** `test-fixtures/sui-lending/`

**Prompt:**
> Review sources/lending.move. Add a borrow cap check and make sure stale oracle prices can't be used for new borrows.

| # | Criterion | Pass/Fail | Notes |
|---|-----------|-----------|-------|
| 1 | Agent loads Sui Move base + lending + math skills together | | |
| 2 | Plan includes refresh-before-act for oracle and reserve | | |
| 3 | Oracle safety covers: stale price, confidence, wrong feed, failure | | |
| 4 | Agent maps Sui object/capability/Coin flow before coding | | |
| 5 | Follows the full core workflow (inspect → plan → threat model → code gate → implement → test → report) | | |

### TC-X.2: Solana Vault End-to-End

**Fixture:** `test-fixtures/solana-vault/`

**Prompt:**
> Review programs/vault/src/lib.rs. This vault accepts token deposits and issues shares. Fix the math, add proper tests, and make sure the account validation is correct.

| # | Criterion | Pass/Fail | Notes |
|---|-----------|-----------|-------|
| 1 | Agent loads Anchor + DeFi math + vault skills together | | |
| 2 | Uses Anchor account validation patterns | | |
| 3 | Share accounting uses fixed-point math with correct rounding | | |
| 4 | Authority model separates admin/operator/user | | |
| 5 | Tests cover deposit, withdraw, first-depositor, and rounding edges | | |
| 6 | Uses `transfer_checked` for USDC (SPL token) | | |

### TC-X.3: EVM Lending + Audit Handoff

**Fixture:** `test-fixtures/solidity-lending/`

**Prompt:**
> The lending protocol in src/LendingPool.sol is code-complete. Help me prepare it for an external audit.

| # | Criterion | Pass/Fail | Notes |
|---|-----------|-----------|-------|
| 1 | Agent uses pre-audit-handoffs skill, not just code review | | |
| 2 | Uses the EVM pre-audit checklist specifically | | |
| 3 | Self-audit findings are classified by severity | | |
| 4 | Test gap analysis is concrete (not generic advice) | | |
| 5 | Handoff document follows the audit template structure | | |

---

## Score Sheet

| Skill | Test Cases | Passed | Failed | Notes |
|-------|-----------|--------|--------|-------|
| smart-contract-core | TC-1.1, TC-1.2, TC-1.3 | | | |
| pre-coding-plan | TC-2.1, TC-2.2 | | | |
| threat-model | TC-3.1, TC-3.2 | | | |
| smart-contract-testing | TC-4.1, TC-4.2 | | | |
| pre-audit-handoffs | TC-5.1 | | | |
| pr-workflow | TC-6.1 | | | |
| solana-anchor | TC-7.1, TC-7.2 | | | |
| solana-defi-math | TC-8.1, TC-8.2 | | | |
| solana-lending | TC-9.1, TC-9.2 | | | |
| solana-staking | TC-10.1 | | | |
| solana-vault | TC-11.1 | | | |
| evm-lending-aave | TC-12.1, TC-12.2 | | | |
| evm-lending-pool | TC-13.1 | | | |
| evm-staking-vault | TC-14.1 | | | |
| sui-move | TC-15.1, TC-15.2 | | | |
| sui-defi-math | TC-16.1 | | | |
| sui-lending | TC-17.1, TC-17.2 | | | |
| sui-staking | TC-18.1 | | | |
| sui-vault | TC-19.1 | | | |
| **Cross-cutting** | TC-X.1, TC-X.2, TC-X.3 | | | |
| **TOTAL** | **30** | | | |
