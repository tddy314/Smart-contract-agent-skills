---
name: aave-tokens
description: Use when implementing or reviewing Aave-style token accounting, including aToken mint and burn behavior, variable debt token accounting, index-based balance growth, and reserve-backed supplier or borrower claims.
---

# Aave Tokens

Use this skill when the task is specifically about `aToken`, `VariableDebtToken`, or reserve-backed share and debt accounting.

## Token Model

Use the standard split:

- `aToken`: supplier claim token
- `VariableDebtToken`: borrower debt claim

Default behavior:

- `supply` mints `aToken`
- `withdraw` burns `aToken`
- `borrow` increases variable debt accounting
- `repay` reduces variable debt accounting

Prefer variable debt only unless stable debt is explicitly required.

## Implementation Rules

- Keep supplier claim growth tied to reserve index or reserve-backed accounting, not synthetic balance jumps.
- Keep debt growth tied to borrow indexes.
- Do not let token mint or burn paths bypass pool-level validation.
- Ensure token supply and reserve liquidity accounting stay consistent.
- Emit events for mint, burn, and debt-balance updates as appropriate for the token design.
- Do not treat debt tokens as standalone business logic; they should reflect `Pool`-validated state.

## Read Next

- For reserve state and pool operations:
  Read [../aave-pool/SKILL.md](../aave-pool/SKILL.md)
- For interest accrual:
  Read [../aave-interest-rate-strategy/SKILL.md](../aave-interest-rate-strategy/SKILL.md)
