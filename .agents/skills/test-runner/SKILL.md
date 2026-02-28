---
name: test-runner
description: Runs relevant tests after code changes, analyzes failures, and executes fix/re-run loops. Use when tests need to be verified or fixed.
compatibility: opencode
metadata:
    workflow: testing
    output: test-report
---

# Test Runner Workflow

## Purpose

- Run fast, highly relevant tests first.
- Shorten the loop for failure analysis -> fix -> re-run.
- Never compromise test intent just to make it pass.

## Workflow

1. **Find Test Commands**
    - Locate official test commands from README.md, AGENTS.md, or CI configs.
    - For monorepos, narrow down commands based on the modified app/package.

2. **Execution Strategy**
    - 1st Pass: Fastest relevant tests (unit/specs).
    - 2nd Pass: Integration/E2E tests (if any).
    - 3rd Pass: Full test suite (if necessary).

3. **Failure Analysis**
    - Summarize the first failure log.
    - Categorize failure as "Environment" vs. "Logic".
    - Identify flaky tests via re-runs, but find the root cause.

4. **Fix (If Needed)**
    - Fix code/test while preserving the original test intent.
    - **MUST NOT**: Hide failures (e.g., removing assertions, abusing skip).
    - **MUST NOT**: Run UI tests (XCUITest, VoyagerUITests). Use `-skip-testing:AppUITests` or equivalent for iOS/macOS.

5. **Re-run & Report**
    - Re-run with the exact same command to verify success.
    - Summarize what was tested, what failed, and how it was fixed.

## Output Format

- Commands: Test commands executed.
- Result: Pass/Fail summary.
- Failures: 3-5 line summary of key errors.
- Fix/Next: Modifications made or next actions.
