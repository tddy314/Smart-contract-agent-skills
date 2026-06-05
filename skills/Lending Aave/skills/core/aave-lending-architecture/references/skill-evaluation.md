# Skill Evaluation

## Scope

Read this file when testing whether the `Lending Aave` skill package improves agent performance, not just whether the resulting contracts compile or pass tests.

## Evaluation Layers

Use three layers:

### 1. Contract Tests

Validate the produced contracts directly with unit, invariant, and fuzz-style coverage where appropriate.

### 2. Task Tests

Validate realistic end-to-end tasks such as:

- scaffold an Aave-style repo
- implement `Pool` and `PoolConfigurator`
- add an `aToken` and `VariableDebtToken`
- wire interest-rate strategy
- wire oracle checks
- implement liquidation and health-factor checks

### 3. A/B Skill Tests

Compare:

- `A`: no skill
- `B`: with skill

Use fresh threads, identical repo state, identical task wording, and avoid leaking expected answers.

## Suggested Metrics

- compile pass
- test pass
- architectural adherence
- missed security checks
- number of repair iterations
- total time

## Stop Conditions

Do not claim the skill is validated if:

- only one task was tested
- runs did not start from equivalent conditions
- prior outputs leaked into later runs
- success was judged only by compile passing
