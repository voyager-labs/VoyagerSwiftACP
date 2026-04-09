import ComposableArchitecture
@testable import Voyager
import VoyagerEntitiesEntry
import VoyagerFeaturesEntryOperations
import XCTest

@MainActor
final class EntryViewLayoutEntryOperationsContractTests: XCTestCase {
    func testEntryOperationsStateAccessibleViaApprovedAccessor() {
        var state = EntryViewLayoutState()

        XCTAssertFalse(state.entryOperations.isCollectionMode)

        state.entryOperations.isCollectionMode = true
        XCTAssertTrue(state.entryOperations.isCollectionMode)
    }

    func testDisplayItemsReturnsRegularItemsWhenNotCollectionMode() {
        var state = EntryViewLayoutState()
        let item = EntryModel.temporaryFolder(id: "/tmp/test.txt", name: "test.txt")
        state.entryOperations.items = [item]

        XCTAssertFalse(state.entryOperations.isCollectionMode)
        XCTAssertEqual(state.entryOperations.displayItems.count, 1)
        XCTAssertEqual(state.entryOperations.displayItems.first?.id, item.id)
    }

    func testDisplayItemsReturnsCollectionItemsWhenCollectionMode() {
        var state = EntryViewLayoutState()
        let item = EntryModel.temporaryFolder(id: "/tmp/col.txt", name: "col.txt")
        state.entryOperations.collectionItems = [item]
        state.entryOperations.isCollectionMode = true

        XCTAssertTrue(state.entryOperations.isCollectionMode)
        XCTAssertEqual(state.entryOperations.displayItems.count, 1)
        XCTAssertEqual(state.entryOperations.displayItems.first?.id, item.id)
    }

    func testWindowIDAccessibleViaApprovedAccessor() {
        var state = EntryViewLayoutState()
        let windowID = UUID()

        XCTAssertNil(state.entryOperations.windowID)

        state.entryOperations.windowID = windowID
        XCTAssertEqual(state.entryOperations.windowID, windowID)
    }

    func testRenamingItemIdAccessibleViaApprovedAccessor() {
        var state = EntryViewLayoutState()
        let itemId = "test-item-id"

        XCTAssertNil(state.entryOperations.renamingItemId)

        state.entryOperations.renamingItemId = itemId
        XCTAssertEqual(state.entryOperations.renamingItemId, itemId)
    }
}
