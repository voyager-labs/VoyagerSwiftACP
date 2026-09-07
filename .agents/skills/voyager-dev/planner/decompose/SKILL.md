---
name: decompose
description: Plans Voyager TCA reducer decomposition and ownership cleanup. Use when splitting large features, moving State/Action into Model files, or clarifying parent-child reducer boundaries.
compatibility: opencode
metadata:
    parent_skill: voyager-dev
    role: planner
    shape: decompose
---

# Voyager Dev Decompose Planner

## Instructions

1. Build the concern-owner table in the existing plan before changing ownership: concrete State/Action, write set, effects, cancellation, accepted-result fence, lifetime, outputs and tests.
2. Load `references/orchestrator-spec.md` and only the relevant TCA references from `../../implementer/tca-contract/references/`.
3. Add `../../implementer/spec-test-authoring/references/testing-playbook.md` when routing or reducer tests change.
4. Emit the explicit composition, immutable inputs/outcomes, removed old writers/routes and focused verification. Hand implementers exact paths, signatures, preserved invariants and non-goals.
5. Keep one aggregate when phases cannot be separated without duplicate authority. Do not split just for file length, new folder names, or Controller/Service symmetry.
6. A changed ownership contract needs compile/behavior evidence. AST success is a syntactic check, not proof of single-writer, cancellation or native lifecycle correctness.
