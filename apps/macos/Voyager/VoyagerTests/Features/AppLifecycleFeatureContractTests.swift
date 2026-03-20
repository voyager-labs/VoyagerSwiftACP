import ComposableArchitecture
@testable import Voyager
import XCTest

@MainActor
final class AppLifecycleFeatureContractTests: XCTestCase {
    func testInitialStateHasDidStartHelperFalse() {
        let state = AppLifecycleState()
        XCTAssertFalse(state.didStartHelper)
        XCTAssertNil(state.terminationAttemptID)
    }

    func testStateIsEquatable() {
        let id = UUID()
        let state1 = AppLifecycleState(didStartHelper: true, terminationAttemptID: id)
        let state2 = AppLifecycleState(didStartHelper: true, terminationAttemptID: id)
        XCTAssertEqual(state1, state2)
    }

    func testLaunchActionsHaveProperStructure() {
        XCTAssertTrue(AppLifecycleAction.willFinishLaunching.is(\.willFinishLaunching))
        XCTAssertTrue(AppLifecycleAction.didFinishLaunching.is(\.didFinishLaunching))
    }

    func testReopenActionHasProperStructure() {
        let reopenAction = AppLifecycleAction.appReopen(hasVisibleWindows: true)
        XCTAssertTrue(reopenAction.is(\.appReopen))
    }

    func testTerminationActionsHaveProperStructure() {
        let attemptID = UUID()
        let result = QuitConfirmationResult(shouldQuit: true, isAlertBeforeQuitEnabled: false)

        XCTAssertTrue(AppLifecycleAction.requestTermination.is(\.requestTermination))

        let responseAction = AppLifecycleAction.quitConfirmationResponse(attemptID: attemptID, result: result)
        XCTAssertTrue(responseAction.is(\.quitConfirmationResponse))

        let startCleanupAction = AppLifecycleAction.startTerminationCleanup(attemptID: attemptID)
        XCTAssertTrue(startCleanupAction.is(\.startTerminationCleanup))

        let completeAction = AppLifecycleAction.completeTerminationAttempt(attemptID: attemptID, shouldTerminate: true)
        XCTAssertTrue(completeAction.is(\.completeTerminationAttempt))

        XCTAssertTrue(AppLifecycleAction.willTerminate.is(\.willTerminate))
    }

    func testDelegateActionsHaveProperStructure() {
        let openInitialAction = AppLifecycleAction.delegate(.openInitialWindowIfNeeded)
        XCTAssertTrue(openInitialAction.is(\.delegate))

        let reopenAction = AppLifecycleAction.delegate(.reopenWindowIfNeeded(hasVisibleWindows: true))
        XCTAssertTrue(reopenAction.is(\.delegate))
    }
}
