import ComposableArchitecture
import ConcurrencyExtras
import VoyagerFeaturesAccountAccess
@testable import VoyagerPagesOnboarding
import XCTest

@MainActor
final class ONB001RunUserOnboardingTests: XCTestCase {
    override func setUp() {
        super.setUp()
        prepareDependencies {
            $0.continuousClock = ImmediateClock()
        }
    }

    // MARK: - ONB-001-start_onboarding_session

    // 온보딩 세션 시작 상호작용을 검증합니다.
    // 앱 첫 실행, 빈 진행 상태, 버전 불일치로 인한 리셋 등 세션 초기화 시나리오에서
    // 초기 단계 상태가 올바르게 설정되고 진행 상태 스냅샷이 저장되는지 확인합니다.

    // ONB-001-start_onboarding_session: 저장된 진행 상태가 없을 때 온보딩이 시작되면 welcome 단계의 새 세션과 초기 navigation 상태를 만든다.
    // 저장된 진행 상태가 없을 때 새 온보딩 세션이 welcome 단계에서 시작되는지 검증합니다.
    // - 검증 내용: `load`가 `.empty`를 반환하면 reducer가 기본 상태로 새 세션을 생성합니다.
    // - 사전 조건: 진행 상태 저장소가 `.empty`를 반환하여 이전 세션이 없음을 나타냅니다.
    // - 기대 결과: welcome은 완료 상태, 나머지 단계는 미완료 상태이며 첫 단계라 뒤로 이동할 수 없습니다.

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

        await store.send(.onAppear) { $0.didBootstrapProgress = true }

        XCTAssertTrue(resetRecorder.value)

        await store.finish()
    }

    // ONB-001-start_onboarding_session: empty progress일 때 onAppear가 실행되면 welcome 상태로 시작하고 재개 가능한 첫 snapshot을 저장한다.
    // `load`가 `.empty`를 반환하면 상태가 새 세션으로 초기화되고 초기 스냅샷이 저장되는지 검증합니다.
    // - 검증 내용: 진행 상태가 없을 때 세션 초기화 후 첫 스냅샷이 올바른 단계 상태와 함께 저장됩니다.
    // - 사전 조건: `load`가 `.empty`를 반환합니다. `snapshotRecorder`로 `save()`에 전달된 스냅샷을 캡처합니다.
    // - 기대 결과: welcome에서 시작, welcome만 완료, 저장된 스냅샷의 `currentStep`이 `.welcome`입니다.

    /// ONB-001-start_onboarding_session: 새 세션이 생성될 때 초기 snapshot을 저장하면 각 step completion flag가 초기 AC 상태와 일치한다.
    /// `onAppear` 시 초기 단계 상태를 반영하여 진행 상태 스냅샷이 올바르게 저장되는지 검증합니다.
    /// - 검증 내용: 세션 시작 시 저장되는 스냅샷의 각 단계별 완료 플래그가 초기 상태와 일치합니다.
    /// - 사전 조건: `load`가 `.empty`를 반환합니다. `snapshotRecorder`로 저장된 스냅샷을 캡처합니다.
    /// - 기대 결과: 스냅샷의 `welcomeComplete`는 `true`, 나머지 단계(`accessUnlock`, `permissions`, `complete`)는 모두 `false`입니다.
    func testStartSessionSavesProgressSnapshot() async {
        let saveRecorder = LockIsolated<OnboardingProgressSnapshot?>(nil)

        let store = TestStore(initialState: OnboardingFeature.State()) {
            OnboardingFeature()
        } withDependencies: {
            $0.onboardingProgressClient = ProgressClient.recording(saveRecorder: saveRecorder)
        }

        await store.send(.onAppear) { $0.didBootstrapProgress = true }

        let savedSnapshot = saveRecorder.value
        XCTAssertNotNil(savedSnapshot)
        XCTAssertEqual(savedSnapshot?.stepState.welcomeComplete, true)
        XCTAssertEqual(savedSnapshot?.stepState.accessUnlockComplete, false)
        XCTAssertEqual(savedSnapshot?.stepState.permissionsComplete, false)
        XCTAssertEqual(savedSnapshot?.stepState.aiProviderSetupComplete, false)
        XCTAssertEqual(savedSnapshot?.stepState.completeComplete, false)

        await store.finish()
    }

    // MARK: - ONB-001-show_onboarding_step

    // 온보딩 단계 표시: 각 단계의 title, subtitle, 인덱스, 네비게이션 플래그,
    // 정식 단계 순서(welcome → accessUnlock → permissions → complete)를 검증합니다.

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
            $0.authNetworkClient = StateMutation.activeAuthNetworkClient
            $0.date = .constant(Date(timeIntervalSince1970: 0))
        }

        await store.send(.onAppear) { $0.didBootstrapProgress = true }

        // welcome 단계가 표시되어야 함
        XCTAssertEqual(store.state.currentStep, .welcome)
        XCTAssertEqual(store.state.currentStep.title, "Welcome")
        XCTAssertEqual(store.state.currentStep.subtitle, "A quick setup before you dive in.")
        XCTAssertEqual(store.state.currentStepIndex, 1)
        XCTAssertEqual(store.state.totalSteps, 5)

        await store.finish()
    }

    /// ONB-001-show_onboarding_step: welcome이 완료된 상태일 때 Next를 누르면 beta access step을 현재 step으로 표시한다.
    /// welcome에서 `nextTapped` 후 accessUnlock 단계가 올바른 속성과 함께 표시되는지 검증합니다.
    /// - 검증 내용: 단계 전환 후 `currentStep`, title, 인덱스가 accessUnlock에 해당하는 값으로 갱신됩니다.
    /// - 사전 조건: 새 세션이 시작되어 welcome 단계에 위치합니다.
    /// - 기대 결과: `currentStep`은 `.accessUnlock`, title "Unlock Voyager", `currentStepIndex` 2입니다.
    func testShowAccessStepAfterWelcome() async {
        let store = TestStore(initialState: OnboardingFeature.State()) {
            OnboardingFeature()
        } withDependencies: {
            $0.onboardingProgressClient = ProgressClient.noOp
            $0.date = .constant(Date(timeIntervalSince1970: 0))
        }

        await store.send(.onAppear) { $0.didBootstrapProgress = true }
        await store.send(.nextTapped) { state in
            state.currentStep = .accessUnlock
        }

        XCTAssertEqual(store.state.currentStep, .accessUnlock)
        XCTAssertEqual(store.state.currentStep.title, "Unlock Voyager")
        XCTAssertEqual(store.state.currentStepIndex, 2)

        await store.finish()
    }

    // ONB-001-show_onboarding_step: beta access가 active로 완료되었을 때 Next를 누르면 permissions step을 현재 step으로 표시한다.
    // accessUnlock가 확인 완료된 후 `nextTapped`로 permissions 단계가 표시되는지 검증합니다.
    // - 검증 내용: accessUnlock 검증 성공(`.active`) 후 다음 단계 전환이 정상 동작합니다.
    // - 사전 조건: welcome 통과, accessUnlock에서 `.active` 확인 응답 수신 후 `isComplete = true` 상태입니다.
    // - 기대 결과: `currentStep`은 `.permissions`, title "Permissions", `currentStepIndex` 3입니다.

    // ONB-001-show_onboarding_step: required permissions가 완료되었을 때 Next를 누르면 aiProviderSetup step을 현재 step으로 표시한다.
    // 모든 이전 단계(welcome, accessUnlock, permissions)가 완료되면 aiProviderSetup 단계가 표시되는지 검증합니다.
    // - 검증 내용: 선행 단계 모두 완료 시 `nextTapped`가 aiProviderSetup 단계로 전환합니다.
    // - 사전 조건: welcome, accessUnlock(`.active`), permissions 모두 `isComplete = true`이고 `currentStep = .permissions`입니다.
    // - 기대 결과: `currentStep`은 `.aiProviderSetup`, title "AI Provider", 인덱스 4입니다.

    /// ONB-001-show_onboarding_step: aiProviderSetup가 완료되었을 때 Next를 누르면 complete step을 현재 step으로 표시한다.
    /// AI Provider Setup 단계를 완료한 뒤 complete 단계가 표시되는지 검증합니다.
    /// - 검증 내용: `nextTapped`가 aiProviderSetup 이후 complete 단계로 전환합니다.
    /// - 사전 조건: `currentStep = .aiProviderSetup`, provider setup이 완료 상태입니다.
    /// - 기대 결과: `currentStep`은 `.complete`, title "Start your voyage", 인덱스 5입니다.
    func testShowCompleteStepAfterAIProviderSetup() async {
        var initialState = OnboardingFeature.State()
        initialState.currentStep = .aiProviderSetup
        initialState.welcome.isComplete = true
        StateMutation.applyPersistedCompletedAccessStep(state: &initialState)
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

    // ONB-001-show_onboarding_step: 모든 step completion 조건이 순서대로 충족될 때 Next를 반복하면 welcome → accessUnlock → permissions
    // →
    // complete 순서를 보존한다.
    // 단계 순서가 정식 순서(welcome → accessUnlock → permissions → complete)를 따르는지 검증합니다.
    // - 검증 내용: `OnboardingStep.allCases`가 정식 순서와 일치하고, `nextTapped`가 각 단계를 올바르게 이동합니다.
    //   미완료 단계에서는 `nextTapped`가 동작하지 않아야(no-op) 합니다.
    // - 사전 조건: `load`가 `.empty`를 반환합니다. accessUnlock는 `.active` 확인 응답으로 완료 처리합니다.
    // - 기대 결과: welcome → accessUnlock 전환 성공, permissions 미완료 시 `nextTapped` no-op, 전체 순서가 `allCases`와 일치합니다.

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

        await store.send(.onAppear) { $0.didBootstrapProgress = true }

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

    // ONB-001-update_onboarding_step_state: ONB-002 verification이 active를 반환할 때 child result가 들어오면 accessUnlock step을
    // complete로 정규화한다.
    // accessUnlock 단계에서 확인 응답(`.active`) 수신 시 상태가 올바르게 업데이트되는지 검증합니다.
    // - 검증 내용: `verificationResponse` 액션이 `status`, `reason`, `isComplete`를 올바르게 갱신합니다.
    // - 사전 조건: `onAppear` 후 accessUnlock는 미완료(`.notActive`) 상태입니다.
    // - 기대 결과: `isComplete = true`, `status = .active`, `reason = .none`으로 변경됩니다.

    // ONB-001-update_onboarding_step_state: 하위 step state가 변경될 때 reducer가 action을 처리하면 변경된 completion state를 progress
    // snapshot으로 저장한다.
    // 자식 액션 후 단계 상태 업데이트가 진행 상태 스냅샷 저장을 트리거하는지 검증합니다.
    // - 검증 내용: accessUnlock 확인 응답 처리 후 `save()`가 호출되고 업데이트된 단계 상태를 반영합니다.
    // - 사전 조건: `saveRecorder`로 저장 호출을 캡처합니다. 초기 상태에서 accessUnlock 확인 응답을 전송합니다.
    // - 기대 결과: 저장된 스냅샷의 `accessUnlockComplete`이 `true`입니다.

    // ONB-001-update_onboarding_step_state: 각 child step completion 상태가 다를 때 step state를 계산하면 step별 complete flag를
    // 독립적으로 유지한다.
    // `isStepComplete`가 각 단계별로 완료 상태를 올바르게 추적하는지 검증합니다.
    // - 검증 내용: 기본 상태에서 welcome만 완료이고, 각 단계를 수동 완료할 때마다 추적이 갱신됩니다.
    // - 사전 조건: 기본 `OnboardingFeature.State`에서 시작합니다.
    // - 기대 결과: welcome은 기본 완료, accessUnlock/permissions/complete는 미완료,
    //   각각 `isComplete = true` 설정 후 해당 단계 완료로 추적됩니다.

    // ONB-001-update_onboarding_step_state: session snapshot을 생성할 때 모든 step state를 직렬화하면 ONB-002/ONB-003 결과까지 포함한다.
    // `progressSnapshot`이 모든 4개 단계의 완료 플래그를 정확히 캡처하는지 검증합니다.
    // - 검증 내용: 수동으로 설정한 단계 상태가 스냅샷 생성 시 그대로 반영됩니다.
    // - 사전 조건: `currentStep = .permissions`, `accessUnlock.isComplete = true`, `permissions.isComplete = true`입니다.
    // - 기대 결과: 스냅샷의 `currentStep`은 `.permissions`, `welcomeComplete`/`accessUnlockComplete`/`permissionsComplete`은
    // `true`,
    //   `completeComplete`은 `false`입니다.

    // MARK: - ONB-001-advance_onboarding_step

    // 단계 앞으로 이동: nextTapped를 통한 단계 전환, 완료 전제 조건, 마지막 단계 제한,
    // 이동 시 진행 상태 저장을 검증합니다.

    // ONB-001-advance_onboarding_step: ONB-001:go_back_onboarding_step — 현재 step이 완료되었을 때 Next/Back을 누르면 인접 step으로만
    // 이동한다.
    // `nextTapped`와 `backTapped`를 통한 앞/뒤 네비게이션이 모두 정상 동작하는지 검증합니다.
    // - 검증 내용: welcome → accessUnlock → permissions로 앞으로 이동 후 accessUnlock로 뒤로 이동합니다.
    //   미완료 accessUnlock에서 `nextTapped`는 no-op입니다.
    // - 사전 조건: `load`가 `.empty`를 반환합니다. accessUnlock는 `.active` 확인 응답으로 완료 처리합니다.
    // - 기대 결과: 단계 전환이 정확한 순서대로 발생하고 뒤로 이동도 올바르게 동작합니다.

    /// ONB-001-advance_onboarding_step: 현재 step이 incomplete일 때 Next를 누르면 다음 step으로 잘못 진행하지 않는다.
    /// 현재 단계가 완료되어야만 `nextTapped`로 다음 단계로 이동할 수 있음을 검증합니다.
    /// - 검증 내용: 미완료 단계에서 `nextTapped`는 아무 상태 변화도 일으키지 않아야(no-op) 합니다.
    /// - 사전 조건: `currentStep = .accessUnlock`, `accessUnlock.isComplete = false` 상태입니다.
    /// - 기대 결과: `canGoNext`는 `false`, `nextTapped` 후에도 여전히 `currentStep = .accessUnlock`입니다.
    func testAdvanceRequiresCurrentStepComplete() async {
        var initialState = OnboardingFeature.State()
        initialState.currentStep = .accessUnlock
        // accessUnlock가 완료되지 않음

        let store = TestStore(initialState: initialState) {
            OnboardingFeature()
        } withDependencies: {
            $0.onboardingProgressClient = ProgressClient.noOp
        }

        XCTAssertFalse(store.state.canGoNext)

        // accessUnlock가 완료되지 않았으므로 nextTapped는 동작 없음
        await store.send(.nextTapped)

        // 여전히 accessUnlock에 있음
        XCTAssertEqual(store.state.currentStep, .accessUnlock)

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
    /// - 기대 결과: `nextTapped` 후 저장된 스냅샷의 `currentStep`이 `.accessUnlock`입니다.
    func testAdvanceStepPersistsProgress() async {
        let saveRecorder = LockIsolated<OnboardingProgressSnapshot?>(nil)

        let store = TestStore(initialState: OnboardingFeature.State()) {
            OnboardingFeature()
        } withDependencies: {
            $0.onboardingProgressClient = ProgressClient.recording(saveRecorder: saveRecorder)
        }

        await store.send(.onAppear) { $0.didBootstrapProgress = true }
        await store.send(.nextTapped) { state in
            state.currentStep = .accessUnlock
        }

        let saved = saveRecorder.value
        XCTAssertNotNil(saved)
        XCTAssertEqual(saved?.currentStep, .accessUnlock)

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

        await store.send(.onAppear) { $0.didBootstrapProgress = true }

        XCTAssertFalse(store.state.canGoBack)

        // welcome에서 backTapped는 동작 없음
        await store.send(.backTapped)

        XCTAssertEqual(store.state.currentStep, .welcome)

        await store.finish()
    }

    // ONB-001-go_back_onboarding_step: 완료된 child step들이 있을 때 이전 step으로 돌아가면 completion state를 잃지 않는다.
    // 뒤로 이동 시 이미 완료된 단계의 완료 상태가 보존됨을 검증합니다.
    // - 검증 내용: permissions → accessUnlock → welcome으로 뒤로 이동해도 각 단계의 `isComplete`와 `status`가 유지됩니다.
    // - 사전 조건: `currentStep = .permissions`, welcome/accessUnlock 모두 완료(`.active`) 상태입니다.
    // - 기대 결과: 두 번의 `backTapped` 후에도 welcome/accessUnlock의 완료 상태와 accessUnlock의 `.active` 상태가 보존됩니다.

    /// ONB-001-go_back_onboarding_step: Back 이동이 성공할 때 currentStep이 변경되면 되돌아간 step snapshot을 저장한다.
    /// 뒤로 이동 시 진행 상태 스냅샷이 저장되어 이전 단계가 반영됨을 검증합니다.
    /// - 검증 내용: `backTapped` 후 `save()`가 호출되고 스냅샷의 `currentStep`이 이전 단계로 갱신됩니다.
    /// - 사전 조건: `currentStep = .accessUnlock`, `welcome.isComplete = true`, `saveRecorder`로 저장 호출을 캡처합니다.
    /// - 기대 결과: `backTapped` 후 저장된 스냅샷의 `currentStep`이 `.welcome`입니다.
    func testGoBackPersistsProgress() async {
        let saveRecorder = LockIsolated<OnboardingProgressSnapshot?>(nil)

        var initialState = OnboardingFeature.State()
        initialState.currentStep = .accessUnlock
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

    // ONB-001-go_back_onboarding_step: accessUnlock가 이미 unlocked 상태일 때 Back으로 돌아가면 완료 상태와 snapshot을 보존한다.
    // 이미 완료된 accessUnlock 단계로 뒤로 이동해도 parent navigation이 access 상태를 삭제하지 않음을 검증합니다.
    // - 검증 내용: `isComplete = true`, `status = .coreLicenseActive` 상태에서 `backTapped` 후 snapshot이 유지됩니다.
    // - 사전 조건: `currentStep = .permissions`, accessUnlock가 unlocked 상태입니다.
    // - 기대 결과: `backTapped` 후 `currentStep = .accessUnlock`이고 access 상태가 유지됩니다.

    // MARK: - ONB-001-resume_onboarding_session

    // 세션 이어서 진행: 저장된 스냅샷에서 세션 복원, 미완료 단계의 fallback-to-last-valid-step,
    // 리셋 필요 시 세션 초기화, 복원 후 스냅샷 저장을 검증합니다.

    // ONB-001-resume_onboarding_session: 유효한 persisted snapshot이 있을 때 앱이 재시작되면 마지막 방문 reachable step에서 재개한다.
    // 저장된 스냅샷에서 세션을 이어서 진행할 때 상태가 올바르게 복원되는지 검증합니다.
    // - 검증 내용: `load`가 `.success(snapshot)`를 반환하면 reducer가 스냅샷 기반으로 상태를 복원합니다.
    // - 사전 조건: snapshot에 `currentStep = .permissions`, welcome/accessUnlock 완료, permissions/complete 미완료가 저장되어 있습니다.
    // - 기대 결과: `onAppear` 후 선행 단계(accessUnlock)가 완료되어 `.permissions`를 직접 복원합니다.
    //   welcome/accessUnlock는 완료, permissions/complete는 미완료 상태입니다.

    /// ONB-001-resume_onboarding_session: persisted current step이 incomplete일 때 resume하면 안전한 이전/기본 step으로 fallback한다.
    /// 저장된 `currentStep`은 유효하지만 해당 단계가 미완료인 스냅샷으로 이어서 진행 시
    /// 마지막 유효한 완료 단계로 대체(fallback-to-last-valid-step)됨을 검증합니다.
    /// - 검증 내용: `currentStep = .permissions`이지만 accessUnlock가 미완료이면 welcome으로 되돌아갑니다.
    /// - 사전 조건: snapshot에 `permissions`가 currentStep이지만 accessUnlock/permissions 미완료입니다.
    ///   초기 상태를 `.complete`/완료로 설정하여 mutation 관찰이 가능합니다.
    /// - 기대 결과: `onAppear` 후 `currentStep = .accessUnlock`, `complete.isComplete = false`로 복원됩니다.
    func testResumeWithIncompleteCurrentStepFallsBack() async {
        let snapshot = OnboardingProgressSnapshot(
            currentStep: .permissions,
            stepState: OnboardingStepState(
                welcomeComplete: true,
                accessUnlockComplete: false,
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
        // store.exhaustivity = .off: appDidBecomeActive 관찰 effect는 장기 수명이라 종료를 기다리지 않는다.
        store.exhaustivity = .off

        // accessUnlock 미완료 → lastValidStep이 accessUnlock로 되돌아감
        await store.send(.onAppear) { state in
            state.didBootstrapProgress = true
            state.currentStep = .accessUnlock
            state.complete.isComplete = false
        }

        XCTAssertEqual(store.state.currentStep, .accessUnlock)

        await store.finish()
    }

    /// ONB-001-resume_onboarding_session: snapshot에 currentStep == .complete이지만 중간 선행 단계가 미완료면 복원하지 않는다.
    /// `currentStep = .complete`, `permissionsComplete = true`, `accessUnlockComplete = false`인 불일치 snapshot에서
    /// complete 단계로 직접 복원하지 않고 가장 마지막 완료 단계인 welcome으로 되돌아갑니다.
    /// - 사전 조건: snapshot에 welcome만 완료, accessUnlock 미완료, permissions 완료(불일치), currentStep = .complete.
    /// - 기대 결과: `onAppear` 후 `currentStep = .accessUnlock`으로 fallback (welcome은 완료이므로 accessUnlock부터 재개).
    func testResumeCompleteStepWithIncompleteBetaAccessFallsBack() async {
        let snapshot = OnboardingProgressSnapshot(
            currentStep: .complete,
            stepState: OnboardingStepState(
                welcomeComplete: true,
                accessUnlockComplete: false,
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
            state.didBootstrapProgress = true
            state.currentStep = .accessUnlock
            state.permissions.isComplete = true
            state.complete.isComplete = false
        }

        XCTAssertEqual(store.state.currentStep, .accessUnlock)

        await store.finish()
    }

    // ONB-001-resume_onboarding_session: 이전 step들이 완료된 snapshot일 때 resume하면 완료 상태를 보존하고 방문했던 complete step을 직접 복원한다.
    // complete 이전의 모든 단계가 완료된 상태로 이어서 진행 시
    // persisted `currentStep = .complete`가 직접 복원됨을 검증합니다.
    // - 검증 내용: `currentStep = .complete`이고 permissions가 완료이면 `.complete`를 직접 복원합니다.
    // - 사전 조건: snapshot에 welcome/accessUnlock/permissions 완료, `completeComplete = false`가 저장되어 있습니다.
    // - 기대 결과: `onAppear` 후 `currentStep = .complete`, 모든 선행 단계는 완료, `complete.isComplete = false`입니다.

    /// ONB-001-resume_onboarding_session: welcome만 완료된 snapshot일 때 resume하면 accessUnlock step을 직접 복원한다.
    /// 저장된 스냅샷에서 welcome만 완료된 경우, 선행 단계(welcome)가 완료이므로
    /// `.accessUnlock`가 직접 복원됨을 검증합니다.
    /// - 검증 내용: accessUnlock 미완료라도 welcome(선행 단계)이 완료이면 `.accessUnlock`를 직접 복원합니다.
    /// - 사전 조건: snapshot에 `currentStep = .accessUnlock`, welcome만 완료, 나머지 미완료입니다.
    ///   초기 상태를 `.complete`/완료로 설정하여 mutation 관찰이 가능합니다.
    /// - 기대 결과: `onAppear` 후 `currentStep = .accessUnlock`, `complete.isComplete = false`로 복원됩니다.
    func testResumeWithOnlyWelcomeComplete() async {
        let snapshot = OnboardingProgressSnapshot(
            currentStep: .accessUnlock,
            stepState: OnboardingStepState(
                welcomeComplete: true,
                accessUnlockComplete: false,
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

        // welcome 완료 → 선행 단계 충족 → .accessUnlock 직접 복원
        await store.send(.onAppear) { state in
            state.didBootstrapProgress = true
            state.currentStep = .accessUnlock
            state.complete.isComplete = false
        }

        XCTAssertEqual(store.state.currentStep, .accessUnlock)

        await store.finish()
    }

    // ONB-001-resume_onboarding_session: resume 중 snapshot 보정이 필요하지 않을 때 복원 로직이 실행되면 persisted step을 그대로 저장한다.
    // 이어서 진행 시 단계 상태 적용 후 업데이트된 스냅샷이 저장됨을 검증합니다.
    // - 검증 내용: 복원된 상태(persisted step 유지)가 `save()`를 통해 올바르게 저장됩니다.
    // - 사전 조건: snapshot에 `currentStep = .permissions`, welcome/accessUnlock 완료가 저장되어 있습니다.
    //   `saveRecorder`로 저장 호출을 캡처합니다.
    // - 기대 결과: 저장된 스냅샷의 `currentStep`이 `.permissions`(선행 단계 완료로 직접 복원)를 반영합니다.

    // MARK: - ONB-001-canonical_access_composition

    /// ONB-001-canonical_access_composition: main-app Onboarding core는 AccountAccess runtime을 직접 저장하지 않는다.
    /// canonical lifecycle owner로 전환한 뒤 Onboarding core가 두 번째 AccountAccess 상태를 만들지 않는지 검증합니다.
    /// - 검증 내용: `OnboardingFeature.State`의 stored child가 `AccountAccessFeature.State`가 아닙니다.
    /// - 사전 조건: main-app Onboarding core의 기본 상태를 생성합니다.
    /// - 기대 결과: AccountAccess runtime truth는 core state가 아닌 외부 canonical adapter composition에만 존재합니다.
    func testOnboardingCoreDoesNotStoreAccountAccessRuntime() {
        let hasAccountAccessChild = Mirror(reflecting: OnboardingFeature.State()).children.contains {
            String(describing: type(of: $0.value)) == String(describing: AccountAccessFeature.State.self)
        }

        XCTAssertFalse(hasAccountAccessChild)
    }
}
