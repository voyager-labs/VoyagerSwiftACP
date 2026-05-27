---
description: "Keep local agent harness runtime artifacts visible but untracked."
alwaysApply: true
---

# Agent Harness Artifacts

## Must

- Treat root-level agent harness runtime directories as local-only artifacts.
- Apply this rule to current known harness artifacts: `.omx/` and `.sisyphus/`.
- Keep these artifacts visible in `git status` unless the user explicitly changes repository policy.
- Check `git status --short` before any staging or commit-related task after agent tooling runs.
- Warn the user if `.omx/` or `.sisyphus/` appears in staged or tracked paths.

## Must not

- Stage, commit, or intentionally track any path under `.omx/` or `.sisyphus/`.
- Add `.omx/` or `.sisyphus/` to `.gitignore` just to hide harness output.
- Treat harness artifacts as durable project files unless the user explicitly asks to export them elsewhere.

## Execution steps

1. If agent tooling ran, inspect `git status --short` for `.omx/` and `.sisyphus/`.
2. Before any `git add` or commit work, confirm neither directory appears in the staged set.
3. If either directory is already staged or tracked, stop and surface it as a repository hygiene issue instead of folding it into the task.

## Verification

- `git status --short` shows `.omx/` and `.sisyphus/` only as unstaged local artifacts, or not at all.
- `git diff --cached --name-only` contains no path under `.omx/` or `.sisyphus/`.
