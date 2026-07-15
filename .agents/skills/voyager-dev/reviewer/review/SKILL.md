---
name: review
description: Reviews Voyager reuse/adapt/new decisions and FSD layer, segment, slice, package, and public-boundary compliance. Use when evaluating proposed abstractions, ownership, dependency direction, file placement, or public API changes.
compatibility: opencode
metadata:
    parent_skill: voyager-dev
    role: reviewer
    shape: architecture-boundary-review
---

# Voyager Dev Architecture and Boundary Reviewer

## Instructions

1. Load `references/architecture-gate-spec.md`, `references/decision-matrix.md`, `references/layer-and-segment-rules.md`, `references/public-boundary-spec.md`, and `../../planner/reuse-evaluation/references/reuse-discovery-spec.md`.
2. Verify existing candidates were searched and scored before creating new abstractions.
3. Check ownership, dependency direction, reuse/adapt/new rationale, FSD placement, public API necessity, reverse imports, and rejected candidates.
4. Distinguish compiler-required public visibility from unjustified public-surface expansion during Swift 6 migration.
5. Report PASS/FAIL with concrete file paths, the violated boundary or gate, and supporting evidence.
6. Do not rewrite implementation code or suggest style nits unrelated to architecture and boundary correctness.
