# Finding Severity

Use severity to communicate expected impact and practical likelihood. Do not inflate severity to make the report look useful.

## Critical

Use when an issue can directly cause catastrophic protocol failure.

Typical impact:

- theft or permanent loss of most user funds;
- unrestricted mint, burn, drain, or ownership takeover;
- insolvency of a lending, staking, or vault system;
- permanent bricking of core protocol operations.

Likelihood should be realistic, not purely hypothetical. If exploitation requires impossible privileges or broken assumptions outside the system, lower the severity or mark it as trust assumption.

## High

Use when an issue can cause material fund loss, severe accounting corruption, or bypass of an important security boundary.

Examples:

- unauthorized withdrawal or claim path for a subset of funds;
- stale oracle or rate use that enables profitable exploitation;
- liquidation or collateral bug that creates bad debt;
- admin/operator check bypass;
- replay or receipt reuse that moves value twice.

## Medium

Use when an issue can cause limited loss, denial of service, incorrect accounting under constrained conditions, or meaningful risk that needs mitigation.

Examples:

- funds can become temporarily stuck;
- important action fails for valid users;
- rounding leak is bounded but repeatable;
- missing state guard allows inconsistent but recoverable state;
- external dependency failure leaves the protocol in a poor state.

## Low

Use when impact is limited, difficult to exploit, or mostly affects correctness, observability, or hardening.

Examples:

- event mismatch that affects monitoring;
- missing input validation with no direct loss;
- confusing privilege boundary that is currently safe;
- minor bounded rounding dust.

## Informational

Use for assumptions, documentation gaps, centralization risks, operational requirements, or reviewer notes.

Examples:

- trusted admin can pause or upgrade;
- deployment order must be followed;
- oracle choice is trusted by design;
- tests do not cover an edge case but no bug is confirmed.

## Classification Rules

Consider both impact and likelihood.

- If impact is severe but exploitation requires a trusted admin acting maliciously, classify as a trust assumption unless the design claims trustlessness.
- If the issue is only missing tests, classify as `Test gap`, not a vulnerability.
- If evidence is incomplete, mark the status as `Needs user confirmation`.
- If a finding depends on a chain-specific execution model, cite the relevant object/account/transaction behavior.
