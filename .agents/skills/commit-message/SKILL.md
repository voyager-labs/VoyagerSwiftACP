---
name: commit-message
description: Generates a single, convention-compliant commit message based exclusively on currently staged changes. Use when creating a git commit.
compatibility: opencode
metadata:
    workflow: git
    output: commit-message
---

# Commit Message Generator

## Purpose

Generates exactly one commit message for the current staged changes, strictly following repo conventions (e.g. Conventional Commits).
Focuses on the "Why" rather than just the "What".

## Hard Rules

- **Ground Truth**: Use ONLY staged changes. NEVER mention unstaged changes.
- **Fresh Context**: Always run the script to gather the latest index state on every invocation. Do not reuse past outputs.
- **Output Only**: Return the "commit message text" ONLY. No headers, code fences, or explanations.
- **Follow Templates**: Use `references/output-template.md` and `references/response-template.md`.
- **Comprehensive Subject**: If multiple files are staged, the subject MUST cover the intent of ALL staged changes. Do not write a subject that only covers one file.
- **Empty State**: If no files are staged, do not hallucinate a message. Inform the user to stage files.
- **Bullet Format**: If adding a body, use `- ` for all bullet points.
- **No Secrets**: Never include API keys, tokens, or PII in the commit message.

## Workflow

1. **Collect Staged Context**
    - Run the script to gather the latest index state:

    ```bash
    python3 .claude/skills/commit-message/scripts/collect_staged_context.py
    ```

    - If the patch is too long, reduce lines to avoid token overflow:

    ```bash
    python3 .claude/skills/commit-message/scripts/collect_staged_context.py --head-lines 600 --tail-lines 600
    ```

2. **Draft the Message**
    - **Convention Priority**: Project commit guidelines > Recent commit style > Language.
    - **Scope**: Infer from paths. Omit if ambiguous.
    - **Subject**: 1-line summary encompassing all staged changes.
    - **Body**: Use bullet points (`- `) to explain "Why/Impact/Risk". Keep it short. Do not over-explain implementation details.

## Bundled Resources

- `scripts/collect_staged_context.py`: Extracts staged files, statistics, branch/issue hints, and recent commit style in one go.
- `references/output-template.md`: Template for subject/body formatting, including double-newline rules.
- `references/response-template.md`: Template for edge cases (e.g., empty staging area).
