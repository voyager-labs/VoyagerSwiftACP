---
name: architecture-gate
description: Reviews Voyager reuse/adapt/new and architecture gate decisions. Use when checking whether a proposed abstraction respects existing symbols, ownership, and package boundaries.
compatibility: opencode
metadata:
    parent_skill: voyager-dev
    role: reviewer
    shape: architecture-gate
---

# Voyager Dev Architecture Gate Reviewer

## Instructions

1. Load `references/architecture-gate-spec.md`, `references/decision-matrix.md`, and `../../planner/reuse-evaluation/references/reuse-discovery-spec.md`.
2. Verify that existing candidates were searched and scored before creating new abstractions.
3. Check ownership, dependency direction, reuse/adapt/new rationale, and rejected candidates.
4. Report PASS/FAIL with concrete file paths and gate evidence.
5. Do not rewrite implementation code from this reviewer role.
