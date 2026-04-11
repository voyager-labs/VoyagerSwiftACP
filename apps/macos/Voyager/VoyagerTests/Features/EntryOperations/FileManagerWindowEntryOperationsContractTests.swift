import ComposableArchitecture
@testable import Voyager
import VoyagerFeaturesEntryOperations
import XCTest

@MainActor
final class FileManagerWindowEntryOpsContractTests: XCTestCase {
    func testMakeInitialSetsWindowIDThroughApprovedAccessor() {
        let windowID = UUID()
        let state = FileManagerWindowState.makeInitial(windowID: windowID, path: nil)

        XCTAssertEqual(state.content.entryViewLayout.entryOperations.windowID, windowID)
    }

    func testMakeInitialSeedsPathThroughNavigationState() {
        let windowID = UUID()
        let path = "/Users/test/Documents"
        let state = FileManagerWindowState.makeInitial(windowID: windowID, path: path)

        XCTAssertEqual(state.content.entryViewLayout.entryOperations.windowID, windowID)
    }

    func testContentStateCanSaveCollectionUsesLayoutIsCollectionMode() {
        var state = FileManagerWindowState()

        XCTAssertFalse(state.content.canSaveCollection)

        state.content.collectionContext = CollectionContext(query: "", scopes: [], conditions: [])
        state.content.entryViewLayout.isCollectionMode = true

        XCTAssertTrue(state.content.canSaveCollection)
    }

    func testWindowDefaultStateHasNoCollectionMode() {
        let state = FileManagerWindowState()

        XCTAssertFalse(state.content.entryViewLayout.isCollectionMode)
        XCTAssertNil(state.content.entryViewLayout.entryOperations.windowID)
    }

    func testContentEntryOperationsResetPreservesWindowID() {
        let windowID = UUID()
        var state = FileManagerWindowState.makeInitial(windowID: windowID, path: nil)
        state.content.entryViewLayout.isCollectionMode = true

        state.content.entryViewLayout.entryOperations = EntryOperationsState()
        XCTAssertNil(state.content.entryViewLayout.entryOperations.windowID)
        XCTAssertFalse(state.content.entryViewLayout.isCollectionMode)

        state.content.entryViewLayout.entryOperations.windowID = windowID
        XCTAssertEqual(state.content.entryViewLayout.entryOperations.windowID, windowID)
    }
}
