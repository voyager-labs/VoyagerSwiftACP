---
description: "Reducer-owned external observation lifecycle for SwiftUI + TCA views."
globs: "apps/macos/**/*.swift"
schemaVersion: 2
---

# TCA Observation Lifecycle

## Outcome

- External and system observation is owned by a feature reducer, with explicit start/stop actions, dependency-backed effects, cancellation ownership, semantic event routing, and focused reducer coverage.
- Views remain lifecycle/action senders; UI-only local presentation state may remain in the view.
- This rule is the canonical invariant owner. `../SKILL.md` and `observation-lifecycle-spec.md` own the migration procedure.

## Default Actions

1. Classify the signal as UI-local or external/system-driven.
2. For external/system signals, add or extend feature `State`/`Action`, explicit start/stop lifecycle actions, a dependency client, and a feature-owned cancellation ID.
3. Route raw callbacks through a semantic feature action before state mutation or child forwarding; keep the view limited to lifecycle/user action sends.
4. Load the observation implementer and add focused reducer tests for start, cancellation, and semantic event routing.

## Decision Rules

- Treat a signal as reducer-owned when it originates outside the view tree, must survive rendering, or affects feature state or child reducers.
- UI-only geometry, temporary hover/focus visuals, and one-off local animations can stay view-owned.
- Start long-lived effects with `.cancellable(id: ..., cancelInFlight: true)` and stop them with `.cancel(id: ...)`.
- For migration-heavy work, load `.agents/skills/voyager-dev/orchestrator/SKILL.md` before the observation playbook.

## Stop Conditions

- Do not use `NotificationCenter.default.publisher`, `.onReceive(...)`, observer tokens, long-lived task loops, or `@Dependency` in `Ui/*.swift` for external/system observation.
- Do not store external observation lifecycle in view-local `@State` or start a long-lived observation without cancellation.
- Do not move UI-only local interaction into reducers merely for symmetry.

## Verification

- Confirm the moved signal is absent from `NotificationCenter.default.publisher` and `.onReceive(` in the target view.
- Confirm reducer start/stop actions, `.cancellable`, `.cancel`, and semantic event routing exist.
- Confirm focused reducer tests cover start, stop/cancellation, and routed semantic actions.
- Confirm touched Swift files have no LSP errors.
