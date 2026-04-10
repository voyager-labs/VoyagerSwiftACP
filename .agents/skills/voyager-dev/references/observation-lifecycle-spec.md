# Voyager Dev Observation Lifecycle Spec

## Use when

- A `Ui/*.swift` file uses `.onReceive(...)`, `NotificationCenter.default.publisher`, observer tokens, or a long-lived `Task` for non-visual behavior.
- A SwiftUI view introduces `@Dependency` to watch system or app events.
- A feature needs `State`, `Action`, and reducer-owned effects so external observation lifecycle moves out of the view layer.

## Goal

- Keep views as lifecycle/action senders only.
- Keep external/system observation in reducer effects with explicit cancellation ownership.
- Preserve behavior while making observation testable and reusable.

## Workflow

1. Classify the signal.
   - Keep UI-only signals in the view, such as geometry changes or purely visual local state.
   - Move system-driven signals into TCA, such as app activation, menu tracking, timers, pasteboard changes, and async streams.
   - Borderline rule: if the event originates outside the view tree or must survive view re-rendering, treat it as reducer-owned.
   - Borderline rule: if the value only affects local presentation and does not observe the outside world, it can stay in the view.
2. Identify the owner.
   - Find the owning feature reducer.
   - Add or extend `Model/*State.swift` and `Model/*Action.swift` if the feature lacks lifecycle control.
3. Add lifecycle actions.
   - Add `startObserving...` and `stopObserving...` actions.
   - Add a semantic internal action for the routed event, such as `systemAppDidBecomeActive`.
4. Move observation into the reducer.
   - Use an injected dependency client.
   - Start the effect with `.run`.
   - Add `.cancellable(id: ..., cancelInFlight: true)`.
   - Stop it with `.cancel(id: ...)`.
5. Simplify the view.
   - Remove direct external observation.
   - Keep only lifecycle triggers such as `.onAppear { store.send(...) }` and `.onDisappear { store.send(...) }`.
6. Add focused tests.
   - Cover start/cancel lifecycle.
   - Cover routing from the raw signal to the semantic action.
   - Cover state changes or forwarded child actions caused by the semantic action.

## Hard checks

- Do not leave `NotificationCenter.default.publisher` or `.onReceive(...)` in the target `Ui/*.swift` file for the moved signal.
- Do not add `@Dependency` to SwiftUI views for external/system observation.
- Do not start long-lived reducer observation without cancellation.
- Do not move UI-only local interaction into reducers just for symmetry.

## Borderline examples

- Keep in the view: geometry width changes, temporary hover state, focus ring visuals, one-off local animations.
- Move into TCA: `NotificationCenter` app lifecycle events, menu tracking end, timer-driven refresh, pasteboard/watcher streams, workspace notifications.

## Repo examples

- `apps/macos/Voyager/Voyager/02_Pages/FileManager/Content/Ui/ContentPageView.swift`
- `apps/macos/Voyager/Voyager/02_Pages/FileManager/Sidebar/Ui/SidebarView.swift`
- `apps/macos/Voyager/Voyager/02_Pages/FileManager/Content/Reducer/FileManagerContentFeature.swift`
- `apps/macos/Voyager/Voyager/02_Pages/FileManager/Sidebar/Reducer/FileManagerSidebarFeature.swift`
