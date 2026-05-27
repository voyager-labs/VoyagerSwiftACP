# Split Staging Workflow

Use this reference when the user asks to split current changes, stage one group, choose a commit message, commit, and continue with the next group.

## Scope preparation

1. Inspect changed paths before staging:

```bash
git status --short
git diff --stat
git diff --cached --stat
```

2. Propose atomic groups before the first `git add`:
    - Split by concern, module, and revertability.
    - Keep tests with the implementation they verify.
    - Keep generated/local artifacts out unless explicitly requested.
    - Treat `opencode.json`, `.omx/`, and `.sisyphus/` as protected local files.

3. Stage exactly one group:
    - Prefer explicit pathspecs for whole-file groups.
    - Use hunk staging only when one file contains multiple unrelated concerns.
    - After staging, run `git diff --cached --stat` and confirm the staged set matches one group.

4. Generate candidates from the staged group only:
    - Run `python3 .agents/skills/commit-message/scripts/collect_staged_context.py` after staging each group.
    - Do not mention remaining unstaged changes in candidate messages.

5. Present 3 candidates plus `Reroll`, then commit the selected candidate using `selection-and-commit.md`.

6. After commit success:
    - Report the commit hash only for that commit.
    - Re-run `git status --short`.
    - If more planned groups remain, stage the next group and repeat.
    - If only protected/local-only files remain, stop and report that they were intentionally left unstaged.

## Split plan format

```text
Commit groups:
1. <intent>
   - path/a
   - path/b
2. <intent>
   - path/c

Left unstaged:
- path/local-only — reason
```

## Anti-patterns

- Do not stage all files and then write a broad message.
- Do not mix skill/rule changes with application code unless one cannot work without the other.
- Do not stage ignored or local harness artifacts to make the working tree look clean.
- Do not continue to the next group after a failed commit; fix or unstage first.
