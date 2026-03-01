# Voyager Dev Orchestrator Spec

## Use when

- A feature file is too long and mixes unrelated concerns.
- Logic is scattered across many `Feature+*.swift` files and ownership/state flow is hard to trace.

## Parent/child decomposition contract

1. Keep parent feature as a single entry point.
2. Split concerns into child slices, e.g.:
   - `Navigation`
   - `Loading`
   - `Selection`
   - `Commands`
   - `SideEffects`
3. Implement child slices as thin reducer objects.
4. Inject child reducers into parent.
5. Compose with `.merge` in parent reducer body.

Parent/child is defined by reducer composition (`Scope`, `ifLet`, `forEach`), not by folder names.

## Action boundary

- UI adapters emit only the composing feature `Action.view` (or `@ViewAction`).
- `delegate` and internal actions are emitted from reducer logic, not UI adapters.
- A composing reducer must consume child `delegate` outputs and map them to concrete actions/effects (no orphan delegates).

## Cancellation policy

- Define and own cancellation IDs at parent level.
- Do not scatter cancellation ownership across child reducers.
