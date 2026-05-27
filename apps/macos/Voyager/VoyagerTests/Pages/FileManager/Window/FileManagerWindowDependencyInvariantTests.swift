import ComposableArchitecture
@testable import Voyager
import VoyagerFeaturesContentPageNavigation
import VoyagerFeaturesEntryOperations
@testable import VoyagerPagesFileManager
import XCTest

@MainActor
final class WindowDependencyInvariantTests: XCTestCase {
    /// testCreateInitialStateSeedsPathForFreshWindow 시나리오가 FileManager 계약을 위반하지 않음을 검증한다.
    func testCreateInitialStateSeedsPathForFreshWindow() {
        let state = FileManagerWindowCoordinator.createInitialState(
            path: "/tmp/voyager",
            duplicateState: nil,
        )

        XCTAssertNil(state.content.entryViewLayout.entryOperations.windowID)
        XCTAssertEqual(state.content.navigation.currentPath, "/tmp/voyager")
    }

    /// testCreateInitialStatePreservesDuplicateStateAndOverridesPath 시나리오가 FileManager 계약을 위반하지 않음을 검증한다.
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
