---
name: product-owner
description: Orchestrate delegated Voyager PRODUCT-harness work through project-scoped subagents when the user explicitly asks for subagents, delegation, parallel work, or PRODUCT_OWNER-style coordination. Use this as the orchestration entrypoint for FI, IA, FS, consistency review, and implementation-issue drafting across `.codex/agents/`. Do not trigger for routine single-agent edits.
---

# Product Owner

Use this skill only when the user explicitly wants delegated or parallel orchestration for Voyager product-documentation work.

## Quick Rules

- Stay inside the `PRODUCT` harness unless the user explicitly asks for another lane.
- Keep the parent agent responsible for integration, final edits, validation choice, and the final answer.
- Keep subagent tasks narrow, role-specific, and reviewable.
- Keep existing author/reviewer skills independent; do not physically nest or relocate them under this skill.

## Required References

- `references/orchestration-workflow.md`
- `references/structure-validation.md`
- `references/skill-map.md`
- `.codex/agents/README.md`

## Default Output

Return:

1. the orchestration brief
2. the chosen subagent route
3. the parent-owned integration and validation step

Do not turn routine single-agent work into orchestration unless the user explicitly asked for it.
