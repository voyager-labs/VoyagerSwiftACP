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

1. Build an owner table for state, actions, effects, cancellation, lifecycle, and child routing before editing.
2. Load `references/orchestrator-spec.md` plus TCA references from `../../implementer/tca-contract/references/`.
3. Add `../../verifier/testing/references/testing-playbook.md` when routing or reducer tests change.
4. Emit the parent/child reducer split, action boundary, cancellation owner, and focused test surface.
5. Do not split purely for file-count reduction; split only when ownership becomes clearer.
