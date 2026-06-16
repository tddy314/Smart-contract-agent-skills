---
name: aave-interest-rate-strategy
description: Use when implementing or reviewing Aave-style reserve-specific interest accrual, index updates, utilization logic, and DefaultReserveInterestRateStrategy behavior for supplier and borrower accounting.
---

# Aave Interest Rate Strategy

Use this skill when the task is about utilization, borrow rate strategy, liquidity rate, reserve indexes, or reserve-factor handling.

## Responsibilities

This module should define:

- reserve utilization behavior
- variable borrow rate behavior
- liquidity rate behavior
- index accrual timing
- reserve-factor extraction from accrued interest

## Implementation Rules

- Accrue indexes before debt- or liquidity-dependent checks.
- Bound base rate, optimal utilization, slope1, and slope2.
- Do not create synthetic debt when no real borrow exposure exists.
- Apply reserve factor only to accrued interest, not principal.
- Keep rounding behavior deterministic and test it explicitly.
- Emit events when strategy configuration changes if the design exposes them.

## Read Next

- For debt and claim token accounting:
  Read [../aave-tokens/SKILL.md](../aave-tokens/SKILL.md)
- For pool-level integration:
  Read [../aave-pool/SKILL.md](../aave-pool/SKILL.md)
