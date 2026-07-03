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
- When composing an owned child reducer with `Scope(state:action:)`, keep the corresponding parent action case as a direct child-action case rather than nesting it under `delegate`.
- Reserve `delegate` for semantic outward/upward events leaving the feature boundary. If a scoped child needs to notify its parent, prefer `child(.delegate(...))` over moving scoped child routing into the parent's `delegate` namespace.

Preferred parent boundary shape:

```swift
enum ParentAction {
    case view(View)
    case delegate(Delegate)
    case child(ChildFeature.Action)
}

Scope(state: \.child, action: \.child) {
    ChildFeature()
}

// Parent consumes semantic child output here:
// case .child(.delegate(.didFinish))
```

Avoid collapsing owned child routing into the parent's delegate namespace:

```swift
enum ParentAction {
    case view(View)
    case delegate(Delegate)

    enum Delegate {
        case child(ChildFeature.Action)
        case didFinish
    }
}
```

## View boundary rules

- "UI adapters" include SwiftUI views, representables, and coordinators.
- UI adapters emit only `Action.view` (or `@ViewAction`) for the feature store they are initialized with.
- UI adapters must not construct or send `delegate` / internal actions directly.
- Keep `view`, `delegate`, and internal/effect-result responsibilities distinct.
- Treat system events, callback routing, and async completions as reducer-owned internal flow.
- In UIKit/AppKit coordinators with observable state, use `observe { ... }` for state-driven UI updates.
- Do not add new `Store.publisher`/`ViewStore.publisher`-based state subscriptions in coordinators.
- For external UI events (scroll/notification/delegate), prefer notification tokens + delegate callbacks + imperative schedulers (throttle/debounce), not Combine pipelines.

## Side-effect rules

- Wrap async IO in reducer effects (e.g. `.run { send in ... }`).
- Route success/failure back through typed actions.
- Prefer emitting follow-up actions with `.send(...)` over directly invoking downstream handlers when an effect result should remain observable in tests and logs.
- Do not call network/filesystem/system SDK directly from SwiftUI views.
- Give long-lived work a feature-owned `CancelID` and cancel it explicitly from reducer lifecycle.
- Use `cancelInFlight` only when repeated user intent should replace the earlier in-flight work.
- Keep every step of a multi-stage async user intent under one cancellation boundary when later steps depend on earlier steps (for example acquire input → verify → persist durable state).
- Before emitting durable state or persistence effects from an async completion, verify the completion still matches the current user intent/session and was not cancelled or superseded.
- Protect mutation phases from lifecycle probes: `onAppear`, manual retry, and follow-up diagnostics must not overwrite an in-flight setting/restoring/saving phase unless the reducer explicitly models that transition.
- Preserve failure ownership through follow-up effects: automatic re-diagnosis may update health/status, but it must not clear a user-visible error unless the source and phase prove the original failed operation has been superseded.
- Do not read nondeterministic globals such as `UUID()`, `Date()`, clocks, `Task.sleep`, or persistent stores directly when the value should be controlled in tests.
- In `.run` effects, capture immutable snapshots and dependencies explicitly; do not rely on mutable reducer state escaping into async work.
- Treat fallback behavior as a typed policy decision, not a catch-all error branch; distinguish network, configuration, authorization, decoding, and server failures before using cached or synthetic state.

## Dependency client rules

- Introduce an `Api/*Client.swift` when the code touches system APIs, IO, process or network boundaries, global services, time/UUID/randomness, or any dependency that tests should fake.
- Keep pure calculations, filtering, sorting, formatting, and local presentation logic out of dependency clients.
- Put app-wide or shared environment clients in `01_App/Api` or `06_Shared/Api`; otherwise prefer the nearest owning slice `Api/`.
- Dependency surfaces used across concurrency boundaries should be designed so their usage remains `Sendable`-safe.
- Verify externally owned payloads, URLs, and config contracts with real or captured fixtures instead of relying only on mocks that mirror Swift property names.
- Separate sensitive credential storage from non-sensitive snapshot/cache persistence; credentials must flow through secure storage clients, while status snapshots may use ordinary persistence clients.
- For clients that mutate external system state in multiple steps, model partial failure deliberately: read the prior state from the write boundary, stop on uncertain reads, rollback earlier steps when a later step fails, and never persist sentinel/error placeholder values as real state.

## Dependency direction stance

- Follow the structural dependency direction defined in `../../../reviewer/boundary/references/layer-and-segment-rules.md`.
- Keep `tca-contract.md` focused on TCA ownership and execution mechanics that sit inside those boundaries.

## Cancellation ownership

- Keep cancellation ownership close to the reducer orchestrating the effect.
- Prefer `enum CancelID: Hashable, Sendable` inside the feature or reducer owner.
- Do not scatter cancellation IDs across helper extensions when a parent reducer owns the lifecycle.
- Choose `CancelID` granularity by concern/user intent, not by individual implementation step, so cancellation aborts the whole flow including post-verification persistence.
