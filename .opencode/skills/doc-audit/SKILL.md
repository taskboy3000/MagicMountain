---
name: doc-audit
description: >-
  On-request audit. The user asks e.g. "audit my change against the
  docs" and you read the diff, cross-reference against
  docs/GAME_MECHANICS.md and AGENTS.md, and report what's outdated,
  missing, unclear, or confirmed accurate. Does NOT auto-trigger.
---

The user has asked you to audit a code change against the project
documentation. Do NOT run automatically — only when invoked.

## Workflow

1. Read `git diff HEAD` for the files to audit (or the full diff
   if no specific files were given).
2. Read `docs/GAME_MECHANICS.md`.
3. Read `AGENTS.md`.
4. For each section of each doc that the changed code touches,
   compare the doc's statement against the actual code.
5. Produce a report.

## Sections to cross-reference

### From GAME_MECHANICS.md

- **Structures table**: do the column names still match the model
  classes?
- **Field Ownership table**: does the frozen/updated-mid-day boundary
  still hold?
- **Data Lifecycle — Daily Maintenance**: is the order of operations
  still correct?
- **Activity State Machines**: do the transition tables match the
  code?
- **Crier Message priority list**: does it match Crier.pm?

### From AGENTS.md

- **Layer rules**: controllers dispatching to services, not
  implementing game rules.
- **URL rules**: all URLs through `url_for`, never hardcoded.
- **Model rules**: no direct table access, no `_saveTable`.
- **JS rules**: no inline JS, `Accept: application/json` on JSON
  fetches, data-attribute convention.
- **Route naming**: `<resource>#<action>` pattern.

## Report format

```
### Outdated
- <doc section>: <what changed, what doc says>

### Missing
- <doc section>: <new thing not documented>

### Confirmed accurate
- <doc section> — still matches code
```

Do NOT edit the docs. Only report.
