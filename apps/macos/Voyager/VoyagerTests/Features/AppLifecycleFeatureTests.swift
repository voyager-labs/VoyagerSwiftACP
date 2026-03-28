import ComposableArchitecture
@testable import Voyager
import XCTest

@MainActor
final class AppLifecycleFeatureTests: XCTestCase {
    func testStartTerminationCleanupDoesNotStopHelperOnNormalQuit() async {
        await VoyagerTerminationCoordinator.shared.end()
        let attemptID = UUID()
        var didStopHelper = false
        var repliedValues: [Bool] = []

        let store = TestStore(
            initialState: AppLifecycleState(
                didStartHelper: true,
                terminationAttemptID: attemptID,
            ),
        ) {
            AppLifecycleFeature()
        } withDependencies: {
            $0.helperAppClient.stop = {
                didStopHelper = true
            }
            $0.appTerminationReplyClient.reply = { repliedValues.append($0) }
            $0.uuid = .incrementing
        }

        await store.send(.startTerminationCleanup(attemptID: attemptID))
        await store.receive(.willTerminate)
        await store.receive(.completeTerminationAttempt(attemptID: attemptID, shouldTerminate: true)) {
            $0.terminationAttemptID = nil
        }

        XCTAssertFalse(didStopHelper)
        XCTAssertEqual(repliedValues, [true])
        await VoyagerTerminationCoordinator.shared.end()
    }
}
