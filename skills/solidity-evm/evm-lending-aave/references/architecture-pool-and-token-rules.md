# Pool And Token Rules

## Scope

Read this file when implementing or reviewing the `Pool`, `PoolConfigurator`, `aToken`, or `VariableDebtToken`.

## Rules

- Revert if a reserve is inactive, paused, or frozen in a way that blocks the requested action.
- Do not bypass `PoolConfigurator` risk settings in user flows.
- Keep `aToken` supply and underlying reserve liquidity consistent.
- Keep debt token state and reserve debt indexes consistent.
- Do not let token mint and burn paths bypass pool-level validation.
- Emit events for reserve configuration changes and user-facing state changes.
