# Pool And Tokens

## Scope

Read this file when implementing or changing the `Pool`, `PoolConfigurator`, reserve state, supplier claim tokens, or debt tokens.

## Pool

The `Pool` is the main user-facing gateway.

Responsibilities:

- Handle supply, withdraw, borrow, repay, `setUseAsCollateral`, and `liquidationCall`.
- Track reserve state.
- Track user reserve positions and collateral usage.
- Accrue indexes before debt- or liquidity-dependent checks.
- Expose account data and health factor.

The `Pool` should not:

- bypass reserve config
- bypass collateral enablement rules
- bypass oracle-backed health checks

## PoolConfigurator

Use `PoolConfigurator` or an equivalent admin boundary for:

- reserve activation
- collateral settings
- risk parameter changes
- borrow and supply caps
- pause and freeze flags

Keep hot user logic out of configurator paths.

## Token Model

Use an Aave-style token split:

- `aToken`: supplier claim token
- `VariableDebtToken`: borrower debt claim

Default rules:

- supply mints `aToken`
- withdraw burns `aToken`
- borrow mints or updates variable debt accounting
- repay burns or reduces variable debt accounting

Prefer variable debt only unless stable debt is explicitly required.
