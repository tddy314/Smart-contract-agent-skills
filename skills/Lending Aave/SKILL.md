---
name: lending-aave
description: Use when planning or implementing Aave-style lending systems in Solidity, including Hardhat setup, reserve-first architecture, Pool and PoolConfigurator design, aToken and debt-token accounting, oracle and interest-rate strategy design, liquidation, admin controls, and evaluation of skill effectiveness.
---

# Lending Aave

Use this skill as the package overview when the task is to fork, reproduce, or adapt an Aave-style lending system.

This package is split into focused skills:

- For Hardhat and OpenZeppelin project scaffolding:
  Read [skills/foundation/set-up-project/SKILL.md](skills/foundation/set-up-project/SKILL.md)
- For high-level fork planning and Aave-style reserve-first architecture:
  Read [skills/core/aave-lending-architecture/SKILL.md](skills/core/aave-lending-architecture/SKILL.md)
- For the user-facing `Pool` contract and reserve operations:
  Read [skills/core/aave-pool/SKILL.md](skills/core/aave-pool/SKILL.md)
- For reserve configuration and admin update boundaries:
  Read [skills/core/aave-configurator/SKILL.md](skills/core/aave-configurator/SKILL.md)
- For `aToken` and debt-token accounting:
  Read [skills/core/aave-tokens/SKILL.md](skills/core/aave-tokens/SKILL.md)
- For oracle-backed account data and reserve risk policy:
  Read [skills/core/aave-oracle-and-risk/SKILL.md](skills/core/aave-oracle-and-risk/SKILL.md)
- For interest accrual and reserve-specific rate strategy:
  Read [skills/core/aave-interest-rate-strategy/SKILL.md](skills/core/aave-interest-rate-strategy/SKILL.md)
- For liquidation flow and unhealthy-account handling:
  Read [skills/core/aave-liquidation/SKILL.md](skills/core/aave-liquidation/SKILL.md)

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
