---
name: pr-review
description: Structurally reviews PRs or local diffs focusing on quality, security, tests, and risks. Used for rapid, comment-ready code reviews.
compatibility: opencode
metadata:
    workflow: review
    output: review
---

# PR Review

## Purpose

Rapidly review PRs (or local diffs) and compile actionable, "ready-to-post" review comments.

This repository's root `AGENTS.md` review policy is authoritative: write review output in Korean, keep code symbols and paths in English, and report only P0/P1 findings with concrete evidence. Do not produce lint, formatting, naming, nit, or low-confidence comments.

## Workflow

1. **Grasp Intent**
    - Read PR description/issue links. If none, summarize the diff's goal in 1-2 sentences.

2. **Summarize Scope**
    - Categorize functional impact based on changed files/modules.
    - Check for API, Data Model, Migration, or UX changes.

3. **Checklist-Based Review**
    - **Correctness**: Edge cases, error handling, nil/optional, concurrency, state mismatch.
    - **Security**: Input validation, authn/authz, secret exposure, path/SQL injection, permissions.
    - **Credential/Storage Path Consistency**: When the diff changes credential storage paths (file locations, keychain access patterns, storage format), verify the path matches any recorded design decision and implementation conventions. Flag mismatches as P1 (correctness/data-loss risk). See `.agents/rules/30-macos/06-file-backed-storage-invariants.md` for storage conventions.
    - **Performance**: N+1 queries, unnecessary I/O, cache/batching, UI rendering cost.
    - **Maintainability**: Separation of concerns, naming, duplication, over-abstraction.
    - **Tests**: Regression, snapshot, integration tests, debugging feasibility on failure.
    - **Docs/UX**: User impact, doc/guide updates.

4. **Draft Comments**
    - Format each comment: `[P0]` or `[P1]` + problem + why it matters for this project + alternative/patch.
    - Report only blocker or high-confidence structural/runtime risks. Suppress Medium/Low/Nit findings.
    - Consolidate multiple symptoms of the same root cause into one finding at the strongest representative location.
    - Always include the file path or identifier (function/type/endpoint).

5. **Validation/Risks**
    - List 2-3 critical flows potentially broken by these changes.
    - Propose specific tests or manual QA steps.

## Output Format

- **TL;DR**: 3-line summary.
- **Findings**: Bulleted list of Korean P0/P1 comments ordered by priority.
- **Tests/QA**: Specific commands or user flows to verify.
- **Risk**: Warnings regarding rollbacks, feature flags, or migrations.
