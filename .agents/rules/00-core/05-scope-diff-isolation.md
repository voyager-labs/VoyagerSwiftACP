---
alwaysApply: true
description: "Require baseline-bound diff evidence when verifying task-local scope fidelity. Reject accumulated whole-branch diffs as scope proof."
---

# Scope-Diff Isolation

## Applies when

- Verifying that changes made for a specific task or issue stayed within their intended scope.
- The working branch or worktree contains changes from prior tasks, issues, or unrelated work.
- Any scope-fidelity claim appears in evidence, review output, or verification reports.

## Must

- Capture a baseline commit or tag before starting work on a task when the branch already carries prior changes.
- Use a task-bounded diff (`git diff <baseline>..<end>`) as the primary evidence for scope-fidelity claims.
- Record the baseline reference (commit SHA, tag, or boundary marker) in the task evidence or report.
- If only an accumulated whole-branch diff is available, document the limitation explicitly and downgrade scope confidence to `limited` or `unverified`.

## Must not

- Treat an accumulated working-tree diff (e.g., `git diff main...HEAD` on a multi-task branch) as proof that a single task's changes are scope-contained.
- Claim `scope-verified` or equivalent high-confidence status when the diff basis includes changes from other tasks.
- Omit the baseline reference from scope evidence, even if the diff looks small or the task seems trivial.

## Execution steps

1. Before starting a task on a branch with prior commits, capture a baseline:
   `git rev-parse HEAD > .sisyphus/baseline-<task-id>.txt` or record the SHA in the task evidence file.
2. After completing the task, generate the scope diff:
   `git diff <baseline>..HEAD --name-only` for the file list,
   `git diff <baseline>..HEAD --stat` for the summary.
3. Compare the changed files against the task's allowed and forbidden paths.
4. Record the baseline SHA, the diff output, and the scope verdict in the task evidence file.
5. If a baseline was not captured before starting:
    - Attempt to reconstruct it from commit history, issue boundary markers, or branch topology.
    - If reconstruction is ambiguous, document the gap and set scope confidence to `limited`.
    - Never fabricate a baseline.

## Verification

- Confirm the evidence file includes a baseline commit SHA or equivalent boundary reference.
- Confirm the diff command in evidence uses the baseline, not the branch root or merge base against main.
- Confirm scope confidence is `limited` or `unverified` when only accumulated diffs are available.
- Confirm no scope-fidelity claim relies on a diff that includes files from other tasks.

## Few-shot examples

- **Bad:** A task on a branch with three prior issues runs `git diff main...HEAD --name-only`, sees only expected files, and claims full scope verification.
  **Good:** The task uses `git diff <baseline-captured-before-task>..HEAD --name-only` and records the baseline SHA in evidence.

- **Bad:** Scope review says "all changes are in the expected module" without stating what diff basis was used.
  **Good:** Scope review states "baseline: abc123f, diff: abc123f..def456a, files: [list], verdict: scope-contained."

- **Bad:** No baseline was captured, the reviewer reconstructs one by guessing which commit started the task, and claims full confidence.
  **Good:** The reviewer documents that the baseline is reconstructed, notes the ambiguity, and sets scope confidence to `limited`.

## Illustrative examples

These show how the rule applies in practice. The paths below are examples, not normative requirements.

- A multi-issue feature branch where issue VOY-225 is the third issue. Before starting, the agent records `git rev-parse HEAD` as the baseline. After finishing, it diffs from that baseline to verify changes are isolated to the feature module.
- A hotfix branch with a single issue needs no special isolation because the branch root is the natural baseline. The rule still applies but the default baseline (branch creation point) is sufficient.
