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
- Put fixtures, recorders, dependency doubles, builders, and helper assertions under `Tests/<TestTargetName>/Support/` as flat files named by role/type, not by spec ID.
- Keep product behavior in the spec suite. Support files must never become behavior owners.

### 3. Author interaction AC methods

1. Use one `// MARK: - <spec-id>-<interaction_id>` section per interaction AC.
2. Add one or more test methods under each section for happy path, failure, retry, cancellation, stale response, and edge variants that matter.
3. Add a required `///` traceability doc comment immediately before every executable interaction test method. The comment must include:
    - First line: `<SPEC-ID>-<interaction_id>: <scenario summary>`.
    - One sentence explaining the user/product situation being verified.
    - `- 검증 내용`: the reducer/action/effect/state contract under test.
    - `- 사전 조건`: the initial state, fixture, dependency override, or stored snapshot.
    - `- 기대 결과`: the observable state, emitted action, dependency call, persistence, or completion result.
4. Keep `// MARK:` for interaction section navigation only. Do not replace method traceability docs with plain `//` line comments.
5. If a product behavior currently lives in `PolicyTests`, `ContractTests`, or `LifecycleTests`, move it under the spec owner unless it is a true technical contract with no AC owner.

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
xcrun swift test --package-path <package-path> \
  --filter <SpecID><PascalCaseSpecTitle>Tests
```

## Checklist

- [ ] Every product behavior test has a single spec owner.
- [ ] New spec suite names use `<SpecID><PascalCaseSpecTitle>Tests.swift`, not `FeatureTests`.
- [ ] Interaction ACs are `// MARK:` sections inside the owning suite, not separate files.
- [ ] Every executable interaction test method has the required `///` traceability doc comment shape.
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
    ├── PaymentFixtures.swift
    ├── PaymentRecorders.swift
    └── PaymentClients.swift
```

Inside `PAY002ConfirmPaymentTests.swift`:

```swift
@MainActor
final class PAY002ConfirmPaymentTests: XCTestCase {
    // MARK: - PAY-002-select_payment_method

    /// PAY-002-select_payment_method: saved card를 선택하면 현재 결제 수단으로 저장한다.
    /// 사용자가 결제 수단 목록에서 saved card를 선택하는 대표 성공 경로를 검증한다.
    /// - 검증 내용: `.selectPaymentMethod` action이 selected method state와 persistence dependency를 갱신한다.
    /// - 사전 조건: saved card fixture가 결제 수단 목록에 있고 선택된 결제 수단은 없다.
    /// - 기대 결과: selected method가 saved card로 설정되고 저장 dependency가 한 번 호출된다.
    func testSelectingPaymentMethodStoresSelection() async {
        // TestStore scenario here.
    }

    // MARK: - PAY-002-submit_payment

    /// PAY-002-submit_payment: 유효한 결제 수단으로 제출하면 authorization 성공 상태로 라우팅한다.
    /// 사용자가 결제를 제출한 뒤 성공 응답을 받는 happy path를 검증한다.
    /// - 검증 내용: submit effect가 payment client를 호출하고 성공 응답을 승인 완료 state로 반영한다.
    /// - 사전 조건: selected method가 있고 payment client는 success authorization을 반환한다.
    /// - 기대 결과: 결제 상태가 authorized로 바뀌고 에러 상태는 비어 있다.
    func testSubmitPaymentRoutesSuccessfulAuthorization() async {
        // TestStore scenario here.
    }

    // MARK: - PAY-002-handle_payment_failure

    /// PAY-002-handle_payment_failure: authorization 실패 시 retry 가능한 실패 상태를 표시한다.
    /// 결제 client 실패가 사용자에게 복구 가능한 오류로 노출되는지 검증한다.
    /// - 검증 내용: 실패 응답 action이 error message와 retry 가능 상태를 설정한다.
    /// - 사전 조건: selected method가 있고 payment client는 retryable failure를 반환한다.
    /// - 기대 결과: payment state가 failed이고 retry affordance가 활성화된다.
    func testPaymentFailureShowsRetryState() async {
        // TestStore scenario here.
    }
}
```

## Review-Driven Test Cleanup

When a review or refactor reveals duplicate or low-value tests, clean up with this workflow instead of ad-hoc deletion.

Use this section whenever the request says "review feedback", "cleanup duplicate tests", "reduce repeated setup", "merge redundant specs", or similar. The output must prove coverage preservation before any test is deleted.

### Workflow

1. **Inventory duplicates before deleting anything.** Map every candidate-for-removal to the test that preserves its coverage. Build a table: removed or merged test name, preserved-by test/helper/assertion, reason (exact duplicate, subset, near-duplicate with narrower scope).
2. **Verify the mapping.** Read both tests side by side. Confirm the preserved-by test covers every assertion path the removed test exercised. If a removed test has even one unique assertion, keep it or merge that assertion.
3. **Remove bottom-to-top in large files.** When removing multiple tests from one file, delete from the bottom of the file upward so line numbers stay valid for subsequent edits.
4. **Run targeted verification.** Execute only the affected test class filter, not the full suite. Confirm the preserved-by tests pass after removal.
5. **Record evidence.** Save the coverage mapping and removal rationale in evidence or notepad. Future reviewers need to see why coverage was not lost.

### Required cleanup evidence

Capture a compact table before implementation starts:

| Removed/Merged test | Preserved by                     | Reason          | Unique assertions kept? |
| ------------------- | -------------------------------- | --------------- | ----------------------- |
| `testOldName`       | `testNewName` / helper assertion | exact duplicate | yes/no                  |

The table is a guardrail, not documentation polish. If a row cannot identify the surviving assertion path, do not delete that test yet.

### Do / Don't

- Do extract repeated setup after the coverage map identifies stable patterns.
- Do keep failure, retry, stale-response, cancellation, and idempotency scenarios explicit when those branches carry distinct behavior.
- Do record the focused filter that proves the cleaned suite still passes.
- Don't delete tests only because they look similar or because file length is high.
- Don't use broad rewrites as a substitute for traceable removed → preserved-by mapping.

### When to stop

If two tests look similar but test different initial states, entry paths, or assertion focus, keep both. Collapsing distinct scenarios into one test hides real coverage gaps.

## Common mistakes

| Mistake                                                                                | Fix                                                                                 |
| -------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------- |
| Creating one test file per interaction AC                                              | Create one spec-owner suite and put interactions in `// MARK:` sections.            |
| Naming new suites `...FeatureTests.swift`                                              | Use `<SpecID><PascalCaseSpecTitle>Tests.swift`.                                     |
| Keeping product behavior in `PolicyTests` or `ContractTests` after a spec owner exists | Move the behavior under the spec suite; keep only pure technical contracts outside. |
| Mixing fixtures and executable assertions in the same support file                     | Keep support files limited to infrastructure; assertions live in spec suites.       |
| Documenting test intent with plain `//` method comments                                | Use the required `///` traceability shape before every interaction test method.     |
| Adding `TestStore.send` mutation closures for actions that do not change state         | Omit the closure and assert external effects or unchanged state separately.         |
| Using the test target name as the SwiftPM filter                                       | Filter by suite class, such as `--filter <SpecID><PascalCaseSpecTitle>Tests`.       |

## Quick reference

| Decision                  | Default                                                                               |
| ------------------------- | ------------------------------------------------------------------------------------- |
| Spec suite name           | `<SpecID><PascalCaseSpecTitle>Tests.swift`                                            |
| Interaction layout        | `// MARK: - <spec-id>-<interaction_id>` inside owning suite                           |
| Method doc comment        | `/// <SPEC-ID>-<interaction_id>: <scenario>` + intent + 검증 내용/사전 조건/기대 결과 |
| Product behavior location | Owning spec suite under `Specs/`                                                      |
| Fixture/recorder location | Flat files under `Support/`, named by role/type such as `PaymentFixtures.swift`       |
| Verification handoff      | `../../testing/SKILL.md` with focused class filter                                    |
