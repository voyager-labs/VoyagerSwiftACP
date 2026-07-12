---
description: "Define shared project harness scope versus local agent artifacts."
globs: ".agents/**"
schemaVersion: 2
---

# Harness Taxonomy

## Outcome

- Treat the shared project harness as tracked, reusable infrastructure that helps humans and agents execute, verify, review, and hand off changes consistently.
- Include these tracked surfaces when evaluating harness scope:
    - agent instructions, skills, and rules: `AGENTS.md`, `.agents/**`
    - CI and automation: `.github/workflows/**`, `scripts/**`
    - local developer checks: pre-commit configs, formatter/linter/typecheck config, bootstrap targets
    - test harnesses: test entrypoints, package inventories, fixtures, validators, and reporting scripts
    - shared configuration templates or defaults that are secret-free and machine-independent
- Treat local runtime artifacts as untracked session state; lefthook's `sisyphus-artifacts-guard` prevents staging `.sisyphus/` paths.
- Promote only reusable, deterministic, secret-free changes into tracked files.
- Evaluate harness changes with `07-harness-change-evaluation.md` before treating them as adopted improvements.
- When compound-review finds a repeated pattern, decide whether the durable promotion target is a skill, rule, script, CI check, hook, test harness, or configuration template.
- Use documentation to explain harness policy and ownership; do not count docs themselves as agent harness runtime.

## Default Actions

1. Classify the requested harness change as one or more of: agent, CI, script, hook, test, config, or local artifact.
2. If the source is local evidence, extract the reusable lesson and choose a tracked promotion target.
3. If configuration is involved, separate shared defaults/templates from local overrides.
4. Check existing harness surfaces before adding a new one, and prefer extending the canonical owner.
5. Evaluate whether the proposed change improves the target behavior compared with baseline.
6. Record what remains local-only and what becomes shared through tracked files.

## Decision Rules

## Stop Conditions

- Equate harness work with skill edits only.
- Commit local evidence, session state, machine-specific config, secrets, tokens, or user-managed runtime files.
- Treat `opencode.json` as shared harness unless the user explicitly asks to convert a safe subset into a tracked template/default.
- Hide local artifacts by broad `.gitignore` changes unless repository policy explicitly changes.
- Add CI, hook, or script automation without documenting its scope, runtime cost, and rollback path.

## Verification

- A harness plan lists every affected surface category, not just skills/rules.
- `git diff --name-only` contains only tracked promotion targets intended for sharing.
- `git diff --cached --name-only` contains no `.sisyphus/`, `.omx/`, secrets, or user-managed local config.
- Shared config changes are secret-free and do not contain absolute user paths or account-specific values.
- The adoption notes include an evaluation verdict: `adopt`, `revise`, `rollback`, or `defer`.
