// swiftlint:disable file_length

import ComposableArchitecture
import VoyagerFeaturesBetaAccess
@testable import VoyagerPagesOnboarding
import XCTest

// swiftlint:disable type_body_length
@MainActor
final class ONB001RunUserOnboardingFeatureTests: XCTestCase {
    // MARK: - ONB-001-start_onboarding_session

    // 온보딩 세션 시작 상호작용을 검증합니다.
    // 앱 첫 실행, 빈 진행 상태, 버전 불일치로 인한 리셋 등 세션 초기화 시나리오에서
    // 초기 단계 상태가 올바르게 설정되고 진행 상태 스냅샷이 저장되는지 확인합니다.

    /// 저장된 버전이 앱 버전과 불일치할 때 세션이 완전히 초기화되는지 검증합니다.
    /// - 검증 내용: `load`가 `.resetRequired`를 반환하면 reducer가 기존 진행 상태를 버리고 새 세션을 시작합니다.
    /// - 사전 조건: `onboardingProgressClient.load`가 `.resetRequired`를 반환하여 앱 업데이트 등으로 인한 리셋 필요를 나타냅니다.
    /// - 기대 결과: `currentStep`이 `.welcome`으로 초기화, welcome은 완료, 나머지 단계는 미완료 상태입니다.
    /// - 관련 사양: ONB-001-start_onboarding_session
    /// - 부가 검증: ONB-001-show_onboarding_step (onAppear가 초기 단계 표시를 트리거).
    func testResetOnVersionMismatch() async {
        let store = TestStore(initialState: OnboardingFeature.State()) {
            OnboardingFeature()
        } withDependencies: {
            $0.onboardingProgressClient = OnboardingProgressClient(
                load: { .resetRequired },
                save: { _ in },
                reset: {},
            )
        }

        await store.send(.onAppear)

        XCTAssertEqual(store.state.currentStep, .welcome)
        XCTAssertTrue(store.state.welcome.isComplete)
        XCTAssertFalse(store.state.betaAccess.isComplete)
        XCTAssertFalse(store.state.permissions.isComplete)
        XCTAssertFalse(store.state.complete.isComplete)

        await store.finish()
    }

    /// 저장된 진행 상태가 없을 때 새 온보딩 세션이 welcome 단계에서 시작되는지 검증합니다.
    /// - 검증 내용: `load`가 `.empty`를 반환하면 reducer가 기본 상태로 새 세션을 생성합니다.
    /// - 사전 조건: 진행 상태 저장소가 `.empty`를 반환하여 이전 세션이 없음을 나타냅니다.
    /// - 기대 결과: welcome은 완료 상태, 나머지 단계는 미완료 상태이며 첫 단계라 뒤로 이동할 수 없습니다.
    /// - 관련 사양: ONB-001-start_onboarding_session
    func testStartFreshSessionOnEmptyProgress() async {
        let store = TestStore(initialState: OnboardingFeature.State()) {
            OnboardingFeature()
        } withDependencies: {
            $0.onboardingProgressClient = OnboardingProgressClient(
                load: { .empty },
                save: { _ in },
                reset: {},
            )
        }

        await store.send(.onAppear)

        // 새 세션은 항상 welcome에서 시작
        XCTAssertEqual(store.state.currentStep, .welcome)
        XCTAssertTrue(store.state.welcome.isComplete)
        XCTAssertFalse(store.state.betaAccess.isComplete)
        XCTAssertFalse(store.state.permissions.isComplete)
        XCTAssertFalse(store.state.complete.isComplete)

        // canGoNext가 true인지 확인 (welcome은 기본적으로 완료 상태)
        XCTAssertTrue(store.state.canGoNext)
        XCTAssertFalse(store.state.canGoBack)

        await store.finish()
    }

    /// `resetRequired` 응답 시 reducer가 `reset()`과 `save()`를 모두 호출하는지 검증합니다.
    /// - 검증 내용: 세션 리셋 시 실제 저장소 초기화와 새 진행 상태 저장이 순차적으로 발생합니다.
    /// - 사전 조건: `load`가 `.resetRequired`를 반환합니다. `resetRecorder`로 `reset()` 호출 여부를 추적합니다.
    /// - 기대 결과: `resetRecorder.value`가 `true`로 설정되어 `reset()`이 실제로 호출되었음을 확인합니다.
    /// - 관련 사양: ONB-001-start_onboarding_session
    func testResetSessionCallsResetAndSave() async {
        let resetRecorder = LockIsolated(false)

        let store = TestStore(initialState: OnboardingFeature.State()) {
            OnboardingFeature()
        } withDependencies: {
            $0.onboardingProgressClient = OnboardingProgressClient(
                load: { .resetRequired },
                save: { _ in },
                reset: { resetRecorder.setValue(true) },
            )
        }

        await store.send(.onAppear)

        XCTAssertTrue(resetRecorder.value)

        await store.finish()
    }

    /// `load`가 `.empty`를 반환하면 상태가 새 세션으로 초기화되고 초기 스냅샷이 저장되는지 검증합니다.
    /// - 검증 내용: 진행 상태가 없을 때 세션 초기화 후 첫 스냅샷이 올바른 단계 상태와 함께 저장됩니다.
    /// - 사전 조건: `load`가 `.empty`를 반환합니다. `snapshotRecorder`로 `save()`에 전달된 스냅샷을 캡처합니다.
    /// - 기대 결과: welcome에서 시작, welcome만 완료, 저장된 스냅샷의 `currentStep`이 `.welcome`입니다.
    /// - 관련 사양: ONB-001-start_onboarding_session
    func testEmptyProgressStartsFreshSession() async {
        let snapshotRecorder = SnapshotRecorder()

        let store = TestStore(initialState: OnboardingFeature.State()) {
            OnboardingFeature()
        } withDependencies: {
            $0.onboardingProgressClient = OnboardingProgressClient(
                load: { .empty },
                save: { snapshot in
                    Task { await snapshotRecorder.set(snapshot) }
                },
                reset: {},
            )
        }

        await store.send(.onAppear)

        // 새 세션은 항상 welcome에서 시작
        XCTAssertEqual(store.state.currentStep, .welcome)
        XCTAssertTrue(store.state.welcome.isComplete)
        XCTAssertFalse(store.state.betaAccess.isComplete)
        XCTAssertFalse(store.state.permissions.isComplete)
        XCTAssertFalse(store.state.complete.isComplete)

        // 올바른 초기 상태로 스냅샷이 저장되었는지 확인
        let savedSnapshot = await snapshotRecorder.value
        XCTAssertNotNil(savedSnapshot)
        XCTAssertEqual(savedSnapshot?.currentStep, .welcome)

        await store.finish()
    }

    /// `onAppear` 시 초기 단계 상태를 반영하여 진행 상태 스냅샷이 올바르게 저장되는지 검증합니다.
    /// - 검증 내용: 세션 시작 시 저장되는 스냅샷의 각 단계별 완료 플래그가 초기 상태와 일치합니다.
    /// - 사전 조건: `load`가 `.empty`를 반환합니다. `snapshotRecorder`로 저장된 스냅샷을 캡처합니다.
    /// - 기대 결과: 스냅샷의 `welcomeComplete`는 `true`, 나머지 단계(`betaAccess`, `permissions`, `complete`)는 모두 `false`입니다.
    /// - 관련 사양: ONB-001-start_onboarding_session
    func testStartSessionSavesProgressSnapshot() async {
        let snapshotRecorder = SnapshotRecorder()

        let store = TestStore(initialState: OnboardingFeature.State()) {
            OnboardingFeature()
        } withDependencies: {
            $0.onboardingProgressClient = OnboardingProgressClient(
                load: { .empty },
                save: { snapshot in
                    Task { await snapshotRecorder.set(snapshot) }
                },
                reset: {},
            )
        }

        await store.send(.onAppear)

        let savedSnapshot = await snapshotRecorder.value
        XCTAssertNotNil(savedSnapshot)
        XCTAssertEqual(savedSnapshot?.stepState.welcomeComplete, true)
        XCTAssertEqual(savedSnapshot?.stepState.betaAccessComplete, false)
        XCTAssertEqual(savedSnapshot?.stepState.permissionsComplete, false)
        XCTAssertEqual(savedSnapshot?.stepState.completeComplete, false)

        await store.finish()
    }

    // MARK: - ONB-001-show_onboarding_step

    // 온보딩 단계 표시: 각 단계의 title, subtitle, 인덱스, 네비게이션 플래그,
    // 정식 단계 순서(welcome → betaAccess → permissions → complete)를 검증합니다.

    /// 초기 `onAppear` 시 welcome 단계가 올바른 속성(title, subtitle, 인덱스, 총 단계 수)과 함께 표시되는지 검증합니다.
    /// - 검증 내용: welcome 단계의 메타데이터와 네비게이션 컨텍스트가 기대값과 일치합니다.
    /// - 사전 조건: `load`가 `.empty`를 반환하여 새 세션이 시작됩니다.
    /// - 기대 결과: `currentStep`은 `.welcome`, title "Welcome", subtitle "A quick setup before you dive in.",
    ///   `currentStepIndex` 1, `totalSteps` 4입니다.
    /// - 관련 사양: ONB-001-show_onboarding_step
    func testShowWelcomeStepOnAppear() async {
        let store = TestStore(initialState: OnboardingFeature.State()) {
            OnboardingFeature()
        } withDependencies: {
            $0.onboardingProgressClient = OnboardingProgressClient(
                load: { .empty },
                save: { _ in },
                reset: {},
            )
        }

        await store.send(.onAppear)

        // welcome 단계가 표시되어야 함
        XCTAssertEqual(store.state.currentStep, .welcome)
        XCTAssertEqual(store.state.currentStep.title, "Welcome")
        XCTAssertEqual(store.state.currentStep.subtitle, "A quick setup before you dive in.")
        XCTAssertEqual(store.state.currentStepIndex, 1)
        XCTAssertEqual(store.state.totalSteps, 4)

        await store.finish()
    }

    /// welcome에서 `nextTapped` 후 betaAccess 단계가 올바른 속성과 함께 표시되는지 검증합니다.
    /// - 검증 내용: 단계 전환 후 `currentStep`, title, 인덱스가 betaAccess에 해당하는 값으로 갱신됩니다.
    /// - 사전 조건: 새 세션이 시작되어 welcome 단계에 위치합니다.
    /// - 기대 결과: `currentStep`은 `.betaAccess`, title "Beta Access", `currentStepIndex` 2입니다.
    /// - 관련 사양: ONB-001-show_onboarding_step
    func testShowBetaAccessStepAfterWelcome() async {
        let store = TestStore(initialState: OnboardingFeature.State()) {
            OnboardingFeature()
        } withDependencies: {
            $0.onboardingProgressClient = OnboardingProgressClient(
                load: { .empty },
                save: { _ in },
                reset: {},
            )
        }

        await store.send(.onAppear)
        await store.send(.nextTapped) { state in
            state.currentStep = .betaAccess
        }

        XCTAssertEqual(store.state.currentStep, .betaAccess)
        XCTAssertEqual(store.state.currentStep.title, "Beta Access")
        XCTAssertEqual(store.state.currentStepIndex, 2)

        await store.finish()
    }

    /// betaAccess가 확인 완료된 후 `nextTapped`로 permissions 단계가 표시되는지 검증합니다.
    /// - 검증 내용: betaAccess 검증 성공(`.active`) 후 다음 단계 전환이 정상 동작합니다.
    /// - 사전 조건: welcome 통과, betaAccess에서 `.active` 확인 응답 수신 후 `isComplete = true` 상태입니다.
    /// - 기대 결과: `currentStep`은 `.permissions`, title "Permissions", `currentStepIndex` 3입니다.
    /// - 관련 사양: ONB-001-show_onboarding_step
    func testShowPermissionsStepAfterBetaAccess() async {
        let store = TestStore(initialState: OnboardingFeature.State()) {
            OnboardingFeature()
        } withDependencies: {
            $0.onboardingProgressClient = OnboardingProgressClient(
                load: { .empty },
                save: { _ in },
                reset: {},
            )
        }

        await store.send(.onAppear)
        await store.send(.nextTapped) { state in
            state.currentStep = .betaAccess
        }
        await store.send(.betaAccess(.verificationResponse(BetaAccessVerificationResult(status: .active)))) { state in
            state.betaAccess.status = .active
            state.betaAccess.reason = .none
            state.betaAccess.isComplete = true
        }
        await store.send(.nextTapped) { state in
            state.currentStep = .permissions
        }

        XCTAssertEqual(store.state.currentStep, .permissions)
        XCTAssertEqual(store.state.currentStep.title, "Permissions")
        XCTAssertEqual(store.state.currentStepIndex, 3)

        await store.finish()
    }

    /// 모든 이전 단계(welcome, betaAccess, permissions)가 완료되면 complete 단계가 표시되는지 검증합니다.
    /// - 검증 내용: 선행 단계 모두 완료 시 `nextTapped`가 complete 단계로 전환합니다.
    /// - 사전 조건: welcome, betaAccess(`.active`), permissions 모두 `isComplete = true`이고 `currentStep = .permissions`입니다.
    /// - 기대 결과: `currentStep`은 `.complete`, title "Start your voyage", 인덱스 4, `canGoNext`는 `false`(마지막 단계)입니다.
    /// - 관련 사양: ONB-001-show_onboarding_step
    func testShowCompleteStepAfterPermissions() async {
        var initialState = OnboardingFeature.State()
        initialState.currentStep = .permissions
        initialState.welcome.isComplete = true
        initialState.betaAccess.isComplete = true
        initialState.betaAccess.status = .active
        initialState.betaAccess.reason = .none
        initialState.permissions.isComplete = true

        let store = TestStore(initialState: initialState) {
            OnboardingFeature()
        } withDependencies: {
            $0.onboardingProgressClient = OnboardingProgressClient(
                load: { .empty },
                save: { _ in },
                reset: {},
            )
        }

        await store.send(.nextTapped) { state in
            state.currentStep = .complete
        }

        XCTAssertEqual(store.state.currentStep, .complete)
        XCTAssertEqual(store.state.currentStep.title, "Start your voyage")
        XCTAssertEqual(store.state.currentStepIndex, 4)
        XCTAssertFalse(store.state.canGoNext)

        await store.finish()
    }

    /// 초기 `onAppear` 시 welcome 단계가 올바른 네비게이션 플래그(`canGoNext`, `canGoBack`)와 함께 표시되는지 검증합니다.
    /// - 검증 내용: 첫 단계에서 앞으로는 이동 가능, 뒤로는 이동 불가능한지 확인합니다.
    /// - 사전 조건: `load`가 `.empty`를 반환하여 새 세션이 시작됩니다.
    /// - 기대 결과: `currentStep`은 `.welcome`, `canGoNext`는 `true`(welcome은 기본 완료), `canGoBack`은 `false`(첫 단계)입니다.
    /// - 관련 사양: ONB-001-show_onboarding_step
    func testOnAppearDisplaysWelcomeStep() async {
        let store = TestStore(initialState: OnboardingFeature.State()) {
            OnboardingFeature()
        } withDependencies: {
            $0.onboardingProgressClient = OnboardingProgressClient(
                load: { .empty },
                save: { _ in },
                reset: {},
            )
        }

        await store.send(.onAppear)

        XCTAssertEqual(store.state.currentStep, .welcome)
        XCTAssertTrue(store.state.canGoNext)
        XCTAssertFalse(store.state.canGoBack)

        await store.finish()
    }

    /// 단계 순서가 정식 순서(welcome → betaAccess → permissions → complete)를 따르는지 검증합니다.
    /// - 검증 내용: `OnboardingStep.allCases`가 정식 순서와 일치하고, `nextTapped`가 각 단계를 올바르게 이동합니다.
    ///   미완료 단계에서는 `nextTapped`가 동작하지 않아야(no-op) 합니다.
    /// - 사전 조건: `load`가 `.empty`를 반환합니다. betaAccess는 `.active` 확인 응답으로 완료 처리합니다.
    /// - 기대 결과: welcome → betaAccess 전환 성공, permissions 미완료 시 `nextTapped` no-op, 전체 순서가 `allCases`와 일치합니다.
    /// - 관련 사양: ONB-001-show_onboarding_step
    func testCurrentStepAdvancesThroughCanonicalOrder() async {
        XCTAssertEqual(OnboardingStep.allCases, [.welcome, .betaAccess, .permissions, .complete])

        let store = TestStore(initialState: OnboardingFeature.State()) {
            OnboardingFeature()
        } withDependencies: {
            $0.onboardingProgressClient = OnboardingProgressClient(
                load: { .empty },
                save: { _ in },
                reset: {},
            )
        }

        await store.send(.onAppear)

        // welcome → betaAccess
        await store.send(.nextTapped) { state in
            state.currentStep = .betaAccess
        }

        // beta access를 완료하여 다음 네비게이션 활성화
        await store.send(.betaAccess(.verificationResponse(BetaAccessVerificationResult(status: .active)))) { state in
            state.betaAccess.status = .active
            state.betaAccess.reason = .none
            state.betaAccess.isComplete = true
        }

        // betaAccess → permissions
        await store.send(.nextTapped) { state in
            state.currentStep = .permissions
        }

        // permissions 미완료 — nextTapped는 동작 없음
        await store.send(.nextTapped)

        await store.finish()
    }

    // MARK: - ONB-001-update_onboarding_step_state

    // 단계 상태 업데이트: 자식 액션을 통한 단계 완료 상태 변경, 진행 상태 저장 트리거,
    // 단계별 완료 추적 및 스냅샷 캡처를 검증합니다.

    /// 자식 액션(`.welcome(.setCompleted)`)을 통한 welcome 단계 완료 상태 변경이 올바르게 전파되는지 검증합니다.
    /// - 검증 내용: welcome의 `isComplete`를 끄고 다시 켤 때 `canGoNext`가 그에 맞게 변경됩니다.
    /// - 사전 조건: `onAppear` 후 welcome은 완료 상태입니다.
    /// - 기대 결과: `isComplete = false` 시 `canGoNext = false`, `isComplete = true` 시 `canGoNext = true`로 복원됩니다.
    /// - 관련 사양: ONB-001-update_onboarding_step_state
    func testUpdateWelcomeStepStateViaChildAction() async {
        let store = TestStore(initialState: OnboardingFeature.State()) {
            OnboardingFeature()
        } withDependencies: {
            $0.onboardingProgressClient = OnboardingProgressClient(
                load: { .empty },
                save: { _ in },
                reset: {},
            )
        }

        await store.send(.onAppear)

        // welcome은 완료 상태로 시작; 끄고 다시 켬
        await store.send(.welcome(.setCompleted(false))) { state in
            state.welcome.isComplete = false
        }

        XCTAssertFalse(store.state.welcome.isComplete)
        XCTAssertFalse(store.state.canGoNext) // welcome 미완료 → 다음으로 이동 불가

        await store.send(.welcome(.setCompleted(true))) { state in
            state.welcome.isComplete = true
        }

        XCTAssertTrue(store.state.welcome.isComplete)
        XCTAssertTrue(store.state.canGoNext)

        await store.finish()
    }

    /// betaAccess 단계에서 확인 응답(`.active`) 수신 시 상태가 올바르게 업데이트되는지 검증합니다.
    /// - 검증 내용: `verificationResponse` 액션이 `status`, `reason`, `isComplete`를 올바르게 갱신합니다.
    /// - 사전 조건: `onAppear` 후 betaAccess는 미완료(`.notActive`) 상태입니다.
    /// - 기대 결과: `isComplete = true`, `status = .active`, `reason = .none`으로 변경됩니다.
    /// - 관련 사양: ONB-001-update_onboarding_step_state
    func testUpdateBetaAccessStepStateOnVerification() async {
        let store = TestStore(initialState: OnboardingFeature.State()) {
            OnboardingFeature()
        } withDependencies: {
            $0.onboardingProgressClient = OnboardingProgressClient(
                load: { .empty },
                save: { _ in },
                reset: {},
            )
        }

        await store.send(.onAppear)

        // beta access는 미완료 상태로 시작
        XCTAssertFalse(store.state.betaAccess.isComplete)
        XCTAssertEqual(store.state.betaAccess.status, .notActive)

        // 성공적인 확인이 상태를 업데이트
        await store.send(.betaAccess(.verificationResponse(BetaAccessVerificationResult(status: .active)))) { state in
            state.betaAccess.status = .active
            state.betaAccess.reason = .none
            state.betaAccess.isComplete = true
        }

        XCTAssertTrue(store.state.betaAccess.isComplete)
        XCTAssertEqual(store.state.betaAccess.status, .active)

        await store.finish()
    }

    /// 자식 액션 후 단계 상태 업데이트가 진행 상태 스냅샷 저장을 트리거하는지 검증합니다.
    /// - 검증 내용: betaAccess 확인 응답 처리 후 `save()`가 호출되고 업데이트된 단계 상태를 반영합니다.
    /// - 사전 조건: `saveRecorder`로 저장 호출을 캡처합니다. 초기 상태에서 betaAccess 확인 응답을 전송합니다.
    /// - 기대 결과: 저장된 스냅샷의 `betaAccessComplete`이 `true`입니다.
    /// - 관련 사양: ONB-001-update_onboarding_step_state
    func testStepStateUpdateTriggersProgressSave() async {
        let saveRecorder = LockIsolated<OnboardingProgressSnapshot?>(nil)

        let store = TestStore(initialState: OnboardingFeature.State()) {
            OnboardingFeature()
        } withDependencies: {
            $0.onboardingProgressClient = OnboardingProgressClient(
                load: { .empty },
                save: { snapshot in saveRecorder.setValue(snapshot) },
                reset: {},
            )
        }

        await store.send(.betaAccess(.verificationResponse(BetaAccessVerificationResult(status: .active)))) { state in
            state.betaAccess.status = .active
            state.betaAccess.reason = .none
            state.betaAccess.isComplete = true
        }

        // 업데이트된 스냅샷으로 save가 호출되어야 함
        let saved = saveRecorder.value
        XCTAssertNotNil(saved)
        // swiftlint:disable:next force_unwrapping
        XCTAssertTrue(saved!.stepState.betaAccessComplete)

        await store.finish()
    }

    /// `isStepComplete`가 각 단계별로 완료 상태를 올바르게 추적하는지 검증합니다.
    /// - 검증 내용: 기본 상태에서 welcome만 완료이고, 각 단계를 수동 완료할 때마다 추적이 갱신됩니다.
    /// - 사전 조건: 기본 `OnboardingFeature.State`에서 시작합니다.
    /// - 기대 결과: welcome은 기본 완료, betaAccess/permissions/complete는 미완료,
    ///   각각 `isComplete = true` 설정 후 해당 단계 완료로 추적됩니다.
    /// - 관련 사양: ONB-001-update_onboarding_step_state
    func testStepStateTracksCompletionPerStep() {
        var state = OnboardingFeature.State()

        XCTAssertTrue(state.isStepComplete(.welcome))
        XCTAssertFalse(state.isStepComplete(.betaAccess))
        XCTAssertFalse(state.isStepComplete(.permissions))
        XCTAssertFalse(state.isStepComplete(.complete))

        state.betaAccess.isComplete = true
        XCTAssertTrue(state.isStepComplete(.betaAccess))

        state.permissions.isComplete = true
        XCTAssertTrue(state.isStepComplete(.permissions))

        state.complete.isComplete = true
        XCTAssertTrue(state.isStepComplete(.complete))
    }

    /// `progressSnapshot`이 모든 4개 단계의 완료 플래그를 정확히 캡처하는지 검증합니다.
    /// - 검증 내용: 수동으로 설정한 단계 상태가 스냅샷 생성 시 그대로 반영됩니다.
    /// - 사전 조건: `currentStep = .permissions`, `betaAccess.isComplete = true`, `permissions.isComplete = true`입니다.
    /// - 기대 결과: 스냅샷의 `currentStep`은 `.permissions`, `welcomeComplete`/`betaAccessComplete`/`permissionsComplete`은
    /// `true`,
    ///   `completeComplete`은 `false`입니다.
    /// - 관련 사양: ONB-001-update_onboarding_step_state
    func testProgressSnapshotCapturesAllStepStates() {
        var state = OnboardingFeature.State()
        state.currentStep = .permissions
        state.betaAccess.isComplete = true
        state.permissions.isComplete = true

        let snapshot = state.progressSnapshot

        XCTAssertEqual(snapshot.currentStep, .permissions)
        XCTAssertTrue(snapshot.stepState.welcomeComplete)
        XCTAssertTrue(snapshot.stepState.betaAccessComplete)
        XCTAssertTrue(snapshot.stepState.permissionsComplete)
        XCTAssertFalse(snapshot.stepState.completeComplete)
    }

    // MARK: - ONB-001-advance_onboarding_step

    // 단계 앞으로 이동: nextTapped를 통한 단계 전환, 완료 전제 조건, 마지막 단계 제한,
    // 이동 시 진행 상태 저장을 검증합니다.

    /// `nextTapped`와 `backTapped`를 통한 앞/뒤 네비게이션이 모두 정상 동작하는지 검증합니다.
    /// - 검증 내용: welcome → betaAccess → permissions로 앞으로 이동 후 betaAccess로 뒤로 이동합니다.
    ///   미완료 betaAccess에서 `nextTapped`는 no-op입니다.
    /// - 사전 조건: `load`가 `.empty`를 반환합니다. betaAccess는 `.active` 확인 응답으로 완료 처리합니다.
    /// - 기대 결과: 단계 전환이 정확한 순서대로 발생하고 뒤로 이동도 올바르게 동작합니다.
    /// - 관련 사양: ONB-001-advance_onboarding_step, ONB-001-go_back_onboarding_step
    func testNextBackNavigation() async {
        let store = TestStore(initialState: OnboardingFeature.State()) {
            OnboardingFeature()
        } withDependencies: {
            $0.onboardingProgressClient = OnboardingProgressClient(
                load: { .empty },
                save: { _ in },
                reset: {},
            )
        }

        await store.send(.onAppear)

        await store.send(.nextTapped) { state in
            state.currentStep = .betaAccess
        }

        await store.send(.nextTapped)

        await store.send(.betaAccess(.verificationResponse(BetaAccessVerificationResult(status: .active)))) { state in
            state.betaAccess.status = .active
            state.betaAccess.reason = .none
            state.betaAccess.isComplete = true
        }

        await store.send(.nextTapped) { state in
            state.currentStep = .permissions
        }

        await store.send(.backTapped) { state in
            state.currentStep = .betaAccess
        }

        await store.finish()
    }

    /// 현재 단계가 완료되어야만 `nextTapped`로 다음 단계로 이동할 수 있음을 검증합니다.
    /// - 검증 내용: 미완료 단계에서 `nextTapped`는 아무 상태 변화도 일으키지 않아야(no-op) 합니다.
    /// - 사전 조건: `currentStep = .betaAccess`, `betaAccess.isComplete = false` 상태입니다.
    /// - 기대 결과: `canGoNext`는 `false`, `nextTapped` 후에도 여전히 `currentStep = .betaAccess`입니다.
    /// - 관련 사양: ONB-001-advance_onboarding_step
    func testAdvanceRequiresCurrentStepComplete() async {
        var initialState = OnboardingFeature.State()
        initialState.currentStep = .betaAccess
        // betaAccess가 완료되지 않음

        let store = TestStore(initialState: initialState) {
            OnboardingFeature()
        } withDependencies: {
            $0.onboardingProgressClient = OnboardingProgressClient(
                load: { .empty },
                save: { _ in },
                reset: {},
            )
        }

        XCTAssertFalse(store.state.canGoNext)

        // betaAccess가 완료되지 않았으므로 nextTapped는 동작 없음
        await store.send(.nextTapped)

        // 여전히 betaAccess에 있음
        XCTAssertEqual(store.state.currentStep, .betaAccess)

        await store.finish()
    }

    /// 마지막 단계(complete)에서는 `nextTapped`로 더 이상 앞으로 이동할 수 없음을 검증합니다.
    /// - 검증 내용: complete 단계는 `currentStep.next`가 `nil`이며 `nextTapped`가 no-op입니다.
    /// - 사전 조건: `currentStep = .complete` 상태입니다.
    /// - 기대 결과: `canGoNext`는 `false`, `nextTapped` 후에도 `currentStep = .complete`입니다.
    /// - 관련 사양: ONB-001-advance_onboarding_step
    func testCannotAdvanceBeyondCompleteStep() async {
        var initialState = OnboardingFeature.State()
        initialState.currentStep = .complete

        let store = TestStore(initialState: initialState) {
            OnboardingFeature()
        } withDependencies: {
            $0.onboardingProgressClient = OnboardingProgressClient(
                load: { .empty },
                save: { _ in },
                reset: {},
            )
        }

        XCTAssertNil(store.state.currentStep.next)
        XCTAssertFalse(store.state.canGoNext)

        await store.send(.nextTapped)

        XCTAssertEqual(store.state.currentStep, .complete)

        await store.finish()
    }

    /// 단계 이동 시 진행 상태 스냅샷이 저장되어 새 단계가 반영되는지 검증합니다.
    /// - 검증 내용: `nextTapped` 후 `save()`가 호출되고 갱신된 `currentStep`이 스냅샷에 반영됩니다.
    /// - 사전 조건: `saveRecorder`로 저장 호출을 캡처합니다. `onAppear` 후 welcome 단계입니다.
    /// - 기대 결과: `nextTapped` 후 저장된 스냅샷의 `currentStep`이 `.betaAccess`입니다.
    /// - 관련 사양: ONB-001-advance_onboarding_step
    func testAdvanceStepPersistsProgress() async {
        let saveRecorder = LockIsolated<OnboardingProgressSnapshot?>(nil)

        let store = TestStore(initialState: OnboardingFeature.State()) {
            OnboardingFeature()
        } withDependencies: {
            $0.onboardingProgressClient = OnboardingProgressClient(
                load: { .empty },
                save: { snapshot in saveRecorder.setValue(snapshot) },
                reset: {},
            )
        }

        await store.send(.onAppear)
        await store.send(.nextTapped) { state in
            state.currentStep = .betaAccess
        }

        let saved = saveRecorder.value
        XCTAssertNotNil(saved)
        XCTAssertEqual(saved?.currentStep, .betaAccess)

        await store.finish()
    }

    // MARK: - ONB-001-go_back_onboarding_step

    // 단계 뒤로 이동: backTapped를 통한 이전 단계 복귀, 첫 단계 제한,
    // 완료 상태 보존 및 진행 상태 저장을 검증합니다.

    /// 첫 번째 단계(welcome)에서는 `backTapped`로 뒤로 이동할 수 없음을 검증합니다.
    /// - 검증 내용: welcome에서 `backTapped`는 no-op이며 단계가 유지됩니다.
    /// - 사전 조건: `onAppear` 후 `currentStep = .welcome`, `canGoBack = false` 상태입니다.
    /// - 기대 결과: `backTapped` 후에도 `currentStep = .welcome`입니다.
    /// - 관련 사양: ONB-001-go_back_onboarding_step
    func testCannotGoBackFromWelcomeStep() async {
        let store = TestStore(initialState: OnboardingFeature.State()) {
            OnboardingFeature()
        } withDependencies: {
            $0.onboardingProgressClient = OnboardingProgressClient(
                load: { .empty },
                save: { _ in },
                reset: {},
            )
        }

        await store.send(.onAppear)

        XCTAssertFalse(store.state.canGoBack)

        // welcome에서 backTapped는 동작 없음
        await store.send(.backTapped)

        XCTAssertEqual(store.state.currentStep, .welcome)

        await store.finish()
    }

    /// 뒤로 이동 시 이미 완료된 단계의 완료 상태가 보존됨을 검증합니다.
    /// - 검증 내용: permissions → betaAccess → welcome으로 뒤로 이동해도 각 단계의 `isComplete`와 `status`가 유지됩니다.
    /// - 사전 조건: `currentStep = .permissions`, welcome/betaAccess 모두 완료(`.active`) 상태입니다.
    /// - 기대 결과: 두 번의 `backTapped` 후에도 welcome/betaAccess의 완료 상태와 betaAccess의 `.active` 상태가 보존됩니다.
    /// - 관련 사양: ONB-001-go_back_onboarding_step
    func testGoBackPreservesStepCompletionState() async {
        var initialState = OnboardingFeature.State()
        initialState.currentStep = .permissions
        initialState.welcome.isComplete = true
        initialState.betaAccess.status = .active
        initialState.betaAccess.reason = .none
        initialState.betaAccess.isComplete = true

        let store = TestStore(initialState: initialState) {
            OnboardingFeature()
        } withDependencies: {
            $0.onboardingProgressClient = OnboardingProgressClient(
                load: { .empty },
                save: { _ in },
                reset: {},
            )
        }

        // permissions → betaAccess로 뒤로 이동
        await store.send(.backTapped) { state in
            state.currentStep = .betaAccess
        }

        // 단계 완료 상태가 보존됨
        XCTAssertTrue(store.state.welcome.isComplete)
        XCTAssertTrue(store.state.betaAccess.isComplete)
        XCTAssertEqual(store.state.betaAccess.status, .active)

        // betaAccess → welcome으로 뒤로 이동
        await store.send(.backTapped) { state in
            state.currentStep = .welcome
        }

        XCTAssertTrue(store.state.welcome.isComplete)
        XCTAssertTrue(store.state.betaAccess.isComplete)

        await store.finish()
    }

    /// 뒤로 이동 시 진행 상태 스냅샷이 저장되어 이전 단계가 반영됨을 검증합니다.
    /// - 검증 내용: `backTapped` 후 `save()`가 호출되고 스냅샷의 `currentStep`이 이전 단계로 갱신됩니다.
    /// - 사전 조건: `currentStep = .betaAccess`, `welcome.isComplete = true`, `saveRecorder`로 저장 호출을 캡처합니다.
    /// - 기대 결과: `backTapped` 후 저장된 스냅샷의 `currentStep`이 `.welcome`입니다.
    /// - 관련 사양: ONB-001-go_back_onboarding_step
    func testGoBackPersistsProgress() async {
        let saveRecorder = LockIsolated<OnboardingProgressSnapshot?>(nil)

        var initialState = OnboardingFeature.State()
        initialState.currentStep = .betaAccess
        initialState.welcome.isComplete = true

        let store = TestStore(initialState: initialState) {
            OnboardingFeature()
        } withDependencies: {
            $0.onboardingProgressClient = OnboardingProgressClient(
                load: { .empty },
                save: { snapshot in saveRecorder.setValue(snapshot) },
                reset: {},
            )
        }

        await store.send(.backTapped) { state in
            state.currentStep = .welcome
        }

        let saved = saveRecorder.value
        XCTAssertNotNil(saved)
        XCTAssertEqual(saved?.currentStep, .welcome)

        await store.finish()
    }

    // MARK: - ONB-001-resume_onboarding_session

    // 세션 이어서 진행: 저장된 스냅샷에서 세션 복원, 미완료 단계의 fallback-to-last-valid-step,
    // 리셋 필요 시 세션 초기화, 복원 후 스냅샷 저장을 검증합니다.

    /// 저장된 스냅샷에서 세션을 이어서 진행할 때 상태가 올바르게 복원되는지 검증합니다.
    /// - 검증 내용: `load`가 `.success(snapshot)`를 반환하면 reducer가 스냅샷 기반으로 상태를 복원합니다.
    /// - 사전 조건: snapshot에 `currentStep = .permissions`, welcome/betaAccess 완료, permissions/complete 미완료가 저장되어 있습니다.
    /// - 기대 결과: `onAppear` 후 마지막 완료 단계인 `.betaAccess`로 복원되고,
    ///   welcome/betaAccess는 완료, permissions/complete는 미완료 상태입니다.
    /// - 관련 사양: ONB-001-resume_onboarding_session
    func testResumeFromPersistedState() async {
        let snapshot = OnboardingProgressSnapshot(
            currentStep: .permissions,
            stepState: OnboardingStepState(
                welcomeComplete: true,
                betaAccessComplete: true,
                permissionsComplete: false,
                completeComplete: false,
            ),
        )

        let store = TestStore(initialState: OnboardingFeature.State()) {
            OnboardingFeature()
        } withDependencies: {
            $0.onboardingProgressClient = OnboardingProgressClient(
                load: { .success(snapshot) },
                save: { _ in },
                reset: {},
            )
        }

        await store.send(.onAppear) { state in
            state.currentStep = .betaAccess
            state.welcome.isComplete = true
            state.betaAccess.status = .active
            state.betaAccess.reason = .none
            state.betaAccess.isComplete = true
            state.permissions.isComplete = false
            state.complete.isComplete = false
        }

        await store.finish()
    }

    /// 저장된 `currentStep`은 유효하지만 해당 단계가 미완료인 스냅샷으로 이어서 진행 시
    /// 마지막 유효한 완료 단계로 대체(fallback-to-last-valid-step)됨을 검증합니다.
    /// - 검증 내용: `currentStep = .permissions`이지만 betaAccess가 미완료이면 welcome으로 되돌아갑니다.
    /// - 사전 조건: snapshot에 `permissions`가 currentStep이지만 betaAccess/permissions 미완료입니다.
    ///   초기 상태를 `.complete`/완료로 설정하여 mutation 관찰이 가능합니다.
    /// - 기대 결과: `onAppear` 후 `currentStep = .welcome`, `complete.isComplete = false`로 복원됩니다.
    /// - 관련 사양: ONB-001-resume_onboarding_session
    func testResumeWithIncompleteCurrentStepFallsBack() async {
        let snapshot = OnboardingProgressSnapshot(
            currentStep: .permissions,
            stepState: OnboardingStepState(
                welcomeComplete: true,
                betaAccessComplete: false,
                permissionsComplete: false,
                completeComplete: false,
            ),
        )

        // 이어서 진행 mutation을 관찰 가능하도록 비기본 초기 상태로 시작
        var initialState = OnboardingFeature.State()
        initialState.currentStep = .complete
        initialState.complete.isComplete = true

        let store = TestStore(initialState: initialState) {
            OnboardingFeature()
        } withDependencies: {
            $0.onboardingProgressClient = OnboardingProgressClient(
                load: { .success(snapshot) },
                save: { _ in },
                reset: {},
            )
        }

        // permissions 미완료 → lastValidStep이 welcome으로 되돌아감
        await store.send(.onAppear) { state in
            state.currentStep = .welcome
            state.complete.isComplete = false
        }

        XCTAssertEqual(store.state.currentStep, .welcome)

        await store.finish()
    }

    /// complete 이전의 모든 단계가 완료된 상태로 이어서 진행 시
    /// 마지막 완료 단계인 permissions에 위치해야 함을 검증합니다.
    /// - 검증 내용: `currentStep = .complete`이지만 `complete` 미완료 시 `permissions`로 fallback합니다.
    /// - 사전 조건: snapshot에 welcome/betaAccess/permissions 완료, `completeComplete = false`가 저장되어 있습니다.
    /// - 기대 결과: `onAppear` 후 `currentStep = .permissions`, 모든 선행 단계는 완료, `complete.isComplete = false`입니다.
    /// - 관련 사양: ONB-001-resume_onboarding_session
    func testResumeWithCompletedPriorSteps() async {
        let snapshot = OnboardingProgressSnapshot(
            currentStep: .complete,
            stepState: OnboardingStepState(
                welcomeComplete: true,
                betaAccessComplete: true,
                permissionsComplete: true,
                completeComplete: false,
            ),
        )

        let store = TestStore(initialState: OnboardingFeature.State()) {
            OnboardingFeature()
        } withDependencies: {
            $0.onboardingProgressClient = OnboardingProgressClient(
                load: { .success(snapshot) },
                save: { _ in },
                reset: {},
            )
        }

        // complete 미완료 → lastValidStep이 permissions(완료됨)로 되돌아감
        await store.send(.onAppear) { state in
            state.currentStep = .permissions
            state.welcome.isComplete = true
            state.betaAccess.status = .active
            state.betaAccess.reason = .none
            state.betaAccess.isComplete = true
            state.permissions.isComplete = true
            state.complete.isComplete = false
        }

        XCTAssertEqual(store.state.currentStep, .permissions)

        await store.finish()
    }

    /// 저장된 스냅샷에서 welcome만 완료된 경우 welcome 단계가 표시되어야 함을 검증합니다.
    /// - 검증 내용: betaAccess 미완료 시 fallback-to-last-valid-step이 welcome을 선택합니다.
    /// - 사전 조건: snapshot에 `currentStep = .betaAccess`, welcome만 완료, 나머지 미완료입니다.
    ///   초기 상태를 `.complete`/완료로 설정하여 mutation 관찰이 가능합니다.
    /// - 기대 결과: `onAppear` 후 `currentStep = .welcome`, `complete.isComplete = false`로 복원됩니다.
    /// - 관련 사양: ONB-001-resume_onboarding_session
    func testResumeWithOnlyWelcomeComplete() async {
        let snapshot = OnboardingProgressSnapshot(
            currentStep: .betaAccess,
            stepState: OnboardingStepState(
                welcomeComplete: true,
                betaAccessComplete: false,
                permissionsComplete: false,
                completeComplete: false,
            ),
        )

        // 이어서 진행 mutation을 관찰 가능하도록 비기본 초기 상태로 시작
        var initialState = OnboardingFeature.State()
        initialState.currentStep = .complete
        initialState.complete.isComplete = true

        let store = TestStore(initialState: initialState) {
            OnboardingFeature()
        } withDependencies: {
            $0.onboardingProgressClient = OnboardingProgressClient(
                load: { .success(snapshot) },
                save: { _ in },
                reset: {},
            )
        }

        // betaAccess 미완료 → welcome(완료됨)으로 대체
        await store.send(.onAppear) { state in
            state.currentStep = .welcome
            state.complete.isComplete = false
        }

        XCTAssertEqual(store.state.currentStep, .welcome)

        await store.finish()
    }

    /// 이어서 진행 시 단계 상태 적용 후 업데이트된 스냅샷이 저장됨을 검증합니다.
    /// - 검증 내용: 복원된 상태(보정된 단계 포함)가 `save()`를 통해 올바르게 저장됩니다.
    /// - 사전 조건: snapshot에 `currentStep = .permissions`, welcome/betaAccess 완료가 저장되어 있습니다.
    ///   `saveRecorder`로 저장 호출을 캡처합니다.
    /// - 기대 결과: 저장된 스냅샷의 `currentStep`이 보정된 `.betaAccess`(permissions 아님)를 반영합니다.
    /// - 관련 사양: ONB-001-resume_onboarding_session
    func testResumeSavesUpdatedSnapshot() async {
        let saveRecorder = LockIsolated<OnboardingProgressSnapshot?>(nil)
        let snapshot = OnboardingProgressSnapshot(
            currentStep: .permissions,
            stepState: OnboardingStepState(
                welcomeComplete: true,
                betaAccessComplete: true,
                permissionsComplete: false,
                completeComplete: false,
            ),
        )

        let store = TestStore(initialState: OnboardingFeature.State()) {
            OnboardingFeature()
        } withDependencies: {
            $0.onboardingProgressClient = OnboardingProgressClient(
                load: { .success(snapshot) },
                save: { snapshot in saveRecorder.setValue(snapshot) },
                reset: {},
            )
        }

        await store.send(.onAppear) { state in
            state.currentStep = .betaAccess
            state.welcome.isComplete = true
            state.betaAccess.status = .active
            state.betaAccess.reason = .none
            state.betaAccess.isComplete = true
            state.permissions.isComplete = false
            state.complete.isComplete = false
        }

        let saved = saveRecorder.value
        XCTAssertNotNil(saved)
        // 저장된 스냅샷은 보정된 단계(betaAccess, permissions 아님)를 반영해야 함
        XCTAssertEqual(saved?.currentStep, .betaAccess)

        await store.finish()
    }

    /// `load`가 `.resetRequired`를 반환하면 상태가 welcome으로 초기화되고 새 스냅샷이 저장됨을 검증합니다.
    /// - 검증 내용: 손상되거나 호환되지 않는 진행 상태를 감지하면 세션을 완전히 리셋합니다.
    /// - 사전 조건: `load`가 `.resetRequired`를 반환합니다. `snapshotRecorder`로 저장된 스냅샷을 캡처합니다.
    /// - 기대 결과: `currentStep = .welcome`, welcome만 완료, 저장된 스냅샷도 동일한 초기 상태를 반영합니다.
    /// - 관련 사양: ONB-001-resume_onboarding_session
    func testResumeFromCorruptStepStateFallsBackToWelcome() async {
        let snapshotRecorder = SnapshotRecorder()

        let store = TestStore(initialState: OnboardingFeature.State()) {
            OnboardingFeature()
        } withDependencies: {
            $0.onboardingProgressClient = OnboardingProgressClient(
                load: { .resetRequired },
                save: { snapshot in
                    Task { await snapshotRecorder.set(snapshot) }
                },
                reset: {},
            )
        }

        await store.send(.onAppear)

        XCTAssertEqual(store.state.currentStep, .welcome)
        XCTAssertTrue(store.state.welcome.isComplete)
        XCTAssertFalse(store.state.betaAccess.isComplete)

        let saved = await snapshotRecorder.value
        XCTAssertNotNil(saved)
        XCTAssertEqual(saved?.currentStep, .welcome)
        XCTAssertEqual(saved?.stepState.welcomeComplete, true)
        XCTAssertEqual(saved?.stepState.betaAccessComplete, false)

        await store.finish()
    }

    /// 스냅샷에 유효한 단계(`.complete`)가 있지만 선행 조건이 미완료면
    /// 마지막 유효 단계로 대체됨을 검증합니다.
    /// - 검증 내용: complete/betaAccess/permissions가 모두 미완료이면 welcome으로 fallback합니다.
    /// - 사전 조건: snapshot에 `currentStep = .complete`, welcome만 완료, 나머지 미완료가 저장되어 있습니다.
    /// - 기대 결과: `onAppear` 후 `currentStep = .welcome`, welcome만 완료, betaAccess 미완료입니다.
    /// - 관련 사양: ONB-001-resume_onboarding_session
    func testResumeFromUnknownStepFallsBackToLastValidStep() async {
        let snapshot = OnboardingProgressSnapshot(
            currentStep: .complete,
            stepState: OnboardingStepState(
                welcomeComplete: true,
                betaAccessComplete: false,
                permissionsComplete: false,
                completeComplete: false,
            ),
        )

        let store = TestStore(initialState: OnboardingFeature.State()) {
            OnboardingFeature()
        } withDependencies: {
            $0.onboardingProgressClient = OnboardingProgressClient(
                load: { .success(snapshot) },
                save: { _ in },
                reset: {},
            )
        }

        // complete ✗ → permissions ✗ → betaAccess ✗ → welcome ✓
        // 적용된 상태가 기본값과 동일하므로 클로저 불필요
        await store.send(.onAppear)

        XCTAssertEqual(store.state.currentStep, .welcome)
        XCTAssertTrue(store.state.isStepComplete(.welcome))
        XCTAssertFalse(store.state.isStepComplete(.betaAccess))

        await store.finish()
    }

    // MARK: - ONB-001-complete_onboarding_session

    // 세션 완료: startUsingTapped를 통한 완료 처리, 메인 창 열기, 진행 상태 저장,
    // 재진입 시 세션 스킵, 실패/재시도/멱등성을 검증합니다.

    /// 세션 완료 시 메인 창이 열리고 진행 상태가 저장되는지 검증합니다.
    /// - 검증 내용: `startUsingTapped`가 `isComplete`, `isOpeningWindow`를 설정하고
    ///   `openWindowResponse` 수신 후 메인 창 경로가 기록되며 `completeComplete`이 저장됩니다.
    /// - 사전 조건: `currentStep = .complete` 상태입니다. `snapshotRecorder`와 `pathRecorder`로
    ///   저장/열기 호출을 캡처합니다.
    /// - 기대 결과: 창이 `.defaultTabPath`로 1회 열리고, 저장된 스냅샷의 `completeComplete`이 `true`입니다.
    /// - 관련 사양: ONB-001-complete_onboarding_session
    func testCompleteOpensWindowAndSavesProgress() async {
        let snapshotRecorder = SnapshotRecorder()
        let pathRecorder = PathRecorder()

        var initialState = OnboardingFeature.State()
        initialState.currentStep = .complete

        let store = TestStore(initialState: initialState) {
            OnboardingFeature()
        } withDependencies: {
            $0.onboardingProgressClient = OnboardingProgressClient(
                load: { .empty },
                save: { snapshot in
                    Task {
                        await snapshotRecorder.set(snapshot)
                    }
                },
                reset: {},
            )
            $0.onboardingWindowClient = OnboardingWindowClient(
                isRequired: { false },
                showIfNeeded: { false },
                showWindow: {},
                closeWindow: {},
                openMainWindow: { request in
                    await pathRecorder.append(request)
                    return true
                },
            )
        }

        await store.send(.complete(.startUsingTapped)) { state in
            state.complete.isComplete = true
            state.complete.isOpeningWindow = true
            state.complete.openWindowError = nil
        }

        await store.receive(\.complete.openWindowResponse) { state in
            state.complete.isOpeningWindow = false
        }

        let openedPaths = await pathRecorder.snapshot()
        XCTAssertEqual(openedPaths.count, 1)
        XCTAssertEqual(openedPaths[0], .defaultTabPath)
        let savedSnapshot = await snapshotRecorder.value
        XCTAssertEqual(savedSnapshot?.stepState.completeComplete, true)
        await store.finish()
    }

    /// 세션 완료 후 재진입 시 이어서 진행 세션이 완료된 상태로 건너뜀을 검증합니다.
    /// - 검증 내용: 모든 단계가 완료된 스냅샷이 저장되어 있으면 `onAppear` 시 바로 complete 상태로 복원됩니다.
    /// - 사전 조건: snapshot에 모든 단계가 완료(`completeComplete = true`)로 저장되어 있습니다.
    /// - 기대 결과: `onAppear` 후 모든 단계가 완료 상태, `currentStep = .complete`로 복원됩니다.
    /// - 관련 사양: ONB-001-complete_onboarding_session
    func testResumeSkipsBannerWhenCompleted() async {
        let snapshot = OnboardingProgressSnapshot(
            currentStep: .complete,
            stepState: OnboardingStepState(
                welcomeComplete: true,
                betaAccessComplete: true,
                permissionsComplete: true,
                completeComplete: true,
            ),
        )

        let store = TestStore(initialState: OnboardingFeature.State()) {
            OnboardingFeature()
        } withDependencies: {
            $0.onboardingProgressClient = OnboardingProgressClient(
                load: { .success(snapshot) },
                save: { _ in },
                reset: {},
            )
        }

        await store.send(.onAppear) { state in
            state.currentStep = .complete
            state.welcome.isComplete = true
            state.betaAccess.status = .active
            state.betaAccess.reason = .none
            state.betaAccess.isComplete = true
            state.permissions.isComplete = true
            state.complete.isComplete = true
        }

        await store.finish()
    }

    /// 완료 시 모든 단계가 완료로 표시된 스냅샷이 저장되는지 검증합니다.
    /// - 검증 내용: `startUsingTapped` 후 `save()`가 호출되고 `completeComplete`과 `currentStep`이 올바르게 저장됩니다.
    /// - 사전 조건: `currentStep = .complete` 상태입니다. `snapshotRecorder`로 저장된 스냅샷을 캡처합니다.
    /// - 기대 결과: 저장된 스냅샷의 `completeComplete = true`, `currentStep = .complete`입니다.
    /// - 관련 사양: ONB-001-complete_onboarding_session
    func testCompletionSavesCompleteStepState() async {
        let snapshotRecorder = SnapshotRecorder()

        var initialState = OnboardingFeature.State()
        initialState.currentStep = .complete

        let store = TestStore(initialState: initialState) {
            OnboardingFeature()
        } withDependencies: {
            $0.onboardingProgressClient = OnboardingProgressClient(
                load: { .empty },
                save: { snapshot in
                    Task { await snapshotRecorder.set(snapshot) }
                },
                reset: {},
            )
            $0.onboardingWindowClient = OnboardingWindowClient(
                isRequired: { false },
                showIfNeeded: { false },
                showWindow: {},
                closeWindow: {},
                openMainWindow: { _ in true },
            )
        }

        await store.send(.complete(.startUsingTapped)) { state in
            state.complete.isComplete = true
            state.complete.isOpeningWindow = true
            state.complete.openWindowError = nil
        }

        await store.receive(\.complete.openWindowResponse) { state in
            state.complete.isOpeningWindow = false
        }

        let saved = await snapshotRecorder.value
        XCTAssertNotNil(saved)
        XCTAssertEqual(saved?.stepState.completeComplete, true)
        XCTAssertEqual(saved?.currentStep, .complete)

        await store.finish()
    }

    /// `startUsingTapped`를 두 번 호출하면 창이 두 번 열리는지(reducer에 멱등성 가드 없음) 검증합니다.
    /// - 검증 내용: 연속 탭 시 reducer가 전체 완료 흐름을 반복 실행합니다.
    /// - 사전 조건: `currentStep = .complete` 상태입니다. `pathRecorder`로 창 열기 호출을 캡처합니다.
    /// - 기대 결과: `pathRecorder`에 2개의 경로가 기록되어 창이 각 탭마다 열렸음을 확인합니다.
    /// - 관련 사양: ONB-001-complete_onboarding_session
    func testCompletionRepeatedTapReopensWindow() async {
        let pathRecorder = PathRecorder()

        var initialState = OnboardingFeature.State()
        initialState.currentStep = .complete

        let store = TestStore(initialState: initialState) {
            OnboardingFeature()
        } withDependencies: {
            $0.onboardingProgressClient = OnboardingProgressClient(
                load: { .empty },
                save: { _ in },
                reset: {},
            )
            $0.onboardingWindowClient = OnboardingWindowClient(
                isRequired: { false },
                showIfNeeded: { false },
                showWindow: {},
                closeWindow: {},
                openMainWindow: { request in
                    await pathRecorder.append(request)
                    return true
                },
            )
        }

        // 첫 번째 완료
        await store.send(.complete(.startUsingTapped)) { state in
            state.complete.isComplete = true
            state.complete.isOpeningWindow = true
            state.complete.openWindowError = nil
        }
        await store.receive(\.complete.openWindowResponse) { state in
            state.complete.isOpeningWindow = false
        }

        // 두 번째 호출 — reducer가 전체 흐름 반복
        await store.send(.complete(.startUsingTapped)) { state in
            state.complete.isComplete = true
            state.complete.isOpeningWindow = true
            state.complete.openWindowError = nil
        }
        await store.receive(\.complete.openWindowResponse) { state in
            state.complete.isOpeningWindow = false
        }

        let paths = await pathRecorder.snapshot()
        XCTAssertEqual(paths.count, 2, "Window opened on each tap")

        await store.finish()
    }

    /// `openMainWindow`가 `false`를 반환하면 에러 상태가 설정됨을 검증합니다.
    /// - 검증 내용: 창 열기 실패 시 `openWindowError`에 사용자 친화적 메시지가 설정됩니다.
    /// - 사전 조건: `currentStep = .complete` 상태입니다. `openMainWindow`가 항상 `false`를 반환합니다.
    /// - 기대 결과: `openWindowResponse` 수신 후 `isOpeningWindow = false`,
    ///   `openWindowError`에 에러 메시지가 설정됩니다.
    /// - 관련 사양: ONB-001-complete_onboarding_session
    func testCompletionOpenWindowFailureShowsError() async {
        var initialState = OnboardingFeature.State()
        initialState.currentStep = .complete

        let store = TestStore(initialState: initialState) {
            OnboardingFeature()
        } withDependencies: {
            $0.onboardingProgressClient = OnboardingProgressClient(
                load: { .empty },
                save: { _ in },
                reset: {},
            )
            $0.onboardingWindowClient = OnboardingWindowClient(
                isRequired: { false },
                showIfNeeded: { false },
                showWindow: {},
                closeWindow: {},
                openMainWindow: { _ in false },
            )
        }

        await store.send(.complete(.startUsingTapped)) { state in
            state.complete.isComplete = true
            state.complete.isOpeningWindow = true
            state.complete.openWindowError = nil
        }

        await store.receive(\.complete.openWindowResponse) { state in
            state.complete.isOpeningWindow = false
            state.complete.openWindowError = "We couldn't open a file manager window. Please try again."
        }

        XCTAssertNotNil(store.state.complete.openWindowError)
        XCTAssertFalse(store.state.complete.isOpeningWindow)

        await store.finish()
    }

    /// 완료 실패 경로 — `openMainWindow`가 `false`를 반환하고 에러가 설정됨을 검증합니다.
    /// - 검증 내용: `testCompletionOpenWindowFailureShowsError`와 동일한 시나리오의 독립 검증입니다.
    /// - 사전 조건: `currentStep = .complete` 상태입니다. `openMainWindow`가 항상 `false`를 반환합니다.
    /// - 기대 결과: `openWindowResponse` 수신 후 `openWindowError`가 `nil`이 아닙니다.
    /// - 관련 사양: ONB-001-complete_onboarding_session
    func testCompletionFailurePath() async {
        var initialState = OnboardingFeature.State()
        initialState.currentStep = .complete

        let store = TestStore(initialState: initialState) {
            OnboardingFeature()
        } withDependencies: {
            $0.onboardingProgressClient = OnboardingProgressClient(
                load: { .empty },
                save: { _ in },
                reset: {},
            )
            $0.onboardingWindowClient = OnboardingWindowClient(
                isRequired: { false },
                showIfNeeded: { false },
                showWindow: {},
                closeWindow: {},
                openMainWindow: { _ in false },
            )
        }

        await store.send(.complete(.startUsingTapped)) { state in
            state.complete.isComplete = true
            state.complete.isOpeningWindow = true
            state.complete.openWindowError = nil
        }

        await store.receive(\.complete.openWindowResponse) { state in
            state.complete.isOpeningWindow = false
            state.complete.openWindowError = "We couldn't open a file manager window. Please try again."
        }

        XCTAssertNotNil(store.state.complete.openWindowError)

        await store.finish()
    }

    /// 완료 실패 후 `retryTapped`가 창 열기를 재시도하는지 검증합니다.
    /// - 검증 내용: 에러 상태에서 재시도 시 `openWindowError`가 초기화되고 창이 다시 열립니다.
    /// - 사전 조건: `currentStep = .complete`, `isComplete = true`,
    ///   `openWindowError`에 기존 에러 메시지가 설정되어 있습니다.
    /// - 기대 결과: 재시도 성공 후 `openWindowError = nil`, `pathRecorder`에 1개의 경로가 기록됩니다.
    /// - 관련 사양: ONB-001-complete_onboarding_session
    func testCompletionRetryAfterFailure() async {
        let pathRecorder = PathRecorder()
        var initialState = OnboardingFeature.State()
        initialState.currentStep = .complete
        initialState.complete.isComplete = true
        initialState.complete.openWindowError = "We couldn't open a file manager window. Please try again."

        let store = TestStore(initialState: initialState) {
            OnboardingFeature()
        } withDependencies: {
            $0.onboardingProgressClient = OnboardingProgressClient(
                load: { .empty },
                save: { _ in },
                reset: {},
            )
            $0.onboardingWindowClient = OnboardingWindowClient(
                isRequired: { false },
                showIfNeeded: { false },
                showWindow: {},
                closeWindow: {},
                openMainWindow: { request in
                    await pathRecorder.append(request)
                    return true
                },
            )
        }

        await store.send(.complete(.retryTapped)) { state in
            state.complete.isOpeningWindow = true
            state.complete.openWindowError = nil
        }

        await store.receive(\.complete.openWindowResponse) { state in
            state.complete.isOpeningWindow = false
        }

        // 성공적인 재시도 후 에러가 초기화되어야 함
        XCTAssertNil(store.state.complete.openWindowError)
        let paths = await pathRecorder.snapshot()
        XCTAssertEqual(paths.count, 1)

        await store.finish()
    }

    /// 멱등적 완료 — `startUsingTapped`를 두 번 호출해도 `isComplete`가 일관되게 유지됨을 검증합니다.
    /// - 검증 내용: 두 번째 호출 시에도 동일한 상태 변화(`isOpeningWindow`, `openWindowError = nil`)가 발생합니다.
    /// - 사전 조건: `currentStep = .complete` 상태입니다. `pathRecorder`로 창 열기 호출을 캡처합니다.
    /// - 기대 결과: 두 시도 모두 창을 열어(`paths.count = 2`), 최종적으로 `isComplete = true`입니다.
    /// - 관련 사양: ONB-001-complete_onboarding_session
    func testIdempotentCompletion() async {
        let pathRecorder = PathRecorder()
        var initialState = OnboardingFeature.State()
        initialState.currentStep = .complete

        let store = TestStore(initialState: initialState) {
            OnboardingFeature()
        } withDependencies: {
            $0.onboardingProgressClient = OnboardingProgressClient(
                load: { .empty },
                save: { _ in },
                reset: {},
            )
            $0.onboardingWindowClient = OnboardingWindowClient(
                isRequired: { false },
                showIfNeeded: { false },
                showWindow: {},
                closeWindow: {},
                openMainWindow: { request in
                    await pathRecorder.append(request)
                    return true
                },
            )
        }

        // 첫 번째 완료
        await store.send(.complete(.startUsingTapped)) { state in
            state.complete.isComplete = true
            state.complete.isOpeningWindow = true
            state.complete.openWindowError = nil
        }
        await store.receive(\.complete.openWindowResponse) { state in
            state.complete.isOpeningWindow = false
        }

        // 두 번째 완료 시도 (멱등)
        await store.send(.complete(.startUsingTapped)) { state in
            state.complete.isOpeningWindow = true
            state.complete.openWindowError = nil
        }
        await store.receive(\.complete.openWindowResponse) { state in
            state.complete.isOpeningWindow = false
        }

        // 두 시도 모두 창을 열어야 함
        let paths = await pathRecorder.snapshot()
        XCTAssertEqual(paths.count, 2)
        XCTAssertTrue(store.state.complete.isComplete)

        await store.finish()
    }

    /// 재진입: 이미 온보딩을 완료한 사용자가 다시 실행하면
    /// 세션이 완전히 완료된 상태로 로드되고 `isSessionComplete`이 `true`임을 검증합니다.
    /// - 검증 내용: 모든 단계 완료 스냅샷 복원 후 `isSessionComplete`이 올바르게 설정됩니다.
    /// - 사전 조건: snapshot에 모든 단계가 완료로 저장되어 있습니다.
    /// - 기대 결과: `isSessionComplete = true`, `currentStep = .complete`, 모든 단계 완료 상태입니다.
    /// - 관련 사양: ONB-001-complete_onboarding_session
    func testCompletedSessionReEntryShowsCompletionState() async {
        let snapshot = OnboardingProgressSnapshot(
            currentStep: .complete,
            stepState: OnboardingStepState(
                welcomeComplete: true,
                betaAccessComplete: true,
                permissionsComplete: true,
                completeComplete: true,
            ),
        )

        let store = TestStore(initialState: OnboardingFeature.State()) {
            OnboardingFeature()
        } withDependencies: {
            $0.onboardingProgressClient = OnboardingProgressClient(
                load: { .success(snapshot) },
                save: { _ in },
                reset: {},
            )
        }

        await store.send(.onAppear) { state in
            state.currentStep = .complete
            state.welcome.isComplete = true
            state.betaAccess.status = .active
            state.betaAccess.reason = .none
            state.betaAccess.isComplete = true
            state.permissions.isComplete = true
            state.complete.isComplete = true
        }

        XCTAssertTrue(store.state.isSessionComplete)
        XCTAssertEqual(store.state.currentStep, .complete)

        await store.finish()
    }
    // swiftlint:enable type_body_length
}

// swiftlint:enable file_length
