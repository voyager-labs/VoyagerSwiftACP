---
name: voyager-dev
description: Unified Voyager(macOS) development workflow for TCA + FSD (module scaffolding + large feature decomposition).
compatibility: opencode
metadata:
  area: macos
  pattern: voyager-dev-tca-fsd
---

Use this skill for Voyager macOS TCA/FSD work.

## Trigger

- Add a new Voyager module with TCA + FSD structure.
- Refactor a large feature into parent orchestrator + child reducers.
- Migrate nested `State`/`Action` to `Model/*` split files.
- Before implementation, find reusable symbols and enforce clean architecture gates.

## Workflow

1. Pick mode: `scaffold`, `decompose`, or `reuse-guard`.
2. Load mode-specific spec:
   - Scaffold: `references/scaffold-spec.md`
   - Decompose: `references/orchestrator-spec.md`
   - Reuse guard: `references/reuse-discovery-spec.md`
3. Apply common TCA constraints from `references/tca-contract.md`.
4. For `reuse-guard`, run architecture gate and scoring:
   - `references/architecture-gate-spec.md`
   - `references/decision-matrix.md`
5. Execute checks in `references/verification.md`.

## Hard constraints

- Keep non-trivial `State`/`Action` in `Model/`.
- Keep orchestration in `Reducer/*Feature.swift`.
- Views send only `Action.view`/`@ViewAction` actions.
- Keep external calls behind dependency clients.

## Required references

- `references/scaffold-spec.md`
- `references/orchestrator-spec.md`
- `references/reuse-discovery-spec.md`
- `references/architecture-gate-spec.md`
- `references/decision-matrix.md`
- `references/tca-contract.md`
- `references/verification.md`

## Source docs

- `../../../docs/architecture/macos-app.md`
- `../../../docs/architecture/coding-standards.md`
