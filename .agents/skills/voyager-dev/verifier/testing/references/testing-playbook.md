# Voyager Dev Testing Playbook

## Goal

Keep TCA verification proportional: exhaustive where local correctness matters, intentionally lighter where integration breadth matters.

## Default testing posture

- Leaf reducers and narrowly scoped flows should default to exhaustive `TestStore` tests.
- Broader integration flows may use non-exhaustive testing deliberately when asserting every internal step would create noise rather than confidence.
- The narrower the ownership boundary, the more exhaustive the test should be.

## Test execution loop

Voyager-dev owns test selection, execution, failure analysis, fix, and rerun loops for Voyager/macOS/SPM work.

1. **Find the right command**
    - Prefer official commands from this playbook, `../../verification/references/verification.md`, `../../verification/references/xcodebuildmcp-workflow.md`, README/AGENTS, or CI config.
    - For monorepos, narrow by modified app/package before broad runs.
2. **Run targeted first**
    - First pass: fastest relevant unit/spec tests.
    - Second pass: package/module integration tests when behavior crosses boundaries.
    - Third pass: full suite only when shared reducers, package APIs, or broad dependencies changed.
3. **Analyze failures**
    - Summarize the first failure log.
    - Classify as environment, test expectation, or product logic.
    - Re-run suspected flaky tests, but still identify the root cause.
4. **Fix without weakening intent**
    - Preserve the original test purpose.
    - Do not remove assertions, skip tests, hide failures, or add blanket error suppression.
    - Do not run UI tests unless explicitly required; use skip flags for UI suites when running app-level tests.
5. **Rerun and report**
    - Re-run the same focused command that failed.
    - Record commands, pass/fail result, key failure summary, and any fix/next action.

## Test selection rules

- `scaffold`
    - Add at least one focused reducer test when new behavior is introduced.
- `decompose`
    - Preserve existing tests and add focused tests for the new parent/child routing boundary.
- `observation-refactor`
    - Add focused tests for start/stop lifecycle, routed semantic action, and cancellation behavior.
- `reuse-guard`
    - Prefer regression tests around the reused abstraction if behavior moved or widened.
- For critical routed flows, keep at least one test that exercises the real downstream chain instead of proving routing only.
- If a test intercepts a routed action and returns `.none`, treat that as routing coverage only and add a separate full-chain test when downstream execution is the real risk.
- When behavior changes across lifecycle or callback boundaries, cover the meaningful success, failure, cancel, reload, and teardown variants rather than a single happy path.
- When a feature has branch-specific semantics, assert state at each boundary where those branches are meant to diverge so distinct behaviors cannot collapse together silently.
- For multi-step async flows, include at least one stale-completion, cancellation-between-steps, or superseded-request test when a later step can persist or commit durable state.

## Test preparation

- Before writing multiple test files for the same domain, audit existing test helpers and extract shared fixtures first. This eliminates duplication across subsequent test files and establishes consistent patterns.
- Name test files by domain/behavior (e.g., `AiConnectionOAuthTests`), not by issue identifier (e.g., `Voy218SettingsGapTests`). Coverage maps belong in notepad or evidence, not in runtime test code.

## TCA TestStore patterns

- Use `TestStore(initialState:) { Reducer() } withDependencies: { ... }` for deterministic mock injection. Test both state mutations (in `send` closure) and received effects (`store.receive`). Use `.off` exhaustivity for complex reducer flows with computed properties.

## Dependency testing rules

- Override nondeterministic or external values in tests: time, UUID, clocks, storage, network, workspace, notifications, file system.
- For filesystem-backed tests, isolate via dependency/env overrides and assert real user files are unchanged; do not assume the real file is absent.
- Do not let reducers call direct globals like `UUID()`, `Date()`, `Task.sleep`, or `UserDefaults.standard` when tests should control them.
- Prefer dependency clients and test overrides through `TestStore` dependencies.
- Prefer shared test helper files over file-private helpers when multiple test classes need the same test infrastructure. If a helper must be file-private, colocate tests requiring it in the same file.

## Exhaustivity rules

- If a test turns exhaustivity off for an integration flow, leave a short rationale in the test body or surrounding context.
- Use exhaustive assertions by default for leaf features and local state transitions.
- When the store lifetime could hide unfinished long-lived effects, use `store.finish()` or an equivalent explicit completion check.

## Review checks

- Is the chosen test scope aligned with the ownership boundary?
- Are nondeterministic values injected rather than read from globals?
- If exhaustivity is relaxed, is the reason clear?
- Could an in-flight effect be silently left running at test end?
- Does at least one test prove the real downstream execution path for the highest-risk routed flow?
- Do tests distinguish routing-only assertions from execution-chain assertions where both matter?

## SPM Package Test Guidance

### Package inventory (8 macOS packages)

| #   | Package         | Path                                               | Testable          |
| --- | --------------- | -------------------------------------------------- | ----------------- |
| 1   | Onboarding      | `apps/macos/Packages/02_Pages/Onboarding/`         | ✅                |
| 2   | Settings        | `apps/macos/Packages/02_Pages/Settings/`           | ✅                |
| 3   | BetaAccess      | `apps/macos/Packages/04_Features/BetaAccess/`      | ✅                |
| 4   | EntryOperations | `apps/macos/Packages/04_Features/EntryOperations/` | ✅                |
| 5   | Ai              | `apps/macos/Packages/05_Entities/Ai/`              | ✅                |
| 6   | AppPreferences  | `apps/macos/Packages/05_Entities/AppPreferences/`  | ❌ No test target |
| 7   | Entry           | `apps/macos/Packages/05_Entities/Entry/`           | ✅                |
| 8   | VoyagerShared   | `apps/macos/Packages/06_Shared/VoyagerShared/`     | ❌ No test target |

### Discovery commands

```bash
# List all macOS packages with test targets
find apps/macos/Packages -name "Package.swift" -maxdepth 3 -exec sh -c 'grep -q "testTarget" "$1" && echo "$1"' _ {} \;

# Or per-package check
grep "testTarget" apps/macos/Packages/05_Entities/Ai/Package.swift
```

### Per-package test execution

```bash
# Run all tests in a specific package
xcrun swift test --package-path apps/macos/Packages/05_Entities/Ai

# Run filtered tests (preferred for evidence capture)
xcrun swift test --package-path apps/macos/Packages/05_Entities/Ai \
  --filter 'AiRuntimeAdapterTests|ProviderConnectionStateTests'
```

### Evidence capture

- Split evidence per package or per test class, not full package runs.
- For packages with >100 tests, use `--filter` to capture incremental evidence.
- No-test-target packages: explicitly document as skipped with reason.

### Failure handling

- A failed package test must propagate nonzero exit code.
- Do not silence failures by wrapping in `|| true`.
- Report per-package pass/fail status separately.

## Few-shot examples

- **Bad:** A test proves that `.routing(.doThing)` was emitted and then returns `.none`, but never checks what the real reducer/effect chain does next.
  **Good:** Keep the routing assertion if useful, but add a second test that exercises the real downstream execution path.

- **Bad:** A callback-heavy feature gets one happy-path test even though failure, cancel, and teardown branches have different semantics.
  **Good:** Add focused tests for the meaningful branch variants where state is supposed to diverge.
