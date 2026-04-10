# Voyager Dev Scaffold Spec

## Input contract

- `layer`: `App | Pages | Widgets | Features | Entities | Shared`
- `slice`: `UpperCamelCase`
- `segments`: subset of `Api | Model | Reducer | Ui | Lib | Config`

## Layer defaults

- `App`: usually `Api | Config | Lib | Reducer | Ui`
- `Pages`: usually `Api | Lib | Model | Reducer | Ui`
- `Widgets`: usually `Lib | Model | Reducer | Ui`
- `Features`: usually `Api | Lib | Model | Reducer | Ui`
- `Entities`: usually `Api | Lib | Model | Reducer | Ui | Config`
- `Shared`: usually `Api | Config | Lib | Model`

Widget rule:

- Do not add `Widgets/Api` for ordinary UI sections.
- If a widget seems to need its own external client, re-check whether the logic belongs in `Features`, `Entities`, or should be injected from a parent layer.

## Layer-specific segment bans

- `01_App`: do not create app-only business helpers that really belong in `Pages`, `Features`, or `Entities`.
- `02_Pages`: do not turn page containers into domain logic buckets.
- `03_Widgets`: do not add ordinary `Api/`; do not own standalone navigation or storage.
- `04_Features`: do not depend on `Pages` or page containers.
- `05_Entities`: do not reference `Pages` or `Features` above them.
- `06_Shared`: do not depend on upper layers or slice-specific types.

## Slice boundary checklist

- Name the slice by business/domain meaning, not by technical role.
- Decide what the stable external surface of the slice is before adding internals.
- Avoid creating peer-slice dependencies on the same layer unless there is a deliberate, narrow exception.
- If peer slices need to cooperate, prefer composing them upward in `Pages` or `App`.

## Layer path mapping

- `App` -> `apps/macos/Voyager/Voyager/01_App`
- `Pages` -> `apps/macos/Voyager/Voyager/02_Pages/<Slice>`
- `Widgets` -> `apps/macos/Voyager/Voyager/03_Widgets/<Slice>`
- `Features` -> `apps/macos/Voyager/Voyager/04_Features/<Slice>`
- `Entities` -> `apps/macos/Voyager/Voyager/05_Entities/<Slice>`
- `Shared` -> `apps/macos/Voyager/Voyager/06_Shared`

## Minimum file set

1. `Model/<Slice>State.swift`
2. `Model/<Slice>Action.swift`
3. `Reducer/<Slice>Feature.swift`

## Required type shape

- `State`: `@ObservableState` + `Equatable`
- `Action`: `Sendable` (`@CasePathable` when split-model routing needs case paths)
- `Feature`: `@Reducer` + `typealias State/Action`

## Segment placement rules

- `Reducer/`: scope composition, orchestration, effect routing
- `Model/`: state/action/domain types
- `Ui/`: SwiftUI rendering and user input wiring
- `Api/`: dependency clients and boundary adapters
- `Lib/`: helpers, mappers, and coordinators; do not park primary external boundary ownership here when it belongs in `Api/`
- `Config/`: constants, design tokens, static config

## Module checklist

- Confirm the chosen layer is correct before creating files.
- Keep the slice name domain-oriented and stable.
- Add only the segments the module actually needs.
- For non-trivial slices, create `Model/<Slice>State.swift`, `Model/<Slice>Action.swift`, and `Reducer/<Slice>Feature.swift` together.
- Check whether orchestration belongs in the parent reducer before introducing new decomposition helpers.
- Check whether a new external boundary should become an `Api/*Client.swift` instead of leaking into `Ui/` or `Lib/`.
- Check whether the module should own a `Lib/*Coordinator.swift` instead of pushing SDK delegate/lifecycle orchestration into `Ui/`.
- Check whether the new client belongs in the nearest slice `Api/` or should live in `01_App/Api` / `06_Shared/Api`.
- Check whether the slice boundary would still make sense if later extracted into a package target; if that question matters, load `package-extraction-posture.md`.

## Required output

- `layer`
  - chosen layer plus one-line ownership rationale
- `slice-boundary`
  - stable external surface the slice should expose
- `segments`
  - selected segments plus intentionally omitted segments
- `file-plan`
  - files to create or modify, including the minimum `Model/*State`, `Model/*Action`, and `Reducer/*Feature` set when the slice is non-trivial
- `verification`
  - focused tests, search checks, and formatting/lint commands to run after the scaffold lands
