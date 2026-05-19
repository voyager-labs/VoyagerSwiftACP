import ComposableArchitecture
import VoyagerFeaturesBetaAccess
@testable import VoyagerPagesOnboarding
import XCTest

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

    // MARK: - ONB-001-show_onboarding_step

    // (Tests to be added in future task)

    // MARK: - ONB-001-update_onboarding_step_state

    // (Tests to be added in future task)

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

    // MARK: - ONB-001-go_back_onboarding_step

    // (Covered by testNextBackNavigation above — backTapped at end of test)

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
}
