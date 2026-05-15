import ComposableArchitecture
@testable import Voyager
import VoyagerEntitiesCollection
import VoyagerFeaturesEntryArrangements
import VoyagerFeaturesEntryOperations
import XCTest

@MainActor
final class FileManagerContentEntryOpsContractTests: XCTestCase {
    func testIsCollectionModeOnLayoutState() {
        var state = FileManagerContentState()

        XCTAssertFalse(state.entryViewLayout.isCollectionMode)

        state.entryViewLayout.isCollectionMode = true
        XCTAssertTrue(state.entryViewLayout.isCollectionMode)
    }

    func testCanSaveCollectionRequiresIsCollectionMode() {
        var state = FileManagerContentState()
        state.collection.collectionContext = CollectionContext(query: "", scopes: [], conditions: [])

        XCTAssertFalse(state.canSaveCollection)

        state.entryViewLayout.isCollectionMode = true
        XCTAssertTrue(state.canSaveCollection)
    }

    func testCanSaveCollectionFalseWhenNotInCollectionMode() {
        var state = FileManagerContentState()
        state.collection.collectionContext = CollectionContext(query: "", scopes: [], conditions: [])

        XCTAssertFalse(state.entryViewLayout.isCollectionMode)
        XCTAssertFalse(state.canSaveCollection)
    }
}
