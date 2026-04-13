import ComposableArchitecture
@testable import Voyager
import VoyagerEntitiesEntry
import VoyagerFeaturesEntryOperations
@testable import VoyagerWidgetsEntryViewLayout
import XCTest

@MainActor
final class EntryViewLayoutCollectionModeStateTests: XCTestCase {
    func testCollectionItemsDefaultEmpty() {
        let state = EntryViewLayoutState()
        XCTAssertTrue(state.collectionItems.isEmpty)
    }

    func testIsCollectionModeDefaultFalse() {
        let state = EntryViewLayoutState()
        XCTAssertFalse(state.isCollectionMode)
    }

    func testDisplayItemsReturnsEntryOperationsItemsWhenNotCollectionMode() {
        var state = EntryViewLayoutState()
        let item = EntryModel.temporaryFolder(id: "/tmp/regular.txt", name: "regular.txt")
        state.entryOperations.items = [item]

        XCTAssertFalse(state.isCollectionMode)
        XCTAssertEqual(state.displayItems.count, 1)
        XCTAssertEqual(state.displayItems.first?.id, item.id)
    }

    func testDisplayItemsReturnsCollectionItemsWhenCollectionMode() {
        var state = EntryViewLayoutState()
        let regularItem = EntryModel.temporaryFolder(id: "/tmp/regular.txt", name: "regular.txt")
        let collectionItem = EntryModel.temporaryFolder(id: "/tmp/col.txt", name: "col.txt")

        state.entryOperations.items = [regularItem]
        state.collectionItems = [collectionItem]
        state.isCollectionMode = true

        XCTAssertEqual(state.displayItems.count, 1)
        XCTAssertEqual(state.displayItems.first?.id, collectionItem.id)
    }

    func testDisplayItemsIgnoresRegularItemsInCollectionMode() {
        var state = EntryViewLayoutState()
        let regularItem = EntryModel.temporaryFolder(id: "/tmp/regular.txt", name: "regular.txt")
        state.entryOperations.items = [regularItem]
        state.isCollectionMode = true

        XCTAssertTrue(state.displayItems.isEmpty)
    }

    func testDisplayOrderItemsReturnsArrayOfDisplayItems() {
        var state = EntryViewLayoutState()
        let item1 = EntryModel.temporaryFolder(id: "/tmp/a.txt", name: "a.txt")
        let item2 = EntryModel.temporaryFolder(id: "/tmp/b.txt", name: "b.txt")
        state.entryOperations.items = [item1, item2]

        XCTAssertEqual(state.displayOrderItems.count, 2)
        XCTAssertEqual(state.displayOrderItems[0].id, item1.id)
        XCTAssertEqual(state.displayOrderItems[1].id, item2.id)
    }

    func testDisplayOrderItemsWithCollectionMode() {
        var state = EntryViewLayoutState()
        let colItem1 = EntryModel.temporaryFolder(id: "/tmp/col1.txt", name: "col1.txt")
        let colItem2 = EntryModel.temporaryFolder(id: "/tmp/col2.txt", name: "col2.txt")
        state.collectionItems = [colItem1, colItem2]
        state.isCollectionMode = true

        XCTAssertEqual(state.displayOrderItems.count, 2)
        XCTAssertEqual(state.displayOrderItems[0].id, colItem1.id)
        XCTAssertEqual(state.displayOrderItems[1].id, colItem2.id)
    }

    func testDisplayOrderItemsEmptyByDefault() {
        let state = EntryViewLayoutState()
        XCTAssertTrue(state.displayOrderItems.isEmpty)
    }

    func testSettingCollectionItems() {
        var state = EntryViewLayoutState()
        let item = EntryModel.temporaryFolder(id: "/tmp/col.txt", name: "col.txt")
        state.collectionItems = [item]

        XCTAssertEqual(state.collectionItems.count, 1)
        XCTAssertEqual(state.collectionItems.first?.id, item.id)
    }

    func testTogglingCollectionModeSwitchesDisplaySource() {
        var state = EntryViewLayoutState()
        let regularItem = EntryModel.temporaryFolder(id: "/tmp/regular.txt", name: "regular.txt")
        let collectionItem = EntryModel.temporaryFolder(id: "/tmp/col.txt", name: "col.txt")

        state.entryOperations.items = [regularItem]
        state.collectionItems = [collectionItem]

        XCTAssertEqual(state.displayItems.first?.id, regularItem.id)

        state.isCollectionMode = true
        XCTAssertEqual(state.displayItems.first?.id, collectionItem.id)

        state.isCollectionMode = false
        XCTAssertEqual(state.displayItems.first?.id, regularItem.id)
    }
}
