---
name: pr-feedback-triage
description: Triage GitHub PR feedback, CI failures, review bot comments, Greptile/Coderabbit findings, and check runs into a small actionable plan. Use when a PR has failing checks, review comments, bot feedback, requested changes, flaky CI, or when the user says to watch, inspect, handle, or summarize PR feedback.
compatibility: opencode
metadata:
    workflow: pr
    output: triage-plan
---

# PR Feedback Triage

## When to use this skill

- A PR has failing GitHub checks, CI logs, review comments, or bot feedback.
- The user asks to inspect Greptile/Coderabbit/review bot output before editing.
- The task is to decide what is actually actionable, not to perform a full PR review.

## Workflow

1. **Collect PR state**
    - Read PR title/body, branch, base, commits, check runs, and review threads.
    - Separate human requested changes, bot comments, CI failures, and stale/noisy feedback.

2. **Classify feedback**
    - `must-fix`: correctness, security, failing required check, broken release path.
    - `verify-first`: likely flaky, environment-specific, or missing local evidence.
    - `noise`: style-only, outdated diff position, duplicated finding, or contradicted by code.
    - `follow-up`: valid but outside current PR scope.

3. **Root-cause CI failures**
    - Identify the first failing command or test, not the final cascade.
    - Link each failure to the touched surface area when possible.
    - Mark failures as pre-existing only when there is clear evidence outside the current diff.

4. **Produce an action plan**
    - Keep it short: fix order, exact files/checks to inspect, and verification commands.
    - If code changes are needed, hand off to the relevant implementation or verification skill.

## Must not

- Do not treat every bot comment as correct.
- Do not bury required CI failures under optional lint/style feedback.
- Do not claim a failure is flaky or pre-existing without evidence.
- Do not update the PR body; use `pr-execution` for body/title synchronization.
- Do not perform a structural code review; use `pr-review` for P0/P1 review findings.

## Output format

```markdown
## PR feedback triage

- **Must fix:** ...
- **Verify first:** ...
- **Noise / no action:** ...
- **Follow-up:** ...

## Recommended order

1. ...

## Verification

- ...
```
