---
name: smart-contract-testing
description: >
  Teaches the agent how to write useful smart contract tests across Solidity/EVM,
  Sui Move, Anchor/Solana, and CosmWasm. ALWAYS use this skill when a smart
  contract task changes behavior, permissions, state transitions, asset movement,
  migrations, or deployment-related code and tests must be added, updated, or
  proposed. This skill prevents happy-path-only coverage and pushes the agent to
  validate failure cases, invariants, and framework-specific edge cases.
---

# Smart Contract Testing

This skill defines how the agent should validate smart contract changes.

`smart-contract-core` owns the overall workflow. This skill owns test quality. Use it when the task needs tests, test updates, or a concrete test plan.

---

## When to Use

- Feature implementation
- Bug fixing
- Refactoring that changes logic or permissions
- Audit fixes
- Permission changes
- Asset movement
- Migration logic
- Deployment-related code
- Standalone test generation tasks

**Do not use** for pure documentation edits, comment-only changes, or cosmetic refactors with no behavior change.

---

## Testing Goal

Do not stop at "works once."

Optimize for bug-finding, not for superficial coverage counts.

When the task is test generation or test revision, assume the code may hide:

- wrong recipient or wrong beneficiary updates;
- missing decrement or stale accounting updates;
- off-by-one or exact-boundary failures;
- skipped `require` / authorization checks;
- wrong state transition or wrong terminal state.

The agent should create or propose tests that answer:

- What succeeds in the normal case?
- Who must be rejected?
- What invalid inputs or invalid state must fail?
- What boundary values matter?
- What happens if the same action is replayed or repeated?
- What happens if a downstream dependency fails?
- What must still hold true after the operation?

If you cannot point to the specific bug class each test is meant to catch, the suite is probably too generic.

If a category is not applicable, say so explicitly in the final report.

---

## Workflow

### Step 1: Inspect the Existing Test Stack

Before writing tests, inspect the repo's current testing setup.

- Identify framework and test language
- Read existing test files before adding new ones
- Follow current naming, fixtures, helpers, and assertion style
- Reuse existing deployment/setup helpers when they are clear and trustworthy
- Prefer the smallest test addition that matches existing patterns

Inspect whichever of these exist:

- `test/`
- `tests/`
- `src/tests/`
- `foundry.toml`
- `hardhat.config.*`
- `Move.toml`
- `Anchor.toml`
- `Cargo.toml`
- `package.json`
- CI workflows that run tests

### Step 2: Map the Behavior to Test Cases

Use the implementation plan and current code to derive coverage.

Derive tests directly from the code, not from intuition alone. Walk these sources in order:

1. Each privileged or signer-gated function
2. Each `require` / custom error / abort path
3. Each state mutation
4. Each asset movement or payout path
5. Each event or externally visible effect

For each changed function or flow, identify:

- entry point;
- authorized actor;
- unauthorized actor;
- state preconditions;
- assets or objects involved;
- boundary values;
- external dependency behavior;
- invariants that should still hold after execution.

If multiple tests cover the same happy path but none targets a distinct failure mode, collapse them and spend the budget on sharper negative coverage.

### Step 3: Cover the Baseline Matrix

Unless clearly not applicable, cover these categories:

1. Happy path
2. Role / permission test
3. Invalid state transition test
4. Invalid asset / token / denom / mint / object test
5. Boundary / exact-value test
6. Duplicate / replay / already-done test
7. External call failure test
8. Event assertion for important state changes
9. Invariant or fuzz test, if supported
10. Migration or upgrade case when relevant

Do not force every category into every task. Instead:

- include it if relevant;
- omit it only with a reason;
- note missing coverage in the final output.

### Step 4: Write Focused Tests

Write tests close to the changed behavior.

- One assertion theme per test when possible
- Prefer descriptive names over generic names
- Verify externally visible behavior: return values, state, events, errors, balances, ownership, emitted messages
- Do not overfit to internal implementation details unless the repo already tests that way
- Do not add broad fixture rewrites unless needed
- Prefer fewer high-signal tests over many redundant happy-path tests
- Make each test answer: "what bug would survive if this test did not exist?"

### Step 5: Run the Right Commands

Run the narrowest relevant test command first, then broader commands if appropriate.

Examples:

- single test file or filtered test command while iterating;
- full suite before finishing, when practical;
- format/lint only if that repo normally couples them to test work.

### Step 6: Report Coverage and Gaps

Always report:

- what tests were added or updated;
- which commands were run;
- which cases are covered;
- which cases are still missing;
- what reviewers should double-check.

---

## Chain-Specific Guidance

Use the section that matches the repo. If the repo spans multiple stacks, apply all relevant sections.

### Solidity / EVM

Common stacks:

- Foundry
- Hardhat

Hardhat's official testing guidance treats both Solidity tests and TypeScript tests as first-class options.

- Use Solidity tests for unit-level checks, fuzzing, and invariants when the repo already follows that style
- Use TypeScript tests for end-to-end flows, chain-level assertions, integrations, forking, and consumer-facing usage examples
- In mixed repos, follow the existing split instead of forcing everything into one style

Prioritize:

- revert tests for unauthorized callers and invalid input;
- event tests for important state changes;
- balance/accounting assertions after asset movement;
- state-machine tests for allowed and forbidden transitions;
- exact-boundary tests for timeouts, allowances, balances, and zero/non-zero cases;
- fuzz tests for input ranges and arithmetic-sensitive logic;
- invariant tests for protocol-level properties;
- fork tests only when the change depends on real deployed integrations or mainnet state.

Apply official Solidity guidance where relevant:

- checks-effects-interactions around external calls;
- withdrawal-pattern behavior for refunds and payouts;
- state-machine guarding for staged flows;
- never rely on `tx.origin` for authorization.

Useful patterns from official Foundry guidance:

- `setUp()` for fixture creation
- `vm.expectRevert(...)` for failure paths
- `vm.expectEmit(...)` for event checks
- `testFuzz_*` for fuzz coverage

Useful patterns from official Hardhat guidance:

- `loadFixture(...)` from `hardhat-network-helpers` for reusable snapshot-based setup
- event assertions with `.to.emit(...).withArgs(...)`
- revert assertions such as `.to.be.revertedWith(...)` and custom error matchers
- balance change assertions when testing value transfer and accounting
- impersonation helpers and balance setup for non-default actors when needed

Useful commands:

```bash
forge test
forge test -vvv
forge test --match-test <name>
forge test --match-contract <name>
npx hardhat test
npm test
```

What to check:

- access control;
- custom errors or revert reasons;
- event emission;
- state transition correctness;
- precision and rounding;
- payout recipient correctness;
- accounting deltas after every asset-moving action;
- ERC20/ERC721/ERC1155 assumptions;
- replay or signature reuse;
- timeout and timestamp boundaries;
- upgrade/migration compatibility when relevant.

### Sui Move

Common stacks:

- Move unit tests
- Sui `test_scenario`

Prioritize:

- object ownership transitions;
- capability checks;
- capability transfer implications;
- shared object behavior;
- coin / balance movement correctness;
- principal vs reward segregation when balances represent different economic roles;
- accumulator or checkpoint update ordering for reward and staking logic;
- transfer rules;
- multi-transaction flows when object state changes across transactions.

Useful patterns from Sui docs:

- `#[test]` for unit tests
- `#[expected_failure(...)]` when abort behavior is the thing under test
- descriptive test names without a redundant `test_` prefix in `_tests` modules
- `assert_eq!` for value comparisons so failures show both sides
- `#[test, expected_failure(abort_code = ..., location = module)]` on one line when the abort originates outside the test module
- `tx_context::dummy()` for simple single-transaction tests
- `test_scenario` for multi-transaction or multi-sender flows
- explicit object cleanup or return-to-sender when tests create owned objects
- `take_shared(...)` with matching `return_shared(...)` for shared-object tests
- transaction effects inspection after `next_tx(...)` when exact created/shared/transferred outputs matter
- `#[test_only]` helpers or modules for test-only setup code
- system object creation helpers when tests need `Clock`, `Random`, `DenyList`, or other test-only framework objects
- scenario tests for multi-transaction and multi-sender ownership flows
- capability-pattern tests that prove only the holder can exercise the protected path
- no cleanup after an expected-failure abort; let the test abort naturally

Useful commands:

```bash
sui move test
sui move test --statistics
```

What to check:

- wrong owner cannot use object;
- missing capability fails;
- moved or transferred capability changes who can act;
- shared object entry points reject invalid state;
- object is transferred/shared/frozen as intended;
- coin and balance sources match the intended economic meaning;
- same-checkpoint and cross-checkpoint accounting behave as intended;
- stale oracle/confidence and stale exchange-rate cases fail safely;
- hot-potato receipts cannot be dropped, replayed, or settled against the wrong object;
- multi-step scenario still preserves expected ownership and state;
- transaction effects match what the step was supposed to create, share, or transfer.

### Mutation-Oriented Mode

When the task is explicitly to expand tests, kill mutants, or catch hidden logic bugs, bias the suite toward bug classes that often survive weak smart-contract tests.

Try to kill at least these patterns when relevant:

- wrong recipient receives funds or tokens;
- allowance, balance, debt, or supply is not decremented or updated;
- `>` vs `>=`, `<` vs `<=`, or zero/non-zero boundary mistakes;
- missing authorization or missing state guard;
- wrong state enum written after success or refund;
- stale checkpoint / stale rate / stale debt in accounting flows.

In mutation-oriented mode, the best test is the smallest one that proves a concrete bad implementation would fail.

### Anchor / Solana

Common stacks:

- `anchor test` with TypeScript integration tests
- Rust-side tests for helpers or lower-level logic

Prioritize:

- account validation;
- signer validation;
- PDA seed and bump validation;
- malicious account substitution;
- token mint and token authority validation;
- CPI target/account validation.

Useful patterns from Anchor docs:

- `anchor test` builds, starts a validator, deploys, and runs the configured suite
- integration tests usually live under `tests/`
- advanced setups may use lighter-weight test harnesses, but repo conventions should lead
- TypeScript integration tests commonly use `anchor.workspace`, `AnchorProvider.env()`, and local-validator accounts
- Rust tests are valid when the repo already uses the Anchor Rust client or lower-level Rust harnesses
- PDA signer tests should derive the PDA in the test and exercise the exact CPI path used by the program

Useful commands:

```bash
anchor test
anchor test --skip-build
anchor test --skip-deploy
cargo test
cargo clippy
```

What to check:

- wrong signer fails;
- wrong PDA seeds or bump fail;
- attacker-supplied account fails validation;
- CPI cannot be redirected to an unexpected program;
- duplicate mutable account or authority mismatch is rejected.

### CosmWasm

Common stacks:

- `cargo test`
- `cw-multi-test`

Prioritize:

- instantiate / execute / query separation;
- unauthorized sender;
- funds and denom validation;
- reply and submessage behavior;
- migration compatibility;
- multi-contract interaction where relevant.

Useful patterns from `cw-multi-test` docs:

- simulate multi-contract interactions;
- simulate bank/staking module behavior when the contract depends on them;
- prefer realistic execution flows over direct internal helper testing when behavior spans contracts.

Useful commands:

```bash
cargo test
cargo clippy
cargo fmt --check
```

What to check:

- wrong sender fails;
- wrong denom or missing funds fail;
- reply handler behavior is asserted;
- migration preserves old state assumptions;
- cross-contract flow produces the expected messages and state transitions.

---

## Common Mistakes to Avoid

- Writing only happy-path tests
- Copying an existing test pattern without checking whether it covers the new risk
- Adding broad fixtures when a small local setup is enough
- Testing internal helper details instead of externally visible behavior
- Skipping permission tests because access control "looks obvious"
- Skipping migration or replay coverage on stateful flows
- Using live networks or production endpoints for normal test work
- Claiming coverage is complete when important categories were intentionally skipped

---

## Final Output

Use this format when handing test work to the user:

```
Tests added:
- <test name> — <what it proves>

Tests run:
- <command> — <result>

Cases covered:
- <happy path / unauthorized / boundary / etc.>

Cases not covered:
- <missing case> — <why not covered yet>

Suggested extra tests:
- <useful follow-up test>
```

---

## Example

**Task:** "Add admin-controlled reward rate update."

**Good test plan:**

```
Tests added:
- admin can update reward rate — proves normal path works
- non-admin cannot update reward rate — proves access control
- reward rate above max reverts — proves boundary check
- reward update emits event — proves off-chain observers can track changes

Tests run:
- forge test --match-contract RewardConfigTest — 4 passed

Cases covered:
- Happy path
- Unauthorized caller
- Boundary value
- Event emission

Cases not covered:
- Invariant test — not added yet because repo has no invariant harness
- Upgrade case — not relevant for this non-upgradeable contract

Suggested extra tests:
- Fuzz reward rate within valid range
```

---

## Rules

1. Read existing tests before writing new ones.
2. Cover failure paths, not just success.
3. Prefer minimal, behavior-focused tests.
4. State explicitly when a test category is not applicable.
5. Run relevant commands when possible.
6. Never imply that passing tests prove the contract is secure.
