import ComposableArchitecture
@testable import Voyager
import XCTest

@MainActor
final class AppLifecycleFeatureTests: XCTestCase {
    func testStartTerminationCleanupDoesNotStopHelperOnNormalQuit() async {
        await VoyagerTerminationCoordinator.shared.end()
        let attemptID = UUID()
        let recorder = Recorder()

        let store = TestStore(
            initialState: AppLifecycleState(
                didStartHelper: true,
                terminationAttemptID: attemptID,
            ),
        ) {
            AppLifecycleFeature()
        } withDependencies: {
            $0.helperAppClient.stop = {
                await recorder.recordDidStopHelper()
            }
            $0.appTerminationReplyClient.reply = { shouldTerminate in
                await recorder.appendReply(shouldTerminate)
            }
            $0.uuid = .incrementing
        }

        await store.send(.termination(.startTerminationCleanup(attemptID: attemptID)))
        await store.receive(\.termination.willTerminate)
        await store.receive(\.termination.completeTerminationAttempt) {
            $0.terminationAttemptID = nil
        }

        let didStopHelper = await recorder.didStopHelperValue()
        let repliedValues = await recorder.repliedValuesValue()
        XCTAssertFalse(didStopHelper)
        XCTAssertEqual(repliedValues, [true])
        await VoyagerTerminationCoordinator.shared.end()
    }
}

private actor Recorder {
    private var didStopHelperFlag = false
    private var replyValues: [Bool] = []

    func recordDidStopHelper() {
        didStopHelperFlag = true
    }

    func appendReply(_ value: Bool) {
        replyValues.append(value)
    }

    func didStopHelperValue() -> Bool {
        didStopHelperFlag
    }

    func repliedValuesValue() -> [Bool] {
        replyValues
    }
}
