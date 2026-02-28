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

## Workflow

1. **Grasp Intent**
    - Read PR description/issue links. If none, summarize the diff's goal in 1-2 sentences.

2. **Summarize Scope**
    - Categorize functional impact based on changed files/modules.
    - Check for API, Data Model, Migration, or UX changes.

3. **Checklist-Based Review**
    - **Correctness**: Edge cases, error handling, nil/optional, concurrency, state mismatch.
    - **Security**: Input validation, authn/authz, secret exposure, path/SQL injection, permissions.
    - **Performance**: N+1 queries, unnecessary I/O, cache/batching, UI rendering cost.
    - **Maintainability**: Separation of concerns, naming, duplication, over-abstraction.
    - **Tests**: Regression, snapshot, integration tests, debugging feasibility on failure.
    - **Docs/UX**: User impact, doc/guide updates.

4. **Draft Comments**
    - Format each comment: `[Priority] Problem + Why it's a problem + Alternative/Patch`.
    - Prioritize: Blocker > High > Medium > Low > Nit.
    - Always include the file path or identifier (function/type/endpoint).

5. **Validation/Risks**
    - List 2-3 critical flows potentially broken by these changes.
    - Propose specific tests or manual QA steps.

## Output Format

- **TL;DR**: 3-line summary.
- **Findings**: Bulleted list of comments ordered by priority (Blocker to Nit).
- **Tests/QA**: Specific commands or user flows to verify.
- **Risk**: Warnings regarding rollbacks, feature flags, or migrations.
