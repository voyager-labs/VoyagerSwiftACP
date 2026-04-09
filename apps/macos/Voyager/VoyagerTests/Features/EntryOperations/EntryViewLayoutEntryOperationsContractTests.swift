import ComposableArchitecture
@testable import Voyager
import VoyagerEntitiesEntry
import VoyagerFeaturesEntryOperations
import XCTest

@MainActor
final class EntryViewLayoutEntryOperationsContractTests: XCTestCase {
    func testItemsAccessibleViaLoadingContext() {
        var state = EntryViewLayoutState()
        let item = EntryModel.temporaryFolder(id: "/tmp/test.txt", name: "test.txt")

        XCTAssertTrue(state.entryOperations.items.isEmpty)

        state.entryOperations.items = [item]
        XCTAssertEqual(state.entryOperations.items.count, 1)
        XCTAssertEqual(state.entryOperations.items.first?.id, item.id)
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

    func testRenamingItemStoredOnStartRename() {
        var state = EntryViewLayoutState()
        let item = EntryModel.temporaryFolder(id: "/tmp/test.txt", name: "test.txt")

        XCTAssertNil(state.entryOperations.renamingItem)

        state.entryOperations.renamingItemId = item.id
        state.entryOperations.renamingItem = item
        XCTAssertEqual(state.entryOperations.renamingItem?.id, item.id)
    }
}
