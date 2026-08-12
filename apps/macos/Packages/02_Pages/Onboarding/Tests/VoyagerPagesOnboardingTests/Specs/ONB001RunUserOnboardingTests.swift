import ComposableArchitecture
@testable import VoyagerPagesOnboarding
import XCTest

@MainActor
final class ONB001RunUserOnboardingTests: XCTestCase {
    func testFreshSessionStartsAtWelcomeWithFourSteps() async {
        let store = TestStore(initialState: OnboardingFeature.State()) {
            OnboardingFeature()
        } withDependencies: {
            $0.onboardingProgressClient = ProgressClient.noOp
        }

        await store.send(.onAppear) { state in
            state.didBootstrapProgress = true
        }

        XCTAssertEqual(store.state.currentStep, .welcome)
        XCTAssertEqual(store.state.totalSteps, 4)
        await store.finish()
    }

    func testNextMovesFromWelcomeToPermissions() async {
        var initialState = OnboardingFeature.State()
        initialState.welcome.isComplete = true
        let store = TestStore(initialState: initialState) {
            OnboardingFeature()
        } withDependencies: {
            $0.onboardingProgressClient = ProgressClient.noOp
        }

        await store.send(.nextTapped) { state in
            state.currentStep = .permissions
        }
        await store.finish()
    }
}
