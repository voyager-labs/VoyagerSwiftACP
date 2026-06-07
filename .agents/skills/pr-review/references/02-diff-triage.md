# 02 — Diff Triage

Run after `01-policy-load-and-skip-checks.md` when the review was not skipped.

## Steps

1. **Measure diff size.**
    - Count changed files and total changed lines.
    - Classify as **large** when any threshold is met: >200 files, >1500 changed lines, or >3 top-level modules/layers affected.
2. **Classify changed areas.**
    - FSD layers: `01_App`, `02_Pages`, `03_Widgets`, `04_Features`, `05_Entities`, `06_Shared`.
    - Package boundaries crossed.
    - Change types: API, data model, migration, persistence, UI, reducer, observation, AppKit coordinator, config.
3. **Plan review scope.**
    - Normal PR: review all changes directly.
    - Large PR: group changed paths by area and state explicit coverage.
    - Parallel exploration is handled only in `03-context-gathering.md`.

## Output of this workflow step

Write a triage summary containing file count, changed-line count, layers touched, normal/large classification, and planned review scope.

## Detailed commands

Use `references/review-playbook.md` §Diff Collection Commands and §Large-PR Thresholds for concrete command patterns.
