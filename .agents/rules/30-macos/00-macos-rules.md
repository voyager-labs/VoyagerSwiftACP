---
globs: apps/macos/**/*.swift
description: "macOS SwiftUI + TCA structure and dependency rules."
---

# macOS Rules

## Applies when

- Editing Swift code under `apps/macos/**`.

## Must

- Follow FSD dependency direction:
    - `App -> Pages -> (Widgets|Features|Entities|Shared)`
    - `Widgets -> (Features|Entities|Shared)`
    - `Features -> (Entities|Shared)`
    - `Entities -> Shared`
- Keep TCA dependencies injected (`@Dependency`) and testable.
- Keep reducers focused (`@Reducer`, effect routing in reducer, no side effects in views).
- Keep each cross-layer concern owned by one canonical type or module.
- Keep user-facing messages and presentation copy in feature/model-owned state, not low-level API/status clients.
- Keep shared visual metadata such as icons or labels behind a single helper or registry.
- Route cross-feature or window-level commands through actions, delegate events, or dedicated handlers.
- Follow `.agents/rules/30-macos/02-tca-observation-lifecycle.md` when moving external/system observation out of SwiftUI views.
- Follow `.agents/rules/30-macos/03-voyager-app-workflow.md` for `apps/macos/Voyager/Voyager/**` work.
- For scaffold/orchestrator-style TCA work, load:
    - `.agents/skills/voyager-dev/SKILL.md`

## Must not

- Introduce reverse dependencies (e.g., `Entities` importing `Features/Pages`).
- Call network/filesystem/system SDK directly from SwiftUI views.
- Use global singletons when a dependency client can be injected.
- Maintain parallel canonical types or aliases for the same concept across layers.
- Put presentation copy or UI-facing policy in API clients or raw status wrappers.
- Duplicate shared icon/label mapping logic across views or reducers when a common helper can own it.
- Bypass reducer or action boundaries with direct cross-feature state mutation.

## Execution steps

1. Identify the owning layer before editing state, copy, shared visual metadata, or command routing.
2. Reuse existing dependency clients, reducers, and shared helpers instead of introducing parallel abstractions.
3. Keep views focused on rendering and action sending; move ownership and orchestration decisions into reducers or model-owned helpers.
4. Apply the path-specific Voyager workflow when the change is inside `apps/macos/Voyager/Voyager/**`.

## Verification

- Confirm the changed code still follows FSD dependency direction and does not add reverse imports.
- Confirm system or service access remains behind dependencies/reducers rather than SwiftUI views.
- Confirm each touched concept has one canonical owner after the change.
- Confirm cross-feature or window-level commands are routed through actions, delegate events, or dedicated handlers.
- Confirm this rule file does not contain issue-specific type names, file-path ownership maps, or temporary migration directives.
