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
- Follow `.agents/rules/30-macos/02-tca-observation-lifecycle.md` when moving external/system observation out of SwiftUI views.
- Follow `.agents/rules/30-macos/03-voyager-app-workflow.md` for `apps/macos/Voyager/Voyager/**` work.
- For scaffold/orchestrator-style TCA work, load:
  - `.agents/skills/voyager-dev/SKILL.md`

## Must not

- Introduce reverse dependencies (e.g., `Entities` importing `Features/Pages`).
- Call network/filesystem/system SDK directly from SwiftUI views.
- Use global singletons when a dependency client can be injected.

## Execution steps

1. Confirm target layer and dependency direction.
2. Apply minimal code changes following nearby patterns.
3. For model split or large-feature decomposition, use `.agents/skills/voyager-dev/SKILL.md`.
4. Add or update focused reducer tests.

## Verification

- Run `xcodebuild test -scheme Voyager-Dev -project apps/macos/Voyager/Voyager.xcodeproj` when feasible for changed logic.
