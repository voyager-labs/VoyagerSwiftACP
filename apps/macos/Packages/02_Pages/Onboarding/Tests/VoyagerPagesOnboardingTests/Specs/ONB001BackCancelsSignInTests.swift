import ComposableArchitecture
@testable import VoyagerPagesOnboarding
import XCTest

@MainActor
final class ONB001BackCancelsSignInTests: XCTestCase {
    func testGoBackFromAccessUnlockCancelsPendingSignIn() async {
        var initialState = OnboardingFeature.State()
        initialState.currentStep = .accessUnlock
        initialState.welcome.isComplete = true
        initialState.accessUnlock.isSignInInProgress = true
        initialState.accessUnlock.handoffPendingState = "pending-state-abc"

        let store = TestStore(initialState: initialState) {
            OnboardingFeature()
        } withDependencies: {
            $0.onboardingProgressClient = ProgressClient.noOp
        }

        await store.send(.backTapped) { state in
            state.currentStep = .welcome
        }

        await store.receive(\.accessUnlock.cancelSignIn) { state in
            state.accessUnlock.isSignInInProgress = false
            state.accessUnlock.didSignInFail = false
            state.accessUnlock.handoffPendingState = nil
        }

        await store.finish()
    }
}
