---
description: "TDD evidence requirements for macOS implementation tasks."
---

# TDD Evidence Policy

## Must

- Run the test before source edits and record the failure (RED evidence).
- Run the test after implementation and record the pass (GREEN evidence).
- Write evidence to `.sisyphus/evidence/` or the task log with exact commands and exit codes.
- Follow the `spec-test-authoring` skill workflow when authoring tests.
- For runtime UI claims, record a visible app window showing the requested state or matching app logs that prove the state transition.

## Must not

- Edit production source files before recording RED evidence for the target behavior.
- Mark a task complete without RED and GREEN evidence records.
- Skip RED evidence by writing tests and implementation simultaneously.
- Treat a successful build, process launch, `open -b` exit code, or screenshot file existence as proof that the requested UI state appeared.

## Execution steps

1. Write or extend the test for the target behavior.
2. Run the test; confirm failure; record command and output as RED evidence.
3. Write the minimum implementation to make the test pass.
4. Run the test; confirm pass; record command and output as GREEN evidence.
5. Refactor if needed; re-run tests to confirm GREEN still holds.
6. When the acceptance criteria require runtime UI behavior, launch the matching app surface and capture the visible window state or matching app logs. If neither is observable, classify the runtime QA result as degraded and keep the UI behavior unverified.

## Verification

- Each implementation task has both a RED and a GREEN evidence record.
- Evidence records include the exact test command and its exit code.
- No production source edit lacks a preceding RED evidence record.
- Runtime UI success claims identify the visible window state or matching log evidence; launch-only evidence is explicitly insufficient.
