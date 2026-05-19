---
description: "Defines discrete task units, their entry/exit invariants, and provenance anchor separation."
alwaysApply: true
---

# Task Boundary Contract

## Must

- Treat a task as a discrete unit bounded by one intent, one scope, and one outcome.
- Record the task intent before starting work (what this task exists to achieve).
- Record the task outcome when work finishes (pass, fail, degraded, or exception, per `99-agent/07-outcome-classification.md`).
- Keep provenance anchors (origin sources: issue refs, plan checkboxes, design docs) separate from derivative artifacts (generated code, evidence files, reports).
- At task exit, confirm: (a) stated intent was addressed, (b) scope did not drift beyond the stated boundary, (c) outcome is explicitly classified.
- If a task cannot be completed within its boundary, stop and report a blocked outcome rather than silently expanding scope.

## Must not

- Start work without a stated intent.
- Expand scope mid-task without acknowledging the boundary change and reclassifying.
- Mix provenance anchors into derivative artifacts. Anchors are immutable references; derivatives are mutable outputs.
- Treat partial completion as pass. Use degraded or exception classification from `99-agent/07-outcome-classification.md`.
- Carry uncommitted side effects across task boundaries. Each task exits with a clean or explicitly documented state.

## Execution steps

1. Before work: state the task intent in one sentence and list the scope boundary (files, modules, or domains affected).
2. During work: if scope expands, pause, log the drift, and decide whether to split into a new task or reclassify.
3. After work: run verification matching the intent (see `99-agent/06-verification-intent-parity.md`).
4. Classify the outcome using the taxonomy in `99-agent/07-outcome-classification.md`.
5. Write evidence to the canonical location with provenance anchors in a separate section from findings.

## Verification

- Task has a recorded intent and a recorded outcome.
- No scope drift between entry intent and exit scope without an explicit boundary-change note.
- Provenance anchors are in a clearly separated section from derivative content in evidence artifacts.
- Outcome classification matches the actual state (no "pass" when work is incomplete).
