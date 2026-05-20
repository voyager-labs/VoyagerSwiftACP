@testable import Voyager
import XCTest

@MainActor
/// 정렬/헤더/메뉴 동작 회귀를 검증하는 테스트 모음이다.
final class EntryViewLayoutColumnsMenuModelTests: XCTestCase {
    /// 컬럼 상태 회귀를 방지한다.
    func testToggleItemsCoverAllEntryListColumns() {
        let model = EntryViewLayoutColumnsMenuModel(visibleColumns: EntryListColumn.defaultVisibleColumns)

        XCTAssertEqual(model.toggleItems.count, EntryListColumn.allCases.count)
        XCTAssertEqual(Set(model.toggleItems.map(\.column)), Set(EntryListColumn.allCases))
    }

    /// 컬럼 상태 회귀를 방지한다.
    func testRequiredNameColumnIsNotHideable() {
        let model = EntryViewLayoutColumnsMenuModel(visibleColumns: [.dateModified])

        let nameItem = model.toggleItems.first(where: { $0.column == .name })
        XCTAssertNotNil(nameItem)
        XCTAssertEqual(nameItem?.isEnabled, false)
        XCTAssertEqual(nameItem?.isChecked, true)
    }

    /// 컬럼 상태 회귀를 방지한다.
    func testCheckedStateReflectsVisibilityForNonRequiredColumns() {
        let visibleColumns: [EntryListColumn] = [.name, .size]
        let model = EntryViewLayoutColumnsMenuModel(visibleColumns: visibleColumns)

        let sizeItem = model.toggleItems.first(where: { $0.column == .size })
        XCTAssertNotNil(sizeItem)
        XCTAssertEqual(sizeItem?.isChecked, true)
        XCTAssertEqual(sizeItem?.isEnabled, true)

        let kindItem = model.toggleItems.first(where: { $0.column == .kind })
        XCTAssertNotNil(kindItem)
        XCTAssertEqual(kindItem?.isChecked, false)
        XCTAssertEqual(kindItem?.isEnabled, true)
    }

    /// 테스트 시나리오 회귀를 방지하기 위한 동작을 검증한다.
    func testResetItemExists() {
        let model = EntryViewLayoutColumnsMenuModel(visibleColumns: EntryListColumn.defaultVisibleColumns)
        XCTAssertEqual(model.resetItem.title, "Reset Columns")
    }

    /// 태그 표시/가시성 회귀를 방지한다.
    func testVOY216MenuStillCoversOnlyMetadataColumnsWithoutSeparateTagsColumn() {
        let model = EntryViewLayoutColumnsMenuModel(visibleColumns: EntryListColumn.defaultVisibleColumns)
        let columns = model.toggleItems.map(\.column)

        XCTAssertTrue(columns.contains(.application))
        XCTAssertTrue(columns.contains(.dateAdded))
        XCTAssertTrue(columns.contains(.dateCreated))
        XCTAssertTrue(columns.contains(.dateLastOpened))
        XCTAssertFalse(columns.contains(where: { $0.rawValue == "tags" }))
    }

    /// 컬럼 상태 회귀를 방지한다.
    func testVOY216MetadataColumnsRemainOffByDefaultAfterNormalization() {
        let model = EntryViewLayoutColumnsMenuModel(visibleColumns: EntryListColumn.defaultVisibleColumns)

        let applicationItem = model.toggleItems.first(where: { $0.column == .application })
        let dateAddedItem = model.toggleItems.first(where: { $0.column == .dateAdded })
        let dateCreatedItem = model.toggleItems.first(where: { $0.column == .dateCreated })
        let dateLastOpenedItem = model.toggleItems.first(where: { $0.column == .dateLastOpened })

        XCTAssertEqual(applicationItem?.isChecked, false)
        XCTAssertEqual(dateAddedItem?.isChecked, false)
        XCTAssertEqual(dateCreatedItem?.isChecked, false)
        XCTAssertEqual(dateLastOpenedItem?.isChecked, false)
    }
}
