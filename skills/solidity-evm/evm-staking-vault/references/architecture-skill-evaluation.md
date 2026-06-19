# Skill Evaluation

## Scope

Read this file when testing whether the `Build Staking Vaults` skill package actually improves agent performance, not just whether the resulting contracts compile or pass tests.

This evaluation should cover:

- contract quality
- task completion quality
- performance difference between runs with the skill and runs without the skill

## Evaluation Layers

Use three layers of evaluation:

### 1. Contract Tests

Validate the produced code directly.

Use the referenced `testing-patterns.md` approach as the baseline for:

- unit tests
- invariant tests
- fuzz tests where appropriate
- async withdrawal edge cases
- access control checks
- fee and reward accounting checks

Minimum contract test areas:

- router registry and activation logic
- deposit and withdraw flows
- instant withdrawal and async withdrawal flows
- share accounting isolation across vaults
- `totalAssets()` correctness
- reward harvesting and reinvestment
- fee safety
- rescue restrictions
- pause behavior

### 2. Task Tests

Validate whether the agent can complete realistic staking-vault tasks end to end.

Example task set:

- scaffold a staking vault project
- design a `VaultRouter`
- add a new protocol-specific vault
- implement an async withdrawal flow
- implement harvest-and-compound logic
- add a fee model
- write invariant-focused tests
- review an implementation with seeded bugs

Use fresh threads for each task.

Do not leak expected answers or prior run outputs into the prompt.

### 3. A/B Skill Tests

Measure whether this skill improves outcomes over a no-skill baseline.

Run each task in two modes:

- `A`: no skill
- `B`: with skill

Example with-skill prompt:

```text
Use $build-staking-vaults at <path-to-skill> to solve <task>.
```

Example no-skill prompt:

```text
Solve <task>.
```

Keep these fixed across both runs:

- same repository state
- same task wording
- same artifact inputs
- same model if possible
- fresh thread for each run

## Scoring Rubric

Score each run on the same rubric.

Suggested dimensions:

- correctness
- architectural adherence
- security hygiene
- test quality
- unnecessary changes
- time or iteration count

Suggested scoring:

```text
0 = poor
1 = partial
2 = solid
```

Total the rubric for each task, then compare:

- average score with skill
- average score without skill
- variance across repeated runs

## Run Protocol

When running skill-vs-no-skill evaluation:

- use fresh threads
- use identical task prompts except for the skill reference
- avoid showing the intended answer
- avoid reusing generated artifacts from earlier runs
- clean up temporary artifacts between runs if they could bias later runs
- review outputs with the same rubric

If possible, do blind review:

- hide whether an output came from the skill or no-skill run before scoring it

## Metrics To Track

Track at least:

- compile success
- test success
- number of logic bugs found in review
- architectural correctness
- missed security checks
- number of repair iterations needed
- total time
- output diff size if useful

## Failure Signals

The skill likely needs improvement if:

- with-skill runs are not consistently better than no-skill runs
- the agent still ignores key invariants from the skill
- the agent repeatedly chooses the wrong architecture
- the agent adds unsafe reward or fee accounting
- the agent omits async withdrawal or router safety checks
- the skill only helps when the prompt leaks too much context

## Evaluation Output Template

Use a simple evaluation record per task:

```text
Task:
Mode: with-skill | without-skill
Compile: pass | fail
Tests: pass | fail
Correctness: 0|1|2
Architecture: 0|1|2
Security: 0|1|2
Tests quality: 0|1|2
Unnecessary changes: 0|1|2
Iterations:
Notes:
```

## Stop Conditions

Do not claim the skill is validated if:

- only one task was tested
- with-skill and no-skill runs did not use the same starting conditions
- prior outputs leaked into later runs
- success was judged only by compile passing
- the scoring rubric changed between runs
