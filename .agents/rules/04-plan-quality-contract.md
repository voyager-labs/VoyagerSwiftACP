---
description: "Mandatory quality sections for implementation plans."
globs: ".sisyphus/plans/**/*.md"
schemaVersion: 2
---

# Plan Quality Contract

## Outcome

- Include TDD evidence, test ownership, and commit strategy sections in every implementation plan that involves code changes.
- For Voyager macOS plans, use `.agents/skills/voyager-dev/orchestrator/references/09-tdd-evidence-policy.md`, `.agents/skills/voyager-dev/orchestrator/references/10-test-ownership-convention.md`, and `.agents/skills/voyager-dev/implementer/spec-test-authoring/references/flow-test-topology.md` as the canonical implementation details.
- Reference the `commit-message` skill for all planned commits unless the plan explicitly justifies an alternative.
- Write per-task acceptance criteria that include evidence requirements.

## Default Actions

1. Before writing tasks, identify the owning platform's TDD and test-topology references.
2. For each implementation task, add QA scenarios showing the RED → GREEN flow.
3. In the Commit Strategy section, reference the `commit-message` skill.
4. Verify every acceptance criterion names its required evidence.

## Decision Rules

- Apply platform-specific test ownership rules from the owning platform skill instead of duplicating them in the plan.
- Plans without source changes may omit RED → GREEN evidence when they state why no executable behavior changes.

## Stop Conditions

- Write implementation tasks without TDD evidence expectations.
- Plan tests outside the owning platform's canonical test topology.
- Duplicate behavior assertions across test owners.
- Plan commits without referencing the `commit-message` skill.

## Verification

- Plan file contains RED and GREEN evidence expectations per implementation task.
- Plan file's Commit Strategy references the `commit-message` skill.
- Every planned test has one canonical owner from the owning platform's test topology.
- No behavior assertion is duplicated across test owners.
