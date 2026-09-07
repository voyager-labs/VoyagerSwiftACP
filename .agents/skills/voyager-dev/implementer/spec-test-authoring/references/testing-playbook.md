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

# App target (repository wrapper)
mise run macos-test -- -only-testing:VoyagerTests/<SpecID><PascalCaseSpecTitle>Tests
```

If the spec ID is the same in both targets, a grep for the spec ID should find tests in both locations. Report pass/fail per target; do not merge results.

The executor matrix in `../../../../code-tooling/SKILL.md` is the single route-selection owner. Use these commands only after identifying the owner, target, and suite or flow. A package run and an app run produce separate receipts; a broader run does not replace a missing focused selection.

For a package build or package-wide test, use `xcrun swift build --package-path <package-path>` or `xcrun swift test --package-path <package-path>`. For a mapped app flow, use `mise run macos-test-flow -- --flow <flow-id>`. For an explicitly broad app check, use `mise run macos-test`.

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

### 버퍼링된 비동기 전달의 상관관계 테스트

payload와 correlation metadata가 비동기 경계를 함께 통과해야 하는 동작은 해당 spec/AC의 owning suite에서 다음 순서로 검증한다. Reducer-owned effect는 `TestStore`를 통해 구동한다.

1. checked continuation 또는 명시적 barrier로 결과 소비를 보류한다.
2. 소비를 재개하기 전에 서로 다른 metadata를 가진 payload를 두 개 이상 enqueue한다.
3. barrier를 해제하고 모든 결과를 소비한다.
4. 각 payload가 원래 metadata와 결합되어 있는지와 owning behavior가 요구하는 enqueue 순서를 함께 단언한다.

`Task.sleep`으로 우연한 interleaving을 기다리지 않는다. 경과 시간 자체가 동작 계약일 때만 controlled clock을 사용한다.

- **RED:** shared `current` 또는 `latest` side channel에서 metadata를 읽는 구현에서 payload-metadata 결합 단언이 실패한다.
- **GREEN:** 각 buffered item이 자신의 immutable payload-metadata value를 소유하면 같은 테스트가 결합과 순서를 모두 보존하며 통과한다.

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

Spec-owner test methods must stay in the canonical suite file; do not introduce `+Subtopic.swift` extension files. When an existing suite is split this way, merge its methods into the canonical file and keep only fixtures, doubles, recorders, and builders under `Support/`.

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

### Manifest and suite discovery

Treat each package manifest and its current test declarations as the inventory. Do not maintain a static package count or a hand-written list of packages with or without tests.

```bash
# List package manifests
rg --files apps/macos/Packages -g 'Package.swift' | sort

# Find package test targets in the current manifests
rg -n --glob 'Package.swift' '\.testTarget\(' apps/macos/Packages

# Inventory every Swift test source for topology violations
rg --files apps/macos/Packages/<package>/Tests -g '*.swift' | sort

# Find declared canonical test suites and methods after selecting a package
rg -n --glob '*Tests.swift' '^[[:space:]]*(final[[:space:]]+)?(class|struct)[[:space:]]+[A-Z].*Tests|^[[:space:]]*func[[:space:]]+test|@Test' apps/macos/Packages/<package>/Tests
```

The manifest identifies the package test target. The complete Swift inventory identifies non-canonical files that must be corrected before treating the package topology as valid; `Specs/` accepts only the canonical `<SpecID><PascalCaseSpecTitle>Tests.swift` suite file, not `+Subtopic.swift` extensions. The suite declaration identifies the focused filter. A package without a `.testTarget` has no package-local test execution evidence to collect; record that owner-level gap instead of inferring status from an app scheme or changing an app test plan.

### Per-package test execution

```bash
# Build one package
xcrun swift build --package-path apps/macos/Packages/05_Entities/Ai

# Run all tests in a specific package
xcrun swift test --package-path apps/macos/Packages/05_Entities/Ai

# Run filtered tests (preferred for evidence capture)
xcrun swift test --package-path apps/macos/Packages/05_Entities/Ai \
  --filter 'AiRuntimeAdapterTests|ProviderConnectionStateTests'

# Use the tracked pin for a representative receipt
xcrun swift test --package-path apps/macos/Packages/05_Entities/AppPreferences \
  --filter SET002ConfigureGeneralSettingsTests \
  --only-use-versions-from-resolved-file
```

### Evidence capture

- Keep package and app receipts separate. For each receipt record:
  - **Owner**: package name or app suite/flow owner
  - **Route**: the exact matrix route used
  - **Package/project path** and **target**
  - **Suite/filter** and the exact command
  - **Exit code** and **executed test count** from runner output
  - **Suite identity** confirmed in the output
  - **Failure phase**: `selection`, `dependency-resolution`, `compilation`, `linking`, `test-discovery`, `test-execution`, or `N/A`
  - **Test result**: `PASS`, `FAIL`, or `BLOCKED`
  - **Task outcome**: `pass`, `fail`, `degraded`, `exception`, or `blocked`
  - **Proof gap** and **log path**
- A receipt is successful only when the intended suite identity matches, the executed count is positive, the exit code is zero, and its assertions pass. Exit zero with no matching tests is `test-discovery`, not success.
- Split evidence per package or per test class when focused evidence is requested. For packages with >100 tests, use `--filter` to capture incremental evidence.
- A package with no `.testTarget` is an owner-level coverage gap; document the reason and keep app coverage independent.

### Failure handling

- A failed package or app test must propagate its nonzero exit code when the runner reaches test execution.
- A dependency-resolution, compiler, linker, or test-discovery failure has no test-execution count; record `N/A` or `unknown` rather than zero.
- Do not silence failures by wrapping in `|| true`.
- Report per-owner pass/fail status separately from route selection and scope integrity.

### Lockfile and test-lint integrity

- When a tracked `Package.resolved` participates in the representative package run, capture its status and hash at the task baseline and after the run, record the declared write set, and use `--only-use-versions-from-resolved-file` for the pinned verification run.
- Treat a pre-existing lockfile diff outside the task's declared write set as baseline contamination. Do not reset or restore it; stop that receipt or move to a clean execution location.
- A task-owned lockfile update is not contamination when it is declared before execution. Record the baseline and post-run hash/diff, verify the exact intended pin change, and report it as scope-integrity evidence alongside the test result.
- A passing suite with an unexplained tracked lockfile mutation is not a passing task. Test execution and scope integrity are separate checks.
- Use the existing `scripts/lint-and-format-macos.sh` routing for Swift lint. Test files under `*Tests/*.swift` use `.swiftlint-tests.yml`; production files use `.swiftlint.yml`. A test pass does not prove test lint, and general Swift lint does not prove the test configuration was applied.

## Few-shot examples

- **Bad:** A test proves that `.routing(.doThing)` was emitted and then returns `.none`, but never checks what the real reducer/effect chain does next.
  **Good:** Keep the routing assertion if useful, but add a second test that exercises the real downstream execution path.

- **Bad:** A callback-heavy feature gets one happy-path test even though failure, cancel, and teardown branches have different semantics.
  **Good:** Add focused tests for the meaningful branch variants where state is supposed to diverge.

## Verification Evidence Requirements

When recording focused test verification results, always include the owner, route, exact package or app command, target, suite/filter, numeric exit code, executed test count, suite identity, test result, task outcome, failure phase, proof gap, and log path.

For packages or app routes where source-level errors prevent test compilation:

- Record the test result as **BLOCKED** and the task outcome as **blocked** when the prerequisite is external
- Include the **first failure path** (file and line)
- Classify the phase as `compilation`, `linking`, or `dependency-resolution` as applicable
- Mark as a **proof gap** — the intended suite was not proven to compile or execute
- Never claim verification passed if tests did not compile

Example evidence matrix:

| Spec    | Result  | Tests | Proof Gap                         |
| ------- | ------- | ----- | --------------------------------- |
| EVM-001 | PASS    | 10    | No                                |
| EVM-002 | BLOCKED | N/A   | Yes (pre-existing source blocker) |
| EVM-004 | PASS    | 10    | No                                |
