# Agent Instructions

This repository separates agent-facing instructions from human-facing documentation.

- **For AI Agents:** All coding standards, rules, and workflows are located in the `.agents/` directory (specifically `.agents/rules/`).
- **Local Agent Artifacts:** Runtime directories such as `.omx/` and `.sisyphus/` are local-only and must never be staged or committed. See `.agents/rules/99-agent/01-agent-harness-artifacts.md`.
- **For Humans:** Product and architecture documentation is located in `docs/index.md`.
