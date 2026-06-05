---
name: pr-review
description: Structurally reviews Voyager macOS PRs and local diffs for architecture, ownership, boundary, lifecycle, storage, and security issues. Use for PR review, review my PR, code review, review changes, review diff, or when a GitHub PR or local diff needs P0/P1-only Korean review grounded in Voyager's TCA/FSD architecture. Triggers on PR review, diff review, code review, review changes, Greptile review policy, and `.greptile/rules.md`. Do NOT use for post-Work compound learning, PR creation, or active Work verification.
compatibility: opencode
metadata:
    workflow: review
    output: review
---

# PR Review — Voyager Repository Review Entry Point

## Purpose

Review Voyager macOS PRs or local diffs and produce actionable, post-ready
P0/P1 findings in Korean. The review is grounded in this repository's
architecture, ownership model, and reuse patterns — not generic linting.

## Policy Source

- `.greptile/rules.md` is the source of truth for review policy.
- `references/rules.md` is a symlink to `.greptile/rules.md` for skill-local access.
- This skill references policy section headings; it does not duplicate policy prose.

## Hard Rules

- **Load policy first:** read `.greptile/rules.md` before judging any PR or local diff.
- **Follow policy conflicts:** if this skill appears to conflict with `.greptile/rules.md`, follow `.greptile/rules.md`.
- **Skip means stop:** if `.greptile/rules.md` §PR auto-review exclusions match, report only the skip reason.
- **P0/P1 only:** do not create generic, speculative, nit, P2, or P3 findings.
- **No fabricated findings:** a clean review is valid.
- **Collect before verdict:** if background exploration is dispatched, collect and reconcile every result before deciding.

## Instructions

Run these workflow references in filename order. The numeric prefixes are the execution order.

1. `references/01-policy-load-and-skip-checks.md`
2. `references/02-diff-triage.md`
3. `references/03-context-gathering.md`
4. `references/04-repository-aware-review-execution.md`
5. `references/05-output-and-decision.md`

Do not skip a workflow document unless an earlier workflow document explicitly stops the review.

## Reference Index

| Reference                                            | Purpose                                                                                                                                   |
| ---------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------- |
| `references/rules.md` → `.greptile/rules.md`         | Authoritative review policy (loaded every run). Symlink to `.greptile/rules.md` which is the SSOT.                                        |
| `references/01-policy-load-and-skip-checks.md`       | Phase 1 workflow: policy load, skip checks, review target, PR SHA consistency.                                                            |
| `references/02-diff-triage.md`                       | Phase 2 workflow: diff size, changed-area classification, planned review scope.                                                           |
| `references/03-context-gathering.md`                 | Phase 3 workflow: intent/context gathering, background exploration, CodeGraph, completion gate.                                           |
| `references/04-repository-aware-review-execution.md` | Phase 4 workflow: policy-section execution, playbook usage, conditional Host checks.                                                      |
| `references/05-output-and-decision.md`               | Phase 5 workflow: output contract, observations, evidence separation, footer, self-check, decision.                                       |
| `references/review-playbook.md`                      | Procedural check methods per review area and large-PR context-gathering tactics.                                                          |
| `references/host-review-checks.md`                   | Host/fixture/Xcode project review checks (load when diff touches `apps/macos/Hosts/**`, host `.xcodeproj`, `*Host*Fixture*`, `*Preview*`) |

## Relationship to Other Skills

| Skill             | Relationship                                                            |
| ----------------- | ----------------------------------------------------------------------- |
| `compound-review` | Post-Work synthesis. Reads `pr-review` outputs after Work completes.    |
| `pr-execution`    | Creates/updates PRs. `pr-review` reviews them.                          |
| `voyager-dev`     | Implementation and test verification during Work. Separate from review. |
