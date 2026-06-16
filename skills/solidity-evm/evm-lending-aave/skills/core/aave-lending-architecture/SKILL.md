---
name: aave-lending-architecture
description: Use when designing or implementing Aave-style lending systems in Solidity, including reserve-first Pool architecture, PoolConfigurator boundaries, aToken and variable debt token accounting, oracle and interest-rate strategy design, collateral and health-factor checks, liquidation, admin controls, and invariant-driven testing.
---

# Aave Lending Architecture

Use this skill before writing Aave-style lending contracts or materially changing reserve accounting, token accounting, oracle pricing, interest accrual, liquidation, admin controls, or user account data logic.

Unless the user explicitly asks for a mock, simulation, or spike, implement real production-facing logic rather than mock-only architecture.

Before implementation, if the target is not already explicit, confirm which Aave line to fork or emulate first:

- Aave V2-like
- Aave V3-like

## Purpose

Design a reserve-first lending system where users supply assets into reserves, receive interest-bearing claim tokens, optionally enable supplied assets as collateral, borrow against account liquidity, accrue debt through indexes, and become liquidatable when health factor falls below the required threshold.

Use this skill as the architecture overview and fork-planning entrypoint. Use the module skills for implementation details on specific Aave components.

## Core Model

The architecture is:

```text
User / Liquidator
 |
 | supply / withdraw / setUseAsCollateral
 | borrow / repay / liquidationCall
 v
Pool
 |
 | reserve state
 | user configuration
 | account data and health factor
 | index accrual
 |
 +--> PoolConfigurator
 +--> PriceOracle
 +--> InterestRateStrategy
 +--> aToken / VariableDebtToken
```

Use these defaults unless requirements say otherwise:

- Use one `Pool` as the main user-facing gateway.
- Use a reserve-first architecture where supplied liquidity backs borrowing directly.
- Use `aToken`-style interest-bearing supplier claims.
- Use variable debt tokens by default unless stable debt is explicitly required.
- Use Chainlink-backed oracle logic unless a different oracle system is explicitly required.
- Use health factor based on total collateral value and total debt value.
- Use reserve-specific interest rate strategy.
- Keep configurator and admin writes separate from hot user paths when possible.
- Use `SafeERC20` for transfers.
- Reject fee-on-transfer and rebasing reserve assets unless explicitly supported.

## Required Inputs

Determine these requirements before selecting or implementing the architecture:

- Whether the target is Aave V2-like or V3-like.
- Which modules are in scope for the first version: `Pool`, `PoolConfigurator`, `aToken`, `VariableDebtToken`, `PriceOracle`, `InterestRateStrategy`, liquidation flow, flash loans, eMode, isolation mode.
- Supported reserve assets.
- Which supplied assets may be used as collateral.
- Reserve-level risk parameters: LTV, liquidation threshold, liquidation bonus, reserve factor, borrow caps, supply caps.
- Oracle source and stale price policy.
- Interest rate strategy parameters.
- Whether stable debt is required.
- Administrative roles and update boundaries.
- Unsupported token behaviors: fee-on-transfer, rebasing, ERC777 hooks, non-standard ERC20 return values.

If requirements are missing, state assumptions explicitly before proposing contracts.

## Core Rules

The main rules are:

- Supply into a reserve should mint the reserve's interest-bearing token claim.
- Borrow should create debt through debt-token or scaled-debt accounting.
- Account liquidity and health factor should be computed from total collateral value and total debt value.
- `Pool` should not bypass configurator or risk settings.
- Reserve state must stay isolated per asset.
- Protocol fees and reserve factor should come from accrued interest, not principal.
- Liquidation should only happen when account health is below the required threshold.

## Fork Workflow

When the user is forking or adapting Aave-style systems:

1. Confirm whether the target is V2-like or V3-like.
2. Confirm which modules are in scope for the first version.
3. Decide which invariants must remain Aave-compatible.
4. Separate customization into:
   - config-only changes
   - module-boundary changes
   - accounting changes
   - liquidation or oracle changes
5. Keep module interfaces stable unless the user explicitly wants a deeper divergence from Aave.

Unless the user asks for a deep redesign, prefer preserving the Aave shape of the system and customizing through reserve config, rate strategy, collateral policy, or limited module extensions.

## Main Components

The main component split is:

- `Pool`: user-facing reserve operations and account data checks.
- `PoolConfigurator`: reserve config writes, flags, and risk updates.
- `aToken`: supplier claim token.
- `VariableDebtToken`: borrower debt claim.
- `PriceOracle`: collateral and debt valuation.
- `InterestRateStrategy`: reserve-specific utilization logic.

## Read References And Rules

Keep `SKILL.md` as the overview. Read the detailed `references/` files for architecture details and the `rules/` files for implementation guardrails.

- For fork planning, version selection, and overall system shape:
  Stay in this file first.
- For the user-facing `Pool`, reserve operations, and account-data entrypoints:
  Read [../aave-pool/SKILL.md](../aave-pool/SKILL.md)
- For reserve configuration and admin boundaries:
  Read [../aave-configurator/SKILL.md](../aave-configurator/SKILL.md)
- For `aToken` and debt-token accounting:
  Read [../aave-tokens/SKILL.md](../aave-tokens/SKILL.md)
- For oracle-backed risk and account-data policy:
  Read [../aave-oracle-and-risk/SKILL.md](../aave-oracle-and-risk/SKILL.md)
- For interest accrual and reserve-specific rate strategy:
  Read [../aave-interest-rate-strategy/SKILL.md](../aave-interest-rate-strategy/SKILL.md)
- For liquidation implementation:
  Read [../aave-liquidation/SKILL.md](../aave-liquidation/SKILL.md)

- For Pool, Configurator, reserve state, and token boundaries:
  See [references/pool-and-tokens.md](references/pool-and-tokens.md)
  For implementation checks on the same area:
  See [rules/pool-and-token-rules.md](rules/pool-and-token-rules.md)
- For reserve config, collateral policy, and health-factor math:
  See [references/reserve-config-and-risk.md](references/reserve-config-and-risk.md)
  For implementation checks on the same area:
  See [rules/risk-rules.md](rules/risk-rules.md)
- For interest accrual, rate strategy, and oracle policy:
  See [references/interest-and-oracle.md](references/interest-and-oracle.md)
  For implementation checks on the same area:
  See [rules/interest-and-oracle-rules.md](rules/interest-and-oracle-rules.md)
- For supply, withdraw, borrow, repay, and liquidation flows:
  See [references/liquidation-and-flows.md](references/liquidation-and-flows.md)
  For implementation checks on the same area:
  See [rules/flow-and-liquidation-rules.md](rules/flow-and-liquidation-rules.md)
- For invariants, contract tests, and A/B skill-vs-no-skill evaluation:
  See [references/security-and-testing.md](references/security-and-testing.md)
  See [references/skill-evaluation.md](references/skill-evaluation.md)
  For system-wide implementation security checks:
  See [rules/security-checks.md](rules/security-checks.md)

## Contract Layout

Use this baseline layout:

```text
contracts/
+-- core/
|   +-- Pool.sol
|   `-- PoolConfigurator.sol
+-- interfaces/
|   +-- IPool.sol
|   +-- IPoolConfigurator.sol
|   +-- IPriceOracle.sol
|   `-- IInterestRateStrategy.sol
+-- tokens/
|   +-- AToken.sol
|   `-- VariableDebtToken.sol
+-- oracle/
|   `-- PriceOracle.sol
+-- rates/
|   `-- DefaultReserveInterestRateStrategy.sol
+-- libraries/
|   +-- WadRayMath.sol
|   +-- PercentageMath.sol
|   `-- ReserveLogic.sol
`-- mocks/
```

## Required Design Output

Before implementation, produce a design brief with:

1. Target Aave version style.
2. Modules in scope for the first version.
3. Reserve asset table.
4. Risk config table.
5. Interest-rate strategy table.
6. Oracle feed and stale-price policy.
7. Contract/file map.
8. Supplier and debt token model.
9. Health-factor and account-data formula.
10. Supply, withdraw, borrow, repay, and liquidation flows.
11. Admin roles and trust assumptions.
12. Security invariants.
13. Test plan mapped to invariants.
14. Unresolved design decisions that block implementation.

## Stop Conditions

Do not implement contracts until these are clear:

- Which Aave line is being forked or emulated first.
- Which modules are in scope for the first version.
- Which assets are supported.
- Which assets may be used as collateral.
- Which risk parameters apply to each reserve.
- Which oracle policy and stale-price checks apply.
- Which interest-rate strategy is expected.
- Whether stable debt is required.
- Which admin roles can update reserve configuration and pause flows.
