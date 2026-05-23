# Spec Test Authoring Workflow

## Overview

Turn product specs and acceptance criteria into Swift/TCA test topology. The core rule is: **spec files own behavior, interaction ACs own sections, test methods own executable scenarios, and Support owns only infrastructure**.

## When to use

- Creating tests from a feature spec, acceptance criteria, or interaction list.
- Reorganizing tests so product behavior is owned by one spec AC suite instead of scattered policy/contract/lifecycle files.
- Deciding whether a fixture, recorder, dependency double, or helper belongs in `Support/`.
- Authoring TCA `TestStore` tests before handing off to the `testing` verifier for execution.

Do not use this workflow only to select or run existing tests; use `../../testing/SKILL.md` for that.

## Workflow

### 1. Establish the spec owner

1. Read the product spec, plan, or AC list before creating files.
2. Identify the owning spec ID and title, such as `ONB-001 Run User Onboarding`.
3. Map every interaction AC to exactly one owning suite. Do not create one file per interaction.
4. Inspect existing tests so stale behavior owners are merged, renamed, or reduced instead of left in parallel.

### 2. Apply the topology

- Spec suite file/class: `<SpecID><PascalCaseSpecTitle>Tests.swift`.
- Do **not** append `FeatureTests` to new spec AC suites.
- Put executable spec tests under `Tests/<TestTargetName>/Specs/` when establishing or cleaning topology.
- Put fixtures, recorders, dependency doubles, builders, and helper assertions under `Tests/<TestTargetName>/Support/`.
- Keep product behavior in the spec suite. Support files must never become behavior owners.

### 3. Author interaction AC methods

1. Use one `// MARK: - <spec-id>-<interaction_id>` section per interaction AC.
2. Add one or more test methods under each section for happy path, failure, retry, cancellation, stale response, and edge variants that matter.
3. Use concise doc comments only when they clarify spec traceability or non-obvious intent.
4. If a product behavior currently lives in `PolicyTests`, `ContractTests`, or `LifecycleTests`, move it under the spec owner unless it is a true technical contract with no AC owner.

### 4. Write deterministic TCA tests

- Make state changes observable by choosing an initial state that differs from the expected post-action state.
- Do not pass state mutation closures for no-op actions.
- Override nondeterministic dependencies through `withDependencies`.
- Use `store.finish()` or equivalent checks when effects could outlive the assertion.
- If exhaustivity is `.off`, leave a short rationale tied to integration breadth.

### 5. Hand off to verification

After authoring, load `../../testing/references/testing-playbook.md` and run the focused command first. Use class-name filters that match the new suite name, then broaden only when changed code crosses package or app boundaries. Do not use the test target name as the `--filter` value.

Example:

```bash
xcrun swift test --package-path apps/macos/Packages/02_Pages/Onboarding \
  --filter ONB004FinishOnboardingTests
```

## Checklist

- [ ] Every product behavior test has a single spec owner.
- [ ] New spec suite names use `<SpecID><PascalCaseSpecTitle>Tests.swift`, not `FeatureTests`.
- [ ] Interaction ACs are `// MARK:` sections inside the owning suite, not separate files.
- [ ] Test infrastructure is under `Support/` and contains no behavior assertions as ownership.
- [ ] TCA tests control dependencies, avoid no-op state closures, and complete long-lived effects.
- [ ] Focused test filters and renamed class/file references are updated together.

## Edge cases

- **Unclear ownership**: If an existing test file covers behavior from two specs, split by spec owner. Do not leave dual-owned files; each product behavior gets exactly one suite.
- **Spec with zero interaction ACs**: Do not create an empty suite. Document the spec as "no testable ACs yet" and revisit when ACs arrive.
- **Mixed policy + product tests in one file**: Extract product behavior lines into the spec owner suite. Leave only pure technical contract assertions, such as parser conformance, serialization, or adapter invariants, in the original file.

## Example

Input: The spec contains `PAY-002 Confirm Payment` with interactions `select_payment_method`, `submit_payment`, and `handle_payment_failure`.

Output topology:

```text
Tests/VoyagerFeaturesPaymentTests/
├── Specs/
│   └── PAY002ConfirmPaymentTests.swift
└── Support/
    ├── PAY002/
    │   ├── PAY002PaymentFixtures.swift
    │   └── PAY002PaymentRecorders.swift
    └── Shared/
```

Inside `PAY002ConfirmPaymentTests.swift`:

```swift
@MainActor
final class PAY002ConfirmPaymentTests: XCTestCase {
    // MARK: - PAY-002-select_payment_method

    func testSelectingPaymentMethodStoresSelection() async {
        // TestStore scenario here.
    }

    // MARK: - PAY-002-submit_payment

    func testSubmitPaymentRoutesSuccessfulAuthorization() async {
        // TestStore scenario here.
    }

    // MARK: - PAY-002-handle_payment_failure

    func testPaymentFailureShowsRetryState() async {
        // TestStore scenario here.
    }
}
```

## Common mistakes

| Mistake                                                                                | Fix                                                                                 |
| -------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------- |
| Creating one test file per interaction AC                                              | Create one spec-owner suite and put interactions in `// MARK:` sections.            |
| Naming new suites `...FeatureTests.swift`                                              | Use `<SpecID><PascalCaseSpecTitle>Tests.swift`.                                     |
| Keeping product behavior in `PolicyTests` or `ContractTests` after a spec owner exists | Move the behavior under the spec suite; keep only pure technical contracts outside. |
| Mixing fixtures and executable assertions in the same support file                     | Keep support files limited to infrastructure; assertions live in spec suites.       |
| Adding `TestStore.send` mutation closures for actions that do not change state         | Omit the closure and assert external effects or unchanged state separately.         |
| Using the test target name as the SwiftPM filter                                       | Filter by suite class, such as `--filter ONB004FinishOnboardingTests`.              |

## Quick reference

| Decision                  | Default                                                     |
| ------------------------- | ----------------------------------------------------------- |
| Spec suite name           | `<SpecID><PascalCaseSpecTitle>Tests.swift`                  |
| Interaction layout        | `// MARK: - <spec-id>-<interaction_id>` inside owning suite |
| Product behavior location | Owning spec suite under `Specs/`                            |
| Fixture/recorder location | `Support/<SpecID>/` or `Support/Shared/`                    |
| Verification handoff      | `../../testing/SKILL.md` with focused class filter          |
