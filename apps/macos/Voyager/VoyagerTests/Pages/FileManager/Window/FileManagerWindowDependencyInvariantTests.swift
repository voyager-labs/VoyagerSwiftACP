import ComposableArchitecture
@testable import Voyager
import VoyagerFeaturesContentPageNavigation
import VoyagerFeaturesEntryOperations
import XCTest

@testable import Voyager

@MainActor
final class WindowDependencyInvariantTests: XCTestCase {
    func testCreateInitialStateSeedsPathForFreshWindow() {
        let state = FileManagerWindowCoordinator.createInitialState(
            path: "/tmp/voyager",
            duplicateState: nil,
        )

        XCTAssertNil(state.content.entryViewLayout.entryOperations.windowID)
        XCTAssertEqual(state.content.navigation.currentPath, "/tmp/voyager")
    }

    func testCreateInitialStatePreservesDuplicateStateAndOverridesPath() {
        let originalID = UUID()
        var duplicateState = FileManagerFeature.State.makeInitial(path: "/tmp/original")
        duplicateState.content.entryViewLayout.entryOperations.windowID = originalID
        duplicateState.content.navigation.seedInitialFolderPath("/tmp/original")

        let state = FileManagerWindowCoordinator.createInitialState(
            path: "/tmp/override",
            duplicateState: duplicateState,
        )

        XCTAssertEqual(state.content.entryViewLayout.entryOperations.windowID, originalID)
        XCTAssertEqual(state.content.navigation.currentPath, "/tmp/override")
    }
}
