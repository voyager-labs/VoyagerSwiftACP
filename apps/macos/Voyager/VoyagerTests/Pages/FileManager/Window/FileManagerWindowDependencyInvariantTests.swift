import ComposableArchitecture
@testable import Voyager
import XCTest

@MainActor
final class WindowDependencyInvariantTests: XCTestCase {
    func testCreateInitialStateSeedsWindowIDForFreshWindow() {
        let windowID = UUID()

        let state = FileManagerWindowCoordinator.createInitialState(
            windowID: windowID,
            path: "/tmp/voyager",
            duplicateState: nil,
        )

        XCTAssertEqual(state.content.entryViewLayout.entryOperations.windowID, windowID)
        XCTAssertEqual(state.content.navigation.currentPath, "/tmp/voyager")
    }

    func testCreateInitialStateSeedsWindowIDAndPathForDuplicateWindow() {
        let originalID = UUID()
        let newID = UUID()
        var duplicateState = FileManagerFeature.State.makeInitial(windowID: originalID, path: "/tmp/original")
        duplicateState.content.navigation.seedInitialFolderPath("/tmp/original")

        let state = FileManagerWindowCoordinator.createInitialState(
            windowID: newID,
            path: "/tmp/override",
            duplicateState: duplicateState,
        )

        XCTAssertEqual(state.content.entryViewLayout.entryOperations.windowID, newID)
        XCTAssertEqual(state.content.navigation.currentPath, "/tmp/override")
    }
}
