---
globs: apps/macos/**/*.swift
description: "Reducer-owned external observation lifecycle for SwiftUI + TCA views."
---

# TCA Observation Lifecycle

## Applies when

- Moving system/app observation out of SwiftUI views under `apps/macos/**`.
- Editing code that reacts to `NotificationCenter`, async streams, timers, menu tracking, app lifecycle, pasteboard change counts, or similar external signals.
- A view starts to accumulate `@State`, `.onReceive`, singleton calls, or observer tokens for non-visual behavior.

## Must

- Keep external observation ownership in TCA reducers, not in SwiftUI views.
- Introduce or extend feature `State` and `Action` when a view needs system-driven behavior.
- Model observation lifecycle explicitly with start/stop actions.
- Run long-lived observation in reducer effects using dependency clients and cancellation IDs.
- Keep views limited to rendering, UI-only local state, and sending lifecycle/user actions.
- Translate raw external events into semantic feature actions before mutating state or forwarding to child reducers.
- Add or update focused reducer tests for observation start, cancellation, and event routing.
- For migration-heavy refactors, load the `voyager-dev` orchestrator entry at `.agents/skills/voyager-dev/orchestrator/SKILL.md` and apply its reducer-owned observation playbook.

## Must not

- Use `NotificationCenter.default.publisher`, `.onReceive(...)`, observer tokens, or long-lived `Task` loops inside `Ui/*.swift` for external/system events.
- Add `@Dependency` to SwiftUI views for external observation.
- Store system observation lifecycle in view-local `@State` when the behavior affects feature state or child reducers.
- Start long-lived observation without cancellation handling.

## Execution steps

1. Detect whether the external signal is truly system-driven or just UI-local.
2. Keep system-driven observation in reducers and keep views as action senders only.
3. Verify the moved behavior with reducer-owned tests and search-based checks.

## Verification

- Confirm target views do not contain `NotificationCenter.default.publisher` or `.onReceive(` for the moved external signal.
- Confirm the owning reducer contains start/stop actions and uses `.cancellable(id: ..., cancelInFlight: true)` plus `.cancel(id: ...)`.
- Confirm touched Swift files have no LSP errors.
- Confirm focused reducer tests cover observation start, stop, and routed semantic actions.
