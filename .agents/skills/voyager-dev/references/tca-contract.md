# Voyager Dev TCA Contract

## Structural rules

- Use `@Reducer` for feature reducers.
- Use `@Dependency` for external interactions.
- Prefer split model for non-trivial slices:
  - `Model/*State.swift`
  - `Model/*Action.swift`
  - `Reducer/*Feature.swift`

## View boundary rules

- Views send only `Action.view` or `@ViewAction` generated actions.
- Views must not emit `delegate` or internal action cases directly.

## Side-effect rules

- Wrap async IO in reducer effects (e.g. `.run { send in ... }`).
- Route success/failure back through typed actions.
- Do not call network/filesystem/system SDK directly from SwiftUI views.

## Dependency direction rules (FSD)

- `App -> Pages -> (Widgets|Features|Entities|Shared)`
- `Widgets -> (Features|Entities|Shared)`
- `Features -> (Entities|Shared)`
- `Entities -> Shared`
- Reverse dependency is forbidden.
