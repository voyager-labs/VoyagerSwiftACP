---
description: "Mandatory quality sections for implementation plans."
alwaysApply: true
schemaVersion: 2
---

# Plan Quality Contract

## Outcome

- Include these mandatory sections in every implementation plan that involves code changes:
    - **TDD Evidence Policy**: each implementation task must specify that a RED test runs and fails before source edits, and a GREEN test runs and passes after implementation.
    - **Test Ownership Convention**: product behavior tests must target either spec-owner suites (`<SpecID><PascalCaseTitle>Tests.swift`) with `// MARK:` sections or canonical flow-document suites under `VoyagerTests/Flows/<CATEGORY>/` when they cover production-composition journeys and cross-feature handoffs. Keep the one-spec-one-owner convention for `Specs/` unchanged. See `.agents/skills/voyager-dev/verifier/spec-test-authoring/references/flow-test-topology.md`.
    - **Commit Strategy**: reference the `commit-message` skill for all commits unless the plan explicitly justifies an alternative.
- Write per-task acceptance criteria that include evidence requirements.

## Default Actions

1. Before writing plan tasks, confirm the plan will include TDD evidence, test ownership, and commit workflow sections.
2. For each implementation task, add QA scenarios showing the RED → GREEN flow.
3. In the Commit Strategy section, reference the `commit-message` skill.
4. Verify every acceptance criterion mentions evidence requirements.
5. Assign production-composition journeys to canonical flow-document suites and interaction AC detail to spec-owner suites.

## Decision Rules

## Stop Conditions

- Write implementation tasks without TDD evidence expectations.
- Plan standalone ad-hoc product behavior test suites outside canonical `Specs/` or `Flows/` ownership.
- Duplicate behavior assertions between `Specs/` and `Flows/`; each behavior has exactly one owning boundary.
- Plan commits without referencing the `commit-message` skill.

## Verification

- Plan file contains RED and GREEN evidence expectations per implementation task.
- Plan file's Commit Strategy references the `commit-message` skill.
- No standalone ad-hoc product behavior test suites are planned.
- Flow-document suites (`<PascalSlug>FlowTests.swift`) own production-composition journeys; spec-owner suites own interaction AC detail, with no duplicated assertions between `Specs/` and `Flows/`.
