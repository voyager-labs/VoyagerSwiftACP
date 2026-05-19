import ComposableArchitecture
@testable import Voyager
import XCTest

@MainActor
final class AppLifecycleFeatureTests: XCTestCase {
    func testStartTerminationCleanupDoesNotStopHelperOnNormalQuit() async {
        await VoyagerTerminationCoordinator.shared.end()
        let attemptID = UUID()

        // 동시 변경 문제를 피하기 위해 actor 격리 저장소 클래스 사용
        let state = TestState()

        let store = TestStore(
            initialState: AppLifecycleState(
                didStartHelper: true,
                terminationAttemptID: attemptID,
            ),
        ) {
            AppLifecycleFeature()
        } withDependencies: {
            $0.helperAppClient.stop = { @MainActor in
                state.didStopHelper = true
            }
            $0.appTerminationReplyClient.reply = { @MainActor reply in
                state.repliedValues.append(reply)
            }
            $0.uuid = .incrementing
        }

        await store.send(AppLifecycleAction.termination(.startTerminationCleanup(attemptID: attemptID)))
        await store.send(AppLifecycleAction.termination(.willTerminate))
        await store.send(AppLifecycleAction.termination(.completeTerminationAttempt(
            attemptID: attemptID,
            shouldTerminate: true,
        ))) {
            $0.terminationAttemptID = nil
        }

        XCTAssertFalse(state.didStopHelper)
        XCTAssertEqual(state.repliedValues, [true])
        await VoyagerTerminationCoordinator.shared.end()
    }

    @MainActor
    private final class TestState: @unchecked Sendable {
        var didStopHelper = false
        var repliedValues: [Bool] = []
    }
}
