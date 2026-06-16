---
name: evm-lending-aave
description: Use when planning or implementing Aave-style lending systems in Solidity, including Hardhat setup, reserve-first architecture, Pool and PoolConfigurator design, aToken and debt-token accounting, oracle and interest-rate strategy design, liquidation, admin controls, and evaluation of skill effectiveness.
---

# Lending Aave

Use this skill as the package overview when the task is to fork, reproduce, or adapt an Aave-style lending system.

This package is split into focused skills:

- For Hardhat and OpenZeppelin project scaffolding:
  Read [references/project-setup.md](references/project-setup.md)
- For high-level fork planning and Aave-style reserve-first architecture:
  Read [references/architecture.md](references/architecture.md)
- For the user-facing `Pool` contract and reserve operations:
  Read [references/pool.md](references/pool.md)
- For reserve configuration and admin update boundaries:
  Read [references/configurator.md](references/configurator.md)
- For `aToken` and debt-token accounting:
  Read [references/tokens.md](references/tokens.md)
- For oracle-backed account data and reserve risk policy:
  Read [references/oracle-and-risk.md](references/oracle-and-risk.md)
- For interest accrual and reserve-specific rate strategy:
  Read [references/interest-rate-strategy.md](references/interest-rate-strategy.md)
- For liquidation flow and unhealthy-account handling:
  Read [references/liquidation.md](references/liquidation.md)

Use this top-level overview when the request is broad and you need to decide whether the work is mainly:

- project setup
- fork planning
- Pool architecture
- Configurator and admin boundaries
- reserve and token accounting
- interest rate and oracle design
- liquidation and risk controls
- invariant-driven testing

Prefer loading only the subskill that matches the task instead of treating this package as one giant skill.
