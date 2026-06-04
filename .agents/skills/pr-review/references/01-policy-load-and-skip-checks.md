# 01 — Policy Load and Skip Checks

Run this first for every `pr-review` execution.

## Steps

1. **Read policy context first.** Open `.greptile/rules.md` in full before judging any PR or local diff.
    - `references/rules.md` is a symlink to `.greptile/rules.md` for skill-local access.
    - Treat `.greptile/rules.md` as the source of truth for skip rules, severity/noise, repository-aware checks, comment format, and review decisions.
2. **Run skip checks** from `.greptile/rules.md` §PR auto-review exclusions.
    - If any exclusion matches, stop immediately.
    - Report only the skip reason.
    - Do not produce findings, coverage, tests, risk, or review decision for skipped reviews.
3. **Identify review target.**
    - GitHub PR: collect PR number, base branch, head branch, title, description, linked issues.
    - Local diff: run `git diff --stat` and `git diff --name-only` against the merge base.
4. **Run PR target consistency check** for GitHub PRs.
    - Run `gh pr view <N> --json headRefName,headRefOid,baseRefName,baseRefOid`.
    - Compare `headRefOid` with `git rev-parse HEAD`.
    - If mismatch: state `Reviewed via gh pr diff only; local worktree was not assumed to match PR head` in review output.
    - If match: state `Reviewed against checked-out PR head (<short SHA>)`.

## Stop condition

If a skip condition matched, do not continue to `02-diff-triage.md`.
