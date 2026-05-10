import ComposableArchitecture
@testable import Voyager
import VoyagerFeaturesEntryArrangements
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
        XCTAssertTrue(AppLifecycleAction.launch(.willFinishLaunching).is(\.launch.willFinishLaunching))
        XCTAssertTrue(AppLifecycleAction.launch(.didFinishLaunching).is(\.launch.didFinishLaunching))
    }

    func testReopenActionHasProperStructure() {
        let reopenAction = AppLifecycleAction.launch(.appReopen(hasVisibleWindows: true))
        XCTAssertTrue(reopenAction.is(\.launch.appReopen))
    }

    func testTerminationActionsHaveProperStructure() {
        let attemptID = UUID()
        let result = QuitConfirmationResult(shouldQuit: true, isAlertBeforeQuitEnabled: false)

        XCTAssertTrue(AppLifecycleAction.termination(.requestTermination).is(\.termination.requestTermination))

        let responseAction = AppLifecycleAction.termination(.quitConfirmationResponse(
            attemptID: attemptID,
            result: result,
        ))
        XCTAssertTrue(responseAction.is(\.termination.quitConfirmationResponse))

        let startCleanupAction = AppLifecycleAction.termination(.startTerminationCleanup(attemptID: attemptID))
        XCTAssertTrue(startCleanupAction.is(\.termination.startTerminationCleanup))

        let completeAction = AppLifecycleAction.termination(.completeTerminationAttempt(
            attemptID: attemptID,
            shouldTerminate: true,
        ))
        XCTAssertTrue(completeAction.is(\.termination.completeTerminationAttempt))

        XCTAssertTrue(AppLifecycleAction.termination(.willTerminate).is(\.termination.willTerminate))
    }

    func testDelegateActionsHaveProperStructure() {
        let openInitialAction = AppLifecycleAction.delegate(.openInitialWindowIfNeeded)
        XCTAssertTrue(openInitialAction.is(\.delegate))

        let reopenAction = AppLifecycleAction.delegate(.reopenWindowIfNeeded(hasVisibleWindows: true))
        XCTAssertTrue(reopenAction.is(\.delegate))
    }
}
