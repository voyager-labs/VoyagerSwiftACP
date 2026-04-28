---
name: product-owner
description: Orchestrate Voyager PRODUCT-harness work through project-scoped subagents by default when the request lands inside the PRODUCT harness. Use this as the default orchestration entrypoint for FI, IA, FS, consistency review, and implementation-issue drafting across `.codex/agents/`. Trivial single-agent edits may stay local after product_owner scoping.
---

# Product Owner

Use this skill as the default operating model for Voyager work inside the `PRODUCT` harness, even when the user does not explicitly ask for delegation.

## Quick Rules

- Stay inside the `PRODUCT` harness unless the user explicitly asks for another lane.
- Keep the parent agent responsible for integration, final edits, validation choice, and the final answer.
- Keep subagent tasks narrow, role-specific, and reviewable.
- Default to delegation for non-trivial PRODUCT work when the runtime allows subagents.
- If runtime policy blocks direct subagent spawning, keep the same route locally and say that delegation fell back to the parent agent.
- Keep existing author/reviewer skills independent; do not physically nest or relocate them under this skill.

## Required References

- `references/orchestration-workflow.md`
- `references/feature-spec-authoring-lifecycle.md`
- `references/structure-validation.md`
- `references/skill-map.md`
- `.codex/agents/README.md`

## Default Output

Return:

1. the orchestration brief
2. the chosen subagent route
3. the parent-owned integration and validation step

Do not turn routine single-agent work into delegation unless the parent scoping pass finds clear value in splitting the work.
For trivial single-file edits with clear scope, the parent may stay single-agent after scoping.
