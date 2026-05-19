// swiftlint:disable file_length

import ComposableArchitecture
import VoyagerFeaturesBetaAccess
@testable import VoyagerPagesOnboarding
import XCTest

// swiftlint:disable type_body_length
@MainActor
final class ONB001RunUserOnboardingFeatureTests: XCTestCase {
    // MARK: - ONB-001-start_onboarding_session

    /// 저장된 버전이 앱 버전과 불일치할 때 세션 초기화를 검증합니다.
    /// 부가 검증: ONB-001-show_onboarding_step (onAppear가 초기 단계 표시를 트리거).
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

    /// 저장된 진행 상태가 없을 때 새 세션 시작을 검증합니다.
    /// 초기 상태가 welcome 단계를 표시하고 올바른 기본 단계 상태를 가지는지 확인합니다.
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

    /// resetRequired가 effect에서 reset()과 save()를 모두 트리거하는지 검증합니다.
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

    /// load가 .empty를 반환하면 → 상태가 새 세션으로 초기화되고 스냅샷을 저장합니다.
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

    /// onAppear가 초기 단계 상태를 반영하여 진행 상태 스냅샷을 저장합니다.
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

    /// 초기 onAppear 시 welcome 단계가 올바른 속성과 함께 표시되는지 검증합니다.
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

    /// welcome에서 이동한 후 betaAccess 단계가 표시되는지 검증합니다.
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

    /// betaAccess가 확인되고 이동한 후 permissions 단계가 표시되는지 검증합니다.
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

    /// 모든 이전 단계가 완료되면 complete 단계가 표시되는지 검증합니다.
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

    /// 초기 상태가 올바른 네비게이션 플래그와 함께 welcome 단계를 표시합니다.
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

    /// 단계 순서 검증: welcome → betaAccess → permissions → complete
    /// nextTapped가 각 단계를 올바르게 이동하는지 확인합니다.
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

    /// 자식 액션을 통한 welcome 단계 상태 업데이트가 올바르게 전파되는지 검증합니다.
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

    /// betaAccess 단계 상태 업데이트가 확인 응답을 통해 전파되는지 검증합니다.
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

    /// 자식 액션 후 단계 상태 업데이트가 스냅샷을 통해 저장되는지 검증합니다.
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

    /// isStepComplete가 각 단계별로 완료 상태를 올바르게 추적합니다.
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

    /// progressSnapshot이 모든 4개 단계의 완료 플래그를 캡처합니다.
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

    /// nextTapped를 통한 온보딩 단계 앞으로 네비게이션을 검증합니다.
    /// ONB-001-go_back_onboarding_step (backTapped를 통한 뒤로 네비게이션)도 함께 검증합니다.
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

    /// 현재 단계가 완료되어야 다음으로 이동할 수 있음을 검증합니다.
    /// 미완료 단계에서 nextTapped는 동작 없음(no-op)이어야 합니다.
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

    /// 마지막 단계(complete)에서는 앞으로 이동할 수 없음을 검증합니다.
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

    /// 이동 시 진행 상태 스냅샷 저장을 통해 새 단계가 저장되는지 검증합니다.
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

    /// 첫 번째 단계(welcome)에서는 뒤로 이동할 수 없음을 검증합니다.
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

    /// 뒤로 이동 시 완료된 단계 상태가 보존됨을 검증합니다.
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

    /// 뒤로 이동 시 진행 상태 스냅샷이 저장됨을 검증합니다.
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

    /// 저장된 currentStep은 유효하지만 해당 단계가 완료되지 않은 스냅샷으로 이어서 진행 시
    /// 마지막 유효한 완료 단계로 대체(fallback)됨을 검증합니다.
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
    /// 마지막 완료 단계에 위치해야 함을 검증합니다.
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

    /// 저장된 스냅샷에서 welcome만 완료된 경우 — welcome이 표시되어야 함을 검증합니다.
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

    /// load가 .resetRequired를 반환하면 → 상태가 welcome으로 초기화되고 새 스냅샷을 저장합니다.
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

    /// 스냅샷에 유효한 단계(complete)가 있지만 선행 조건이 미완료 → 마지막 유효 단계로 대체됨을 검증합니다.
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

    /// 세션 완료 후 재진입 — 이어서 진행 세션이 완료된 상태로 건너뜀을 검증합니다.
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

    /// 완료 시 모든 단계가 완료로 표시된 스냅샷을 저장합니다.
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

    /// startUsingTapped를 두 번 호출하면 창이 두 번 열립니다 (reducer에 멱등성 가드 없음).
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

    /// openMainWindow가 false를 반환하면 → 에러 상태가 설정됩니다.
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

    /// 완료 실패 경로 검증 — openMainWindow가 false를 반환하고 에러가 설정됨.
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

    /// 완료 실패 후 재시도 — retryTapped가 창 열기를 재시도해야 함을 검증합니다.
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

    /// 멱등적 완료 — startUsingTapped를 두 번 호출해도 isComplete가 일관되게 설정됨을 검증합니다.
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
    /// 세션이 완전히 완료된 상태로 로드되고 sessionComplete을 표시함을 검증합니다.
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
