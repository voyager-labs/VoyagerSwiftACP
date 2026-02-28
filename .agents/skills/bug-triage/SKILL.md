---
name: bug-triage
description: Reproduces, isolates, and minimally fixes bugs/test failures. Used for rapid triage of critical issues.
compatibility: opencode
metadata:
    workflow: debugging
    output: triage
---

# Bug Triage

## Purpose

- Reproduce the minimal failing case.
- Isolate down to exactly 1 root cause.
- Fix minimally (NO refactoring).
- Prevent regression (add tests if possible).

## Workflow

1. **Gather Facts**
    - Summarize "Expected vs. Actual" in one sentence.
    - Collect error logs, stack traces, and environment flags.

2. **Reproduce**
    - Create the shortest reproduction steps.
    - If flaky, inject observation points (logs/metrics) to stabilize it.

3. **Isolate**
    - Reduce input/state/timing dependencies.
    - Identify suspect commits/changes to narrow scope.

4. **Identify Root Cause**
    - NEVER mask symptoms (e.g., blanket try/catch, force casting).
    - You must be able to explain _why_ it fails under these specific conditions.

5. **Fix**
    - Keep the fix minimal.
    - Strictly NO unintended refactoring or formatting changes.

6. **Verify**
    - Confirm the minimal reproduction case no longer fails.
    - Check 1-2 related paths/features for side effects.
    - Add a regression test if applicable.

## Output Format

- Root cause: 1-2 sentences.
- Fix: What was changed (core logic only).
- Verification: Tests or manual checks performed.
- Risk: Remaining risks or needed follow-ups.
