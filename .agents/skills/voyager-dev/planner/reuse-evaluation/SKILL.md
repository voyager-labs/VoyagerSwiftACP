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
2. Load `references/reuse-discovery-spec.md` and architecture-gate references from `../../reviewer/architecture-gate/references/`.
3. Add `references/shell-freeze-and-shared-promotion.md` when promotion or compatibility shells are involved.
4. Emit a ranked candidate table, gate result, final choice (`reuse` | `adapt` | `new`), rejected candidates, and implementation delta.
5. Do not implement code until the reuse decision is explicit.
