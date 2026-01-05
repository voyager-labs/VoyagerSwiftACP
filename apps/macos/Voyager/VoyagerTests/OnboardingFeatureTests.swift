import ComposableArchitecture
@testable import Voyager
import XCTest

@MainActor
final class OnboardingFeatureTests: XCTestCase {
    func testNextBackNavigation() async {
        let store = TestStore(initialState: OnboardingFeature.State()) {
            OnboardingFeature()
        } withDependencies: {
            $0.onboardingProgressStore = OnboardingProgressStore(
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

        await store.send(.betaAccess(.setCompleted(true))) { state in
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

    func testResumeFromPersistedState() async {
        let snapshot = OnboardingProgressSnapshot(
            currentStep: .permissions,
            stepState: OnboardingStepState(
                welcomeComplete: true,
                betaAccessComplete: true,
                permissionsComplete: false,
                indexingPresetComplete: false,
                completeComplete: false,
            ),
        )

        let store = TestStore(initialState: OnboardingFeature.State()) {
            OnboardingFeature()
        } withDependencies: {
            $0.onboardingProgressStore = OnboardingProgressStore(
                load: { .success(snapshot) },
                save: { _ in },
                reset: {},
            )
        }

        await store.send(.onAppear) { state in
            state.currentStep = .betaAccess
            state.showResumeBanner = true
            state.welcome.isComplete = true
            state.betaAccess.isComplete = true
            state.permissions.isComplete = false
            state.indexingPreset.isComplete = false
            state.complete.isComplete = false
        }

        await store.finish()
    }

    func testResetOnVersionMismatch() async {
        let store = TestStore(initialState: OnboardingFeature.State()) {
            OnboardingFeature()
        } withDependencies: {
            $0.onboardingProgressStore = OnboardingProgressStore(
                load: { .resetRequired },
                save: { _ in },
                reset: {},
            )
        }

        await store.send(.onAppear)

        XCTAssertEqual(store.state.currentStep, .welcome)
        XCTAssertFalse(store.state.showResumeBanner)
        XCTAssertTrue(store.state.welcome.isComplete)
        XCTAssertFalse(store.state.betaAccess.isComplete)
        XCTAssertFalse(store.state.permissions.isComplete)
        XCTAssertFalse(store.state.indexingPreset.isComplete)
        XCTAssertFalse(store.state.complete.isComplete)

        await store.finish()
    }
}
