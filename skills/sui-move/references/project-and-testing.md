# Sui Project and Testing Reference

Use this when setting up packages, fixing build errors, publishing/upgrading, or writing tests.

## Current package shape

Minimal current `Move.toml`:

```toml
[package]
name = "my_project"
edition = "2024"
```

Do not add legacy Sui framework dependencies in current CLI packages. Add `[dependencies]` only for third-party, MVR, or local packages.

Useful files:

- `Move.toml` - package, dependencies, edition, environments.
- `Published.toml` - published package IDs and upgrade-capability IDs per network.
- `Move.lock` - generated lock file. Do not hand-edit; regenerate when stale.

## Common build issues

- `Dependency 'Sui' is a legacy system name` - remove old `Sui = { git = ... }` dependency.
- `Cannot upgrade package without having a published id` - publish first or populate `Published.toml` correctly.
- Edition mismatch / `public struct` errors - set `edition = "2024"` or preserve legacy syntax if migration is out of scope.
- Environment resolution errors - add `[environments]` or pass `--build-env`.

## Test conventions

- Test functions in `_tests` modules should not be prefixed with `test_`.
- Use `assert_eq!` for equality comparisons.
- Do not pass numeric abort codes to test-only `assert!`.
- Merge attributes on one line: `#[test, expected_failure(abort_code = EBad, location = module)]`.
- Specify `location` when the abort originates in the module under test rather than the test module.
- Do not run cleanup after an expected failure; it will be unreachable.
- Use `tx_context::dummy()` for simple single-transaction tests.
- Use `test_scenario` for multi-sender, shared-object, init, ownership-transfer, or multi-transaction tests.
- Use `sui::test_utils::destroy(obj)` for cleanup when applicable.

## Commands

```bash
sui move build
sui move test
sui move test --statistics
sui move test --filter "<regex>"
```

Run from the package directory that contains the relevant `Move.toml`, not necessarily the repo root.

## Source anchors

- MystenLabs `sui-move-project` skill.
- MystenLabs `move-unit-testing` skill.
- `sui-skills-ref/mystenlabs/sui/docs/content/references/sui-move.mdx`.
