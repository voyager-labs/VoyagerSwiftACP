# VOY-320 EntryThumbnail Public-Surface Inventory

**Date:** 2026-05-10
**Branch:** `refactor/voy-320`
**Objective:** Inventory all source files, symbols, cross-boundary deps, and consumers before package extraction.

---

## Source File Inventory

| #   | File                                         | Segment | Symbols (decl)                                                                                                                                             | Access                                  | Cross-boundary Imports                                                                    | Consumers (external)                                                                                                                           | Access Decision                                                                             |
| --- | -------------------------------------------- | ------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------- | ----------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------- |
| 1   | `Model/EntryThumbnailAction.swift`           | Model   | `EntryThumbnailAction` (enum: CasePathable, Sendable) with cases: `requestThumbnails(paths:)`, `thumbnailsReady(paths:)`, `thumbnailRequestFailed(paths:)` | internal (no access keyword = internal) | `ComposableArchitecture`, `Foundation`                                                    | Only used within EntryThumbnail package (typealias in Feature + RequestReducer)                                                                | **public** — TCA requires Action visible when Feature is a child reducer composed by parent |
| 2   | `Model/EntryThumbnailState.swift`            | Model   | `EntryThumbnailState` (struct: Equatable, Sendable) with properties: `requestsInFlight`, `readyPaths`, `failedPaths`, `renderVersion`                      | internal                                | `Foundation`                                                                              | Only used within EntryThumbnail package (typealias in Feature + RequestReducer)                                                                | **public** — TCA requires State visible when Feature is a child reducer composed by parent  |
| 3   | `Reducer/EntryThumbnailFeature.swift`        | Reducer | `EntryThumbnailFeature` (@Reducer struct) with `body` composing `EntryThumbnailRequestReducer`                                                             | internal                                | `ComposableArchitecture`                                                                  | **3 consumers:** EntryViewLayoutAction (line 15), EntryViewLayoutState (line 29), EntryViewLayoutFeature (line 46), EntryThumbnailFeatureTests | **public** — primary entry point, composed by EntryViewLayout                               |
| 4   | `Reducer/EntryThumbnailRequestReducer.swift` | Reducer | `EntryThumbnailRequestReducer` (@Reducer struct) with `body` Reduce, private helpers `dedupe()`, `requestThumbnailsEffect()`, `makeThumbnailTask()`        | internal                                | `AppKit`, `ComposableArchitecture`, `Foundation`, `VoyagerEntitiesEntry`, `VoyagerShared` | Only referenced inside `EntryThumbnailFeature.body`                                                                                            | **internal** — only consumed by sibling Feature reducer                                     |

---

## Dependency Clients Used

| Client Name                 | Registered In                                              | Dependency KeyPath            | Used By                        |
| --------------------------- | ---------------------------------------------------------- | ----------------------------- | ------------------------------ |
| `thumbnailGeneratorClient`  | `VoyagerShared/Api/ThumbnailGeneratorClient.swift`         | `\.thumbnailGeneratorClient`  | `EntryThumbnailRequestReducer` |
| `entryThumbnailCacheClient` | `VoyagerEntitiesEntry/Api/EntryThumbnailCacheClient.swift` | `\.entryThumbnailCacheClient` | `EntryThumbnailRequestReducer` |

### External consumers of these same clients (NOT part of this package):

- `EntryGridCoordinator` (03_Widgets) — uses `entryThumbnailCacheClient`
- `EntryListCoordinator` (03_Widgets) — uses `entryThumbnailCacheClient`
- `EntryGridCoordinator+Extensions` (03_Widgets) — uses `entryThumbnailCacheClient`
- `EntryOperationsLifecycleReducer` (VoyagerFeaturesEntryOperations package) — uses `entryThumbnailCacheClient`
- Multiple test files

---

## Consumer Map (Who imports EntryThumbnail types)

| Consumer File                      | Location                                | What They Use                                                    |
| ---------------------------------- | --------------------------------------- | ---------------------------------------------------------------- |
| `EntryViewLayoutAction.swift`      | `03_Widgets/EntryViewLayout/Model/`     | `EntryThumbnailFeature.Action` (case path)                       |
| `EntryViewLayoutState.swift`       | `03_Widgets/EntryViewLayout/Model/`     | `EntryThumbnailFeature.State` (child state)                      |
| `EntryViewLayoutFeature.swift`     | `03_Widgets/EntryViewLayout/Reducer/`   | `EntryThumbnailFeature()` (child reducer Scope)                  |
| `EntryThumbnailFeatureTests.swift` | `VoyagerTests/Features/EntryThumbnail/` | `@testable import Voyager`, `EntryThumbnailFeature`, dep clients |

### EntryViewLayout Import Pattern

EntryViewLayout is in `03_Widgets` layer (same app target). It uses `EntryThumbnailFeature` via direct symbol access — no `import` needed because both are in the same Voyager app target. After package extraction, EntryViewLayout will need `import VoyagerFeaturesEntryThumbnail`.

---

## Access-Control Decisions Summary

| Symbol                         | Current                                   | Target       | Rationale                                                          |
| ------------------------------ | ----------------------------------------- | ------------ | ------------------------------------------------------------------ |
| `EntryThumbnailFeature`        | internal                                  | **public**   | Primary reducer; composed as child by EntryViewLayout              |
| `EntryThumbnailFeature.State`  | (via typealias to `EntryThumbnailState`)  | **public**   | Must be visible for parent Scope                                   |
| `EntryThumbnailFeature.Action` | (via typealias to `EntryThumbnailAction`) | **public**   | Must be visible for parent case path                               |
| `EntryThumbnailState`          | internal                                  | **public**   | Required by typealias chain; parent needs direct access            |
| `EntryThumbnailAction`         | internal                                  | **public**   | Required by typealias chain; parent needs case-path access         |
| `EntryThumbnailRequestReducer` | internal                                  | **internal** | Only used inside EntryThumbnailFeature.body; no external consumers |

---

## Package Dependencies (imports required by extracted package)

| Dependency             | Module        | Used By                                      | Type      |
| ---------------------- | ------------- | -------------------------------------------- | --------- |
| ComposableArchitecture | TCA           | Feature, RequestReducer, Action              | Framework |
| Foundation             | stdlib        | Action, State, RequestReducer                | SDK       |
| AppKit                 | stdlib        | RequestReducer (NSScreen, NSImage)           | SDK       |
| VoyagerEntitiesEntry   | Local package | RequestReducer (`entryThumbnailCacheClient`) | Package   |
| VoyagerShared          | Local package | RequestReducer (`thumbnailGeneratorClient`)  | Package   |

---

## Key Findings

1. **No Ui/ segment files** — EntryThumbnail has no views; it's a pure reducer package.
2. **No Api/ segment files** — Dependency clients live in `VoyagerEntitiesEntry` and `VoyagerShared`; this package consumes them, doesn't define them.
3. **Single consumer widget** — EntryViewLayout (03_Widgets) is the sole non-test consumer, using Feature as a child reducer via TCA Scope.
4. **Test file uses `@testable import Voyager`** — will need updating to `@testable import VoyagerFeaturesEntryThumbnail` or similar after extraction.
5. **All types are currently internal** (no explicit `public` keyword) — they live in the same app target, so internal is sufficient now but must change on extraction.
6. **EntryThumbnailRequestReducer can stay internal** — only consumed by EntryThumbnailFeature within the same module.
