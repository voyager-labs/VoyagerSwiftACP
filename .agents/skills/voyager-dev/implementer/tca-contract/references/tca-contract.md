# Voyager Dev TCA Contract

## Structural rules

- Use `@Reducer` for feature reducers and `@Dependency` for external interactions.
- Prefer split models for non-trivial slices: `Model/*State.swift`, `Model/*Action.swift`, `Reducer/*Feature.swift`. Small local reducers may keep inline types; file length alone must not force a split.
- Avoid `State+*`, `Action+*`, `Feature+*`, or `Reducer+*` decomposition when it hides state movement. Protocol conformances and focused same-owner helpers may use extensions; the concern's writer and lifetime must stay traceable.
- Split State, Action, transitions and effect lifecycle together. Several reducers with `State = ParentState` are implementation partitions of one aggregate, not independently owned children.
- Compose child reducers with `Scope`, `ifLet`, `forEach` and ReducerBuilder. `Effect.merge` combines independent effects and does not define reducer order or child domains.
- Use `.concatenate` or a single `.run` only when sequential effects are required. Do not assume `.merge` establishes an ordering contract.
- Run the real composed reducers in tests and override clients. Injecting mock reducer objects or creating Controller/Service pairs is not mandatory.
- Keep child Action cases direct. `delegate` is for semantic outward/upward outputs, not for hiding scoped child routes.

```swift
enum ParentAction {
    case view(View)
    case child(ChildFeature.Action)
    case delegate(Delegate)
}

Scope(state: \.child, action: \.child) {
    ChildFeature()
}
// The parent handles .child(.delegate(.didFinish)).
```

## State mutation and execution boundaries

- Each concern has one authoritative writer/transition boundary. A parent may own child initialization, removal or transfer, but must not duplicate the child's phase logic.
- Same-owner synchronous work belongs in a private method or pure policy, not a chain of setter/sync actions. User intents, cross-owner commands and async completions remain typed actions.
- Direct `reduce(into:action:)` calls are allowed only when the child is executed once and the returned effect is preserved/mapped with dependency and cancellation semantics intact. Never ignore the effect to reuse a calculation.
- Put fields with atomic invariants in the same small aggregate. Commit a new presentation and its reconciled selection together rather than repairing inconsistent intermediate states through extra actions.
- Distinguish canonical state, edit draft, committed baseline, candidate reload and immutable projection. Eliminate competing writable authority, not every legitimate snapshot.
- Immutable async inputs include the relevant owner/request identity and revision. Reject stale results at the receiving owner before initiating persistence.

## View boundary rules

- UI adapters include SwiftUI views, representables and coordinators. They emit semantic `Action.view` (or `@ViewAction`) for their store, not delegate/internal/effect-result actions.
- Do not call network/filesystem/persistence SDKs from views or merely move that work to a view-local dependency. The owning reducer initiates domain work through its client.
- In native coordinators with observable state, prefer `observe { ... }`. Do not add new `Store.publisher`/`ViewStore.publisher` state subscriptions. Existing paths migrate with behavior/performance tests, not a blind syntax swap.
- Native row maps, responder bookkeeping, programmatic-selection guards, bounds/frame observation and teardown tokens belong to the adapter when they are physical UI state.
- Native geometry observation may remain in the coordinator with explicit mount/unmount cleanup and late-callback tests. Do not introduce a dependency client and high-frequency reducer actions solely to wrap scroll notifications.
- Domain/system observation, background processing and external side effects remain reducer/client-owned. The Coordinator filename allowance in lint is not semantic proof of this boundary.
- Distinguish explicit user clear intent from empty lifecycle selection callbacks. Preserve ID-based selection after insertion, remount and tab switching.

## Side-effect rules

- Wrap async IO in effects and route typed success/failure back to the owner.
- Capture immutable inputs and dependency values; mutable reducer State must not escape into async work.
- Use cancellable effects for long-lived work. `cancelInFlight` is appropriate only when the new intent replaces the earlier work.
- Dependent stages of one user intent need a coherent cancellation boundary, including verification and persistence. A late completion must match current intent/session and legal phase before producing durable follow-up writes.
- Cancellation does not prove that an external mutation was undone. Model partial application, ambiguous execution, rollback or read-back recovery instead of retrying destructive work blindly.
- Lifecycle probes (`onAppear`, retry, re-diagnosis) must not overwrite an in-flight setting/restoring/saving phase or erase the error of an operation that has not been superseded.
- Use controlled clocks, UUID/date clients and injected external stores where tests need deterministic values. Do not read nondeterministic globals in reducer transitions.
- Classify network, configuration, authorization, decoding and server failures before applying a fallback policy; no catch-all synthetic success.
- Heavy CPU work must have an explicit execution/isolation plan. Merely putting synchronous work inside `.run` is not sufficient evidence that it leaves the main actor; measure the actual path.
- Selection-only and thumbnail-only changes should not rebuild/sort/diff unchanged content. Coalesce before expensive projection work and verify invocation counts rather than inventing speedup numbers.

## Dependency client rules

- Put clients around system/process/network/persistence/time/randomness boundaries that need replacement in tests, usually in the nearest owning `Api/`.
- Keep pure filtering, sorting, normalization and projection out of dependency clients.
- Use `01_App/Api` for genuinely app-global composition and `06_Shared/Api` only for layer-agnostic boundaries. DI does not legitimize an upward FSD dependency.
- Design concurrency-crossing values as Sendable-safe. Validate external payloads/URLs with real or captured fixtures, not mocks that only mirror Swift property names.
- Separate sensitive credential storage from non-sensitive snapshots/cache. Credentials use secure-storage clients.
- Multi-step external mutations read prior state from the write boundary, stop on uncertain reads, and expose partial failure/rollback. Never persist error/sentinel values as real state.

Client granularity, `live(...)` factory semantics, late dependency resolution and the manual `DependencyKey` convention are owned by `.agents/skills/voyager-dev/orchestrator/references/11-dependency-client-design.md`.

## Dependency direction stance

Follow `../../../reviewer/review/references/layer-and-segment-rules.md` and `../../../reviewer/review/references/public-boundary-spec.md`. A TCA feature may remain page-local. Do not create a package per reducer or promote one-slice contracts into Shared just to avoid a peer import.

## Cancellation ownership

- Keep CancelID near the reducer that launches and settles the effect. Prefer a typed `Hashable, Sendable` ID with real owner identity where needed.
- The parent owns aggregate lifetime, not every child CancelID. Document cancellation/transfer when a tab/window/session is removed.
- Visibility, State existence and effect lifetime are separate. Hidden retained tabs/background chat may keep State and work; optional presentation State is for actual presentation lifetime, not a blanket optimization.
- Do not scatter cancellation logic through helper extensions or duplicate it in AppKit and reducer owners.

## Verification boundary

AST/lint rules verify only declared syntax. Use compiler/access-control checks for type boundaries, TestStore for transitions and stale/cancel behavior, and native tests for physical mount/selection/teardown. A passing syntactic rule or a filled owner table is not proof of global single-writer correctness.
