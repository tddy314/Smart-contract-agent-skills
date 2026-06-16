---
name: aave-pool
description: Use when implementing or reviewing the Aave-style Pool contract, including supply, withdraw, borrow, repay, setUseAsCollateral, reserve-state updates, account-data checks, and user-facing reserve operations.
---

# Aave Pool

Use this skill when the task is specifically about the `Pool` contract or the hot user-facing execution path.

Unless the user explicitly asks for a mock or spike, implement production-facing pool logic rather than simplified simulation flows.

## Responsibilities

The `Pool` should:

- handle `supply`, `withdraw`, `borrow`, `repay`, and collateral usage toggles
- update reserve state and indexes before debt- or liquidity-dependent checks
- enforce health-factor checks on borrow and collateral-reducing withdraw paths
- coordinate with `aToken`, debt-token, oracle, and rate-strategy modules

The `Pool` should not:

- bypass configurator-set reserve parameters
- own unrelated admin configuration logic
- rely on caller-provided pricing

## Implementation Rules

- Revert if the reserve is inactive, paused, or frozen for the requested action.
- Revert on zero-amount operations unless the design explicitly allows them.
- Revert if a borrow or withdraw would violate health-factor requirements.
- Accrue reserve indexes before borrow, repay, withdraw, liquidation, and account-data checks that depend on debt or liquidity.
- Keep underlying transfers, `aToken` mint or burn, and debt updates consistent in one state transition.
- Emit events for supply, withdraw, borrow, repay, and collateral usage changes.

## Read Next

- For reserve config and admin boundaries:
  Read [../aave-configurator/SKILL.md](../aave-configurator/SKILL.md)
- For token accounting:
  Read [../aave-tokens/SKILL.md](../aave-tokens/SKILL.md)
- For risk and oracle checks:
  Read [../aave-oracle-and-risk/SKILL.md](../aave-oracle-and-risk/SKILL.md)
- For liquidation behavior:
  Read [../aave-liquidation/SKILL.md](../aave-liquidation/SKILL.md)
