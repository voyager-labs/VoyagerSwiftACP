---
name: pr-review
description: Structurally reviews Voyager macOS PRs and local diffs for architecture, ownership, boundary, lifecycle, storage, and security issues. Use for PR review, review my PR, code review, review changes, review diff, or when a GitHub PR or local diff needs P0/P1-only Korean review grounded in Voyager's TCA/FSD architecture. Triggers on PR review, diff review, code review, review changes, Greptile review policy, and `.greptile/rules.md`. Do NOT use for post-Work compound learning, PR creation, or active Work verification.
compatibility: opencode
metadata:
    workflow: review
    output: review
---

# PR Review — Phased Voyager Repository Review

## Purpose

Review Voyager macOS PRs or local diffs and produce actionable, post-ready
P0/P1 findings in Korean. The review is grounded in this repository's
architecture, ownership model, and reuse patterns — not generic linting.

**Policy source of truth:** `.greptile/rules.md`. This skill references
section headings from that file. It does not duplicate policy prose.

**Greptile context requirement:** Treat Greptile-related review rules as
mandatory input. Before judging a PR or local diff, read `.greptile/rules.md`
and use its section headings as the policy checklist for what to review, what
to skip, how to format comments, and when to approve/request changes.

## When to Skip

Before starting review, apply `.greptile/rules.md` §PR auto-review
exclusions. If any exclusion matches, stop and report only the skip reason to
the operator. Do not produce findings, coverage, tests, risk, or a review
decision for skipped reviews.

## Hard Rules

- **Policy load:** Read `.greptile/rules.md` before every review. It is the
  authoritative source for exclusions, language, severity/noise, repository
  checks, comment format, and review decisions.
- **Workflow only:** This skill defines the order of operations and tool usage.
  If this skill appears to conflict with `.greptile/rules.md`, follow
  `.greptile/rules.md`.
- **No policy duplication:** Do not copy policy prose from this skill into
  review output. Use the current `.greptile/rules.md` text.

---

## Instructions

### Phase 1: Policy Load and Skip Checks

1. **Read Greptile policy context first:** open `.greptile/rules.md` in full before proceeding. This is the authoritative review policy for skip rules, severity/noise, repository-aware checks, comment format, and review decisions.
2. **Run skip checks** from `.greptile/rules.md` §PR auto-review exclusions. If any match, stop and report.
3. **Identify review target:**
    - GitHub PR: collect PR number, base branch, head branch, title, description, linked issues.
    - Local diff: run `git diff --stat` and `git diff --name-only` against the merge base.

**Stop:** If skip condition met → report skip reason. Do not produce findings.

### Phase 2: Diff Triage

1. **Measure diff size:**
    - Count changed files and total changed lines.
    - **Large PR threshold:** >200 files OR >1500 changed lines OR >3 top-level modules/layers affected.
2. **Classify changes** by area:
    - FSD layers touched (`01_App`, `02_Pages`, `03_Widgets`, `04_Features`, `05_Entities`, `06_Shared`).
    - Package boundaries crossed.
    - Change types: API, data model, migration, persistence, UI, reducer, observation, AppKit coordinator, config.
3. **Plan review scope:**
    - Normal PR: review all changes directly.
    - Large PR: group by area, state explicit coverage, and consider parallel exploration for hotspot areas (see Phase 3).

**Output of this phase:** Triage summary — file count, line count, layers touched, large/normal classification, planned review scope.

### Phase 3: Context Gathering

1. **Read PR description and linked issues** to understand intent. If none, summarize the diff's goal in 1-2 sentences.
2. **Gather architecture context:**
    - For FSD boundary changes: read relevant `Package.swift` files and segment structures to verify dependency direction.
    - For TCA reducer changes: read the owning reducer, its parent/child wiring, and dependency client registrations.
    - For persistence/storage changes: read the file-backed storage conventions at `.agents/rules/30-macos/06-file-backed-storage-invariants.md`.
3. **Large-PR parallel exploration** (when background agents are available):
    - Dispatch 2-3 explore agents for hotspot areas: architecture boundary, async lifecycle/cancellation, credential/storage paths, environment/build settings, helper/XPC contracts, package/public boundaries.
    - **Anti-duplication:** After delegating exploration, do not repeat the same searches manually. Wait for results, then proceed.
    - **Fallback:** When no background agents are available, read changed files directly in priority order: reducers → models → API clients → views → config.
4. **Tool strategy:**
    - Use `grep` / `ast_grep_search` for pattern checks across changed files.
    - Use `read` for targeted file inspection.
    - Use `lsp_diagnostics` for type-level errors in changed files.

### Phase 4: Repository-Aware Review Execution

Apply the current `.greptile/rules.md` policy sections in priority order. Do
not restate their policy text here:

1. §Repository-aware review priority
2. §Voyager architecture model
3. §TCA and segment ownership
4. §Reuse and duplicate detection
5. §Cross-feature command routing
6. §AppKit coordinator review
7. §Async lifecycle and cancellation
8. §File-backed storage and credentials
9. §Backend API contracts
10. §Environment, secrets, and build settings
11. §Helper and XPC contracts
12. §Package and public boundaries
13. §Local-only artifacts
14. §Test review

**Reference playbook:** For detailed check methods per area, see `references/review-playbook.md` (when available). That playbook operationalizes these checks with concrete commands and patterns without duplicating `.greptile/rules.md` policy.

### Phase 5: Output and Review Decision

Use `.greptile/rules.md` §Comment format and §Review output and decision as
the authoritative output contract. For large or partial reviews, use
`references/review-playbook.md` §Coverage Statement Format for the coverage
table shape.

Do not fabricate findings to justify the review. A clean review is a valid
outcome.

---

## Reference Index

| Reference                       | Purpose                                                                         |
| ------------------------------- | ------------------------------------------------------------------------------- |
| `.greptile/rules.md`            | Authoritative review policy (loaded every run)                                  |
| `references/review-playbook.md` | Procedural check methods per review area and large-PR context-gathering tactics |

---

## Relationship to Other Skills

| Skill             | Relationship                                                            |
| ----------------- | ----------------------------------------------------------------------- |
| `compound-review` | Post-Work synthesis. Reads `pr-review` outputs after Work completes.    |
| `pr-execution`    | Creates/updates PRs. `pr-review` reviews them.                          |
| `voyager-dev`     | Implementation and test verification during Work. Separate from review. |
