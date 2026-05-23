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

## Scope boundary

This reference covers TestStore authoring mechanics and gotchas. For test execution commands, failure analysis, rerun loops, and dependency testing rules, load `../../testing/references/testing-playbook.md`.
