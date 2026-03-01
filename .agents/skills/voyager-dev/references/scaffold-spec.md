# Voyager Dev Scaffold Spec

## Input contract

- `layer`: `App | Pages | Widgets | Features | Entities | Shared`
- `slice`: `UpperCamelCase`
- `segments`: subset of `Api | Model | Reducer | Ui | Lib | Config`

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
- `Lib/`: pure helper logic (no IO)
- `Config/`: constants, design tokens, static config
