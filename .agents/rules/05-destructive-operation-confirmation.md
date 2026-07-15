---
description: "Require explicit user confirmation before destructive git and filesystem operations."
alwaysApply: true
schemaVersion: 2
---

# Destructive Operation Confirmation

## Outcome

- Ask the user for explicit confirmation before running any of these commands:
    - `git checkout -- .` or `git checkout -- <path>` (discard working tree changes).
    - `git restore .` or `git restore <path>` (discard working tree changes).
    - `git clean -fd` or `git clean -fdx` (remove untracked files).
    - `git reset --hard` (reset working tree and index).
    - `git reset --hard HEAD~N` (reset to previous commits).
    - `git stash drop` or `git stash clear` (permanent stash removal).
    - `git rebase` or `git reset` that rewrites commit history.
    - `rm -rf` on directories containing tracked or untracked project files.
- Explain what will be lost before asking for confirmation.
- Wait for the user's explicit approval before proceeding.
- Apply this rule even when tool permissions technically allow the operation.

## Default Actions

1. Before running a destructive command, list exactly what will be lost or changed.
2. Present the exact command and its expected impact to the user.
3. Wait for explicit approval ("yes", "진행", "OK", or equivalent).
4. After approval, run only the confirmed command and report the result.
5. If the user declines or suggests an alternative, follow the alternative.

## Decision Rules

## Stop Conditions

- Run destructive commands immediately, even if the operation seems necessary to fix a problem.
- Assume that having tool permission implies user consent for destructive actions.
- Bundle destructive operations with other commands to bypass confirmation (e.g., `git checkout -- . && git pull`).
- Skip confirmation because the changes "look small" or "seem unimportant."

## Verification

- No destructive command runs without a preceding user confirmation in the conversation.
- Each confirmation request includes the exact command and its expected impact.
- No destructive command is bundled with non-destructive operations in a single invocation.
