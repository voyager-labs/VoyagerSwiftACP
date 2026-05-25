import ComposableArchitecture
@testable import Voyager
import VoyagerEntitiesEntry
import VoyagerFeaturesContentPageNavigation
import VoyagerFeaturesEntryArrangements
import VoyagerFeaturesEntryOperations
import XCTest

@MainActor
/// 컬렉션 모드 상태 도출 — 디스플레이 아이템 소스 전환과 기본 정렬을 검증.
final class EntryViewLayoutCollectionModeStateTests: XCTestCase {
    /// testCollectionItemsDefaultEmpty 테스트 동작을 검증한다.
    func testCollectionItemsDefaultEmpty() {
        let state = EntryViewLayoutState()
        XCTAssertTrue(state.collectionItems.isEmpty)
    }

    /// testIsCollectionModeDefaultFalse 테스트 동작을 검증한다.
    func testIsCollectionModeDefaultFalse() {
        let state = EntryViewLayoutState()
        XCTAssertFalse(state.isCollectionMode)
    }

    /// testDisplayItemsReturnsEntryOperationsItemsWhenNotCollectionMode 테스트 동작을 검증한다.
    func testDisplayItemsReturnsEntryOperationsItemsWhenNotCollectionMode() {
        var state = EntryViewLayoutState()
        let item = EntryModel.temporaryFolder(id: "/tmp/regular.txt", name: "regular.txt")
        state.entryOperations.items = [item]

        XCTAssertFalse(state.isCollectionMode)
        XCTAssertEqual(state.displayItems.count, 1)
        XCTAssertEqual(state.displayItems.first?.id, item.id)
    }

    /// testDisplayItemsReturnsCollectionItemsWhenCollectionMode 테스트 동작을 검증한다.
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

    /// testDisplayItemsIgnoresRegularItemsInCollectionMode 테스트 동작을 검증한다.
    func testDisplayItemsIgnoresRegularItemsInCollectionMode() {
        var state = EntryViewLayoutState()
        let regularItem = EntryModel.temporaryFolder(id: "/tmp/regular.txt", name: "regular.txt")
        state.entryOperations.items = [regularItem]
        state.isCollectionMode = true

        XCTAssertTrue(state.displayItems.isEmpty)
    }

    /// testDisplayOrderItemsReturnsArrayOfDisplayItems 테스트 동작을 검증한다.
    func testDisplayOrderItemsReturnsArrayOfDisplayItems() {
        var state = EntryViewLayoutState()
        let item1 = EntryModel.temporaryFolder(id: "/tmp/a.txt", name: "a.txt")
        let item2 = EntryModel.temporaryFolder(id: "/tmp/b.txt", name: "b.txt")
        state.entryOperations.items = [item1, item2]

        XCTAssertEqual(state.displayOrderItems.count, 2)
        XCTAssertEqual(state.displayOrderItems[0].id, item1.id)
        XCTAssertEqual(state.displayOrderItems[1].id, item2.id)
    }

    /// testDisplayOrderItemsWithCollectionMode 테스트 동작을 검증한다.
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

    /// testDisplayOrderItemsEmptyByDefault 테스트 동작을 검증한다.
    func testDisplayOrderItemsEmptyByDefault() {
        let state = EntryViewLayoutState()
        XCTAssertTrue(state.displayOrderItems.isEmpty)
    }

    /// testSettingCollectionItems 테스트 동작을 검증한다.
    func testSettingCollectionItems() {
        var state = EntryViewLayoutState()
        let item = EntryModel.temporaryFolder(id: "/tmp/col.txt", name: "col.txt")
        state.collectionItems = [item]

        XCTAssertEqual(state.collectionItems.count, 1)
        XCTAssertEqual(state.collectionItems.first?.id, item.id)
    }

    /// testTogglingCollectionModeSwitchesDisplaySource 테스트 동작을 검증한다.
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
