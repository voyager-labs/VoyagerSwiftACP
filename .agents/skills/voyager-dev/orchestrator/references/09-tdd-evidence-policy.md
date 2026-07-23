---
description: "TDD evidence requirements for macOS implementation tasks."
---

# TDD Evidence Policy

## Must

- Run the test before source edits and record the failure (RED evidence).
- Run the test after implementation and record the pass (GREEN evidence).
- Write evidence to `.sisyphus/evidence/` or the task log with exact commands and exit codes.
- Follow the `spec-test-authoring` skill workflow when authoring tests.

## Must not

- Edit production source files before recording RED evidence for the target behavior.
- Mark a task complete without RED and GREEN evidence records.
- Skip RED evidence by writing tests and implementation simultaneously.

## Execution steps

1. Write or extend the test for the target behavior.
2. Run the test; confirm failure; record command and output as RED evidence.
3. Write the minimum implementation to make the test pass.
4. Run the test; confirm pass; record command and output as GREEN evidence.
5. Refactor if needed; re-run tests to confirm GREEN still holds.

## Verification

- Each implementation task has both a RED and a GREEN evidence record.
- Evidence records include the exact test command and its exit code.
- No production source edit lacks a preceding RED evidence record.
