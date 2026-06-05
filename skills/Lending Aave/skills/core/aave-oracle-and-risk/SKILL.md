---
name: aave-oracle-and-risk
description: Use when implementing or reviewing Aave-style reserve risk configuration, collateral policy, account-data computation, health factor, oracle-backed valuation, and liquidation eligibility checks.
---

# Aave Oracle And Risk

Use this skill when the task is about collateral policy, reserve risk parameters, health factor, or oracle-backed account data.

## Responsibilities

This area should define:

- which supplied assets count as collateral
- how collateral and debt are valued
- how health factor is computed
- when borrow, withdraw, and liquidation are allowed

## Implementation Rules

- Count only collateral-enabled supplied assets toward collateral value.
- Use one consistent valuation path for total collateral, total debt, available borrow, and health factor.
- Revert if oracle data is missing, stale, zero, negative, or incomplete.
- Normalize token and feed decimals consistently.
- Revert if a borrow or collateral-reducing withdraw would violate health-factor requirements.
- Emit events for oracle or risk-config changes where the module owns them.

## Read Next

- For reserve parameter writes:
  Read [../aave-configurator/SKILL.md](../aave-configurator/SKILL.md)
- For liquidation execution:
  Read [../aave-liquidation/SKILL.md](../aave-liquidation/SKILL.md)
