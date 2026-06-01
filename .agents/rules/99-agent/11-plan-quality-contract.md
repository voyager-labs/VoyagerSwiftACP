---
description: "Mandatory quality sections for implementation plans."
alwaysApply: true
---

# Plan Quality Contract

## Must

- Include these mandatory sections in every implementation plan that involves code changes:
    - **TDD Evidence Policy**: each implementation task must specify that a RED test runs and fails before source edits, and a GREEN test runs and passes after implementation.
    - **Test Ownership Convention**: product behavior tests must target spec-owner suites (`<SpecID><PascalCaseTitle>Tests.swift`) with `// MARK:` sections; no standalone ad-hoc test files.
    - **Commit Strategy**: reference the `commit-message` skill for all commits unless the plan explicitly justifies an alternative.
- Write per-task acceptance criteria that include evidence requirements.

## Must not

- Write implementation tasks without TDD evidence expectations.
- Plan standalone ad-hoc product behavior test suites outside spec ownership.
- Plan commits without referencing the `commit-message` skill.

## Execution steps

1. Before writing plan tasks, confirm the plan will include TDD evidence, test ownership, and commit workflow sections.
2. For each implementation task, add QA scenarios showing the RED → GREEN flow.
3. In the Commit Strategy section, reference the `commit-message` skill.
4. Verify every acceptance criterion mentions evidence requirements.

## Verification

- Plan file contains RED and GREEN evidence expectations per implementation task.
- Plan file's Commit Strategy references the `commit-message` skill.
- No standalone ad-hoc product behavior test suites are planned.
