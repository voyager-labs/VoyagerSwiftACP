# Voyager Dev Skill Namespace

`voyager-dev/` is a namespace for Voyager macOS TCA/FSD work, not a direct skill entry point.

## Entry point

- Use `orchestrator/SKILL.md` as the main skill entry point for non-trivial `apps/macos/**` work.
- The orchestrator routes to role entry points under `planner/`, `implementer/`, `reviewer/`, and `verifier/`.
- Source-of-truth references live under the owning role's `references/` directory.

## Trigger scope

Route through this namespace for:

- Voyager macOS work under `apps/macos/Voyager/**`, `apps/macos/Packages/**`, or `apps/macos/Hosts/**`.
- TCA/FSD scaffolding, decomposition, implementation, verification, test selection, and architecture review.
- SwiftPM package creation, segmentation, product/target/dependency graph changes, and consumer wiring verification.
- View-owned observation moved into reducer-owned TCA lifecycle.
- Reuse/adapt/new decisions that affect Voyager macOS boundaries.

## Structure

- `orchestrator/` — task classification, routing, integration, and structure validation.
- `planner/` — scaffold, decompose, and reuse-evaluation planning.
- `implementer/` — TCA contract and observation implementation mechanics.
- `reviewer/` — architecture-gate and boundary review.
- `verifier/` — spec test authoring, test execution/failure analysis, and final verification discipline.
- Role `references/` directories — canonical Voyager-dev references owned by the role that uses them most directly. Do not duplicate long policy text across roles.

## Rules

- Keep role skill files thin and responsibility-focused.
- Keep detailed guidance in the owning role's `references/` directory.
- Do not create a top-level skill file; that makes this namespace compete with the orchestrator entry point.
- Update `orchestrator/references/skill-map.md` whenever role entry points change.
