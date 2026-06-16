---
name: sui-move
description: >
  Chain-specific implementation skill for Sui Move smart contracts and Move packages. Use whenever a task touches
  `Move.toml`, `sources/*.move`, `tests/*.move`, Sui objects, capabilities, shared objects, dynamic fields,
  Coin/Balance movement, package publishing/upgrades, or Move 2024 syntax. ALWAYS use this skill for Sui work when it
  is recognized from `sui move`, `sui::` imports, `UID`, shared objects, `TxContext` in a Sui repo, `AdminCap`,
  `TreasuryCap`, Sui framework packages, `sui move build`, or `sui move test`. Do not use for Aptos, Movement, or
  vanilla Move unless the repo clearly targets Sui. For lending protocols also load `sui-lending`; for liquid staking,
  validator staking, LSTs, or staking reward accounting load `sui-staking`; for strategy vaults
  load `sui-vault`; for rates, shares, decimals, fees, or oracle math load `sui-defi-math`.
---

# Sui Move

This skill teaches the agent how to work safely and consistently in Sui Move repositories. It adapts the team's smart-contract workflow to Sui's object-centric execution model and incorporates patterns from MystenLabs skills/docs, the Move Book, Navi, Suilend, and Sui liquid-staking/strategy-wrapper contracts.

`smart-contract-core` owns the overall workflow: inspect, plan, threat-model, implement, test, report. This skill provides the Sui-specific checklists and implementation rules at each stage. Load the companion skills named in the frontmatter when the task is protocol-specific.

---

## When to Use

- Sui Move module implementation, review, debugging, or refactoring
- Move package setup, `Move.toml`, `Published.toml`, `Move.lock`, publishing, or upgrades
- Sui objects, `UID`, object ownership, shared objects, dynamic fields, collections, or transfer rules
- Capability-based authorization (`AdminCap`, `OperatorCap`, `TreasuryCap`, `UpgradeCap`, custom caps)
- Coin / Balance movement, mint, burn, split, join, stake, redeem, deposit, withdraw
- Move unit tests, `test_scenario`, multi-transaction flows, or `sui move test`
- Programmable Transaction Block composability questions that affect Move function signatures

**Do not use** for non-Sui Move dialects unless the repo clearly targets Sui framework modules. For frontend-only Sui dApps with no Move changes, use a frontend/client skill instead. For Aptos, Movement, or generic Move language questions without Sui framework/object evidence, do not use this skill.

---

## The One Rule That Matters Most

**Sui bugs are usually object-flow bugs: the wrong object, capability, shared object state, or coin balance is allowed to move.**

Before changing function logic, map every object and resource:

1. Who owns it now?
2. Who can borrow or mutate it?
3. Which capability proves authorization?
4. Does it become shared, frozen, wrapped, transferred, split, joined, or destroyed?
5. Which economic balance does each `Coin<T>` or `Balance<T>` represent?

Only then inspect or write business logic. Correct arithmetic on the wrong object is still exploitable.

---

## Repository Inspection

Before planning, inspect:

- `Move.toml` - package name, edition, dependencies, environments, legacy vs current package format
- `Published.toml` and `Move.lock` - published IDs, upgrade-capability IDs, pinned dependencies
- `sources/` - module boundaries, public API, objects, capabilities, events, dynamic fields
- `tests/` - unit-test style, `test_scenario`, helper modules, expected failure patterns
- package docs / README - deployment addresses, public object IDs, integration assumptions
- protocol-specific folders - `lending_core`, `liquid_staking`, `strategy_wrapper`, `oracles`, etc.

Identify before planning:

- The primary state objects: singleton config, reserve, market, pool, position, receipt, registry, storage
- Ownership model: address-owned, shared, immutable, wrapped, child/dynamic object, or transferred object
- Capability map: which cap gates each privileged function and who receives it during `init`
- Coin / balance flow: where coins enter, become balances, join reserves, split back out, or burn/mint
- Shared-object contention: which functions take `&mut` shared objects and therefore serialize execution
- Upgrade/public API constraints: any `public` signatures or structs that cannot be safely changed after publish

---

## Move 2024 and Project Conventions

For new code, follow the current Sui/Move 2024 shape unless the repo is legacy and cannot migrate in-scope:

- `Move.toml` uses `edition = "2024"`.
- Do not add legacy `Sui = { git = ... }` dependencies in current CLI packages.
- Module declarations are single-line: `module package::module;` with no outer braces.
- Structs are explicit: `public struct Name has key, store { ... }`.
- Any object with `key` has `id: UID` as the first field and creates it with `object::new(ctx)`.
- Use method syntax where available: `ctx.sender()`, `coin.value()`, `payment.into_balance()`, `id.delete()`.
- Use `public(package)` for package-internal APIs; avoid widening to `public` unless composability requires it.
- Never use `public entry`; choose `public` for composable functions or `entry` for convenience endpoints.
- Core functions should return objects/coins instead of transferring to `ctx.sender()` so PTBs can compose them; add thin `entry` wrappers only when useful.

Function parameter order:

```
primary mutable objects → immutable objects → capabilities → primitive args → Clock → &mut TxContext
```

Use a local repo's existing ordering if it is consistent and changing it would be a breaking API change.

---

## Object and Capability Checklist

For each public or entry function, verify:

- **Object type and ability** - Does it need `store`? If an object should have custom transfer rules, do not give it `store` casually.
- **Ownership** - Is the object address-owned, shared, immutable, wrapped, or stored under a dynamic field? Does the function assume the correct owner?
- **Capability authorization** - Does the function require the right cap by reference? Avoid hardcoded admin addresses unless the protocol deliberately uses them.
- **Cap lifecycle** - Where is the cap created, transferred, wrapped, borrowed, returned, rotated, or destroyed?
- **Shared-object mutation** - Is `&mut` needed? Prefer immutable `&` for shared objects when no mutation is required to preserve parallel execution.
- **Dynamic fields** - Is field existence checked before borrow/remove? Are all child fields removed before deleting a parent object?
- **Version / stale state** - If the repo has version fields or refresh epochs, is the version checked before mutation?
- **Destruction** - Objects without `drop` must be unpacked and their `UID` deleted.

---

## Coin and Balance Discipline

Sui code should make economic roles explicit:

- Convert `Coin<T>` to `Balance<T>` for internal accounting and storage.
- Keep principal, reserves, rewards, fees, insurance, and unclaimed balances separate unless the protocol explicitly commingles them.
- Split/join balances with a clear owner and purpose; rewrap as `Coin<T>` only at API boundaries.
- For mint/burn, trace the `TreasuryCap<T>` path and make sure it cannot be leaked or used without authorization.
- If a function receives coins and returns change, return all remainder coins (even zero-value when the repo's convention requires it) or destroy zero values deliberately.

For rates, shares, decimals, fees, and rounding, load `sui-defi-math`.

---

## Testing Commands and Patterns

Use the narrowest useful command first, then broaden:

```bash
sui move build
sui move test
sui move test --statistics
sui move test --filter "<regex>"
```

Testing priorities:

- capability holder succeeds; non-holder fails;
- wrong owner / wrong sender fails in a multi-transaction scenario;
- object transfer/share/freeze/wrap behavior matches intended effects;
- coin and balance deltas match economic intent;
- refresh/checkpoint logic runs before state-changing actions;
- dynamic field cleanup happens before deleting parent objects;
- expected failures specify `location` when aborting from the module under test;
- no cleanup after expected-failure aborts.

Prefer `tx_context::dummy()` for single-transaction pure/module tests and `test_scenario` for multi-sender, shared-object, transfer, or init flows.

---

## Common Mistakes to Avoid

- Treating Sui like EVM storage maps instead of object input/output flow.
- Using address checks where a capability object should prove authorization.
- Adding `store` to an object that needs custom transfer restrictions.
- Calling `transfer::public_transfer` when only the defining module should be able to transfer.
- Deleting a parent object with dynamic fields still attached.
- Exposing `public` APIs or structs that will be hard to change after publish.
- Using legacy Move syntax in a 2024 package.
- Mutating reward rates, reserves, debts, or totals before refreshing/checkpointing accrual.
- Collapsing principal, reward, fee, and reserve balances into one bucket without a protocol reason.

---

## Companion Skill Routing

| Task shape | Also load |
|---|---|
| Fixed-point math, shares, rates, fees, oracle decimal conversion | `sui-defi-math` |
| Lending reserve, obligation, borrow/repay/liquidation, flash loan, oracle-backed LTV | `sui-lending` + `sui-defi-math` |
| Liquid staking, validator pools, LST mint/redeem, epoch refresh, rewards | `sui-staking` + `sui-defi-math` |
| Strategy vault, wrapper, managed rebalancing, relayer/operator, borrowed authority receipts | `sui-vault` + `sui-defi-math` |

---

## Reference Files

- `references/object-model-and-auth.md` - object ownership, abilities, caps, dynamic fields, composability
- `references/project-and-testing.md` - package setup, Move 2024, test conventions, commands

Primary source refs in this repo include MystenLabs skills under `sui-skills-ref/mystenlabs/skills/`, Move Book material under `sui-skills-ref/mystenlabs/move-book/`, and protocol examples under `sui-skills-ref/navi-smart-contracts/` and `sui-skills-ref/suilend-related/`.

---

## Rules

1. Map object, capability, and coin/balance flow before editing logic.
2. Use capability-based authorization unless the existing protocol deliberately uses address checks.
3. Keep `Coin<T>` at API edges and `Balance<T>` in internal accounting.
4. Refresh/checkpoint stale state before mutating rates, reserves, debts, stake, or shares.
5. Keep public APIs composable: return objects/coins from `public` functions; use `entry` wrappers for convenience.
6. Follow Move 2024 syntax and current `Move.toml` format unless the repo is intentionally legacy.
7. Run `sui move build` and relevant `sui move test` commands before reporting completion.
