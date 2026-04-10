---
alwaysApply: true
description: "Global execution contract for all agent tasks."
---

# Execution Contract

## Applies when

- All tasks in this repository.

## Must

- Infer repository conventions from existing code before editing.
- Prefer repository scripts and existing tooling over ad-hoc commands.
- Keep user conversation in Korean unless explicitly requested otherwise.
- Keep code, identifiers, and commands in English.
- Keep new code comments in Korean.
- For multi-file work, explain what changed and why.
- Use minimal, targeted edits; preserve established patterns.

## Must not

- Invent repository structure, APIs, or behavior without reading source.
- Introduce new frameworks/tools without explicit request.
- Use destructive git operations unless explicitly requested.
- Commit without explicit user request.

## Execution steps

1. Identify affected area using `10-routing/00-routing.md`.
2. Read nearby code and matching rules before editing.
3. Apply smallest correct change.
4. Run relevant verification.
5. Report commands, outcomes, and touched paths.

## Failure handling

- If 3 attempts fail, stop, summarize attempts, and ask for a decision.
