// swiftlint:disable file_length

import ComposableArchitecture
import VoyagerFeaturesBetaAccess
@testable import VoyagerPagesOnboarding
import XCTest

// swiftlint:disable type_body_length
@MainActor
final class ONB001RunUserOnboardingFeatureTests: XCTestCase {
    // MARK: - ONB-001-start_onboarding_session

    /// Covers session reset when persisted version mismatches app version.
    /// Secondary coverage: ONB-001-show_onboarding_step (onAppear triggers initial step display).
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

    /// Covers fresh session start when no persisted progress exists.
    /// Verifies initial state shows welcome step and correct default step states.
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

        // Fresh session always starts at welcome
        XCTAssertEqual(store.state.currentStep, .welcome)
        XCTAssertTrue(store.state.welcome.isComplete)
        XCTAssertFalse(store.state.betaAccess.isComplete)
        XCTAssertFalse(store.state.permissions.isComplete)
        XCTAssertFalse(store.state.complete.isComplete)

        // Verify canGoNext is true (welcome is complete by default)
        XCTAssertTrue(store.state.canGoNext)
        XCTAssertFalse(store.state.canGoBack)

        await store.finish()
    }

    /// Covers that resetRequired triggers both reset() and save() in the effect.
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

    /// load returns .empty → state resets to fresh session and saves snapshot.
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

        // Fresh session always starts at welcome
        XCTAssertEqual(store.state.currentStep, .welcome)
        XCTAssertTrue(store.state.welcome.isComplete)
        XCTAssertFalse(store.state.betaAccess.isComplete)
        XCTAssertFalse(store.state.permissions.isComplete)
        XCTAssertFalse(store.state.complete.isComplete)

        // Verify snapshot was saved with correct initial state
        let savedSnapshot = await snapshotRecorder.value
        XCTAssertNotNil(savedSnapshot)
        XCTAssertEqual(savedSnapshot?.currentStep, .welcome)

        await store.finish()
    }

    /// onAppear saves a progress snapshot reflecting the initial step states.
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

    /// Covers that the welcome step is displayed on initial onAppear with correct properties.
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

        // Welcome step should be shown
        XCTAssertEqual(store.state.currentStep, .welcome)
        XCTAssertEqual(store.state.currentStep.title, "Welcome")
        XCTAssertEqual(store.state.currentStep.subtitle, "A quick setup before you dive in.")
        XCTAssertEqual(store.state.currentStepIndex, 1)
        XCTAssertEqual(store.state.totalSteps, 4)

        await store.finish()
    }

    /// Covers that betaAccess step is displayed after advancing from welcome.
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

    /// Covers that permissions step is displayed after betaAccess is verified and advanced.
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

    /// Covers that the complete step is displayed when all prior steps are done.
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

    /// Initial state shows welcome step with correct navigation flags.
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

    /// Verify step order: welcome → betaAccess → permissions → complete
    /// and that nextTapped advances through each step.
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

        // Complete beta access to enable next navigation
        await store.send(.betaAccess(.verificationResponse(BetaAccessVerificationResult(status: .active)))) { state in
            state.betaAccess.status = .active
            state.betaAccess.reason = .none
            state.betaAccess.isComplete = true
        }

        // betaAccess → permissions
        await store.send(.nextTapped) { state in
            state.currentStep = .permissions
        }

        // permissions not complete — nextTapped should be no-op
        await store.send(.nextTapped)

        await store.finish()
    }

    // MARK: - ONB-001-update_onboarding_step_state

    /// Covers that welcome step state update via child action propagates correctly.
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

        // Welcome starts complete; toggle it off then back on
        await store.send(.welcome(.setCompleted(false))) { state in
            state.welcome.isComplete = false
        }

        XCTAssertFalse(store.state.welcome.isComplete)
        XCTAssertFalse(store.state.canGoNext) // welcome not complete → can't go next

        await store.send(.welcome(.setCompleted(true))) { state in
            state.welcome.isComplete = true
        }

        XCTAssertTrue(store.state.welcome.isComplete)
        XCTAssertTrue(store.state.canGoNext)

        await store.finish()
    }

    /// Covers that betaAccess step state updates propagate through verification response.
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

        // Beta access starts incomplete
        XCTAssertFalse(store.state.betaAccess.isComplete)
        XCTAssertEqual(store.state.betaAccess.status, .notActive)

        // Successful verification updates state
        await store.send(.betaAccess(.verificationResponse(BetaAccessVerificationResult(status: .active)))) { state in
            state.betaAccess.status = .active
            state.betaAccess.reason = .none
            state.betaAccess.isComplete = true
        }

        XCTAssertTrue(store.state.betaAccess.isComplete)
        XCTAssertEqual(store.state.betaAccess.status, .active)

        await store.finish()
    }

    /// Covers that step state update persists via snapshot after child action.
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

        // The save should have been called with updated snapshot
        let saved = saveRecorder.value
        XCTAssertNotNil(saved)
        // swiftlint:disable:next force_unwrapping
        XCTAssertTrue(saved!.stepState.betaAccessComplete)

        await store.finish()
    }

    /// isStepComplete correctly tracks completion per step.
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

    /// progressSnapshot captures all 4 step completion flags.
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

    /// Covers forward navigation through onboarding steps via nextTapped.
    /// Also covers ONB-001-go_back_onboarding_step (backward navigation via backTapped).
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

    /// Covers that advancing requires the current step to be complete.
    /// nextTapped on an incomplete step should be a no-op.
    func testAdvanceRequiresCurrentStepComplete() async {
        var initialState = OnboardingFeature.State()
        initialState.currentStep = .betaAccess
        // betaAccess is NOT complete

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

        // nextTapped should be a no-op since betaAccess is not complete
        await store.send(.nextTapped)

        // Still on betaAccess
        XCTAssertEqual(store.state.currentStep, .betaAccess)

        await store.finish()
    }

    /// Covers that advancing from the last step (complete) is not possible.
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

    /// Covers that advancing persists the new step via progress snapshot save.
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

    /// Covers that backward navigation from the first step (welcome) is not possible.
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

        // backTapped on welcome should be a no-op
        await store.send(.backTapped)

        XCTAssertEqual(store.state.currentStep, .welcome)

        await store.finish()
    }

    /// Covers that backward navigation preserves completed step states.
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

        // Go back from permissions → betaAccess
        await store.send(.backTapped) { state in
            state.currentStep = .betaAccess
        }

        // Step completion states are preserved
        XCTAssertTrue(store.state.welcome.isComplete)
        XCTAssertTrue(store.state.betaAccess.isComplete)
        XCTAssertEqual(store.state.betaAccess.status, .active)

        // Go back from betaAccess → welcome
        await store.send(.backTapped) { state in
            state.currentStep = .welcome
        }

        XCTAssertTrue(store.state.welcome.isComplete)
        XCTAssertTrue(store.state.betaAccess.isComplete)

        await store.finish()
    }

    /// Covers that backward navigation saves progress snapshot.
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

    /// Covers resume with a snapshot where the persisted currentStep is valid but
    /// the step itself is not complete — falls back to last valid completed step.
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

        // Start with a non-default initial state so the resume mutation is observable
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

        // permissions is not complete → lastValidStep should walk back to welcome
        await store.send(.onAppear) { state in
            state.currentStep = .welcome
            state.complete.isComplete = false
        }

        XCTAssertEqual(store.state.currentStep, .welcome)

        await store.finish()
    }

    /// Covers resume with all steps prior to complete finished — should land on the last completed step.
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

        // complete is not complete → lastValidStep walks back to permissions (which IS complete)
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

    /// Covers resume when persisted snapshot has only welcome complete — should show welcome.
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

        // Start with a non-default initial state so the resume mutation is observable
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

        // betaAccess not complete → falls back to welcome (which is complete)
        await store.send(.onAppear) { state in
            state.currentStep = .welcome
            state.complete.isComplete = false
        }

        XCTAssertEqual(store.state.currentStep, .welcome)

        await store.finish()
    }

    /// Covers resume persists updated snapshot after applying step state.
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
        // The saved snapshot should reflect the corrected step (betaAccess, not permissions)
        XCTAssertEqual(saved?.currentStep, .betaAccess)

        await store.finish()
    }

    /// load returns .resetRequired → state resets to welcome and saves fresh snapshot.
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

    /// Snapshot has a valid step (complete) but incomplete prerequisites → falls back to last valid step.
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
        // Applied state matches defaults so no closure needed
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

    /// Covers re-entry after session completion — resumed session skips to completed state.
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

    /// Completion saves a snapshot with all steps marked complete.
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

    /// Calling startUsingTapped twice opens the window twice (reducer has no idempotency guard).
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

        // First completion
        await store.send(.complete(.startUsingTapped)) { state in
            state.complete.isComplete = true
            state.complete.isOpeningWindow = true
            state.complete.openWindowError = nil
        }
        await store.receive(\.complete.openWindowResponse) { state in
            state.complete.isOpeningWindow = false
        }

        // Second call — reducer repeats the full flow
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

    /// openMainWindow returns false → error state is set.
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

    /// Covers completion failure path — openMainWindow returns false, error is set.
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

    /// Covers retry after completion failure — retryTapped should re-attempt window open.
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

        // Error should be cleared after successful retry
        XCTAssertNil(store.state.complete.openWindowError)
        let paths = await pathRecorder.snapshot()
        XCTAssertEqual(paths.count, 1)

        await store.finish()
    }

    /// Covers idempotent completion — calling startUsingTapped twice sets isComplete consistently.
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

        // First completion
        await store.send(.complete(.startUsingTapped)) { state in
            state.complete.isComplete = true
            state.complete.isOpeningWindow = true
            state.complete.openWindowError = nil
        }
        await store.receive(\.complete.openWindowResponse) { state in
            state.complete.isOpeningWindow = false
        }

        // Second completion attempt (idempotent)
        await store.send(.complete(.startUsingTapped)) { state in
            state.complete.isOpeningWindow = true
            state.complete.openWindowError = nil
        }
        await store.receive(\.complete.openWindowResponse) { state in
            state.complete.isOpeningWindow = false
        }

        // Both attempts should open window
        let paths = await pathRecorder.snapshot()
        XCTAssertEqual(paths.count, 2)
        XCTAssertTrue(store.state.complete.isComplete)

        await store.finish()
    }

    /// Covers re-entry: when a user who already completed onboarding relaunches,
    /// the session loads fully complete and marks sessionComplete.
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
