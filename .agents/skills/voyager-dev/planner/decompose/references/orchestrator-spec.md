# Voyager Dev Orchestrator Spec

## Use when

- A feature mixes independent concerns or its state movement is difficult to trace.
- Logic is scattered across `Feature+*.swift` files with competing writers.
- A task changes State, Action, effect lifetime, or a parent/child boundary.

## Parent/child decomposition contract

1. Keep one feature entry point and compose concrete child reducers with `Scope`, `ifLet`, `forEach`, or ReducerBuilder. Reducer composition and `Effect.merge` are different operations; `.merge` combines effects, not child State/Action domains.
2. Split a concern's State, Action, transition rules, effect lifecycle and tests together. A reducer that aliases the whole parent State is an implementation partition, not an isolated child.
3. A composition feature owns child placement and lifetime. A workflow/controller owns a coherent user intent and its coordination state. A capability reducer owns a smaller independent state machine. Pure policies/projections are functions, and external IO belongs behind clients.
4. These are roles, not mandatory layers or type pairs. A small reducer may own workflow and capability. Do not create Controller/Service pairs, protocol wrappers, or dependency keys for pure calculations.
5. Prefer concrete reducer composition. Tests normally run the real reducers with dependency-client overrides; injecting reducers themselves is not a default requirement.
6. Retain tightly coupled phases under one aggregate owner when splitting would duplicate generation, proposal, rollback, or recovery authority.

Parent/child is defined by reducer composition, not folder names. TCA child features may remain internal to an FSD Page; do not extract a new SwiftPM package solely because a new reducer exists. Check the FSD dependency direction before moving a composition downward.

## Action boundary

- UI adapters emit only their feature's semantic `Action.view` (or `@ViewAction`). They do not manufacture effect completions or delegate outcomes.
- Keep child action cases direct: `case listing(ListingAction)`, not hidden under the parent's `delegate` case.
- A composing reducer consumes semantic child outputs and maps them to concrete actions/effects; no orphan delegates.
- Reuse same-owner synchronous work through private methods or pure functions, not chains of setter/sync actions.
- A small parent-domain routing reducer may connect child outcomes. It must not become a second writer of the children's state machines.
- Direct `reduce(into:action:)` calls require one execution, preserved/mapped effects, and preserved dependency/cancellation semantics. Never discard a returned effect to obtain a calculation result; extract the pure calculation instead.

## Cancellation and lifetime policy

- The reducer launching, accepting completions, and cancelling an operation normally owns its CancelID. Do not move every CancelID to the parent merely because it is a parent.
- The parent owns aggregate removal/transfer and process/window lifetime when that is the real boundary. Document how child work stops or is deliberately transferred.
- Partition shared cancellation identifiers by the actual window/tab/session owner where required; unrelated owners must not cancel each other.
- Keep dependent stages of one intent under a coherent lifetime. Validate request identity and current phase before accepting late results or starting durable follow-up writes.
- Cancellation of a UI task is not evidence that an external mutation was rolled back. Model ambiguous execution and read-back recovery explicitly.
- Visibility, retained State, and effect lifetime are separate decisions. Do not destroy background operations just because their view is hidden.

## Pre-split owner audit

The existing implementation plan owns this audit; do not create another durable manifest per reducer. A small local edit that does not alter ownership need not produce a large table.

### Owner taxonomy

| Sub-role | Responsibility |
| --- | --- |
| State owner | Authoritative state and transition methods; no competing cross-concern writer. |
| Effect owner | Launch, success/failure acceptance, recovery and completion. |
| Cancellation owner | Cancel/replace semantics and operation identity. |
| Child-routing owner | Action case path and semantic output handling. |
| Test owner | TestStore/fixture contract for this behavior. |

For each extracted concern, record its concrete State and Action, allowed write set, inputs/outcomes, legal transitions, result-acceptance fence, dependency clients, and the existing writer/routes that will be removed. Use `none` when a sub-role does not apply.

### Audit sequence

1. List cohesive concerns and the actual read/write sites, including helpers and extensions.
2. Name the current and proposed owners; distinguish draft, committed state, reload candidate and derived snapshot rather than calling every copy redundant.
3. Verify that a child receives its own state domain. A controller that keeps editing the child's phase/proposal/selection after extraction is a shadow owner.
4. Place fields that must change atomically in the same small aggregate and commit them together. Do not use a multi-action repair loop to restore transiently broken invariants.
5. Identify exclusive external dependencies, lifetime boundaries, public API changes, downstream consumers and required tests.
6. State what the atomic change removes. Finish wiring, tests and obsolete path removal together; a wrapper-only intermediate state is not completion.

### Output format

```text
Concern | State/Action | Write set | State/effect/cancel owners | Inputs/outcomes
        | Legal transitions + acceptance fence | Dependencies | Removed writers/routes | Tests
```

Name actual symbols, not generic labels such as "service". A new metadata file does not prove that the code follows this table.

### Failure conditions

Do not split when the proposed child is compatibility-only, has no independent boundary, leaves shadow writers in its parent, or adds coordination costs greater than the ownership benefit. Keep that concern under its existing aggregate owner and record the reason. File/line thresholds are review signals, not reasons to spread one state machine across files or to wrap it in a new client.

## Verification and implementation handoff

- Give implementers exact writable paths/types, fixed public contracts, preserved invariants, explicit non-goals and test commands. Do not require another architecture discovery pass for a fully specified small task.
- Parallel implementation tasks must not structurally edit the same State/Action or Swift compile unit concurrently; file-disjoint is not sufficient.
- Use AST checks for their declared syntactic scope, compile checks for access/type correctness and TestStore/native tests for lifetime and state invariants. None alone proves global single-writer semantics.
- Review stale completion, cancellation, retained tabs, reload failure and native selection provenance for affected flows. Preserve negative-path tests when simplifying.

## Neighbor references

- Composition mechanics: `../../../implementer/tca-contract/references/tca-contract.md`
- State lifetime and projections: `../../../implementer/tca-contract/references/state-modeling.md`
- One canonical owner per concern: `../../../implementer/tca-contract/references/development-rules.md`
- Test setup and evidence: `../../../implementer/spec-test-authoring/references/testing-playbook.md`
