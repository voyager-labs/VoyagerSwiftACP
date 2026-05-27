---
name: docs-sync-planner
description: Plans documentation updates across README, docs indexes, developer guides, agent rules, and related references before editing. Use when adding or changing docs, finding insertion points, keeping nearby docs in sync, updating README sections, or checking whether documentation changes require matching references elsewhere.
compatibility: opencode
metadata:
    workflow: docs
    output: docs-plan
---

# Docs Sync Planner

## When to use this skill

- The user asks where to add a README/docs section.
- A code/tooling change needs matching documentation updates.
- Multiple docs may need to stay consistent, but the edit location is unclear.

## Workflow

1. **Map the doc surface**
    - Identify the canonical entry point first: `README.md`, `docs/index.md`, domain docs, `.agents/rules/**`, or skill docs.
    - Read nearby headings and navigation links before proposing an insertion point.

2. **Find sync partners**
    - Search for the same concept, command, file path, scheme, environment variable, or workflow name.
    - Group references as `must update`, `maybe update`, or `do not touch`.

3. **Choose the smallest consistent edit**
    - Prefer one canonical explanation plus links from secondary docs.
    - Keep agent-only rules in `.agents/rules/**`; keep human-facing guidance in README/docs.
    - Avoid duplicating long policy text across files.

4. **Plan verification**
    - For docs-only changes, verify links, command names, paths, and navigation references.
    - If docs describe commands, ensure the command exists or cite why it is illustrative only.

## Must not

- Do not edit every matching file just because a term appears there.
- Do not put human tutorial content in agent rules.
- Do not put agent execution policy in human docs unless it affects developers directly.
- Do not create a new docs page when a nearby canonical page can hold the change.

## Output format

```markdown
## Docs sync plan

- **Primary insertion point:** `path` — reason
- **Must update:** ...
- **Maybe update:** ...
- **Do not touch:** ...
- **Verification:** ...
```
