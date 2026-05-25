# TCA Test Authoring Notes

## TestStore state assertions

- Choose initial state so the expected mutation is observable. If initial state already equals the expected result, `TestStore` can report that no state change occurred.
- Do not provide a mutation closure to `send` or `receive` when the action intentionally leaves state unchanged.
- When a field is derived by reducer methods, drive the action that calls the method instead of assuming memberwise initialization updates derived values.

## Effects and dependencies

- Override nondeterministic dependencies: time, UUID, clocks, storage, network, file system, notifications, workspace, and external services.
- Use recorders or dependency doubles for effect calls that need deterministic proof.
- Prefer actor or `LockIsolated`-style recorders over unstructured `Task { ... }` capture patterns.
- Swift 6 `@Sendable` closures cannot safely capture mutable local vars; use a sendable recorder/wrapper instead.

## Exhaustivity

- Use exhaustive `TestStore` assertions for leaf reducers and local state transitions.
- Use `store.exhaustivity = .off` only for broad integration flows where asserting every internal action creates noise. Add a short rationale.
- Use `store.finish()` or an equivalent completion check when long-lived effects could remain active.

### `store.exhaustivity = .off` rationale requirement

Every `store.exhaustivity = .off` MUST have an adjacent Korean rationale comment explaining why exhaustive assertions are not practical for this test.

**Required comment format:**

```swift
// store.exhaustivity = .off: {reason in Korean}
store.exhaustivity = .off
```

### Classification decision tree

For each `store.exhaustivity = .off`, classify as one of:

1. **Remove**: The test can use exhaustive assertions. No rationale needed.
2. **Keep with rationale**: Exhaustivity is genuinely needed, with documented reason.
3. **Defer with reason**: Unclear, but document the uncertainty to revisit later.

### Safe to remove when

- Single-field synchronous state change
- No-op action with no state mutation
- Fully tracked state changes with no hidden effects
- All effects are fully consumed via `receive` and produce only tracked state mutations

### Must keep when

- Multi-field load effects that update several unrelated state properties
- Fire-and-forget effects where the test does not assert intermediate actions
- Partial state verification where only specific fields matter for the scenario
- Integration breadth tests covering reducer composition across multiple features

### Audit process

1. Read the reducer first to understand effect behavior (sync vs. async, single vs. multi-field).
2. Classify each `store.exhaustivity = .off` usage.
3. Remove the ones that are safe to remove.
4. Add rationale comments to the ones that must stay.

### Audit command

After authoring or reviewing, find all exhaustivity overrides without rationale:

```bash
grep -n 'store.exhaustivity = .off' <SuiteFile>.swift
```

For each match, verify the line above or the same line contains a Korean rationale comment. If not, classify and fix.

### Evidence

Task 4 of VOY-356 audited 36 `store.exhaustivity = .off` usages across GeneralSettingsFeature and AppearanceSettingsFeature: 9 removed as unnecessary (single-field sync toggles, no-op actions), 27 kept with Korean rationale comments.

## `store.finish()` application criteria

`await store.finish()` drains remaining in-flight effects. Apply it selectively, not as a blanket default.

### When to apply

- Test triggers async effects (`.run`) that are fire-and-forget (no `receive` for their completion action).
- Test has in-flight effects not consumed by `receive` assertions.
- Test involves effect cancellation where the cancellation itself is not the final assertion.
- Test spawns long-lived effects (e.g. observation, timer, directory watching) that need clean shutdown.

### When NOT to apply

- Synchronous reducer-only assertions with no effects.
- All effects are fully consumed via `receive`.
- No async lifecycle risk exists (no `.run`, no `.concatenate`, no fire-and-forget).

### Comment convention for non-applicability

When a test has no effects and omits `store.finish()`, no comment is required. When a test has effects but all are consumed via `receive`, add:

```swift
// store.finish() 불필요: 동기 reducer-only assertion
```

or:

```swift
// store.finish() 불필요: 모든 effect가 receive로 소비됨
```

### Evidence

Task 4 of VOY-356 added 3 `await store.finish()` calls for fire-and-forget effects (pickDirectory, applyTheme) where async effects were not consumed by receive assertions. The remaining tests did not need `store.finish()` because they were synchronous or fully consumed.

## RED/GREEN discipline

- A RED test should compile and fail for the intended assertion or receive mismatch, not because the test file does not build.
- Record why the RED failure is expected when the relationship between the spec and current implementation is non-obvious.
- After GREEN, rerun the same focused class filter before any broader verification.

## Common gotchas

| Gotcha                                                               | Fix                                                                                 |
| -------------------------------------------------------------------- | ----------------------------------------------------------------------------------- |
| `.none` resolves to `Optional.none` in optional contexts             | Use the fully qualified enum case when the enum has its own `.none`.                |
| `Set<T>` cannot prove distinctness for non-`Hashable` values         | Use pairwise `XCTAssertNotEqual` loops for `Equatable` values.                      |
| Effect-only routing test returns `.none` before downstream execution | Add a separate test for the real downstream chain when that behavior is the risk.   |
| Tests rely on wall-clock sleep                                       | Replace with controlled clocks, continuations, or deterministic dependency doubles. |

## Deterministic Async Test Synchronization

`Task.sleep` is unreliable in TCA tests because its timing depends on scheduler load, especially under CI. Prefer these alternatives:

### Why Task.sleep fails

A sleep after `fulfillment(of:timeout:)` is redundant when the expectation already guarantees the callback ran. If the callback increments a counter then fulfills, the counter read after fulfillment is deterministic. The sleep adds flakiness under load without adding safety.

### Preferred patterns

1. **Fulfillment-based waiting.** Use `XCTestExpectation` with `fulfillment(of:timeout:)`. After fulfillment returns, reads of state set inside the callback closure are deterministic because fulfillment only fires after the closure completes.
2. **Actor-based recorders.** Use an actor (e.g. `actor Counter { private var value = 0; func increment() { value += 1 }; func value() -> Int { value } }`) to capture side-effect results. Read the actor after fulfillment. No sleep needed.
3. **TestStore `.receive` for effect-driven actions.** When testing reducer effects that produce actions, `store.receive` synchronizes the effect completion. This is the preferred path for TCA effect testing.

### Replacement checklist

- Identify the event that proves the async work happened: fulfilled expectation, actor recorder append, continuation resume, controlled clock advance, or `TestStore.receive`.
- Assert only after that event. If the callback mutates a recorder and then fulfills an expectation, the recorder read after fulfillment is deterministic.
- Document the causality in evidence or a short test comment when replacing an existing sleep.
- Add a static guardrail for the touched file when the plan explicitly removes sleeps, for example `! grep -R "Task.sleep" <test-file>`.
- Do not replace one sleep with a longer sleep or a polling loop unless no event source exists and the poll has a bounded timeout plus a clear rationale.

### When you might still need a wait

For UIKit/AppKit callback sequences where XCTestExpectation does not apply, use `waitForExpectations(timeout:handler:)` with explicit expectations rather than bare `Task.sleep`. If you must poll, use a tight loop with `Task.sleep(nanoseconds: 1_000_000)` (1ms) and a timeout guard, not a single long sleep.

## Scope boundary

This reference covers TestStore authoring mechanics and gotchas. For test execution commands, failure analysis, rerun loops, and dependency testing rules, load `../../testing/references/testing-playbook.md`.
