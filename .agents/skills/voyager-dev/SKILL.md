---
name: voyager-dev
description: Unified Voyager(macOS) workflow for TCA + FSD changes. Use this whenever working in `apps/macos/Voyager/Voyager/**`, especially for State/Action/Reducer refactors, feature decomposition, external observation ownership, model splits, or reuse discovery, even if the user does not explicitly mention `voyager-dev`.
compatibility: opencode
metadata:
    area: macos
    pattern: voyager-dev-tca-fsd
---

Use this skill for Voyager macOS TCA/FSD work.

## Trigger

- Any non-trivial work under `apps/macos/Voyager/Voyager/**`.
- Add a new Voyager module with TCA + FSD structure.
- Refactor a large feature into parent orchestrator + child reducers.
- Migrate nested `State`/`Action` to `Model/*` split files.
- Move view-owned external/system observation into reducer-owned TCA lifecycle.
- Before implementation, find reusable symbols and enforce clean architecture gates.

## Workflow

1. Classify the task shape before editing.
    - New module or feature shell -> load `references/scaffold-spec.md`.
    - Large reducer/feature split or ownership cleanup -> load `references/orchestrator-spec.md`.
    - View-owned external/system observation -> load `references/observation-lifecycle-spec.md`.
    - Reuse/discovery question or duplication risk -> load `references/reuse-discovery-spec.md`, `references/architecture-gate-spec.md`, and `references/decision-matrix.md`.
2. Always apply common guidance from:
    - `references/development-rules.md`
    - `references/macos-architecture-shape.md`
    - `references/public-boundary-spec.md`
    - `references/tca-contract.md`
    - `references/testing-playbook.md`
3. Load every relevant playbook, not just one, when the change spans multiple task shapes.
4. Execute checks from `references/verification.md`.

This skill routes internally. Do not ask the user to pick a mode.

## Not for

- Trivial copy-only or spacing-only SwiftUI tweaks with no TCA, dependency, or architecture impact.
- Non-Voyager macOS work outside `apps/macos/Voyager/Voyager/**` unless the task still clearly matches this skill's TCA/FSD workflow.
- Pure test execution tasks that are better served directly by `.agents/skills/test-runner/SKILL.md`.

## Hard constraints

- Keep non-trivial `State`/`Action` in `Model/`.
- Keep orchestration in `Reducer/*Feature.swift`.
- Avoid splitting TCA core types through `State+*`, `Action+*`, `Feature+*`, or `Reducer+*` files when that spread starts to hide state movement and ownership.
- If a flow grows too large, extract dedicated model types, helper/coordinator types, or child features/reducers and compose them explicitly from the parent.
- UI adapters (SwiftUI views, representables, coordinators) emit only `Action.view`/`@ViewAction` actions for the feature store they are initialized with.
- In UIKit/AppKit coordinators, react to feature state via TCA `observe { ... }`, not `store.publisher`/`sink`.
- Do not introduce Combine-based state subscriptions in coordinators.
- Keep external calls behind dependency clients.
- Accumulate Voyager-specific reusable heuristics in `references/development-rules.md` before promoting them into `.agents/rules/**`.

## Required references

- `references/development-rules.md`
- `references/macos-architecture-shape.md`
- `references/public-boundary-spec.md`
- `references/scaffold-spec.md`
- `references/orchestrator-spec.md`
- `references/observation-lifecycle-spec.md`
- `references/reuse-discovery-spec.md`
- `references/architecture-gate-spec.md`
- `references/decision-matrix.md`
- `references/tca-contract.md`
- `references/testing-playbook.md`
- `references/verification.md`
