# Voyager Dev TCA Contract

## Structural rules

- Use `@Reducer` for feature reducers.
- Use `@Dependency` for external interactions.
- Prefer split model for non-trivial slices:
  - `Model/*State.swift`
  - `Model/*Action.swift`
  - `Reducer/*Feature.swift`
- Avoid decomposing TCA core types through `State+*`, `Action+*`, `Feature+*`, or `Reducer+*` files when that makes state movement and ownership harder to trace.
- When a feature grows too large, prefer separate model types, helper/coordinator types, or child reducers/features that are composed explicitly from the parent.

## View boundary rules

- Views send only `Action.view` or `@ViewAction` generated actions.
- Views must not emit `delegate` or internal action cases directly.
- Keep `view`, `delegate`, and internal/effect-result responsibilities distinct.
- Treat system events, callback routing, and async completions as reducer-owned internal flow.

## Side-effect rules

- Wrap async IO in reducer effects (e.g. `.run { send in ... }`).
- Route success/failure back through typed actions.
- Do not call network/filesystem/system SDK directly from SwiftUI views.
- Give long-lived work a feature-owned `CancelID` and cancel it explicitly from reducer lifecycle.
- Use `cancelInFlight` only when repeated user intent should replace the earlier in-flight work.
- Do not read nondeterministic globals such as `UUID()`, `Date()`, clocks, `Task.sleep`, or persistent stores directly when the value should be controlled in tests.
- In `.run` effects, capture immutable snapshots and dependencies explicitly; do not rely on mutable reducer state escaping into async work.

## Dependency client rules

- Introduce an `Api/*Client.swift` when the code touches system APIs, IO, process or network boundaries, global services, time/UUID/randomness, or any dependency that tests should fake.
- Keep pure calculations, filtering, sorting, formatting, and local presentation logic out of dependency clients.
- Put app-wide or shared environment clients in `01_App/Api` or `06_Shared/Api`; otherwise prefer the nearest owning slice `Api/`.
- Dependency surfaces used across concurrency boundaries should be designed so their usage remains `Sendable`-safe.

## Dependency direction stance

- Follow the structural dependency direction defined in `macos-architecture-shape.md`.
- Keep `tca-contract.md` focused on TCA ownership and execution mechanics that sit inside those boundaries.

## Cancellation ownership

- Keep cancellation ownership close to the reducer orchestrating the effect.
- Prefer `enum CancelID: Hashable, Sendable` inside the feature or reducer owner.
- Do not scatter cancellation IDs across helper extensions when a parent reducer owns the lifecycle.
