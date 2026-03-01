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

This skill writes and updates **high-detail PR bodies** from branch history, validation results, and Linear context.
The default mode is detailed module-level reporting, not summary mode. When new commits are added, commit lists, module details, and validation results must be synchronized.

## Writing Mode

- Default: `detailed` (always)
- Exception: shorten only when the user explicitly asks for a brief summary

## Workflow

1. **Gather context**
   - Commit range:
     - `git log --oneline origin/develop..HEAD`
     - `git diff --name-status origin/develop...HEAD`
   - PR status:
     - `gh pr view <PR_NUMBER> --json title,body,commits,baseRefName,headRefName`
   - List mismatches between current PR body and actual diff

2. **Enforce title format**
   - Format: `[<Linear Issue ids...>] {PR Summary}`
   - If title intent conflicts with body scope, fix the title first

3. **Write/update body (detailed mode)**
   - Template: `references/pr-body-template-ko.md`
   - Detailing rules: `references/detailing-rules-ko.md`
   - Quality checklist: `references/quality-gate-checklist-ko.md`
   - Module sections must include file paths, change type, intent, impact, and risk

4. **Record validation results**
   - Record only commands actually executed
   - Baseline command set: `references/validation-commands.md`
   - For failures, include `cause + impact scope + follow-up action`

5. **Pass quality gates**
   - Commit list consistency
   - Title format consistency
   - No missing core changes in module details
   - Verification section reflects latest runs
   - Checklist: `references/quality-gate-checklist-ko.md`

## Linear Integration Rules

- Put the Linear issue link at the top of the body
- Do not copy-paste Linear text; describe actual code changes from diff
- If implementation differs from issue wording, split into `included in this PR` and `follow-up track`

## New Commit Sync Rules

1. Identify newly added commits with `git log origin/develop..HEAD`
2. Analyze impact with `git show --name-status --pretty=format:'COMMIT %h %s' <new-commit>`
3. Re-sync commit list, module details, and verification section

## Output Format

- Final output must be Korean Markdown ready to paste into the PR body
- Default is detailed mode and must include:
  - Commit-level scope
  - Module-level details (with file paths)
  - Validation commands and outcomes
  - Risks / follow-ups
- Use tables only when explicitly requested

## References

- PR body template: `references/pr-body-template-ko.md`
- Detailing rules: `references/detailing-rules-ko.md`
- Quality gate checklist: `references/quality-gate-checklist-ko.md`
- Validation commands: `references/validation-commands.md`
