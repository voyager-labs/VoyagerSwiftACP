# Agent Instructions

This repository separates agent-facing instructions from human-facing documentation.

- **For AI Agents:** All coding standards, rules, and workflows are located in the `.agents/` directory (specifically `.agents/rules/`).
- **Local Agent Artifacts:** Runtime directories such as `.omx/` and `.sisyphus/` are local-only and must never be staged or committed. See `.agents/rules/99-agent/01-agent-harness-artifacts.md`.
- **For Humans:** Product and architecture documentation is located in `docs/index.md`.

## Protected local files

- Treat `opencode.json` as a user-managed local file.
- Never automatically reset, revert, or discard changes in `opencode.json`.
- Never include `opencode.json` in commits unless the user explicitly asks for it.

## Commit attribution

- Agents must **never** add `Co-authored-by: Sisyphus`, `Co-authored-by: Sisyphus <...>`, `Ultraworked with Sisyphus`, or any similar AI/Sisyphus co-author trailer to commit messages.
- This applies to commit subjects, bodies, and footers alike.
- The only exception is when the user explicitly requests such a trailer.

## PR review rules

Codex and other agents read `AGENTS.md`, but PR review policy must stay centralized in Greptile rules.

- For AI-powered PR reviews, read and follow `.greptile/rules.md`.
- Do not duplicate PR review language, severity, noise, architecture, or reuse rules in this file.
