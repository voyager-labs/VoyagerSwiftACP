# Spec AC Test Topology

## Goal

Make product behavior tests easy to find by giving each feature spec one owning test suite. Interaction ACs are sections inside that suite, not separate files.

## Default directory shape

```text
Tests/<TestTargetName>/
├── Specs/
│   └── <SpecID><PascalCaseSpecTitle>Tests.swift
└── Support/
    ├── <SpecID>/
    │   ├── <SpecID><Purpose>Fixtures.swift
    │   ├── <SpecID><Purpose>Recorders.swift
    │   └── <SpecID><Purpose>DependencyDoubles.swift
    └── Shared/
        └── <SharedPurpose>TestHelpers.swift
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

For `ONB-004 Finish Onboarding`, use `--filter ONB004FinishOnboardingTests`, not `--filter VoyagerPagesOnboardingTests`.

## Ownership rules

- Product behavior belongs in the spec-owner suite.
- Cross-feature flows may assert this spec's routed consequence, but must not re-own another spec's domain behavior.
- Existing `PolicyTests`, `ContractTests`, `LifecycleTests`, or `AdapterTests` files should not receive new product AC coverage once a spec owner exists.
- Keep pure technical contracts outside spec suites only when no product AC owns them, such as parser conformance, serialization compatibility, or platform adapter invariants.

## Support rules

- Put fixtures, recorders, dependency doubles, builders, and helper assertions in `Support/`.
- Spec-local helpers (single-suite consumers) go flat under `Support/<FileName>.swift`, not in a subdirectory.
- Use `Support/Shared/` only after at least two spec suites need the helper.
- Support files must not contain executable product behavior test methods.
- In SwiftPM packages, folders under the same test target compile together. In Xcode project targets, verify target membership when adding files.

### Shared support promotion rule

Promoting a helper to `Support/Shared/` is a deliberate act, not a default. Follow these criteria:

**Default placement**: Flat under `Support/<FileName>.swift`. No spec-specific subdirectories.

**Promote to `Support/Shared/` when:**

- 2 or more spec suites directly reference the helper.
- 1 suite references it directly, but another suite uses it indirectly through a wrapper that would be meaningless without the underlying helper (e.g. `MutationRecorder<T>` is generic infrastructure even if only one suite creates a typed alias).

**Do NOT promote when:**

- Only one spec suite uses the helper with no indirect consumers.
- The helper is tightly coupled to one spec's domain types.

**Exception process:**

- If a helper currently has one consumer but cross-suite use is imminent (already planned, not speculative), document the exception with a comment:
    ```swift
    // Shared promotion 예외: SET004에서도 사용 예정 (VOY-NNN)
    ```
- Without a tracking issue or documented plan, single-consumer helpers stay flat under `Support/`.

**Reference counting before promotion:**

Before moving any helper to `Shared/`, count actual references:

```bash
grep -r 'SymbolName' Specs/
```

If the count is fewer than 2 direct references and no indirect wrapper dependency exists, keep the helper under `Support/`.

### Evidence

Task 5 of VOY-356 applied this rule: `ThemeApplyRecorder` was SET003-only, so it moved out of `Shared/`. `MutationRecorder<T>` stayed in `Shared/` as generic infrastructure used across suites. `InMemoryStorage` stayed in `Shared/` because SET002 and SET003 both use it.
