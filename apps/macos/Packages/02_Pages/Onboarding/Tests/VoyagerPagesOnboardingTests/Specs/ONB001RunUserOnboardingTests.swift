import ComposableArchitecture
import Dependencies
import VoyagerFeaturesBetaAccess
@testable import VoyagerPagesOnboarding
import VoyagerShared
import XCTest

@MainActor
final class ONB001RunUserOnboardingTests: XCTestCase {
    // MARK: - ONB-001-start_onboarding_session

    // 온보딩 세션 시작 상호작용을 검증합니다.
    // 앱 첫 실행, 빈 진행 상태, 버전 불일치로 인한 리셋 등 세션 초기화 시나리오에서
    // 초기 단계 상태가 올바르게 설정되고 진행 상태 스냅샷이 저장되는지 확인합니다.

    /// ONB-001-start_onboarding_session: 저장된 진행 상태가 없을 때 온보딩이 시작되면 welcome 단계의 새 세션과 초기 navigation 상태를 만든다.
    /// 저장된 진행 상태가 없을 때 새 온보딩 세션이 welcome 단계에서 시작되는지 검증합니다.
    /// - 검증 내용: `load`가 `.empty`를 반환하면 reducer가 기본 상태로 새 세션을 생성합니다.
    /// - 사전 조건: 진행 상태 저장소가 `.empty`를 반환하여 이전 세션이 없음을 나타냅니다.
    /// - 기대 결과: welcome은 완료 상태, 나머지 단계는 미완료 상태이며 첫 단계라 뒤로 이동할 수 없습니다.
    func testStartFreshSessionOnEmptyProgress() async {
        let store = TestStore(initialState: OnboardingFeature.State()) {
            OnboardingFeature()
        } withDependencies: {
            $0.onboardingProgressClient = ProgressClient.noOp
        }

        await store.send(.onAppear)

        // 새 세션은 항상 welcome에서 시작
        XCTAssertEqual(store.state.currentStep, .welcome)
        XCTAssertTrue(store.state.welcome.isComplete)
        XCTAssertFalse(store.state.betaAccess.isComplete)
        XCTAssertFalse(store.state.permissions.isComplete)
        XCTAssertFalse(store.state.aiProviderSetup.isComplete)
        XCTAssertFalse(store.state.complete.isComplete)

        // canGoNext가 true인지 확인 (welcome은 기본적으로 완료 상태)
        XCTAssertTrue(store.state.canGoNext)
        XCTAssertFalse(store.state.canGoBack)

        await store.finish()
    }

    /// ONB-001-start_onboarding_session: resetRequired 상태일 때 세션을 재시작하면 저장소 reset과 새 snapshot save가 모두 실행된다.
    /// `resetRequired` 응답 시 reducer가 `reset()`과 `save()`를 모두 호출하는지 검증합니다.
    /// - 검증 내용: 세션 리셋 시 실제 저장소 초기화와 새 진행 상태 저장이 순차적으로 발생합니다.
    /// - 사전 조건: `load`가 `.resetRequired`를 반환합니다. `resetRecorder`로 `reset()` 호출 여부를 추적합니다.
    /// - 기대 결과: `resetRecorder.value`가 `true`로 설정되어 `reset()`이 실제로 호출되었음을 확인합니다.
    func testResetSessionCallsResetAndSave() async {
        let resetRecorder = LockIsolated(false)
        let saveRecorder = LockIsolated<OnboardingProgressSnapshot?>(nil)

        let store = TestStore(initialState: OnboardingFeature.State()) {
            OnboardingFeature()
        } withDependencies: {
            $0.onboardingProgressClient = ProgressClient.resetRequiredWithRecorders(
                saveRecorder: saveRecorder,
                resetRecorder: resetRecorder,
            )
        }

        await store.send(.onAppear)

        XCTAssertTrue(resetRecorder.value)

        await store.finish()
    }

    /// ONB-001-start_onboarding_session: empty progress일 때 onAppear가 실행되면 welcome 상태로 시작하고 재개 가능한 첫 snapshot을 저장한다.
    /// `load`가 `.empty`를 반환하면 상태가 새 세션으로 초기화되고 초기 스냅샷이 저장되는지 검증합니다.
    /// - 검증 내용: 진행 상태가 없을 때 세션 초기화 후 첫 스냅샷이 올바른 단계 상태와 함께 저장됩니다.
    /// - 사전 조건: `load`가 `.empty`를 반환합니다. `snapshotRecorder`로 `save()`에 전달된 스냅샷을 캡처합니다.
    /// - 기대 결과: welcome에서 시작, welcome만 완료, 저장된 스냅샷의 `currentStep`이 `.welcome`입니다.
    func testEmptyProgressStartsFreshSession() async {
        let saveRecorder = LockIsolated<OnboardingProgressSnapshot?>(nil)

        let store = TestStore(initialState: OnboardingFeature.State()) {
            OnboardingFeature()
        } withDependencies: {
            $0.onboardingProgressClient = ProgressClient.recording(saveRecorder: saveRecorder)
        }

        await store.send(.onAppear)

        // 새 세션은 항상 welcome에서 시작
        XCTAssertEqual(store.state.currentStep, .welcome)
        XCTAssertTrue(store.state.welcome.isComplete)
        XCTAssertFalse(store.state.betaAccess.isComplete)
        XCTAssertFalse(store.state.permissions.isComplete)
        XCTAssertFalse(store.state.aiProviderSetup.isComplete)
        XCTAssertFalse(store.state.complete.isComplete)

        // 올바른 초기 상태로 스냅샷이 저장되었는지 확인
        let savedSnapshot = saveRecorder.value
        XCTAssertNotNil(savedSnapshot)
        XCTAssertEqual(savedSnapshot?.currentStep, .welcome)

        await store.finish()
    }

    /// ONB-001-start_onboarding_session: 새 세션이 생성될 때 초기 snapshot을 저장하면 각 step completion flag가 초기 AC 상태와 일치한다.
    /// `onAppear` 시 초기 단계 상태를 반영하여 진행 상태 스냅샷이 올바르게 저장되는지 검증합니다.
    /// - 검증 내용: 세션 시작 시 저장되는 스냅샷의 각 단계별 완료 플래그가 초기 상태와 일치합니다.
    /// - 사전 조건: `load`가 `.empty`를 반환합니다. `snapshotRecorder`로 저장된 스냅샷을 캡처합니다.
    /// - 기대 결과: 스냅샷의 `welcomeComplete`는 `true`, 나머지 단계(`betaAccess`, `permissions`, `complete`)는 모두 `false`입니다.
    func testStartSessionSavesProgressSnapshot() async {
        let saveRecorder = LockIsolated<OnboardingProgressSnapshot?>(nil)

        let store = TestStore(initialState: OnboardingFeature.State()) {
            OnboardingFeature()
        } withDependencies: {
            $0.onboardingProgressClient = ProgressClient.recording(saveRecorder: saveRecorder)
        }

        await store.send(.onAppear)

        let savedSnapshot = saveRecorder.value
        XCTAssertNotNil(savedSnapshot)
        XCTAssertEqual(savedSnapshot?.stepState.welcomeComplete, true)
        XCTAssertEqual(savedSnapshot?.stepState.betaAccessComplete, false)
        XCTAssertEqual(savedSnapshot?.stepState.permissionsComplete, false)
        XCTAssertEqual(savedSnapshot?.stepState.aiProviderSetupComplete, false)
        XCTAssertEqual(savedSnapshot?.stepState.completeComplete, false)

        await store.finish()
    }

    // MARK: - ONB-001-show_onboarding_step

    // 온보딩 단계 표시: 각 단계의 title, subtitle, 인덱스, 네비게이션 플래그,
    // 정식 단계 순서(welcome → betaAccess → permissions → complete)를 검증합니다.

    /// ONB-001-show_onboarding_step: fresh session일 때 첫 화면을 표시하면 welcome step의 title/subtitle/progress metadata가 노출된다.
    /// 초기 `onAppear` 시 welcome 단계가 올바른 속성(title, subtitle, 인덱스, 총 단계 수)과 함께 표시되는지 검증합니다.
    /// - 검증 내용: welcome 단계의 메타데이터와 네비게이션 컨텍스트가 기대값과 일치합니다.
    /// - 사전 조건: `load`가 `.empty`를 반환하여 새 세션이 시작됩니다.
    /// - 기대 결과: `currentStep`은 `.welcome`, title "Welcome", subtitle "A quick setup before you dive in.",
    ///   `currentStepIndex` 1, `totalSteps` 4입니다.
    func testShowWelcomeStepOnAppear() async {
        let store = TestStore(initialState: OnboardingFeature.State()) {
            OnboardingFeature()
        } withDependencies: {
            $0.onboardingProgressClient = ProgressClient.noOp
        }

        await store.send(.onAppear)

        // welcome 단계가 표시되어야 함
        XCTAssertEqual(store.state.currentStep, .welcome)
        XCTAssertEqual(store.state.currentStep.title, "Welcome")
        XCTAssertEqual(store.state.currentStep.subtitle, "A quick setup before you dive in.")
        XCTAssertEqual(store.state.currentStepIndex, 1)
        XCTAssertEqual(store.state.totalSteps, 5)

        await store.finish()
    }

    /// ONB-001-show_onboarding_step: welcome이 완료된 상태일 때 Next를 누르면 beta access step을 현재 step으로 표시한다.
    /// welcome에서 `nextTapped` 후 betaAccess 단계가 올바른 속성과 함께 표시되는지 검증합니다.
    /// - 검증 내용: 단계 전환 후 `currentStep`, title, 인덱스가 betaAccess에 해당하는 값으로 갱신됩니다.
    /// - 사전 조건: 새 세션이 시작되어 welcome 단계에 위치합니다.
    /// - 기대 결과: `currentStep`은 `.betaAccess`, title "Beta Access", `currentStepIndex` 2입니다.
    func testShowBetaAccessStepAfterWelcome() async {
        let store = TestStore(initialState: OnboardingFeature.State()) {
            OnboardingFeature()
        } withDependencies: {
            $0.onboardingProgressClient = ProgressClient.noOp
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

    /// ONB-001-show_onboarding_step: beta access가 active로 완료되었을 때 Next를 누르면 permissions step을 현재 step으로 표시한다.
    /// betaAccess가 확인 완료된 후 `nextTapped`로 permissions 단계가 표시되는지 검증합니다.
    /// - 검증 내용: betaAccess 검증 성공(`.active`) 후 다음 단계 전환이 정상 동작합니다.
    /// - 사전 조건: welcome 통과, betaAccess에서 `.active` 확인 응답 수신 후 `isComplete = true` 상태입니다.
    /// - 기대 결과: `currentStep`은 `.permissions`, title "Permissions", `currentStepIndex` 3입니다.
    func testShowPermissionsStepAfterBetaAccess() async {
        let store = TestStore(initialState: OnboardingFeature.State()) {
            OnboardingFeature()
        } withDependencies: {
            $0.onboardingProgressClient = ProgressClient.noOp
        }

        await store.send(.onAppear)
        await store.send(.nextTapped) { state in
            state.currentStep = .betaAccess
        }
        await store.send(.betaAccess(.verificationResponse(BetaAccessVerificationResult(status: .active)))) { state in
            StateMutation.applyActiveBetaAccess(state: &state)
        }
        await store.send(.nextTapped) { state in
            state.currentStep = .permissions
        }

        XCTAssertEqual(store.state.currentStep, .permissions)
        XCTAssertEqual(store.state.currentStep.title, "Permissions")
        XCTAssertEqual(store.state.currentStepIndex, 3)

        await store.finish()
    }

    /// ONB-001-show_onboarding_step: required permissions가 완료되었을 때 Next를 누르면 aiProviderSetup step을 현재 step으로 표시한다.
    /// 모든 이전 단계(welcome, betaAccess, permissions)가 완료되면 aiProviderSetup 단계가 표시되는지 검증합니다.
    /// - 검증 내용: 선행 단계 모두 완료 시 `nextTapped`가 aiProviderSetup 단계로 전환합니다.
    /// - 사전 조건: welcome, betaAccess(`.active`), permissions 모두 `isComplete = true`이고 `currentStep = .permissions`입니다.
    /// - 기대 결과: `currentStep`은 `.aiProviderSetup`, title "AI Provider", 인덱스 4입니다.
    func testShowAIProviderSetupStepAfterPermissions() async {
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
            $0.onboardingProgressClient = ProgressClient.noOp
        }

        await store.send(.nextTapped) { state in
            state.currentStep = .aiProviderSetup
        }

        XCTAssertEqual(store.state.currentStep, .aiProviderSetup)
        XCTAssertEqual(store.state.currentStep.title, "AI Provider")
        XCTAssertEqual(store.state.currentStepIndex, 4)

        await store.finish()
    }

    /// ONB-001-show_onboarding_step: aiProviderSetup가 완료되었을 때 Next를 누르면 complete step을 현재 step으로 표시한다.
    /// AI Provider Setup 단계를 완료한 뒤 complete 단계가 표시되는지 검증합니다.
    /// - 검증 내용: `nextTapped`가 aiProviderSetup 이후 complete 단계로 전환합니다.
    /// - 사전 조건: `currentStep = .aiProviderSetup`, provider setup이 완료 상태입니다.
    /// - 기대 결과: `currentStep`은 `.complete`, title "Start your voyage", 인덱스 5입니다.
    func testShowCompleteStepAfterAIProviderSetup() async {
        var initialState = OnboardingFeature.State()
        initialState.currentStep = .aiProviderSetup
        initialState.welcome.isComplete = true
        initialState.betaAccess.isComplete = true
        initialState.betaAccess.status = .active
        initialState.betaAccess.reason = .none
        initialState.permissions.isComplete = true
        initialState.aiProviderSetup.choice = .providerConnected
        initialState.aiProviderSetup.status = .complete
        initialState.aiProviderSetup.rows[0].connectionState = .connected

        let store = TestStore(initialState: initialState) {
            OnboardingFeature()
        } withDependencies: {
            $0.onboardingProgressClient = ProgressClient.noOp
        }

        await store.send(.nextTapped) { state in
            state.currentStep = .complete
        }

        XCTAssertEqual(store.state.currentStep, .complete)
        XCTAssertEqual(store.state.currentStep.title, "Start your voyage")
        XCTAssertEqual(store.state.currentStepIndex, 5)
        XCTAssertFalse(store.state.canGoNext)

        await store.finish()
    }

    /// ONB-001-show_onboarding_step: 모든 step completion 조건이 순서대로 충족될 때 Next를 반복하면 welcome → betaAccess → permissions →
    /// complete 순서를 보존한다.
    /// 단계 순서가 정식 순서(welcome → betaAccess → permissions → complete)를 따르는지 검증합니다.
    /// - 검증 내용: `OnboardingStep.allCases`가 정식 순서와 일치하고, `nextTapped`가 각 단계를 올바르게 이동합니다.
    ///   미완료 단계에서는 `nextTapped`가 동작하지 않아야(no-op) 합니다.
    /// - 사전 조건: `load`가 `.empty`를 반환합니다. betaAccess는 `.active` 확인 응답으로 완료 처리합니다.
    /// - 기대 결과: welcome → betaAccess 전환 성공, permissions 미완료 시 `nextTapped` no-op, 전체 순서가 `allCases`와 일치합니다.
    func testCurrentStepAdvancesThroughCanonicalOrder() async {
        XCTAssertEqual(OnboardingStep.allCases, [.welcome, .betaAccess, .permissions, .aiProviderSetup, .complete])

        let store = TestStore(initialState: OnboardingFeature.State()) {
            OnboardingFeature()
        } withDependencies: {
            $0.onboardingProgressClient = ProgressClient.noOp
        }

        await store.send(.onAppear)

        // welcome → betaAccess
        await store.send(.nextTapped) { state in
            state.currentStep = .betaAccess
        }

        // beta access를 완료하여 다음 네비게이션 활성화
        await store.send(.betaAccess(.verificationResponse(BetaAccessVerificationResult(status: .active)))) { state in
            StateMutation.applyActiveBetaAccess(state: &state)
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

    /// ONB-001-update_onboarding_step_state: child welcome action이 발생할 때 step state를 갱신하면 welcome completion state를
    /// session snapshot에 반영한다.
    /// 자식 액션(`.welcome(.setCompleted)`)을 통한 welcome 단계 완료 상태 변경이 올바르게 전파되는지 검증합니다.
    /// - 검증 내용: welcome의 `isComplete`를 끄고 다시 켤 때 `canGoNext`가 그에 맞게 변경됩니다.
    /// - 사전 조건: `onAppear` 후 welcome은 완료 상태입니다.
    /// - 기대 결과: `isComplete = false` 시 `canGoNext = false`, `isComplete = true` 시 `canGoNext = true`로 복원됩니다.
    func testUpdateWelcomeStepStateViaChildAction() async {
        let store = TestStore(initialState: OnboardingFeature.State()) {
            OnboardingFeature()
        } withDependencies: {
            $0.onboardingProgressClient = ProgressClient.noOp
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

    /// ONB-001-update_onboarding_step_state: ONB-002 verification이 active를 반환할 때 child result가 들어오면 betaAccess step을
    /// complete로 정규화한다.
    /// betaAccess 단계에서 확인 응답(`.active`) 수신 시 상태가 올바르게 업데이트되는지 검증합니다.
    /// - 검증 내용: `verificationResponse` 액션이 `status`, `reason`, `isComplete`를 올바르게 갱신합니다.
    /// - 사전 조건: `onAppear` 후 betaAccess는 미완료(`.notActive`) 상태입니다.
    /// - 기대 결과: `isComplete = true`, `status = .active`, `reason = .none`으로 변경됩니다.
    func testUpdateBetaAccessStepStateOnVerification() async {
        let store = TestStore(initialState: OnboardingFeature.State()) {
            OnboardingFeature()
        } withDependencies: {
            $0.onboardingProgressClient = ProgressClient.noOp
        }

        await store.send(.onAppear)

        // beta access는 미완료 상태로 시작
        XCTAssertFalse(store.state.betaAccess.isComplete)
        XCTAssertEqual(store.state.betaAccess.status, .notActive)

        // 성공적인 확인이 상태를 업데이트
        await store.send(.betaAccess(.verificationResponse(BetaAccessVerificationResult(status: .active)))) { state in
            StateMutation.applyActiveBetaAccess(state: &state)
        }

        XCTAssertTrue(store.state.betaAccess.isComplete)
        XCTAssertEqual(store.state.betaAccess.status, .active)

        await store.finish()
    }

    /// ONB-001-update_onboarding_step_state: 하위 step state가 변경될 때 reducer가 action을 처리하면 변경된 completion state를 progress
    /// snapshot으로 저장한다.
    /// 자식 액션 후 단계 상태 업데이트가 진행 상태 스냅샷 저장을 트리거하는지 검증합니다.
    /// - 검증 내용: betaAccess 확인 응답 처리 후 `save()`가 호출되고 업데이트된 단계 상태를 반영합니다.
    /// - 사전 조건: `saveRecorder`로 저장 호출을 캡처합니다. 초기 상태에서 betaAccess 확인 응답을 전송합니다.
    /// - 기대 결과: 저장된 스냅샷의 `betaAccessComplete`이 `true`입니다.
    func testStepStateUpdateTriggersProgressSave() async throws {
        let saveRecorder = LockIsolated<OnboardingProgressSnapshot?>(nil)

        let store = TestStore(initialState: OnboardingFeature.State()) {
            OnboardingFeature()
        } withDependencies: {
            $0.onboardingProgressClient = ProgressClient.recording(saveRecorder: saveRecorder)
        }

        await store.send(.betaAccess(.verificationResponse(BetaAccessVerificationResult(status: .active)))) { state in
            StateMutation.applyActiveBetaAccess(state: &state)
        }

        // 업데이트된 스냅샷으로 save가 호출되어야 함
        let saved = saveRecorder.value
        XCTAssertNotNil(saved)
        XCTAssertTrue(try XCTUnwrap(saved?.stepState.betaAccessComplete))

        await store.finish()
    }

    /// ONB-001-update_onboarding_step_state: 각 child step completion 상태가 다를 때 step state를 계산하면 step별 complete flag를
    /// 독립적으로 유지한다.
    /// `isStepComplete`가 각 단계별로 완료 상태를 올바르게 추적하는지 검증합니다.
    /// - 검증 내용: 기본 상태에서 welcome만 완료이고, 각 단계를 수동 완료할 때마다 추적이 갱신됩니다.
    /// - 사전 조건: 기본 `OnboardingFeature.State`에서 시작합니다.
    /// - 기대 결과: welcome은 기본 완료, betaAccess/permissions/complete는 미완료,
    ///   각각 `isComplete = true` 설정 후 해당 단계 완료로 추적됩니다.
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

    /// ONB-001-update_onboarding_step_state: session snapshot을 생성할 때 모든 step state를 직렬화하면 ONB-002/ONB-003 결과까지 포함한다.
    /// `progressSnapshot`이 모든 4개 단계의 완료 플래그를 정확히 캡처하는지 검증합니다.
    /// - 검증 내용: 수동으로 설정한 단계 상태가 스냅샷 생성 시 그대로 반영됩니다.
    /// - 사전 조건: `currentStep = .permissions`, `betaAccess.isComplete = true`, `permissions.isComplete = true`입니다.
    /// - 기대 결과: 스냅샷의 `currentStep`은 `.permissions`, `welcomeComplete`/`betaAccessComplete`/`permissionsComplete`은
    /// `true`,
    ///   `completeComplete`은 `false`입니다.
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

    /// ONB-001-advance_onboarding_step: ONB-001:go_back_onboarding_step — 현재 step이 완료되었을 때 Next/Back을 누르면 인접 step으로만
    /// 이동한다.
    /// `nextTapped`와 `backTapped`를 통한 앞/뒤 네비게이션이 모두 정상 동작하는지 검증합니다.
    /// - 검증 내용: welcome → betaAccess → permissions로 앞으로 이동 후 betaAccess로 뒤로 이동합니다.
    ///   미완료 betaAccess에서 `nextTapped`는 no-op입니다.
    /// - 사전 조건: `load`가 `.empty`를 반환합니다. betaAccess는 `.active` 확인 응답으로 완료 처리합니다.
    /// - 기대 결과: 단계 전환이 정확한 순서대로 발생하고 뒤로 이동도 올바르게 동작합니다.
    func testNextBackNavigation() async {
        let store = TestStore(initialState: OnboardingFeature.State()) {
            OnboardingFeature()
        } withDependencies: {
            $0.onboardingProgressClient = ProgressClient.noOp
        }

        await store.send(.onAppear)

        await store.send(.nextTapped) { state in
            state.currentStep = .betaAccess
        }

        await store.send(.nextTapped)

        await store.send(.betaAccess(.verificationResponse(BetaAccessVerificationResult(status: .active)))) { state in
            StateMutation.applyActiveBetaAccess(state: &state)
        }

        await store.send(.nextTapped) { state in
            state.currentStep = .permissions
        }

        await store.send(.backTapped) { state in
            state.currentStep = .betaAccess
        }

        await store.finish()
    }

    /// ONB-001-advance_onboarding_step: 현재 step이 incomplete일 때 Next를 누르면 다음 step으로 잘못 진행하지 않는다.
    /// 현재 단계가 완료되어야만 `nextTapped`로 다음 단계로 이동할 수 있음을 검증합니다.
    /// - 검증 내용: 미완료 단계에서 `nextTapped`는 아무 상태 변화도 일으키지 않아야(no-op) 합니다.
    /// - 사전 조건: `currentStep = .betaAccess`, `betaAccess.isComplete = false` 상태입니다.
    /// - 기대 결과: `canGoNext`는 `false`, `nextTapped` 후에도 여전히 `currentStep = .betaAccess`입니다.
    func testAdvanceRequiresCurrentStepComplete() async {
        var initialState = OnboardingFeature.State()
        initialState.currentStep = .betaAccess
        // betaAccess가 완료되지 않음

        let store = TestStore(initialState: initialState) {
            OnboardingFeature()
        } withDependencies: {
            $0.onboardingProgressClient = ProgressClient.noOp
        }

        XCTAssertFalse(store.state.canGoNext)

        // betaAccess가 완료되지 않았으므로 nextTapped는 동작 없음
        await store.send(.nextTapped)

        // 여전히 betaAccess에 있음
        XCTAssertEqual(store.state.currentStep, .betaAccess)

        await store.finish()
    }

    /// ONB-001-advance_onboarding_step: complete step에 도달했을 때 추가 advance가 발생하면 범위를 넘어 진행하지 않는다.
    /// 마지막 단계(complete)에서는 `nextTapped`로 더 이상 앞으로 이동할 수 없음을 검증합니다.
    /// - 검증 내용: complete 단계는 `currentStep.next`가 `nil`이며 `nextTapped`가 no-op입니다.
    /// - 사전 조건: `currentStep = .complete` 상태입니다.
    /// - 기대 결과: `canGoNext`는 `false`, `nextTapped` 후에도 `currentStep = .complete`입니다.
    func testCannotAdvanceBeyondCompleteStep() async {
        var initialState = OnboardingFeature.State()
        initialState.currentStep = .complete

        let store = TestStore(initialState: initialState) {
            OnboardingFeature()
        } withDependencies: {
            $0.onboardingProgressClient = ProgressClient.noOp
        }

        XCTAssertNil(store.state.currentStep.next)
        XCTAssertFalse(store.state.canGoNext)

        await store.send(.nextTapped)

        XCTAssertEqual(store.state.currentStep, .complete)

        await store.finish()
    }

    /// ONB-001-advance_onboarding_step: step advance가 성공할 때 currentStep이 바뀌면 새 currentStep snapshot을 저장한다.
    /// 단계 이동 시 진행 상태 스냅샷이 저장되어 새 단계가 반영되는지 검증합니다.
    /// - 검증 내용: `nextTapped` 후 `save()`가 호출되고 갱신된 `currentStep`이 스냅샷에 반영됩니다.
    /// - 사전 조건: `saveRecorder`로 저장 호출을 캡처합니다. `onAppear` 후 welcome 단계입니다.
    /// - 기대 결과: `nextTapped` 후 저장된 스냅샷의 `currentStep`이 `.betaAccess`입니다.
    func testAdvanceStepPersistsProgress() async {
        let saveRecorder = LockIsolated<OnboardingProgressSnapshot?>(nil)

        let store = TestStore(initialState: OnboardingFeature.State()) {
            OnboardingFeature()
        } withDependencies: {
            $0.onboardingProgressClient = ProgressClient.recording(saveRecorder: saveRecorder)
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

    /// ONB-001-go_back_onboarding_step: welcome step일 때 Back을 누르면 이전 step으로 이동하지 않는다.
    /// 첫 번째 단계(welcome)에서는 `backTapped`로 뒤로 이동할 수 없음을 검증합니다.
    /// - 검증 내용: welcome에서 `backTapped`는 no-op이며 단계가 유지됩니다.
    /// - 사전 조건: `onAppear` 후 `currentStep = .welcome`, `canGoBack = false` 상태입니다.
    /// - 기대 결과: `backTapped` 후에도 `currentStep = .welcome`입니다.
    func testCannotGoBackFromWelcomeStep() async {
        let store = TestStore(initialState: OnboardingFeature.State()) {
            OnboardingFeature()
        } withDependencies: {
            $0.onboardingProgressClient = ProgressClient.noOp
        }

        await store.send(.onAppear)

        XCTAssertFalse(store.state.canGoBack)

        // welcome에서 backTapped는 동작 없음
        await store.send(.backTapped)

        XCTAssertEqual(store.state.currentStep, .welcome)

        await store.finish()
    }

    /// ONB-001-go_back_onboarding_step: 완료된 child step들이 있을 때 이전 step으로 돌아가면 completion state를 잃지 않는다.
    /// 뒤로 이동 시 이미 완료된 단계의 완료 상태가 보존됨을 검증합니다.
    /// - 검증 내용: permissions → betaAccess → welcome으로 뒤로 이동해도 각 단계의 `isComplete`와 `status`가 유지됩니다.
    /// - 사전 조건: `currentStep = .permissions`, welcome/betaAccess 모두 완료(`.active`) 상태입니다.
    /// - 기대 결과: 두 번의 `backTapped` 후에도 welcome/betaAccess의 완료 상태와 betaAccess의 `.active` 상태가 보존됩니다.
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
            $0.onboardingProgressClient = ProgressClient.noOp
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

    /// ONB-001-go_back_onboarding_step: Back 이동이 성공할 때 currentStep이 변경되면 되돌아간 step snapshot을 저장한다.
    /// 뒤로 이동 시 진행 상태 스냅샷이 저장되어 이전 단계가 반영됨을 검증합니다.
    /// - 검증 내용: `backTapped` 후 `save()`가 호출되고 스냅샷의 `currentStep`이 이전 단계로 갱신됩니다.
    /// - 사전 조건: `currentStep = .betaAccess`, `welcome.isComplete = true`, `saveRecorder`로 저장 호출을 캡처합니다.
    /// - 기대 결과: `backTapped` 후 저장된 스냅샷의 `currentStep`이 `.welcome`입니다.
    func testGoBackPersistsProgress() async {
        let saveRecorder = LockIsolated<OnboardingProgressSnapshot?>(nil)

        var initialState = OnboardingFeature.State()
        initialState.currentStep = .betaAccess
        initialState.welcome.isComplete = true

        let store = TestStore(initialState: initialState) {
            OnboardingFeature()
        } withDependencies: {
            $0.onboardingProgressClient = ProgressClient.recording(saveRecorder: saveRecorder)
        }

        await store.send(.backTapped) { state in
            state.currentStep = .welcome
        }

        let saved = saveRecorder.value
        XCTAssertNotNil(saved)
        XCTAssertEqual(saved?.currentStep, .welcome)

        await store.finish()
    }

    /// ONB-001-go_back_onboarding_step: betaAccess가 이미 verified 상태일 때 Back으로 돌아가면 재검증 없이 verified 상태를 유지한다.
    /// 이미 완료된 betaAccess 단계로 뒤로 이동해도 `onAppear`가 재검증을 트리거하지 않음을 검증합니다.
    /// - 검증 내용: `isComplete = true`, `status = .active` 상태에서 `backTapped` 후
    ///   `onAppear`가 호출되어도 `isVerifying`이 `false`로 유지됩니다.
    /// - 사전 조건: `currentStep = .permissions`, betaAccess가 verified(`isComplete = true`, `status = .active`) 상태입니다.
    /// - 기대 결과: `backTapped` 후 `currentStep = .betaAccess`이고, `onAppear` 후에도
    ///   `isVerifying = false`, `status = .active`가 유지됩니다.
    func testGoBackToBetaAccessPreservesVerifiedStateWithoutReverification() async {
        var initialState = OnboardingFeature.State()
        initialState.currentStep = .permissions
        StateMutation.applyActiveBetaAccess(state: &initialState)
        initialState.permissions.isComplete = true

        let store = TestStore(initialState: initialState) {
            OnboardingFeature()
        } withDependencies: {
            $0.onboardingProgressClient = ProgressClient.noOp
        }

        await store.send(.backTapped) { state in
            state.currentStep = .betaAccess
        }

        XCTAssertTrue(store.state.betaAccess.isComplete)
        XCTAssertEqual(store.state.betaAccess.status, .active)
        XCTAssertFalse(store.state.betaAccess.isVerifying)

        await store.send(.betaAccess(.onAppear))

        XCTAssertFalse(
            store.state.betaAccess.isVerifying,
            "onAppear should not trigger re-verification when already verified",
        )
        XCTAssertEqual(store.state.betaAccess.status, .active)

        await store.finish()
    }

    // MARK: - ONB-001-resume_onboarding_session

    // 세션 이어서 진행: 저장된 스냅샷에서 세션 복원, 미완료 단계의 fallback-to-last-valid-step,
    // 리셋 필요 시 세션 초기화, 복원 후 스냅샷 저장을 검증합니다.

    /// ONB-001-resume_onboarding_session: 유효한 persisted snapshot이 있을 때 앱이 재시작되면 마지막 방문 reachable step에서 재개한다.
    /// 저장된 스냅샷에서 세션을 이어서 진행할 때 상태가 올바르게 복원되는지 검증합니다.
    /// - 검증 내용: `load`가 `.success(snapshot)`를 반환하면 reducer가 스냅샷 기반으로 상태를 복원합니다.
    /// - 사전 조건: snapshot에 `currentStep = .permissions`, welcome/betaAccess 완료, permissions/complete 미완료가 저장되어 있습니다.
    /// - 기대 결과: `onAppear` 후 선행 단계(betaAccess)가 완료되어 `.permissions`를 직접 복원합니다.
    ///   welcome/betaAccess는 완료, permissions/complete는 미완료 상태입니다.
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
            $0.onboardingProgressClient = ProgressClient.resuming(from: snapshot)
        }

        await store.send(.onAppear) { state in
            state.currentStep = .permissions
            StateMutation.applyRestoredBetaAccess(state: &state)
        }

        await store.finish()
    }

    /// ONB-001-resume_onboarding_session: persisted current step이 incomplete일 때 resume하면 안전한 이전/기본 step으로 fallback한다.
    /// 저장된 `currentStep`은 유효하지만 해당 단계가 미완료인 스냅샷으로 이어서 진행 시
    /// 마지막 유효한 완료 단계로 대체(fallback-to-last-valid-step)됨을 검증합니다.
    /// - 검증 내용: `currentStep = .permissions`이지만 betaAccess가 미완료이면 welcome으로 되돌아갑니다.
    /// - 사전 조건: snapshot에 `permissions`가 currentStep이지만 betaAccess/permissions 미완료입니다.
    ///   초기 상태를 `.complete`/완료로 설정하여 mutation 관찰이 가능합니다.
    /// - 기대 결과: `onAppear` 후 `currentStep = .betaAccess`, `complete.isComplete = false`로 복원됩니다.
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
            $0.onboardingProgressClient = ProgressClient.resuming(from: snapshot)
        }

        // betaAccess 미완료 → lastValidStep이 betaAccess로 되돌아감
        await store.send(.onAppear) { state in
            state.currentStep = .betaAccess
            state.complete.isComplete = false
        }

        XCTAssertEqual(store.state.currentStep, .betaAccess)

        await store.finish()
    }

    /// ONB-001-resume_onboarding_session: snapshot에 currentStep == .complete이지만 중간 선행 단계가 미완료면 복원하지 않는다.
    /// `currentStep = .complete`, `permissionsComplete = true`, `betaAccessComplete = false`인 불일치 snapshot에서
    /// complete 단계로 직접 복원하지 않고 가장 마지막 완료 단계인 welcome으로 되돌아갑니다.
    /// - 검증 내용: 불일치 progress snapshot을 resume할 때 complete step으로 건너뛰지 않는지 확인합니다.
    /// - 사전 조건: snapshot에 welcome만 완료, betaAccess 미완료, permissions 완료(불일치), currentStep = .complete.
    /// - 기대 결과: `onAppear` 후 `currentStep = .betaAccess`으로 fallback (welcome은 완료이므로 betaAccess부터 재개).
    func testResumeCompleteStepWithIncompleteBetaAccessFallsBack() async {
        let snapshot = OnboardingProgressSnapshot(
            currentStep: .complete,
            stepState: OnboardingStepState(
                welcomeComplete: true,
                betaAccessComplete: false,
                permissionsComplete: true,
                completeComplete: false,
            ),
        )

        var initialState = OnboardingFeature.State()
        initialState.currentStep = .complete
        initialState.complete.isComplete = true

        let store = TestStore(initialState: initialState) {
            OnboardingFeature()
        } withDependencies: {
            $0.onboardingProgressClient = ProgressClient.resuming(from: snapshot)
        }

        await store.send(.onAppear) { state in
            state.currentStep = .betaAccess
            state.permissions.isComplete = true
            state.complete.isComplete = false
        }

        XCTAssertEqual(store.state.currentStep, .betaAccess)

        await store.finish()
    }

    /// ONB-001-resume_onboarding_session: 이전 step들이 완료된 snapshot일 때 resume하면 완료 상태를 보존하고 방문했던 complete step을 직접 복원한다.
    /// complete 이전의 모든 단계가 완료된 상태로 이어서 진행 시
    /// persisted `currentStep = .complete`가 직접 복원됨을 검증합니다.
    /// - 검증 내용: `currentStep = .complete`이고 permissions가 완료이면 `.complete`를 직접 복원합니다.
    /// - 사전 조건: snapshot에 welcome/betaAccess/permissions 완료, `completeComplete = false`가 저장되어 있습니다.
    /// - 기대 결과: `onAppear` 후 `currentStep = .complete`, 모든 선행 단계는 완료, `complete.isComplete = false`입니다.
    func testResumeWithCompletedPriorSteps() async {
        let snapshot = OnboardingProgressSnapshot(
            currentStep: .complete,
            stepState: OnboardingStepState(
                welcomeComplete: true,
                betaAccessComplete: true,
                permissionsComplete: true,
                aiProviderSetupComplete: true,
                aiProviderSetupChoice: .providerConnected,
                aiProviderSetupStatus: .complete,
                completeComplete: false,
            ),
        )

        let store = TestStore(initialState: OnboardingFeature.State()) {
            OnboardingFeature()
        } withDependencies: {
            $0.onboardingProgressClient = ProgressClient.resuming(from: snapshot)
        }

        // permissions 완료 → 선행 단계 모두 완료 → .complete 직접 복원
        await store.send(.onAppear) { state in
            state.currentStep = .complete
            StateMutation.applyRestoredBetaAccess(state: &state)
            state.permissions.isComplete = true
            state.aiProviderSetup.choice = .providerConnected
            state.aiProviderSetup.status = .complete
        }

        XCTAssertEqual(store.state.currentStep, .complete)

        await store.finish()
    }

    /// ONB-001-resume_onboarding_session: welcome만 완료된 snapshot일 때 resume하면 betaAccess step을 직접 복원한다.
    /// 저장된 스냅샷에서 welcome만 완료된 경우, 선행 단계(welcome)가 완료이므로
    /// `.betaAccess`가 직접 복원됨을 검증합니다.
    /// - 검증 내용: betaAccess 미완료라도 welcome(선행 단계)이 완료이면 `.betaAccess`를 직접 복원합니다.
    /// - 사전 조건: snapshot에 `currentStep = .betaAccess`, welcome만 완료, 나머지 미완료입니다.
    ///   초기 상태를 `.complete`/완료로 설정하여 mutation 관찰이 가능합니다.
    /// - 기대 결과: `onAppear` 후 `currentStep = .betaAccess`, `complete.isComplete = false`로 복원됩니다.
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
            $0.onboardingProgressClient = ProgressClient.resuming(from: snapshot)
        }

        // welcome 완료 → 선행 단계 충족 → .betaAccess 직접 복원
        await store.send(.onAppear) { state in
            state.currentStep = .betaAccess
            state.complete.isComplete = false
        }

        XCTAssertEqual(store.state.currentStep, .betaAccess)

        await store.finish()
    }

    /// ONB-001-resume_onboarding_session: resume 중 snapshot 보정이 필요하지 않을 때 복원 로직이 실행되면 persisted step을 그대로 저장한다.
    /// 이어서 진행 시 단계 상태 적용 후 업데이트된 스냅샷이 저장됨을 검증합니다.
    /// - 검증 내용: 복원된 상태(persisted step 유지)가 `save()`를 통해 올바르게 저장됩니다.
    /// - 사전 조건: snapshot에 `currentStep = .permissions`, welcome/betaAccess 완료가 저장되어 있습니다.
    ///   `saveRecorder`로 저장 호출을 캡처합니다.
    /// - 기대 결과: 저장된 스냅샷의 `currentStep`이 `.permissions`(선행 단계 완료로 직접 복원)를 반영합니다.
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
            $0.onboardingProgressClient = ProgressClient.resumingAndRecording(
                snapshot: snapshot,
                saveRecorder: saveRecorder,
            )
        }

        await store.send(.onAppear) { state in
            state.currentStep = .permissions
            StateMutation.applyRestoredBetaAccess(state: &state)
        }

        let saved = saveRecorder.value
        XCTAssertNotNil(saved)
        // 선행 단계(betaAccess)가 완료되어 permissions가 직접 복원됨
        XCTAssertEqual(saved?.currentStep, .permissions)

        await store.finish()
    }

    /// ONB-001-resume_onboarding_session: 손상된 stepState가 저장되어 있을 때 resume하면 welcome fallback으로 안전하게 복구한다.
    /// `load`가 `.resetRequired`를 반환하면 상태가 welcome으로 초기화되고 새 스냅샷이 저장됨을 검증합니다.
    /// - 검증 내용: 손상되거나 호환되지 않는 진행 상태를 감지하면 세션을 완전히 리셋합니다.
    /// - 사전 조건: `load`가 `.resetRequired`를 반환합니다. `snapshotRecorder`로 저장된 스냅샷을 캡처합니다.
    /// - 기대 결과: `currentStep = .welcome`, welcome만 완료, 저장된 스냅샷도 동일한 초기 상태를 반영합니다.
    func testResumeFromCorruptStepStateFallsBackToWelcome() async {
        let saveRecorder = LockIsolated<OnboardingProgressSnapshot?>(nil)
        let resetRecorder = LockIsolated(false)

        let store = TestStore(initialState: OnboardingFeature.State()) {
            OnboardingFeature()
        } withDependencies: {
            $0.onboardingProgressClient = ProgressClient.resetRequiredWithRecorders(
                saveRecorder: saveRecorder,
                resetRecorder: resetRecorder,
            )
        }

        await store.send(.onAppear)

        XCTAssertEqual(store.state.currentStep, .welcome)
        XCTAssertTrue(store.state.welcome.isComplete)
        XCTAssertFalse(store.state.betaAccess.isComplete)

        let saved = saveRecorder.value
        XCTAssertNotNil(saved)
        XCTAssertEqual(saved?.currentStep, .welcome)
        XCTAssertEqual(saved?.stepState.welcomeComplete, true)
        XCTAssertEqual(saved?.stepState.betaAccessComplete, false)

        await store.finish()
    }

    /// ONB-001-resume_onboarding_session: 알 수 없는 currentStep이 저장되어 있을 때 resume하면 마지막 유효 step으로 fallback한다.
    /// 스냅샷에 유효한 단계(`.complete`)가 있지만 선행 조건이 미완료면
    /// 마지막 유효 단계로 대체됨을 검증합니다.
    /// - 검증 내용: complete/betaAccess/permissions가 모두 미완료이면 welcome으로 fallback합니다.
    /// - 사전 조건: snapshot에 `currentStep = .complete`, welcome만 완료, 나머지 미완료가 저장되어 있습니다.
    /// - 기대 결과: `onAppear` 후 `currentStep = .betaAccess`, welcome만 완료, betaAccess 미완료입니다.
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
            $0.onboardingProgressClient = ProgressClient.resuming(from: snapshot)
        }

        // complete ✗ → permissions ✗ → betaAccess: prior chain (welcome) complete → .betaAccess
        await store.send(.onAppear) { state in
            state.currentStep = .betaAccess
        }

        XCTAssertEqual(store.state.currentStep, .betaAccess)
        XCTAssertTrue(store.state.isStepComplete(.welcome))
        XCTAssertFalse(store.state.isStepComplete(.betaAccess))

        await store.finish()
    }

    // MARK: - ONB-001-complete_onboarding_session

    // 세션 완료: startUsingTapped를 통한 완료 처리, 메인 창 열기, 진행 상태 저장,
    // 재진입 시 세션 스킵, 실패/재시도/멱등성을 검증합니다.

    /// ONB-001-complete_onboarding_session: 모든 필수 step이 완료되었을 때 완료 액션을 실행하면 progress를 completed로 저장하고 main window open
    /// contract를 호출한다.
    /// 세션 완료 시 메인 창이 열리고 진행 상태가 저장되는지 검증합니다.
    /// - 검증 내용: `startUsingTapped`가 `isComplete`, `isOpeningWindow`를 설정하고
    ///   `openWindowResponse` 수신 후 메인 창 경로가 기록되며 `completeComplete`이 저장됩니다.
    /// - 사전 조건: `currentStep = .complete` 상태입니다. `snapshotRecorder`와 `pathRecorder`로
    ///   저장/열기 호출을 캡처합니다.
    /// - 기대 결과: 창이 `.defaultTabPath`로 1회 열리고, 저장된 스냅샷의 `completeComplete`이 `true`입니다.
    func testCompleteOpensWindowAndSavesProgress() async {
        let saveRecorder = LockIsolated<OnboardingProgressSnapshot?>(nil)
        let pathRecorder = PathRecorder()
        let closeRecorder = CloseRecorder()

        var initialState = OnboardingFeature.State()
        initialState.currentStep = .complete

        let store = TestStore(initialState: initialState) {
            OnboardingFeature()
        } withDependencies: {
            $0.onboardingProgressClient = ProgressClient.recording(saveRecorder: saveRecorder)
            $0.onboardingWindowClient = WindowClient.recording(
                pathRecorder: pathRecorder,
                closeRecorder: closeRecorder,
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
        let savedSnapshot = saveRecorder.value
        XCTAssertEqual(savedSnapshot?.stepState.completeComplete, true)
        let closeCount = await closeRecorder.snapshot()
        XCTAssertEqual(closeCount, 1, "closeWindow should be called once after successful open")
        await store.finish()
    }

    /// ONB-001-resume_onboarding_session: 이미 completed snapshot이 있을 때 앱이 시작되면 온보딩 표시를 건너뛰는 completed state를 복원한다.
    /// 세션 완료 후 재진입 시 이어서 진행 세션이 완료된 상태로 건너뜀을 검증합니다.
    /// - 검증 내용: 모든 단계가 완료된 스냅샷이 저장되어 있으면 `onAppear` 시 바로 complete 상태로 복원됩니다.
    /// - 사전 조건: snapshot에 모든 단계가 완료(`completeComplete = true`)로 저장되어 있습니다.
    /// - 기대 결과: `onAppear` 후 모든 단계가 완료 상태, `currentStep = .complete`로 복원됩니다.
    func testResumeSkipsBannerWhenCompleted() async {
        let snapshot = OnboardingProgressSnapshot(
            currentStep: .complete,
            stepState: OnboardingStepState(
                welcomeComplete: true,
                betaAccessComplete: true,
                permissionsComplete: true,
                aiProviderSetupComplete: true,
                aiProviderSetupChoice: .providerConnected,
                aiProviderSetupStatus: .complete,
                completeComplete: true,
            ),
        )

        let store = TestStore(initialState: OnboardingFeature.State()) {
            OnboardingFeature()
        } withDependencies: {
            $0.onboardingProgressClient = ProgressClient.resuming(from: snapshot)
        }

        await store.send(.onAppear) { state in
            state.currentStep = .complete
            state.welcome.isComplete = true
            StateMutation.applyRestoredBetaAccess(state: &state)
            state.permissions.isComplete = true
            state.aiProviderSetup.choice = .providerConnected
            state.aiProviderSetup.status = .complete
            state.complete.isComplete = true
        }

        await store.finish()
    }

    /// ONB-001-complete_onboarding_session: complete step에서 완료할 때 progress를 저장하면 completeComplete flag와 completed 상태가
    /// snapshot에 반영된다.
    /// 완료 시 모든 단계가 완료로 표시된 스냅샷이 저장되는지 검증합니다.
    /// - 검증 내용: `startUsingTapped` 후 `save()`가 호출되고 `completeComplete`과 `currentStep`이 올바르게 저장됩니다.
    /// - 사전 조건: `currentStep = .complete` 상태입니다. `snapshotRecorder`로 저장된 스냅샷을 캡처합니다.
    /// - 기대 결과: 저장된 스냅샷의 `completeComplete = true`, `currentStep = .complete`입니다.
    func testCompletionSavesCompleteStepState() async {
        let saveRecorder = LockIsolated<OnboardingProgressSnapshot?>(nil)
        let closeRecorder = CloseRecorder()

        var initialState = OnboardingFeature.State()
        initialState.currentStep = .complete

        let store = TestStore(initialState: initialState) {
            OnboardingFeature()
        } withDependencies: {
            $0.onboardingProgressClient = ProgressClient.recording(saveRecorder: saveRecorder)
            $0.onboardingWindowClient = WindowClient.recording(
                pathRecorder: PathRecorder(),
                closeRecorder: closeRecorder,
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

        let saved = saveRecorder.value
        XCTAssertNotNil(saved)
        XCTAssertEqual(saved?.stepState.completeComplete, true)
        XCTAssertEqual(saved?.currentStep, .complete)
        let closeCount = await closeRecorder.snapshot()
        XCTAssertEqual(closeCount, 1, "closeWindow should be called after successful completion")

        await store.finish()
    }

    /// ONB-001-complete_onboarding_session: main window open이 실패할 때 완료 액션을 실행하면 완료로 위장하지 않고 retry 가능한 error state를
    /// 표시한다.
    /// `openMainWindow`가 `false`를 반환하면 에러 상태가 설정됨을 검증합니다.
    /// - 검증 내용: 창 열기 실패 시 `openWindowError`에 사용자 친화적 메시지가 설정됩니다.
    /// - 사전 조건: `currentStep = .complete` 상태입니다. `openMainWindow`가 항상 `false`를 반환합니다.
    /// - 기대 결과: `openWindowResponse` 수신 후 `isOpeningWindow = false`,
    ///   `openWindowError`에 에러 메시지가 설정됩니다.
    func testCompletionOpenWindowFailureShowsError() async {
        let closeRecorder = CloseRecorder()
        let pathRecorder = PathRecorder()

        var initialState = OnboardingFeature.State()
        initialState.currentStep = .complete

        let store = TestStore(initialState: initialState) {
            OnboardingFeature()
        } withDependencies: {
            $0.onboardingProgressClient = ProgressClient.noOp
            $0.onboardingWindowClient = WindowClient.recordingFailure(
                pathRecorder: pathRecorder,
                closeRecorder: closeRecorder,
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
        let closeCount = await closeRecorder.snapshot()
        XCTAssertEqual(closeCount, 0, "closeWindow should NOT be called when openMainWindow fails")

        await store.finish()
    }

    /// ONB-001-complete_onboarding_session: 이전 completion이 실패했을 때 사용자가 재시도하면 성공 시 completed snapshot과 window open
    /// contract를 회복한다.
    /// 완료 실패 후 `retryTapped`가 창 열기를 재시도하는지 검증합니다.
    /// - 검증 내용: 에러 상태에서 재시도 시 `openWindowError`가 초기화되고 창이 다시 열립니다.
    /// - 사전 조건: `currentStep = .complete`, `isComplete = true`,
    ///   `openWindowError`에 기존 에러 메시지가 설정되어 있습니다.
    /// - 기대 결과: 재시도 성공 후 `openWindowError = nil`, `pathRecorder`에 1개의 경로가 기록됩니다.
    func testCompletionRetryAfterFailure() async {
        let pathRecorder = PathRecorder()
        let closeRecorder = CloseRecorder()
        var initialState = OnboardingFeature.State()
        initialState.currentStep = .complete
        initialState.complete.isComplete = true
        initialState.complete.openWindowError = "We couldn't open a file manager window. Please try again."

        let store = TestStore(initialState: initialState) {
            OnboardingFeature()
        } withDependencies: {
            $0.onboardingProgressClient = ProgressClient.noOp
            $0.onboardingWindowClient = WindowClient.recording(
                pathRecorder: pathRecorder,
                closeRecorder: closeRecorder,
            )
        }

        await store.send(.complete(.retryTapped)) { state in
            state.complete.isOpeningWindow = true
            state.complete.openWindowError = nil
        }

        await store.receive(\.complete.openWindowResponse) { state in
            state.complete.isOpeningWindow = false
        }

        XCTAssertNil(store.state.complete.openWindowError)
        let paths = await pathRecorder.snapshot()
        XCTAssertEqual(paths.count, 1)
        let closeCount = await closeRecorder.snapshot()
        XCTAssertEqual(closeCount, 1, "closeWindow should be called after successful retry")

        await store.finish()
    }

    /// ONB-001-complete_onboarding_session: 이미 완료된 상태일 때 completion을 다시 처리하면 completed state를 안정적으로 유지한다.
    /// 멱등적 완료 — `startUsingTapped`를 두 번 호출해도 `isComplete`가 일관되게 유지됨을 검증합니다.
    /// - 검증 내용: 두 번째 호출 시에도 동일한 상태 변화(`isOpeningWindow`, `openWindowError = nil`)가 발생합니다.
    /// - 사전 조건: `currentStep = .complete` 상태입니다. `pathRecorder`로 창 열기 호출을 캡처합니다.
    /// - 기대 결과: 두 시도 모두 창을 열어(`paths.count = 2`), 최종적으로 `isComplete = true`입니다.
    func testIdempotentCompletion() async {
        let pathRecorder = PathRecorder()
        let closeRecorder = CloseRecorder()

        var initialState = OnboardingFeature.State()
        initialState.currentStep = .complete

        let store = TestStore(initialState: initialState) {
            OnboardingFeature()
        } withDependencies: {
            $0.onboardingProgressClient = ProgressClient.noOp
            $0.onboardingWindowClient = WindowClient.recording(
                pathRecorder: pathRecorder,
                closeRecorder: closeRecorder,
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

        await store.send(.complete(.startUsingTapped)) { state in
            state.complete.isOpeningWindow = true
            state.complete.openWindowError = nil
        }
        await store.receive(\.complete.openWindowResponse) { state in
            state.complete.isOpeningWindow = false
        }

        let paths = await pathRecorder.snapshot()
        XCTAssertEqual(paths.count, 2)
        XCTAssertTrue(store.state.complete.isComplete)
        let closeCount = await closeRecorder.snapshot()
        XCTAssertEqual(closeCount, 2, "closeWindow should be called for each successful completion")

        await store.finish()
    }

    /// ONB-001-complete_onboarding_session: 완료 시 save → openMainWindow → closeWindow 순서로 호출된다.
    /// Parent reducer가 save, openMainWindow, closeWindow를 올바른 순서로 실행하는지 검증합니다.
    /// - 검증 내용: `startUsingTapped` 후 save가 먼저 실행되고, openMainWindow가 호출된 뒤 closeWindow가 호출됩니다.
    /// - 사전 조건: `currentStep = .complete` 상태입니다.
    /// - 기대 결과: saveRecorder에 `completeComplete = true` 스냅샷, pathRecorder에 `.defaultTabPath`,
    ///   closeRecorder에 1회 close가 순서대로 기록됩니다.
    func testOrderedSequenceSaveOpenClose() async {
        let saveRecorder = LockIsolated<OnboardingProgressSnapshot?>(nil)
        let pathRecorder = PathRecorder()
        let closeRecorder = CloseRecorder()
        let eventLog = EventLogSyncBox()

        var initialState = OnboardingFeature.State()
        initialState.currentStep = .complete

        let store = TestStore(initialState: initialState) {
            OnboardingFeature()
        } withDependencies: {
            $0.onboardingProgressClient = ProgressClient.recording(
                saveRecorder: saveRecorder,
                eventLog: eventLog,
            )
            $0.onboardingWindowClient = WindowClient.recording(
                pathRecorder: pathRecorder,
                closeRecorder: closeRecorder,
                eventLog: eventLog,
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

        let savedSnapshot = saveRecorder.value
        XCTAssertNotNil(savedSnapshot, "Snapshot should be saved before opening main window")
        XCTAssertEqual(savedSnapshot?.stepState.completeComplete, true)

        let openedPaths = await pathRecorder.snapshot()
        XCTAssertEqual(openedPaths.count, 1, "openMainWindow should be called once")
        XCTAssertEqual(openedPaths[0], .defaultTabPath)

        let closeCount = await closeRecorder.snapshot()
        XCTAssertEqual(closeCount, 1, "closeWindow should be called after successful openMainWindow")

        XCTAssertEqual(
            eventLog.snapshot(),
            ["save", "open", "close"],
            "save → openMainWindow → closeWindow 순서로 실행되어야 합니다",
        )

        await store.finish()
    }

    /// ONB-001-complete_onboarding_session: openMainWindow가 실패하면 closeWindow가 호출되지 않는다.
    /// 실패 시 온보딩 창이 닫히지 않음을 검증합니다.
    /// - 검증 내용: `openMainWindow`가 `false`를 반환하면 `closeWindow`가 호출되지 않습니다.
    /// - 사전 조건: `currentStep = .complete` 상태입니다. `openMainWindow`가 `false`를 반환합니다.
    /// - 기대 결과: `closeRecorder.snapshot() == 0`, 에러 상태가 설정됩니다.
    func testFailureDoesNotCloseOnboardingWindow() async {
        let closeRecorder = CloseRecorder()
        let pathRecorder = PathRecorder()

        var initialState = OnboardingFeature.State()
        initialState.currentStep = .complete

        let store = TestStore(initialState: initialState) {
            OnboardingFeature()
        } withDependencies: {
            $0.onboardingProgressClient = ProgressClient.noOp
            $0.onboardingWindowClient = WindowClient.recordingFailure(
                pathRecorder: pathRecorder,
                closeRecorder: closeRecorder,
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

        let closeCount = await closeRecorder.snapshot()
        XCTAssertEqual(closeCount, 0, "closeWindow must NOT be called when openMainWindow returns false")
        XCTAssertNotNil(store.state.complete.openWindowError)

        await store.finish()
    }

    /// ONB-001-complete_onboarding_session: ONB-001:resume_onboarding_session — completed session으로 재진입할 때 state를 복원하면
    /// completion 상태와 complete step 표시가 일치한다.
    /// 재진입: 이미 온보딩을 완료한 사용자가 다시 실행하면
    /// 세션이 완전히 완료된 상태로 로드되고 `isSessionComplete`이 `true`임을 검증합니다.
    /// - 검증 내용: 모든 단계 완료 스냅샷 복원 후 `isSessionComplete`이 올바르게 설정됩니다.
    /// - 사전 조건: snapshot에 모든 단계가 완료로 저장되어 있습니다.
    /// - 기대 결과: `isSessionComplete = true`, `currentStep = .complete`, 모든 단계 완료 상태입니다.
    func testCompletedSessionReEntryShowsCompletionState() async {
        let snapshot = OnboardingProgressSnapshot(
            currentStep: .complete,
            stepState: OnboardingStepState(
                welcomeComplete: true,
                betaAccessComplete: true,
                permissionsComplete: true,
                aiProviderSetupComplete: true,
                aiProviderSetupChoice: .providerConnected,
                aiProviderSetupStatus: .complete,
                completeComplete: true,
            ),
        )

        let store = TestStore(initialState: OnboardingFeature.State()) {
            OnboardingFeature()
        } withDependencies: {
            $0.onboardingProgressClient = ProgressClient.resuming(from: snapshot)
        }

        await store.send(.onAppear) { state in
            state.currentStep = .complete
            state.welcome.isComplete = true
            StateMutation.applyRestoredBetaAccess(state: &state)
            state.permissions.isComplete = true
            state.aiProviderSetup.choice = .providerConnected
            state.aiProviderSetup.status = .complete
            state.complete.isComplete = true
        }

        XCTAssertTrue(store.state.isSessionComplete)
        XCTAssertEqual(store.state.currentStep, .complete)

        await store.finish()
    }

    // MARK: - ONB-001-credential_persistence

    // BetaAccess 이메일/토큰의 스냅샷 저장 및 복원을 검증합니다.
    // 검증 완료 후 자격 증명이 스냅샷에 포함되어 저장되고,
    // 복원 시 이전에 입력한 이메일/토큰이 복구되는지 확인합니다.

    /// ONB-001-credential_persistence: betaAccess가 완료된 상태에서 snapshot을 생성하면 email/token이 snapshot에 포함된다.
    /// 검증 완료된 beta access credential이 onboarding progress snapshot에 함께 저장되는지 확인합니다.
    /// - 검증 내용: `progressSnapshot.stepState`에 email/token이 포함됩니다.
    /// - 사전 조건: betaAccess email/token/status/isComplete가 검증 완료 상태입니다.
    /// - 기대 결과: snapshot의 betaAccessEmail/betaAccessToken이 입력 credential과 일치합니다.
    func testProgressSnapshotIncludesCredentialsWhenBetaAccessComplete() {
        var state = OnboardingFeature.State()
        state.betaAccess.email = "user@test.com"
        state.betaAccess.token = "valid-token"
        state.betaAccess.isComplete = true
        state.betaAccess.status = .active

        let snapshot = state.progressSnapshot

        XCTAssertEqual(snapshot.stepState.betaAccessEmail, "user@test.com")
        XCTAssertEqual(snapshot.stepState.betaAccessToken, "valid-token")
    }

    /// ONB-001-credential_persistence: betaAccess가 미완료 상태에서 snapshot을 생성하면 email/token이 nil이다.
    /// 검증되지 않은 beta access credential이 progress snapshot에 저장되지 않는지 확인합니다.
    /// - 검증 내용: 미완료 beta access 상태의 snapshot credential 필드가 비어 있습니다.
    /// - 사전 조건: email/token은 입력되어 있으나 betaAccess는 완료되지 않았습니다.
    /// - 기대 결과: snapshot의 betaAccessEmail/betaAccessToken이 nil입니다.
    func testProgressSnapshotExcludesCredentialsWhenBetaAccessIncomplete() {
        var state = OnboardingFeature.State()
        state.betaAccess.email = "user@test.com"
        state.betaAccess.token = "valid-token"

        let snapshot = state.progressSnapshot

        XCTAssertNil(snapshot.stepState.betaAccessEmail)
        XCTAssertNil(snapshot.stepState.betaAccessToken)
    }

    /// ONB-001-credential_persistence: 자격 증명이 포함된 snapshot에서 복원하면 email/token이 복구된다.
    /// 저장된 beta access credential을 포함한 progress snapshot이 onboarding resume 시 상태로 복원되는지 확인합니다.
    /// - 검증 내용: snapshot의 email/token이 betaAccess state로 복원됩니다.
    /// - 사전 조건: permissions step snapshot에 betaAccessComplete와 credential 필드가 포함되어 있습니다.
    /// - 기대 결과: `onAppear` 후 email/token이 복구되고 restored-verified fallback은 사용하지 않습니다.
    func testResumeFromSnapshotWithCredentialsRestoresEmailAndToken() async {
        let snapshot = OnboardingProgressSnapshot(
            currentStep: .permissions,
            stepState: OnboardingStepState(
                welcomeComplete: true,
                betaAccessComplete: true,
                permissionsComplete: false,
                completeComplete: false,
                betaAccessEmail: "user@test.com",
                betaAccessToken: "valid-token",
            ),
        )

        let store = TestStore(initialState: OnboardingFeature.State()) {
            OnboardingFeature()
        } withDependencies: {
            $0.onboardingProgressClient = ProgressClient.resuming(from: snapshot)
        }

        await store.send(.onAppear) { state in
            state.currentStep = .permissions
            StateMutation.applyActiveBetaAccess(
                state: &state,
                email: "user@test.com",
                token: "valid-token",
            )
        }

        XCTAssertEqual(store.state.betaAccess.email, "user@test.com")
        XCTAssertEqual(store.state.betaAccess.token, "valid-token")
        XCTAssertFalse(store.state.betaAccess.isRestoredVerifiedAccess)

        await store.finish()
    }

    /// ONB-001-credential_persistence: 자격 증명이 없는 이전 snapshot에서 복원하면 restored verified 상태로 복구된다.
    /// legacy snapshot에 credential 필드가 없어도 기존 검증 완료 상태를 안전하게 이어받는지 확인합니다.
    /// - 검증 내용: credential 없는 betaAccessComplete snapshot은 restored verified fallback으로 복원됩니다.
    /// - 사전 조건: snapshot에는 betaAccessComplete만 있고 email/token 필드는 없습니다.
    /// - 기대 결과: email/token은 빈 값이고 isRestoredVerifiedAccess가 true입니다.
    func testResumeFromLegacySnapshotWithoutCredentialsShowsRestoredVerified() async {
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
            $0.onboardingProgressClient = ProgressClient.resuming(from: snapshot)
        }

        await store.send(.onAppear) { state in
            state.currentStep = .permissions
            StateMutation.applyRestoredBetaAccess(state: &state)
        }

        XCTAssertTrue(store.state.betaAccess.isRestoredVerifiedAccess)
        XCTAssertEqual(store.state.betaAccess.email, "")
        XCTAssertEqual(store.state.betaAccess.token, "")

        await store.finish()
    }

    /// ONB-001-credential_persistence: 검증 완료 후 진행 상태를 저장하면 snapshot에 email/token이 포함된다.
    /// beta access verification response가 progress save snapshot에 credential을 포함시키는지 확인합니다.
    /// - 검증 내용: verification response 이후 저장된 snapshot의 betaAccessEmail/betaAccessToken을 확인합니다.
    /// - 사전 조건: 초기 state에 email/token이 있고 progress client save recorder가 설정되어 있습니다.
    /// - 기대 결과: 저장된 snapshot에 입력 email/token이 유지됩니다.
    func testStepStateUpdateSavesCredentialsInSnapshot() async {
        let saveRecorder = LockIsolated<OnboardingProgressSnapshot?>(nil)

        var initialState = OnboardingFeature.State()
        initialState.betaAccess.email = "user@test.com"
        initialState.betaAccess.token = "valid-token"

        let store = TestStore(initialState: initialState) {
            OnboardingFeature()
        } withDependencies: {
            $0.onboardingProgressClient = ProgressClient.recording(saveRecorder: saveRecorder)
        }

        await store.send(.betaAccess(.verificationResponse(BetaAccessVerificationResult(status: .active)))) { state in
            state.betaAccess.status = .active
            state.betaAccess.reason = .none
            state.betaAccess.isComplete = true
        }

        let saved = saveRecorder.value
        XCTAssertNotNil(saved)
        XCTAssertEqual(saved?.stepState.betaAccessEmail, "user@test.com")
        XCTAssertEqual(saved?.stepState.betaAccessToken, "valid-token")

        await store.finish()
    }

    /// ONB-001-credential_persistence: credential 필드가 nil인 이전 JSON도 안전하게 디코딩된다.
    /// 이전 schema의 step state JSON이 credential 필드 없이도 migration-compatible하게 decode되는지 확인합니다.
    /// - 검증 내용: credential key가 없는 JSON을 `OnboardingStepState`로 디코딩합니다.
    /// - 사전 조건: JSON에는 welcome/betaAccess/permissions/complete 완료 여부만 포함되어 있습니다.
    /// - 기대 결과: 완료 여부는 보존되고 betaAccessEmail/betaAccessToken은 nil입니다.
    func testOldSnapshotWithoutCredentialFieldsDecodesSafely() throws {
        let json = """
        {
            "welcomeComplete": true,
            "betaAccessComplete": true,
            "permissionsComplete": false,
            "completeComplete": false
        }
        """
        let data = try XCTUnwrap(json.data(using: .utf8))
        let stepState = try JSONDecoder().decode(OnboardingStepState.self, from: data)

        XCTAssertTrue(stepState.welcomeComplete)
        XCTAssertTrue(stepState.betaAccessComplete)
        XCTAssertNil(stepState.betaAccessEmail)
        XCTAssertNil(stepState.betaAccessToken)
    }

    // MARK: - ONB-001-resume_onboarding_session

    /// ONB-001-resume_onboarding_session: legacy completed progress snapshot은 reset 없이 현재 schema로 migration됨
    /// 1.1 completed onboarding snapshot을 읽을 때 AI provider setup 필드를 안전하게 기본 완료/skip 상태로 보강하는지 검증한다.
    /// - 검증 내용: legacy step state decode, currentVersion write-back, AI provider setup migration 값
    /// - 사전 조건: UserDefaults에 `onboardingProgressVersion=1.1`, complete current step, legacy `OnboardingStepState`
    /// data가 저장됨
    /// - 기대 결과: load 결과가 resetRequired가 아닌 success이며 migrated snapshot과 persisted state가 current schema 기본값을 포함함
    func testLoadMigratesLegacyCompletedSnapshotWithoutResettingSession() throws {
        let userDefaultsClient = UserDefaultsClient.testValue
        let legacyStepState = OnboardingStepState(
            welcomeComplete: true,
            betaAccessComplete: true,
            permissionsComplete: true,
            completeComplete: true,
        )
        let legacyData = try JSONEncoder().encode(legacyStepState)

        userDefaultsClient.setObject(1.1, "onboardingProgressVersion")
        userDefaultsClient.setObject(OnboardingStep.complete.rawValue, "onboardingCurrentStep")
        userDefaultsClient.setObject(legacyData, "onboardingStepState")

        let result = withDependencies {
            $0.userDefaultsClient = userDefaultsClient
        } operation: {
            OnboardingProgressClient.liveValue.load()
        }

        guard case let .success(snapshot) = result else {
            return XCTFail("1.1 completed snapshot must migrate instead of requiring reset")
        }

        XCTAssertEqual(snapshot.currentStep, .complete)
        XCTAssertTrue(snapshot.stepState.aiProviderSetupComplete)
        XCTAssertTrue(snapshot.stepState.aiProviderSetupSkipped)
        XCTAssertEqual(snapshot.stepState.aiProviderSetupChoice, .setUpLater)
        XCTAssertEqual(snapshot.stepState.aiProviderSetupStatus, .skipped)
        XCTAssertTrue(snapshot.stepState.completeComplete)
        XCTAssertEqual(
            userDefaultsClient.object("onboardingProgressVersion") as? Double,
            OnboardingProgressClient.currentVersion,
        )

        let migratedData = try XCTUnwrap(userDefaultsClient.object("onboardingStepState") as? Data)
        let migratedStepState = try JSONDecoder().decode(OnboardingStepState.self, from: migratedData)
        XCTAssertTrue(migratedStepState.aiProviderSetupComplete)
        XCTAssertTrue(migratedStepState.aiProviderSetupSkipped)
        XCTAssertEqual(migratedStepState.aiProviderSetupChoice, .setUpLater)
        XCTAssertEqual(migratedStepState.aiProviderSetupStatus, .skipped)
    }

    // MARK: - ONB-001-run_onboarding_window

    /// ONB-001-run_onboarding_window: presentation pending 상태에서 showIfNeeded가 중복 window 표시를 예약하지 않는다.
    /// 온보딩 window client가 표시 대기 중 중복 표시 요청을 멱등하게 처리하는지 검증합니다.
    /// - 검증 내용: 연속 `showIfNeeded` 호출이 하나의 `showWindow` 실행으로 수렴합니다.
    /// - 사전 조건: progress client는 빈 진행 상태를 반환하고 main window open 요청은 성공합니다.
    /// - 기대 결과: 두 번 호출해도 `showWindow` 호출 횟수는 1회입니다.
    func testShowIfNeededIsIdempotentWhilePresentationIsPending() async {
        let counter = AsyncCounter()
        let showExpectation = expectation(description: "showWindow called once")
        showExpectation.expectedFulfillmentCount = 1

        let client = OnboardingWindowClient.makeClient(
            progressClient: OnboardingProgressClient(
                load: { .empty },
                save: { _ in .success },
                reset: {},
            ),
            openMainWindow: { _ in true },
            showWindow: {
                await counter.increment()
                showExpectation.fulfill()
            },
            closeWindow: {},
        )

        XCTAssertTrue(client.showIfNeeded())
        XCTAssertTrue(client.showIfNeeded())

        await fulfillment(of: [showExpectation], timeout: 1.0)

        let showCount = await counter.value()
        XCTAssertEqual(showCount, 1)
    }

    /// ONB-001-run_onboarding_window: closeWindow 이후 presentation gate가 reset되어 다시 window 표시를 허용한다.
    /// 온보딩 window client가 닫힘 이후 다음 표시 요청을 새 표시 cycle로 처리하는지 검증합니다.
    /// - 검증 내용: `closeWindow` 이후 `showIfNeeded`가 `showWindow`를 다시 실행합니다.
    /// - 사전 조건: 첫 `showIfNeeded`로 온보딩 window 표시가 완료된 뒤 `closeWindow`를 호출합니다.
    /// - 기대 결과: 최초 표시와 재표시를 합쳐 `showWindow`가 총 2회 호출됩니다.
    func testCloseWindowResetsPresentationGateAllowingReopen() async {
        let counter = AsyncCounter()
        let firstShowExpectation = expectation(description: "first showWindow")
        let secondShowExpectation = expectation(description: "second showWindow after close")

        let client = OnboardingWindowClient.makeClient(
            progressClient: OnboardingProgressClient(
                load: { .empty },
                save: { _ in .success },
                reset: {},
            ),
            openMainWindow: { _ in true },
            showWindow: {
                let showCallIndex = await counter.increment()
                if showCallIndex == 1 {
                    firstShowExpectation.fulfill()
                } else {
                    secondShowExpectation.fulfill()
                }
            },
            closeWindow: {},
        )

        XCTAssertTrue(client.showIfNeeded())
        await fulfillment(of: [firstShowExpectation], timeout: 1.0)

        await client.closeWindow()

        XCTAssertTrue(client.showIfNeeded())
        await fulfillment(of: [secondShowExpectation], timeout: 1.0)

        let showCount = await counter.value()
        XCTAssertEqual(showCount, 2, "closeWindow 후 showIfNeeded가 다시 showWindow를 호출해야 한다")
    }
}

private actor AsyncCounter {
    private var count = 0

    @discardableResult
    func increment() -> Int {
        count += 1
        return count
    }

    func value() -> Int {
        count
    }
}
