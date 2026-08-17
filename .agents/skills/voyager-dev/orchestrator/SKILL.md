---
name: voyager-dev
description: Unified Voyager(macOS) orchestrator for TCA + FSD implementation and test verification. Use whenever working in `apps/macos/**` to route scaffold, refactor, reducer, observation, reuse, package graph changes, review, build, or test work through Voyager role entry points.
compatibility: opencode
metadata:
    parent_skill: voyager-dev
    role: orchestrator
---

# Voyager Dev Orchestrator

Use this as the main entry point for Voyager macOS TCA/FSD work. The parent `voyager-dev/` directory is a namespace with `../AGENTS.md`; this orchestrator is the actual routing skill.

## Trigger

- Any non-trivial Voyager macOS work under `apps/macos/Voyager/**`, `apps/macos/Packages/**`, or `apps/macos/Hosts/**`.
- Add or refactor Voyager TCA/FSD modules, reducers, package boundaries, observation lifecycle, or tests.
- Create, delete, segment, or rewire local SwiftPM packages, products, targets, dependencies, or package consumers.
- Choose, run, or fix Voyager/macOS/SPM tests after code changes.
- Enforce reuse, architecture-gate, FSD layer, public-boundary, and cancellation ownership rules.

## Workflow

1. Classify the task shape with `../AGENTS.md` and this orchestrator workflow.
2. Before designing automated coverage, identify its canonical product spec or flow owner. If neither exists, do not create a test file; update the owner document first.
3. Read `references/skill-map.md` to choose role entry points.
4. Read `references/orchestration-workflow.md` for sequencing and handoff rules.
5. Keep source-of-truth details in the owning role's `references/` directory; do not copy long rules into role files.
6. After implementation or review, verify role structure with `references/structure-validation.md`.

## Not for

- Writing Swift code directly.
- Running tests directly.
- Replacing planner, implementer, reviewer, or verifier role files.
