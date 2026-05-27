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

## Ownership rules

- Product behavior belongs in the spec-owner suite.
- Cross-feature flows may assert this spec's routed consequence, but must not re-own another spec's domain behavior.
- Existing `PolicyTests`, `ContractTests`, `LifecycleTests`, or `AdapterTests` files should not receive new product AC coverage once a spec owner exists.
- Keep pure technical contracts outside spec suites only when no product AC owns them, such as parser conformance, serialization compatibility, or platform adapter invariants.

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

### Evidence

VOY-356 Settings support files follow this shape: `InMemoryStorage.swift`, `MutationRecorder.swift`, and `ThemeApplyRecorder.swift` live directly under `Support/` with no nested support directory.
