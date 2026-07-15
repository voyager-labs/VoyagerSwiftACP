---
name: reuse-evaluation
description: Plans reuse/adapt/new decisions for Voyager macOS code. Use when there is duplicate-abstraction risk, shared utility promotion, shell freeze, or uncertainty about existing reusable symbols.
compatibility: opencode
metadata:
    parent_skill: voyager-dev
    role: planner
    shape: reuse-guard
---

# Voyager Dev Reuse Evaluation Planner

## Instructions

1. Discover existing symbols before proposing new abstractions.
2. Load `references/reuse-discovery-spec.md` and architecture-gate references from `../../reviewer/review/references/`.
3. Add `references/shell-freeze-and-shared-promotion.md` when promotion or compatibility shells are involved.
4. Emit a ranked candidate table, gate result, final choice (`reuse` | `adapt` | `new`), rejected candidates, and implementation delta.
5. Do not implement code until the reuse decision is explicit.
6. **Test ownership restructure preference**: When reorganizing tests across owners (e.g. migrating legacy tests to new spec suites), prefer "write new spec-owner tests from scratch, then delete old tests" over "migrate/relocate existing test code." Present both options, but default to rewrite+delete when the spec topology is changing fundamentally. Only suggest migration when the test logic is verbatim-identical and the sole change is file location.
