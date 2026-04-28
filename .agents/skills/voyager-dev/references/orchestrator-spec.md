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

## Pre-split owner audit

Run this audit before any `decompose` task that introduces child reducers, seam reducers, or scoped features. The audit determines whether a split is warranted and, if so, which concern maps to which owner sub-role.

### Owner taxonomy

Every concern in a reducer is owned by up to five sub-roles. A single concern may have different sub-owners for different sub-roles, but no sub-role may be shared across concerns.

| Sub-role                | Responsibility                                                                          |
| ----------------------- | --------------------------------------------------------------------------------------- |
| **State owner**         | Holds the authoritative state fields for the concern. All writes go through this owner. |
| **Effect owner**        | Owns the effect lifecycle: launch, completion, and error handling for the concern.      |
| **Cancellation owner**  | Owns the `CancelID` and cancel/replace logic for the concern's in-flight effects.       |
| **Child-routing owner** | Owns the action case path that maps the concern's output into the parent reducer flow.  |
| **Test owner**          | Owns the `TestStore` setup and assert chain that verifies the concern's behavior.       |

When a concern has no effect lifecycle, the effect-owner and cancellation-owner columns are "none" and the state owner may also serve as the child-routing owner.

### Audit sequence

Perform these steps in order. Stop and fold back if any step fails (see Failure conditions below).

1. **List concerns.** Enumerate every distinct concern in the target reducer. A concern is a cohesive cluster of state fields, effects, and action handling that would remain meaningful if extracted.
2. **Identify sub-role owners.** For each concern, determine which reducer, type, or helper currently fills each sub-role. Record the result in the owner table (see Output format below).
3. **Verify single-writer per state field.** Confirm that no two sub-owners hold write access to the same state field. If a field is written by more than one concern, the concerns are not cleanly separable.
4. **Identify exclusive dependencies.** For each concern, list the dependency clients used exclusively by that concern. A dependency used by only one concern is a strong signal that the concern owns its own boundary. Dependencies shared across concerns are parent-level wiring.
5. **Flag ambiguous ownership.** If any concern has no clear single owner for a sub-role, or if ownership would require the parent to continue writing to nominally child-owned state, mark it as ambiguous. Ambiguous concerns must not be extracted.

### Output format

Produce an owner table before extracting any child reducer. This table is the required `decompose` deliverable.

```
| Concern | State owner    | Effect owner | Cancellation owner | Child-routing owner | Test owner | Dependencies (exclusive) |
|---------|----------------|--------------|--------------|---------------|------------|--------------------------|
| …       | …              | …            | …            | …             | …          | …                        |
```

Each cell names the concrete reducer, helper, or type that fills the sub-role, or "none" if the sub-role is not applicable. The "Dependencies" column lists dependency clients used exclusively by that concern.

### Failure conditions

If any of the following conditions hold, do **not** split. Fold the concern back into the existing monolithic reducer and document the reason.

- **Compatibility-only split.** The proposed child wraps existing behavior without owning new boundaries, new state, or meaningful complexity reduction. (See `development-rules.md` "one canonical owner per concern" principle.)
- **Shadow-owner split.** State is nominally in a child reducer but the parent still writes to it directly. If the parent cannot delegate all writes through the child's action path, the split creates a shadow owner.
- **No clear ownership.** Multiple sub-owners write the same state field and cannot be separated without introducing coupling that exceeds the benefit of the split.

When a failure condition is met: retain the monolithic reducer, record the concern in the owner table with a "folded" annotation, and note the specific failure condition in the `decompose` deliverable.

### Neighbor references

This section defines **who** owns what and **when** to split. For the mechanics listed below, consult the canonical neighbor directly.

- Composition mechanics (how to wire child reducers, `Scope`, `.merge` ordering): `tca-contract.md`
- One-owner-per-concern principle and reuse-before-new heuristics: `development-rules.md`
- Test setup patterns (exhaustivity, dependency overrides, test scope alignment): `testing-playbook.md`
