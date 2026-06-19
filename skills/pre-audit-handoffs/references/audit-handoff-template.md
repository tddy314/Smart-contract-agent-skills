# Audit Handoff Template

Use this template for the final handoff. Keep it concise and reviewer-facing.

```text
Pre-Audit Handoff:

- Scope:
  <contracts/modules/programs/scripts included in review>

- Out of scope:
  <files, deployments, integrations, or assumptions intentionally excluded>

- Protocol summary:
  <2-5 sentences explaining what the system does>

- Architecture map:
  <main components and how value/state flows between them>

- Actors and privileges:
  - <actor> - <permissions and limits>

- Assets and accounting:
  - <asset/account/object/balance> - <what it represents and how it changes>

- External dependencies:
  - <dependency> - <trust/failure assumption>

- Self-audit findings:
  Finding:
  - Severity:
  - Component:
  - Description:
  - Impact:
  - Scenario:
  - Evidence:
  - Recommendation:
  - Status:

- Test gaps:
  - <missing coverage> - <why it matters>

- Commands run:
  - <command> - <result>

- Known limitations:
  - <known design limit, centralization risk, or incomplete area>

- Recommended auditor focus:
  - <specific file/function/flow and why it deserves attention>

- Open questions:
  - <question for protocol team or auditor>
```

## Writing Rules

- Use concrete file, function, module, account, object, or contract names when available.
- Keep confirmed findings separate from test gaps and assumptions.
- Do not hide uncertainty. Mark uncertain points as open questions.
- Do not say the project is safe because no findings were discovered.
- Do not include long checklists that were not relevant to this codebase.
