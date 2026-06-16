---
name: pr-workflow
description: >
  Standardizes how the agent prepares commits, pull request summaries, and
  reviewer handoff notes for smart contract work. ALWAYS use this skill when the
  agent finishes implementation, prepares a PR summary, suggests commit titles,
  or hands work to another developer. This skill enforces clear reviewer-facing
  context, focused change summaries, test reporting, and a conventional commit
  title format.
---

# PR Workflow

This skill defines how the agent should package completed work for human review.

It does not replace human review. It makes the review easier by explaining what changed, why it changed, how it was tested, and where reviewers should focus.

---

## When to Use

- After completing an implementation
- When preparing a PR summary
- When summarizing a bug fix
- When handing work to another developer
- When suggesting commit messages or PR titles
- When preparing review notes for risky smart contract changes

---

## Review Goal

The reviewer should be able to answer these questions quickly:

- What changed?
- Why did it change?
- Which files matter?
- How was it tested?
- What assumptions still exist?
- What security or protocol risks remain?
- Where should I focus my review time?

If the summary does not answer these clearly, rewrite it.

---

## Workflow

### Step 1: Gather the Change Context

Before writing the summary, inspect:

- changed files;
- test additions or updates;
- commands that were run;
- known assumptions;
- security-relevant behavior;
- any cases intentionally left uncovered.

If the task is in a git repo, also inspect:

- branch or PR scope;
- commit structure if multiple commits are expected;
- whether unrelated changes should be excluded from the summary.

If the task is not in a git repo, still produce a reviewer handoff summary using the same structure.

### Step 2: Keep the Scope Focused

Do not mix unrelated work into one PR summary.

- Group changes by user-visible purpose
- Mention follow-up work separately
- If the branch contains unrelated edits, call that out instead of pretending it is one coherent change

### Step 3: Prepare Commit Titles

Use Conventional Commits as the default format:

```text
<type>[optional scope]: <description>
```

Examples:

- `feat(rewards): add admin reward rate update`
- `fix(vault): reject zero-share withdrawals`
- `test(anchor): cover malicious account substitution`
- `refactor(move): simplify capability checks without behavior change`

From the official convention:

- `feat` for a new feature
- `fix` for a bug fix
- `BREAKING CHANGE` footer or `!` for a breaking API change
- other common types: `build`, `chore`, `ci`, `docs`, `perf`, `refactor`, `test`, `revert`

### Step 4: Handle Team-Specific Variants Carefully

Some repos use non-standard labels such as `enh`.

Rule:

- If the repo already uses `enh`, follow that repo convention
- If no local convention is visible, prefer standard `feat`
- Do not invent new commit types for a repo that does not already use them

This keeps the skill compatible with both Conventional Commits and team-local history.

### Step 5: Write a Reviewer-Oriented PR Summary

Follow GitHub's review guidance:

- clear title;
- clear description;
- purpose of the PR;
- overview of what changed;
- links or references when relevant;
- explicit review focus.

Do not rely on an auto-generated summary without checking it. AI-generated PR descriptions can be incomplete or inaccurate.

### Step 6: Call Out Risk Explicitly

For smart contract work, always mention:

- privileged roles touched;
- assets or balances affected;
- migration or upgrade implications;
- external integration assumptions;
- remaining risks or untested paths.

If the change is low risk, say why.

---

## Commit Type Guide

Use the smallest accurate type.

- `feat`: adds new user-visible or protocol-visible functionality
- `fix`: corrects incorrect behavior or closes a bug
- `refactor`: rewrites internals without intended behavior change
- `perf`: improves performance or gas/runtime efficiency
- `test`: test-only changes
- `docs`: documentation-only changes
- `ci`: CI workflow or automation pipeline changes
- `build`: build tooling, dependency, packaging, or compilation changes
- `chore`: maintenance work that does not fit the other categories
- `revert`: reverts a prior change
- `enh`: only if the repo already uses it as a local alias for enhancement work

Prefer a scope when it helps:

- contract/module name
- subsystem name
- chain/framework area

Examples:

- `fix(staking): reject duplicate claim requests`
- `feat(cosmwasm): add admin pause execute path`
- `test(foundry): add fuzz coverage for fee bounds`

---

## PR Title Rules

- Match the main behavioral change, not every file touched
- Keep it specific
- Avoid vague titles like `update contracts` or `fix stuff`
- If the PR is test-only, say so
- If the PR is an audit fix, say so

Good:

- `fix(anchor): validate PDA seeds before CPI`
- `test(move): add shared object ownership scenarios`

Bad:

- `changes`
- `updates`
- `smart contract improvements`

---

## PR Summary Template

Use this exact structure unless the team already has a stricter template:

```
PR Summary:
- What changed:
- Why:
- Files changed:
- Commits:
- Tests added:
- Tests run:
- Commands run:
- Security considerations:
- Assumptions:
- Remaining risks:
- Human review focus:
```

Notes:

- `Commits` can be a final commit title or a recommended split if the work should be separated
- `Tests added` can be `None`
- `Commands run` should list only commands actually executed
- `Remaining risks` should never be silently omitted on smart contract work; say `None identified beyond normal review needs` if appropriate

---

## Example

**Task:** "Add admin-controlled reward rate update and its tests."

**Good handoff:**

```
PR Summary:
- What changed:
  Added an admin-only reward rate update path and matching test coverage.
- Why:
  The protocol needs a controlled way to adjust emissions without redeploying.
- Files changed:
  - contracts/reward.rs
  - tests/reward_update.rs
- Commits:
  - feat(rewards): add admin reward rate update
  - test(rewards): cover unauthorized and invalid rate cases
- Tests added:
  - admin can update reward rate
  - non-admin cannot update reward rate
  - invalid reward rate is rejected
- Tests run:
  - cargo test
- Commands run:
  - cargo test
- Security considerations:
  Admin-only path changes reward configuration. Reviewer should verify owner/auth checks and max-rate validation.
- Assumptions:
  Existing admin ownership model is correct and unchanged.
- Remaining risks:
  No integration test yet for downstream reward accrual behavior after updating the rate.
- Human review focus:
  Please review permission checks, max-rate bounds, and whether the new rate should take effect immediately.
```

---

## Common Mistakes to Avoid

- Vague PR titles
- Commit messages that do not reflect the actual change
- Claiming tests were run when they were only planned
- Hiding untested cases
- Mixing refactors with behavior changes without calling it out
- Omitting security considerations because the change "looks small"
- Using `enh` in a repo that otherwise uses standard Conventional Commits
- Copying an AI-generated PR summary without verifying it

---

## Rules

1. Optimize for reviewer clarity, not author convenience.
2. Use Conventional Commits by default.
3. Use `enh` only when repo history shows that convention already exists.
4. Report only commands that actually ran.
5. Always mention assumptions and remaining risks.
6. Never imply that review or testing is unnecessary for smart contract changes.
