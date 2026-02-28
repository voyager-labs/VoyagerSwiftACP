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
3. Action boundary gate
   - View emits only `Action.view` or `@ViewAction` actions.
   - `delegate`/internal actions originate from reducer logic.
4. Reducer ownership gate
   - Non-trivial slices keep `State`/`Action` in `Model/`.
   - `Reducer/*Feature.swift` is orchestration-only.

## Violation handling

- If any gate fails, do not proceed with implementation.
- Move candidate to `adapter` or `reject`, then pick next candidate.
- Record the failed gate and path in the decision output.

## Required output

- `architecture_passed: true|false`
- `failed_gates: []`
- `required_adapters: []`
