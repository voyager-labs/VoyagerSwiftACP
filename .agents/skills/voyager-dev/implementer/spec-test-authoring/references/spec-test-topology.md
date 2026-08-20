# Spec AC Test Topology

## Goal

Make product behavior tests easy to find by giving each feature spec one owning test suite. Interaction ACs are sections inside that suite, not separate files.

## Default directory shape

```text
Tests/<TestTargetName>/
├── Specs/
│   └── <SpecID><PascalCaseSpecTitle>Tests.swift
└── Support/
    ├── <Purpose>Fixtures.swift
    ├── <Purpose>Recorders.swift
    ├── <Purpose>Clients.swift
    └── <Purpose>DependencyDoubles.swift
```

Use this shape when creating a new test target area or when a task explicitly includes test topology cleanup. If an existing target is flat and the task is a small additive change, avoid broad churn; still apply the naming and ownership rules.

## Naming rules

- Convert spec IDs to compact PascalCase prefixes: `ONB-001` -> `ONB001`, `PAY-002` -> `PAY002`.
- Convert the spec title to PascalCase: `Run User Onboarding` -> `RunUserOnboarding`.
- Name the suite `<SpecID><PascalCaseSpecTitle>Tests.swift` and match the class name exactly.
- Do not use `FeatureTests` as a suffix for new spec AC suites.

Examples:

| Spec                                     | Test file/class                           |
| ---------------------------------------- | ----------------------------------------- |
| `ONB-001 Run User Onboarding`            | `ONB001RunUserOnboardingTests`            |
| `ONB-003 Configure Required Permissions` | `ONB003ConfigureRequiredPermissionsTests` |
| `PAY-002 Confirm Payment`                | `PAY002ConfirmPaymentTests`               |

## Section rules

- Use `// MARK: - <SPEC-ID>-<interaction_id>` for each interaction AC.
- **Canonical format**: `// MARK: - SET-001-do_something` where `<SPEC-ID>` matches `[A-Z]{2,4}-\d{3}` and `<interaction_id>` is lowercase snake*case (`[a-z0-9*]+`).
- Validation regex: `// MARK: - [A-Z]{2,4}-\d{3}-[a-z0-9_]+`
- **Forbidden in MARK headings**: Korean text, em dashes, parenthetical notes, descriptive prose, any non-canonical formatting.
- Human-readable descriptions go in `///` doc comments or prose, NOT in the heading.
- Keep all scenarios for that interaction under the section.
- Use multiple methods when the AC has distinct success, failure, retry, cancellation, stale response, or idempotency semantics.
- Put a `///` traceability doc comment before every executable interaction test method. Use the fixed shape: `<SPEC-ID>-<interaction_id>: <scenario>`, one intent sentence, then `- 검증 내용`, `- 사전 조건`, and `- 기대 결과` bullets.
- Do not create placeholder files for future interactions. If a placeholder is useful, use an empty `// MARK:` section with a clear TODO comment.

### Non-canonical MARK examples to reject

These are real patterns found during VOY-356 Task 3. All must be corrected to the canonical format:

| Bad                                                          | Why it fails                       | Correct                                |
| ------------------------------------------------------------ | ---------------------------------- | -------------------------------------- |
| `// MARK: - SET-003-load_directories — 디렉터리 로드`        | Korean text and em dash in heading | `// MARK: - SET-003-load_directories`  |
| `// MARK: - SET-004-noop_action (package-level no-op)`       | Parenthetical note in heading      | `// MARK: - SET-004-noop_action`       |
| `// MARK: - supplemental current behavior — showHiddenFiles` | Missing spec ID prefix             | `// MARK: - SET-004-show_hidden_files` |

### Audit command

After authoring or renaming, validate all MARK headings in a suite:

```bash
grep -n '// MARK:' <SuiteFile>.swift | grep -vE '// MARK: - [A-Z]{2,4}-[0-9]{3}-[a-z0-9_]+'
```

Non-empty output means non-canonical headings exist. Fix before proceeding.

## Focused filter rule

The first verification command should filter by the owning suite class, not by the test target name.

```bash
xcrun swift test --package-path <package-path> --filter <SpecID><PascalCaseSpecTitle>Tests
```

Use `--filter <SpecID><PascalCaseSpecTitle>Tests`, not the test target name.

## Specs/ directory contents

`Specs/` contains ONLY spec-owner suite files matching `<SpecID><PascalCaseSpecTitle>Tests.swift`. No other test files are permitted in `Specs/`.

### Forbidden in Specs/

- Component or infrastructure unit test files (e.g. `AccountTokenFileStoreTests.swift`, `SomeClientTests.swift`, `TokenMapperTests.swift`).
- Implementation-named suites that are not traceable to a spec AC.
- Any file whose class name does not match `<SpecID><PascalCaseSpecTitle>Tests`.

### Component behavior coverage workflow

When a new component, client, or infrastructure type needs test coverage (atomic write, quarantine, permissions, serialization, mapping):

1. **Identify the owning spec.** Determine which spec AC depends on this component's behavior.
2. **If no AC exists, update the spec document first.** Add the missing AC to the spec's interaction document so the behavior is formally specified.
3. **Add test methods to the owning spec-owner suite.** Place them under the appropriate `// MARK: - <SPEC-ID>-<interaction_id>` section. Use `///` traceability doc comments like any other AC test.
4. **Never create a standalone component test file.** All product behavior verification — including infrastructure-level guarantees like file permissions, atomic writes, or quarantine — belongs as test methods inside the spec-owner suite that exercises the product behavior depending on that component.

Example: `AccountTokenFileStore` atomic write and quarantine behavior is product-relevant (token persistence safety). The correct owner is the spec that requires token persistence — e.g. `ACC001RestoreAccountSessionTests` or `ACC001SignOutAccountTests`. Add test methods there under the relevant `// MARK:` section. Do not create `AccountTokenFileStoreTests.swift`.

## Ownership rules

- Product behavior belongs in the spec-owner suite.
- Cross-feature flows may assert this spec's routed consequence, but must not re-own another spec's domain behavior.
- Existing `PolicyTests`, `ContractTests`, `LifecycleTests`, or `AdapterTests` files should not receive new product AC coverage once a spec owner exists.
- Do not keep pure technical contracts in standalone test suites. Assign parser conformance, serialization compatibility, or platform adapter invariants to the owning product spec or canonical flow before authoring coverage.

## Split-target spec ownership

When a single logical spec spans multiple test targets (for example, one app target and one package target) because ownership boundaries require it, follow these rules:

- Each target owns only the behavior it is responsible for. The app target owns app-scoped behavior (window lifecycle, focus, hosting). The package target owns package-scoped behavior (command routing, reducer logic).
- Each target gets its own `Specs/` directory containing a suite file named with the same spec ID and a scope qualifier: `<SpecID><PascalCaseSpecTitle>Tests.swift` in both targets. Do not create a single suite that spans targets.
- Each target uses target-local `Support/` directories. Shared helpers between the two targets go in `Support/Shared/` within the target that owns the shared abstraction. Do not symlink or cross-reference support files between targets.
- Traceability doc comments use the same spec ID and interaction ID across both targets so a grep for the spec ID finds all related tests.
- The spec ID ties the split suites together logically. Do not invent separate spec IDs for the same logical feature.

Topology example for a split-target spec:

```text
Tests/<AppTestTarget>/
├── Specs/
│   └── <SpecID><PascalCaseSpecTitle>Tests.swift
└── Support/
    └── <SpecID>/

Tests/<PackageTestTarget>/
├── Specs/
│   └── <SpecID><PascalCaseSpecTitle>Tests.swift
└── Support/
    └── <SpecID>/
```

Both suites share the same spec ID prefix and the same interaction IDs in `// MARK:` sections and traceability comments, but each suite only asserts behavior within its own ownership scope.

## Forbidden implementation-named suites

A suite whose filename includes reducer, client, status, contract, or feature implementation terms after the spec ID prefix must not contain product AC coverage. Only `<SpecID><PascalCaseSpecTitle>Tests` owns product ACs.

### Examples of forbidden suite names

These real patterns from AccountAccess package tests (previously LicenseAuth) violate the ownership rule because they embed implementation detail in the suite name:

| Forbidden suite name               | Why it is forbidden                                           |
| ---------------------------------- | ------------------------------------------------------------- |
| `AccountAccessReducerTests`        | Reducer implementation detail, not a spec-owner suite         |
| `AccountAccessClientContractTests` | Client implementation detail, not a spec-owner suite          |
| `AccessStatusActivityTests`        | Status activity implementation detail, not a spec-owner suite |
| `AccessStatusCodingContractTests`  | Coding contract detail, not a spec-owner suite                |
| `AccountAccessFeatureTests`        | Forbidden `FeatureTests` suffix                               |

### Correct owner

The correct spec-owner suite for ONB-002 is `ONB002PresentAccessUnlockStepTests`, derived from the feature inventory:

- `feature_id` = `ONB-002`
- `feature_title` = `Present Access Unlock Step`
- Compact prefix: `ONB002`
- PascalCase title: `PresentAccessUnlockStep`
- Expected suite: `ONB002PresentAccessUnlockStepTests.swift`

Each target that owns ONB-002 behavior should contain a file named `ONB002PresentAccessUnlockStepTests.swift`, not any of the forbidden names above.

### Rule

If a suite name matches the spec-like pattern `[A-Z]{2,4}[0-9]{3}.*Tests\.swift` but does not match the TSV-computed owner suite name `<CompactPrefix><PascalCaseTitle>Tests.swift`, it must not contain product interaction `// MARK:` sections. Such files may exist as technical-only contract or adapter tests, but they must not own product AC coverage.

## Support rules

- Put fixtures, recorders, dependency doubles, builders, and helper assertions in `Support/`.
- Keep `Support/` flat; do not create nested support directories.
- Name support files by role/type, not by spec ID prefix. Good examples: `PermissionFixtures.swift`, `PathRecorder.swift`, `ProgressClient.swift`, `InMemoryStorage.swift`.
- If a helper type name collides with a production type (via `@testable import`), append `Fixture` (e.g. `BetaAccessClientFixture`).
- Support files must not contain executable product behavior test methods.
- In SwiftPM packages, folders under the same test target compile together. In Xcode project targets, verify target membership when adding files.
- After renaming a suite class, search for all references to the old class name and update them.

### Support file naming rule

Support file names should describe the helper role or dependency shape, matching the flat pattern used by Onboarding tests:

- `PermissionFixtures.swift`
- `PermissionClients.swift`
- `PathRecorder.swift`
- `ProgressClient.swift`
- `WindowClient.swift`

Avoid names that merely repeat the spec ID, such as `PAY002PaymentFixtures.swift`, unless the domain term would otherwise be ambiguous.

## SwiftPM package test rules

SwiftPM 패키지 테스트(`Tests/<TestTarget>/`)는 예외 없이 아래 규칙을 따른다.

### Mandatory Specs/ placement

모든 spec 기반 테스트 파일은 `Specs/` 디렉토리 안에 배치한다. 패키지 루트(`Tests/<TestTarget>/`)에 직접 `.swift` 테스트 파일을 두는 것은 금지한다.

```text
Tests/<TestTarget>/
├── Specs/                                    ← 모든 spec 테스트는 여기
│   └── <SpecID><PascalCaseSpecTitle>Tests.swift
└── Support/                                  ← fixture, double, helper
```

프로젝트 전체 50+ SwiftPM 테스트 파일이 이 패턴을 따른다. 새 패키지나 새 테스트 파일을 추가할 때 반드시 확인한다.

### Pre-addition checklist

새 테스트 파일을 생성하기 전에 반드시 확인:

1. **Spec ID가 있는가?** — `<SpecID><PascalCaseTitle>Tests.swift` 형태인가? (`FMW003`, `CBW005`, `RCL003` 등)
2. **`Specs/` 디렉토리에 배치하는가?** — 패키지 루트가 아닌 `Specs/` 하위인가?
3. **구현 이름이 아닌 spec 이름을 사용하는가?** — `OpenRouterFeatureTests` ❌ → `FMW003HandleExternalFileOpenRequestsTests` ✅

### Anti-patterns (rejected during FMW-003 review)

| 잘못된 패턴                                          | 이유                                              | 올바른 형태                                              |
| ---------------------------------------------------- | ------------------------------------------------- | -------------------------------------------------------- |
| `Tests/.../ExternalFileURLParserTests.swift`         | `Specs/` 밖, spec ID 없음                         | `Tests/.../Specs/FMW003ExternalFileURLParserTests.swift` |
| `Tests/.../FilePathNormalizerTests.swift`            | `Specs/` 밖, spec ID 없음                         | `Tests/.../Specs/FMW003FilePathNormalizerTests.swift`    |
| `VoyagerTests/Features/OpenRouterFeatureTests.swift` | `FeatureTests` 접미사 (명시적 금지), spec ID 없음 | `Specs/FMW003HandleExternalFileOpenRequestsTests.swift`  |

### Evidence

VOY-356 Settings support files follow this shape: `InMemoryStorage.swift`, `MutationRecorder.swift`, and `ThemeApplyRecorder.swift` live directly under `Support/` with no nested support directory.
