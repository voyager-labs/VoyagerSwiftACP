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

    /// ONB-001-complete_onboarding: completion passes the typed default start page request to the app boundary.
    /// Onboarding placement remains unchanged while the default-tab payload is preserved for typed preference
    /// resolution.
    /// - 검증 내용: completion invokes `openMainWindow(.defaultTabPath)` rather than discarding the request.
    /// - 사전 조건: onboarding state is complete and the window client records requests.
    /// - 기대 결과: recorder contains exactly `.defaultTabPath`.
    func testCompletionPassesDefaultTabPathPayloadToWindowBoundary() async {
        var initialState = OnboardingFeature.State()
        initialState.currentStep = .complete
        initialState.complete.isComplete = true
        let pathRecorder = PathRecorder()
        let store = TestStore(initialState: initialState) {
            OnboardingFeature()
        } withDependencies: {
            $0.onboardingProgressClient = ProgressClient.noOp
            $0.onboardingWindowClient = WindowClient.recording(pathRecorder: pathRecorder)
        }

        await store.send(.complete(.startUsingTapped)) { state in
            state.complete.isOpeningWindow = true
        }
        await store.receive(\.complete.openWindowResponse) { state in
            state.complete.isOpeningWindow = false
            state.complete.isComplete = true
        }

        let requests = await pathRecorder.snapshot()
        XCTAssertEqual(requests, [.defaultTabPath])
    }
}
