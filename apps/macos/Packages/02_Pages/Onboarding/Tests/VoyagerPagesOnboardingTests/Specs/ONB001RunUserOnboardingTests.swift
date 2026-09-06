import ComposableArchitecture
@testable import VoyagerPagesOnboarding
import XCTest

@MainActor
final class ONB001RunUserOnboardingTests: XCTestCase {
    func testCompletionDoesNotOpenWindowOrEmitSuccessWhenPersistenceFails() async throws {
        let metrics = LockIsolated<[OnboardingProductMetric]>([])
        let openCount = LockIsolated(0)
        var initialState = OnboardingFeature.State()
        initialState.currentStep = .complete
        initialState.permissions.isComplete = true
        initialState.aiProviderSetup.status = .skipped
        let store = TestStore(initialState: initialState) {
            OnboardingFeature()
        } withDependencies: {
            $0.onboardingProgressClient = OnboardingProgressClient(
                load: { .empty },
                save: { _ in .failure },
                reset: {},
            )
            $0.onboardingWindowClient.openMainWindow = { _ in
                openCount.withValue { $0 += 1 }
                return true
            }
            $0.onboardingProductMetricsClient = OnboardingProductMetricsClient(record: { metric in
                metrics.withValue { $0.append(metric) }
            })
        }

        await store.send(.complete(.startUsingTapped)) { state in
            state.complete.isComplete = true
            state.complete.isOpeningWindow = true
        }
        let operationID = try XCTUnwrap(store.state.complete.completionOperationID)
        await store.receive(\.complete.progressSaveResponse) { state in
            state.complete.isComplete = false
            state.complete.isOpeningWindow = false
            state.complete.openWindowError = "Failed to save onboarding progress."
            state.complete.completionOperationID = nil
        }

        XCTAssertEqual(openCount.value, 0)
        XCTAssertEqual(metrics.value, [.completion(operationID: operationID, result: .failure)])
    }

    func testCompletionMetricEmitsOnceOnlyAfterWindowHandoffSucceeds() async throws {
        let metrics = LockIsolated<[OnboardingProductMetric]>([])
        let store = TestStore(initialState: CompleteState()) {
            CompleteFeature()
        } withDependencies: {
            $0.onboardingProductMetricsClient = OnboardingProductMetricsClient(record: { metric in
                metrics.withValue { $0.append(metric) }
            })
        }

        await store.send(.startUsingTapped) { state in
            state.isComplete = true
            state.isOpeningWindow = true
        }
        let operationID = try XCTUnwrap(store.state.completionOperationID)
        await store.send(.progressSaveResponse(operationID, true))
        await store.send(.openWindowResponse(operationID, true)) { state in
            state.isOpeningWindow = false
            state.completionOperationID = nil
        }
        await store.send(.openWindowResponse(operationID, true))

        XCTAssertEqual(metrics.value.count, 1)
        guard case let .completion(_, result) = metrics.value.first else {
            return XCTFail("Expected completion metric")
        }
        XCTAssertEqual(result, .success)
    }

    func testStaleCompletionResponseCannotConsumeNewerOperation() async throws {
        let metrics = LockIsolated<[OnboardingProductMetric]>([])
        let store = TestStore(initialState: CompleteState()) {
            CompleteFeature()
        } withDependencies: {
            $0.onboardingProductMetricsClient = OnboardingProductMetricsClient(record: { metric in
                metrics.withValue { $0.append(metric) }
            })
        }
        store.exhaustivity = .off

        await store.send(.startUsingTapped)
        let firstOperationID = try XCTUnwrap(store.state.completionOperationID)
        await store.send(.retryTapped)
        let secondOperationID = try XCTUnwrap(store.state.completionOperationID)
        XCTAssertNotEqual(firstOperationID, secondOperationID)

        await store.send(.openWindowResponse(firstOperationID, false))
        XCTAssertTrue(metrics.value.isEmpty)
        await store.send(.openWindowResponse(secondOperationID, false))
        XCTAssertEqual(metrics.value.count, 1)
    }

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
