---
alwaysApply: true
description: 'Agent mode guardrails and governance alignment.'
---

# Agent Mode Execution & Modification Guidelines

## Environment self-adaptation

- The agent should infer and respect project conventions (package manager, scripts, config layout) from the repository.
- Prefer repository-defined scripts over ad-hoc commands.
- Avoid introducing tools or flows not present in the repo without explicit approval.
  - Use absolute-style monorepo paths in examples (e.g., `apps/backend/...`, `apps/macos/...`).

## Code modifications

- Before editing, write a brief plan: target files and approach at a high level.
- Provide intermittent explanations during multi-step changes.
- For major logic changes, explain:
  - Why the change is needed.
  - How the new design works at a high level.
- Clarify the scope if making related refactors or fixes beyond the request.
 - For monorepo: specify which app is affected (backend vs macOS) and list files with monorepo paths.

## Blocking issues

- On repeated failures (3+), stop execution.
- Explain the blocker, propose alternatives, and wait for user approval before pivoting.

## Quality/lint

- Match existing code style and formatting.
- Avoid introducing linter errors; keep types explicit for public APIs.

## Rule management

- **Before creating/updating rules**: Check existing rules for conflicts and overlaps.
- **SSOT principle**: Ensure each topic has one authoritative rule file (see [01-rules-governance.md](/.agents/rules/99-agent/01-rules-governance.md) for detailed SSOT enforcement patterns).
- **Cross-references**: Use full paths under `.agents/rules/` (directory + filename), e.g. [03-error-handling-policy.md](/.agents/rules/00-monorepo/03-error-handling-policy.md).
- **Consistency check**: Verify terminology, formatting, and content alignment across all rules.
- **Avoid duplication**: Consolidate repeated content and reference instead of copying.
- **Maintain currency**: Rules must reflect the current state of the codebase 100%.

## Language policy

- Conversation with the user follows the user-selected language (Korean for this project).
- Thinking/searching/coding defaults to English (APIs, symbols, identifiers, queries).
- Rules are written in English. Code comments are written in Korean. Documents/commits follow the project convention (Korean unless specified).
- Commit messages follow [06-commit-messages.md](/.agents/rules/00-monorepo/06-commit-messages.md) standard.
