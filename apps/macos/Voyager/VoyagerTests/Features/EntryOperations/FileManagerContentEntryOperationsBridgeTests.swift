import ComposableArchitecture
@testable import Voyager
import VoyagerEntitiesCollection
import VoyagerFeaturesEntryArrangements
import VoyagerFeaturesEntryOperations
import XCTest

@MainActor
final class FileManagerContentEntryOpsBridgeTests: XCTestCase {
    func testIsCollectionModeOnLayoutState() {
        var state = FileManagerContentState()

        XCTAssertFalse(state.entryViewLayout.isCollectionMode)

        state.entryViewLayout.isCollectionMode = true
        XCTAssertTrue(state.entryViewLayout.isCollectionMode)
    }

    func testCanSaveCollectionRequiresIsCollectionMode() {
        var state = FileManagerContentState()
        state.collectionContext = CollectionContext(query: "", scopes: [], conditions: [])

        XCTAssertFalse(state.canSaveCollection)

        state.entryViewLayout.isCollectionMode = true
        XCTAssertTrue(state.canSaveCollection)
    }

    func testCanSaveCollectionFalseWhenNotInCollectionMode() {
        var state = FileManagerContentState()
        state.collectionContext = CollectionContext(query: "", scopes: [], conditions: [])

        XCTAssertFalse(state.entryViewLayout.isCollectionMode)
        XCTAssertFalse(state.canSaveCollection)
    }

    func testSyncComposerCollectionStateReadsIsCollectionMode() {
        var state = FileManagerContentState()
        state.entryViewLayout.isCollectionMode = true

        state.syncComposerCollectionState()

        XCTAssertTrue(state.composer.isCollectionMode)
    }

    func testSyncComposerCollectionStateFalseWhenNotCollectionMode() {
        var state = FileManagerContentState()

        state.syncComposerCollectionState()

        XCTAssertFalse(state.composer.isCollectionMode)
    }
}
