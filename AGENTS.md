# Agent Instructions

This repository separates agent-facing instructions from human-facing documentation.

- **For AI Agents:** All coding standards, rules, and workflows are located in the `.agents/` directory (specifically `.agents/rules/`).
- **Local Agent Artifacts:** Runtime directories such as `.omx/` and `.sisyphus/` are local-only and must never be staged or committed. See `.agents/rules/99-agent/01-agent-harness-artifacts.md`.
- **For Humans:** Product and architecture documentation is located in `docs/index.md`.

## Review guidelines

This project uses AI-powered PR review. The reviewer is NOT a linter, formatter, or CI substitute. It should behave like a senior engineer who knows this project well.

### Output language

- All review comments and explanations MUST be written in Korean (한국어).
- Code symbols, file paths, API names, and commands remain in English.

### Always check

- Whether the change reuses existing functions, utilities, types, or patterns that already exist in the codebase instead of introducing new ones.
- Whether the change respects the project's layer boundaries, ownership model, and FSD dependency direction.
- Whether responsibilities are placed in the correct owner (reducer vs view vs service vs infra).
- Whether the change introduces duplicate or near-duplicate abstractions when extending an existing one would suffice.
- Whether failure, cancellation, teardown, and rollback paths are handled.
- Whether the change follows established project conventions in both letter and intent — not just syntactically but structurally.

### Skip

- Formatting, import ordering, naming nits, or anything a linter/formatter already catches.
- Type errors, build breaks, or test failures that CI would surface immediately.
- Generic style observations that do not imply a correctness, maintenance, or architectural risk.
- Low-confidence or speculative suggestions without concrete evidence from the diff or surrounding code.

### Severity and noise policy

- Leave only P0 (blocker) and P1 (high-confidence structural or runtime risk) findings.
- P2/nit-level comments are prohibited unless they directly imply correctness, data-loss, security, or architectural drift.
- When several local symptoms share one root cause, leave ONE consolidated finding at the strongest representative location — do not scatter related comments.
- Each comment must explain WHY this matters for this specific project, not just what looks off.
