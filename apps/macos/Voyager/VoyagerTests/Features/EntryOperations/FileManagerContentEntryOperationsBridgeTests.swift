import ComposableArchitecture
@testable import Voyager
import VoyagerFeaturesEntryOperations
import XCTest

@MainActor
final class FileManagerContentEntryOperationsBridgeTests: XCTestCase {
    func testIsCollectionModeAccessorReflectsLoadingContextState() {
        var state = FileManagerContentState()

        XCTAssertFalse(state.entryViewLayout.entryOperations.isCollectionMode)

        state.entryViewLayout.entryOperations.isCollectionMode = true
        XCTAssertTrue(state.entryViewLayout.entryOperations.isCollectionMode)
    }

    func testCanSaveCollectionRequiresIsCollectionMode() {
        var state = FileManagerContentState()
        state.collectionContext = CollectionContext(query: "", scopes: [], conditions: [])

        XCTAssertFalse(state.canSaveCollection)

        state.entryViewLayout.entryOperations.isCollectionMode = true
        XCTAssertTrue(state.canSaveCollection)
    }

    func testCanSaveCollectionFalseWhenNotInCollectionMode() {
        var state = FileManagerContentState()
        state.collectionContext = CollectionContext(query: "", scopes: [], conditions: [])

        XCTAssertFalse(state.entryViewLayout.entryOperations.isCollectionMode)
        XCTAssertFalse(state.canSaveCollection)
    }

    func testSyncComposerCollectionStateReadsIsCollectionMode() {
        var state = FileManagerContentState()
        state.entryViewLayout.entryOperations.isCollectionMode = true

        state.syncComposerCollectionState()

        XCTAssertTrue(state.composer.isCollectionMode)
    }

    func testSyncComposerCollectionStateFalseWhenNotCollectionMode() {
        var state = FileManagerContentState()

        state.syncComposerCollectionState()

        XCTAssertFalse(state.composer.isCollectionMode)
    }
}
