---
name: aave-configurator
description: Use when implementing or reviewing Aave-style PoolConfigurator logic, including reserve activation, pause and freeze flags, collateral settings, reserve-factor updates, caps, and admin-controlled risk configuration.
---

# Aave Configurator

Use this skill when the task is about reserve configuration, risk-parameter updates, and admin-controlled protocol boundaries.

## Responsibilities

The configurator should own writes for:

- reserve activation and deactivation
- pause and freeze flags
- collateral enablement and collateral parameters
- reserve factor, borrow cap, and supply cap
- oracle or rate-strategy attachments if the design exposes them here

Keep hot user execution paths out of the configurator.

## Implementation Rules

- Bound every parameter update: LTV, liquidation threshold, liquidation bonus, reserve factor, borrow caps, and supply caps.
- Revert on zero-address sensitive config such as treasury, oracle, or strategy targets.
- Emit events for every privileged state change.
- Do not allow config writes that immediately make accounting insolvent without an explicit migration or unwind plan.
- Keep admin boundaries clear: configurator updates policy, `Pool` enforces it.

## Read Next

- For overall Aave fork shape:
  Read [aave-lending-architecture/SKILL.md](aave-lending-architecture/SKILL.md)
- For account-data consequences of config changes:
  Read [../aave-oracle-and-risk/SKILL.md](../aave-oracle-and-risk/SKILL.md)
