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
- Keep all scenarios for that interaction under the section.
- Use multiple methods when the AC has distinct success, failure, retry, cancellation, stale response, or idempotency semantics.
- Do not create placeholder files for future interactions. If a placeholder is useful, use an empty `// MARK:` section with a clear TODO comment.

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
- Use `Support/<SpecID>/` for helpers only one spec uses.
- Use `Support/Shared/` only after at least two spec suites need the helper.
- Support files must not contain executable product behavior test methods.
- In SwiftPM packages, folders under the same test target compile together. In Xcode project targets, verify target membership when adding files.
