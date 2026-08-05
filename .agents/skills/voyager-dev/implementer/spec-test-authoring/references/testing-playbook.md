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
    - Prefer official commands from this playbook, `../../../../code-tooling/SKILL.md`, README/AGENTS, or CI config.
    - For monorepos, narrow by modified app/package before broad runs.
2. **Run targeted first**
    - First pass: fastest relevant unit/spec tests.
    - Second pass: package/module integration tests when behavior crosses boundaries.
    - Third pass: full suite only when shared reducers, package APIs, or broad dependencies changed.
    - Do not create tests just to make verification evidence. If no existing focused test covers the change, report the proof gap instead of inventing a new suite.
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

### Test creation gate

This skill verifies with existing tests. It must not author new test files, helper files, or suites as a side effect of implementation verification.

New or modified tests are allowed only when one of these is true:

- The user explicitly asked for test authoring.
- A feature/spec AC already owns the behavior and `spec-test-authoring` is loaded for that owning suite.
- A failing existing test needs a minimal expectation update that preserves its original intent.

If coverage is missing, prefer one of these outcomes instead of creating an ad-hoc test:

1. Run the nearest existing focused test and state the remaining proof gap.
2. Use compile/lint/build evidence when the change is mechanical or wiring-only.
3. Route a separate explicit test-authoring task through `spec-test-authoring` with the owning spec/AC path.

### Split-target spec suites

When a spec owns suites in two targets (app and package), run focused filters against each target separately. Do not rely on a single filter that only hits one target.

```bash
# Package target
xcrun swift test --package-path <package-path> --filter <SpecID><PascalCaseSpecTitle>Tests

# App target (xcodebuild)
xcodebuild test -scheme Voyager-Dev -project apps/macos/Voyager/Voyager.xcodeproj \
  -only-testing:VoyagerTests/<SpecID><PascalCaseSpecTitle>Tests
```

If the spec ID is the same in both targets, a grep for the spec ID should find tests in both locations. Report pass/fail per target; do not merge results.

### Flow suite selection

Canonical flow-document suites under `VoyagerTests/Flows/<CATEGORY>/` are selected by flow ID, not by directory path.

**Human/CI commands** (via mise):

```bash
# Run one flow
mise run macos-test-flow -- --flow onb.access_unlock

# Run all flows in a category
mise run macos-test-flow -- --category onb

# List all mapped flow suites
mise run macos-test-flow -- --list

# Check structural integrity of mapped suites
mise run macos-test-flow -- --check
```

**Agent verification rule**: Agents use the same canonical `mise` tasks as humans and CI. Use the flow task for mapped suites and the Python runner only to inspect the resolved selector or structural mapping:

```bash
# Inspect the selector without executing the test
python3 scripts/dev/macos_test_flow.py --flow onb.access_unlock --dry-run
# Output: scripts/dev/macos-test.sh -only-testing:VoyagerTests/AccessUnlockFlowTests
# Execute through the canonical repository task
mise run macos-test-flow -- --flow onb.access_unlock
```

**v1 migration scope**: The checker reports unmigrated canonical flow documents without failing. Existing mapped suites are strict: structural mismatches (orphan suite, class/file mismatch, missing FLOW-ID marker) cause checker exit 1. Do not treat unmigrated docs as covered or blocked in v1.

See `flow-test-topology.md` for the complete mapping contract.

**Rollout status (v1)**: Pilot first: `AccessUnlockFlowTests` is the initial mapped suite. New and modified flows opt in next. Strict all-flow coverage is deferred to a separate approved task. No manifest, dependency graph, or CI workflow is required or planned for v1.

### Task-shape rules

- `scaffold`
    - Prefer an existing focused reducer/spec test. Add one only through `spec-test-authoring` when the new behavior has an owning spec/AC or the user requested tests.
- `decompose`
    - Preserve existing tests. Add boundary tests only through `spec-test-authoring` when the owning suite/AC is identified.
- `observation-refactor`
    - Verify existing lifecycle tests first. Add lifecycle coverage only through `spec-test-authoring` when the owning interaction is explicit.
- `reuse-guard`
    - Prefer existing regression tests around the reused abstraction. Do not create infrastructure/helper tests solely for reuse proof.
- For critical routed flows, keep at least one test that exercises the real downstream chain instead of proving routing only.
- If a test intercepts a routed action and returns `.none`, treat that as routing coverage only and add a separate full-chain test when downstream execution is the real risk.
- When behavior changes across lifecycle or callback boundaries, cover the meaningful success, failure, cancel, reload, and teardown variants rather than a single happy path.
- When a feature has branch-specific semantics, assert state at each boundary where those branches are meant to diverge so distinct behaviors cannot collapse together silently.
- For multi-step async flows, include at least one stale-completion, cancellation-between-steps, or superseded-request test when a later step can persist or commit durable state.

## Test preparation

- Before writing multiple test files for the same domain, audit existing test helpers and extract shared fixtures first. This eliminates duplication across subsequent test files and establishes consistent patterns.
- Name test files by domain/behavior (e.g., `AiConnectionOAuthTests`), not by issue identifier (e.g., `Voy218SettingsGapTests`). Coverage maps belong in notepad or evidence, not in runtime test code.
- For entry-manipulation, entry collection, `.voycoll`, and entry path-display tests, initialize and use the root `fixtures/` submodule by default. Real fixture files live under `fixtures/fixtures/**`; copy them into temporary directories before mutation or destructive entry operations and record fixture paths in evidence.

## TCA TestStore patterns

- Use `TestStore(initialState:) { Reducer() } withDependencies: { ... }` for deterministic mock injection. Test both state mutations (in `send` closure) and received effects (`store.receive`). Use `.off` exhaustivity for complex reducer flows with computed properties.
- `skipInFlightEffects()`는 effect 처리 중 새로 생성된 downstream effect를 **재귀적으로 처리하지 않는다**. 다단계 effect chain에서는 각 downstream effect를 명시적으로 `receive`해야 한다.

### skipInFlightEffects 한계 및 대응

`skipInFlightEffects()`는 현재 대기 중인 effect만 처리한다. effect 실행 중 새로 생성된 effect는 자동으로 처리되지 않는다.

```swift
// 다단계 chain: unlock delegate → openInitialWindowIfNeeded → externalFileRouter.receive
// BAD: skipInFlightEffects로는 externalFileRouter.receive를 잡을 수 없음
await store.send(.lifecycle(.accountAccess(.delegate(.unlocked(snapshot)))))
store.skipInFlightEffects()  // ← openInitialWindowIfNeeded까지만 처리

// GOOD: 각 downstream effect를 명시적으로 receive
await store.send(.lifecycle(.accountAccess(.delegate(.unlocked(snapshot)))))
await store.receive(\.lifecycle.delegate.openInitialWindowIfNeeded)
await store.receive(\.externalFileRouter.receive)  // ← 명시적 receive
```

> **출처:** PR #329 Task 5. `kw-20260712-tca-teststore-skipinflighteffects`

## Dependency testing rules

- Override nondeterministic or external values in tests: time, UUID, clocks, storage, network, workspace, notifications, file system.
- For filesystem-backed tests, isolate via dependency/env overrides and assert real user files are unchanged; do not assume the real file is absent.
- For fixture-backed filesystem tests, never mutate `fixtures/fixtures/**` directly; copy the selected fixture file or directory into an isolated temporary location first.
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

## Helper Extraction for Test Maintenance

When test files grow large with repeated dependency setup, extract helpers to reduce duplication and improve readability.

### SwiftLint file_length / type_body_length 위반 대응

spec 테스트 파일이 SwiftLint `file_length`(기본 400줄) 또는 `type_body_length`(기본 300줄) 위반 시, suppression comment 없이 3가지로 대응한다. repo 정책상 per-edit suppression(`swiftlint:disable` 등)은 금지이다.

| 우선순위     | 방식                            | 설명                                                                                                                                       |
| ------------ | ------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------ |
| **A (권장)** | Support/ 폴더로 helper 추출     | `setUp`, fixture builder, mutation helper를 `Tests/.../Support/` 파일로 추출하여 class body 축소. 기존 `StateMutation.swift` 패턴과 일관됨 |
| **B (차선)** | 별개 테스트 클래스로 spec 분할  | `ONB001RestorationTests: XCTestCase` 처럼 별개 클래스로 분할. spec ID는 유지하되 테스트 클래스를 나눔                                      |
| **C (정책)** | `.swiftlint.yml` threshold 상향 | `file_length: 1200` 등 limit 자체 상향. project-wide policy change이므로 user 명시적 승인 필요                                             |

extension 파일 분할(`+Subtopic.swift`)도 동작하지만, 같은 타입을 여러 파일에 분산시켜 가독성이 떨어질 수 있다. Support 추출을 우선 시도할 것.

> **출처:** PR #329 Task 8. `kw-20260712-swiftlint-file-length-type-body-length-spec`

### When to extract

Extract when the same dependency construction block appears **3 or more times** across tests. Two occurrences are tolerable. Three or more means a named helper pays for itself in readability and maintenance.

### Where to place helpers

- Test-target-local by default: `Tests/<TestTargetName>/Support/<FeatureOrAC>/` when the helper is owned by one feature, spec, or acceptance-criteria slice.
- Use flat `Tests/<TestTargetName>/Support/` only for helpers intentionally shared by several suites in that test target.
- Use `Support/Shared/` only after multiple feature/AC folders prove a concrete shared need.
- Helpers must not be `public` or leak into production targets.
- File names should describe the dependency or role (e.g. `ProgressClient.swift`, `PermissionFixtures.swift`) inside the owning feature/AC folder.
- If a helper type name collides with a production type (via `@testable import`), append `Fixture` (e.g. `BetaAccessClientFixture`).

### Enum namespace pattern

Use an enum with no cases as a namespace for related helpers. This prevents accidental instantiation and groups variants logically.

```swift
enum FeatureClient {
    static var success: SomeDependencyClient {
        SomeDependencyClient(perform: { _, _ in .ok })
    }
    static func throwing(_ error: SomeError) -> SomeDependencyClient {
        SomeDependencyClient(perform: { _, _ in throw error })
    }
}
```

Variants should cover the common cases: success, failure by error type, and parameterized responses.

### Composite helpers

When multiple dependencies always appear together (e.g. permission checks that grant or deny a set of related capabilities), create a composite helper that configures all of them at once.

```swift
enum PermissionClients {
    static func allGranted(_ deps: inout DependencyValues) {
        deps.fullDiskAccess = .init(status: { .granted })
        deps.helperFolder = .init(checkAccess: { kGranted }, requestAccess: { kGranted })
    }
}
```

Usage inside `withDependencies`:

```swift
withDependencies { PermissionClients.allGranted(&$0) }
```

Composite helpers eliminate the most duplication when N tests need the same multi-dependency setup.

### What not to extract

- Assertion-based verify closures that inspect arguments with `XCTAssertEqual`. These are unique per test and lose their value when generalized.
- Attempt-counter or retry-counting closures that branch on invocation number. The branching logic is test-specific.
- Single-use dependency setups. A helper used once adds indirection without benefit.
- Helpers that would need production visibility widening (`public`/`open`) just to compile.
- Feature-specific helpers promoted to `Shared` before at least two independent suites need them.

### Cleanup evidence pairing

When helper extraction happens as part of duplicate-test cleanup, pair it with the spec-test-authoring coverage map: each removed or merged test must point to the surviving test/helper/assertion that preserves behavior. Helper extraction alone is not evidence that coverage remained intact.

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

## Verification Evidence Requirements

When recording focused test verification results, always include:

- **Command**: The exact `xcrun swift test` command used
- **Exit code**: The numeric exit code
- **Suite filter**: The `--filter` value used
- **Executed test count**: How many tests ran (from XCTest output)
- **Result**: PASS, FAIL, or BLOCKED
- **Failure phase**: `compilation`, `test-execution`, or `N/A`

For packages where source-level build errors prevent test compilation:

- Record as **BLOCKED** (not PASS or FAIL)
- Include the **first failure path** (file and line)
- Classify as **pre-existing source build blocker** or **test-caused blocker**
- Mark as a **proof gap** — changed tests were NOT proven to compile/execute
- Never claim verification passed if tests did not compile

Example evidence matrix:

| Spec    | Result  | Tests | Proof Gap                         |
| ------- | ------- | ----- | --------------------------------- |
| EVM-001 | PASS    | 10    | No                                |
| EVM-002 | BLOCKED | N/A   | Yes (pre-existing source blocker) |
| EVM-004 | PASS    | 10    | No                                |
