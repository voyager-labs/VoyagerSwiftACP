---
alwaysApply: true
description: "Canonical taxonomy for task outcomes and exception ledger policy."
---

# Outcome Classification

## Applies when

- Any task or subtask that produces a result.
- Writing evidence files, status reports, or handoff notes.

## Canonical taxonomy

| Classification | Meaning                                                                                                                             |
| -------------- | ----------------------------------------------------------------------------------------------------------------------------------- |
| **pass**       | All intent items verified. No open gaps.                                                                                            |
| **fail**       | One or more intent items could not be achieved. Root cause known.                                                                   |
| **degraded**   | Core intent achieved but with reduced scope, confidence, or quality. Document what is reduced and why.                              |
| **exception**  | An unexpected condition blocked normal completion (tool failure, environment issue, missing dependency). Root cause may be unknown. |
| **blocked**    | Work cannot proceed due to an external dependency or prerequisite not met. Not a quality issue.                                     |

## Must

- Classify every task outcome using exactly one term from the taxonomy above.
- Use the same terminology across all rule files, evidence artifacts, and status reports.
- For degraded outcomes: document what specifically is reduced (scope, confidence, coverage).
- For exception outcomes: record the exception in the exception ledger (see below).
- For blocked outcomes: identify the blocking dependency and what is needed to unblock.

## Must not

- Invent outcome labels not in the taxonomy.
- Use "pass" when any intent item is unverified.
- Use "fail" when the issue is an external blocker (use "blocked" instead).
- Leave an exception outcome without a ledger entry.

## Execution steps

1. After completing a task or subtask, review the original intent items.
2. If all intent items are verified with no gaps, classify as **pass**.
3. If one or more intent items could not be achieved and root cause is known, classify as **fail**.
4. If core intent was achieved but with reduced scope, confidence, or quality, classify as **degraded** and document what is reduced.
5. If an unexpected condition blocked normal completion, classify as **exception** and create a ledger entry (see Exception ledger policy below).
6. If work cannot proceed due to an external dependency, classify as **blocked** and identify the dependency.
7. Record the classification in the task evidence file.

## Exception ledger policy

Each exception gets a ledger entry with:

1. **Identifier**: task or step reference where the exception occurred.
2. **Symptom**: what was observed (error message, unexpected state).
3. **Classification**: exception (from taxonomy).
4. **Impact**: what work is affected or blocked.
5. **Resolution status**: open, mitigated, or resolved.
6. **Resolution detail**: how it was addressed (when resolved or mitigated).

The ledger lives in the task evidence file, in a dedicated `## Exception ledger` section. Unresolved exceptions are carried forward into handoff notes.

## Verification

- Every task evidence file contains an explicit outcome classification.
- Classification uses only terms from the canonical taxonomy.
- Every exception has a complete ledger entry with all six fields.
- No degraded or exception outcome lacks an explanation of what is reduced or blocked.
