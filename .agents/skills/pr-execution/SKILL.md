---
name: pr-execution
description: Creates or updates PR titles, bodies, verifications, and checklists consistently based on Linear issues. Use for "create PR", "update PR body", or "sync new commits".
compatibility: opencode
metadata:
    workflow: pr
    output: pr-body
---

# PR Execution

## Overview

Compiles branch history, validation results, and Linear issue context to draft/update PR bodies. Highly optimized for syncing commit lists and module-specific change descriptions when new commits are added.

## Workflow

1. **Gather Context**
    - Check current branch commit range:
        - `git log --oneline origin/develop..HEAD`
        - `git diff --name-status origin/develop...HEAD`
    - Check current PR status:
        - `gh pr view <PR_NUMBER> --json title,body,commits,baseRefName,headRefName`
    - Compare PR body's commit list/descriptions with actual commit range.

2. **Enforce Title Format**
    - Format: `[<Linear Issue ids...>] {PR Summary}`
    - Example: `[VOY-164] Decouple local backend runtime for macOS`

3. **Draft/Update Body**
    - Maintain the section order from `references/pr-body-template-ko.md`.
    - If commits are added, ALWAYS synchronize:
        - "Commit-level scope" list
        - "What changed where" module details (include exact file paths)
        - Verification results (test/type-check/build status)

4. **Record Validation Commands**
    - Record only actually executed verifications.
    - Base verification set follows `references/validation-commands.md`.
    - Explicitly list "Cause + Scope + Follow-up" for any failures.

5. **Quality Gates**
    - Update PR body ONLY if:
        - PR commit list matches body commit list.
        - Title follows `[Issue] Summary`.
        - No core changes (additions/deletions/migrations) missing from module details.
        - Verification section reflects latest execution results.

## Linear Integration Rules

- Explicitly link the Linear issue at the top.
- Describe commits/modules based on "actual changed code," not copy-pasting Linear text.
- If actual diff differs from Linear requirements, separate "Applied in this PR" and "Follow-up track".

## Commit Addition Sync Rules

If new commits appear after PR creation:

1. **Identify New Commits**: Compare `git log origin/develop..HEAD` with PR body.
2. **Impact Analysis**: Check files per new commit (`git show --name-status`).
3. **Update Body**: Append to commit list, update module details, re-run verifications.

## Output Format

- Valid, ready-to-use Korean Markdown for the PR body.
- Module-based organization without omitting implementation details.
- Avoid forcing tables unless explicitly requested.

## References

- PR Template: `references/pr-body-template-ko.md`
- Validation Commands: `references/validation-commands.md`
