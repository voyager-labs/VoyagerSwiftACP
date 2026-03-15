# Voyager Dev Testing Playbook

## Goal

Keep TCA verification proportional: exhaustive where local correctness matters, intentionally lighter where integration breadth matters.

## Default testing posture

- Leaf reducers and narrowly scoped flows should default to exhaustive `TestStore` tests.
- Broader integration flows may use non-exhaustive testing deliberately when asserting every internal step would create noise rather than confidence.
- The narrower the ownership boundary, the more exhaustive the test should be.

## Test selection rules

- `scaffold`
  - Add at least one focused reducer test when new behavior is introduced.
- `decompose`
  - Preserve existing tests and add focused tests for the new parent/child routing boundary.
- `observation-refactor`
  - Add focused tests for start/stop lifecycle, routed semantic action, and cancellation behavior.
- `reuse-guard`
  - Prefer regression tests around the reused abstraction if behavior moved or widened.

## Dependency testing rules

- Override nondeterministic or external values in tests: time, UUID, clocks, storage, network, workspace, notifications, file system.
- Do not let reducers call direct globals like `UUID()`, `Date()`, `Task.sleep`, or `UserDefaults.standard` when tests should control them.
- Prefer dependency clients and test overrides through `TestStore` dependencies.

## Exhaustivity rules

- If a test turns exhaustivity off for an integration flow, leave a short rationale in the test body or surrounding context.
- Use exhaustive assertions by default for leaf features and local state transitions.
- When the store lifetime could hide unfinished long-lived effects, use `store.finish()` or an equivalent explicit completion check.

## Review checks

- Is the chosen test scope aligned with the ownership boundary?
- Are nondeterministic values injected rather than read from globals?
- If exhaustivity is relaxed, is the reason clear?
- Could an in-flight effect be silently left running at test end?
