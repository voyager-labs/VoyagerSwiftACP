# Voyager Dev Architecture Gate Spec

## Purpose

Block implementation choices that violate clean architecture or FSD dependency direction.

## Mandatory gates

1. Layer direction gate
   - Must satisfy:
     - `App -> Pages -> (Widgets|Features|Entities|Shared)`
     - `Widgets -> (Features|Entities|Shared)`
     - `Features -> (Entities|Shared)`
     - `Entities -> Shared`
2. Boundary gate
    - Views must not call network/filesystem/system SDK directly.
    - External calls must go through dependency clients.
3. Slice boundary gate
   - Same-layer cross-slice references must be treated as a violation unless there is explicit architectural justification.
   - Do not depend on another slice's internal helpers or decomposition files when a stable boundary should exist.
4. Action boundary gate
    - View emits only `Action.view` or `@ViewAction` actions.
    - `delegate`/internal actions originate from reducer logic.
5. Reducer ownership gate
    - Non-trivial slices keep `State`/`Action` in `Model/`.
    - `Reducer/*Feature.swift` is orchestration-only.
    - New architecture split must not re-fragment `State`/`Action`/`Feature`/`Reducer` via `+*` extension files such as `State+Presentation.swift`; prefer dedicated mapper/projection/helper types.
6. Complexity inflation gate
   - Do not add new models, objects, wrappers, or reducers if an existing type can absorb the change with clearer ownership and lower overall complexity.
   - New wrapper layers created only for compatibility or guardrail reasons must prove they own real translation, migration, or protective behavior.
   - If a new type does not create a clearly new scope, treat it as a design smell and prefer extending or reshaping the existing type.
7. Layer vocabulary gate
   - Prefer standard Voyager/FSD segments (`Ui`, `Api`, `Model`, `Reducer`, `Lib`, `Config`).
   - Avoid introducing generic architecture buckets such as `Components`, `Types`, `Hooks`, or `Utils` as default segment names.

## Violation handling

- If any gate fails, do not proceed with implementation.
- Move candidate to `adapter` or `reject`, then pick next candidate.
- Record the failed gate and path in the decision output.

## Required output

- `architecture_passed: true|false`
- `failed_gates: []`
- `required_adapters: []`
