@testable import VoyagerWidgetsEntryViewLayout
import XCTest

@MainActor
final class EntryViewLayoutColumnsMenuModelTests: XCTestCase {
    /// 컬럼 메뉴가 전체 열 집합을 빠짐없이 노출하는지 검증
    ///
    /// - 검증 내용: toggle item 개수와 컬럼 집합이 allCases와 일치
    /// - 회귀 방지: 메뉴에서 특정 컬럼이 누락되어 사용자가 표시/숨김을 조작하지 못하는 문제 방지
    func testToggleItemsCoverAllEntryListColumns() {
        let model = EntryViewLayoutColumnsMenuModel(visibleColumns: EntryListColumn.defaultVisibleColumns)

        XCTAssertEqual(model.toggleItems.count, EntryListColumn.allCases.count)
        XCTAssertEqual(Set(model.toggleItems.map(\.column)), Set(EntryListColumn.allCases))
    }

    /// 필수 컬럼(name)은 숨길 수 없도록 비활성 상태로 유지되는지 검증
    func testRequiredNameColumnIsNotHideable() {
        let model = EntryViewLayoutColumnsMenuModel(visibleColumns: [.dateModified])

        let nameItem = model.toggleItems.first(where: { $0.column == .name })
        XCTAssertNotNil(nameItem)
        XCTAssertEqual(nameItem?.isEnabled, false)
        XCTAssertEqual(nameItem?.isChecked, true)
    }

    /// 일반 컬럼은 visibleColumns 상태를 그대로 체크박스에 반영하는지 검증
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

    /// 메뉴 하단의 초기화 항목이 고정 문구로 노출되는지 검증
    func testResetItemExists() {
        let model = EntryViewLayoutColumnsMenuModel(visibleColumns: EntryListColumn.defaultVisibleColumns)
        XCTAssertEqual(model.resetItem.title, "Reset Columns")
    }

    /// VOY-216: tags 전용 컬럼 없이 메타데이터 컬럼만 메뉴에 포함되는지 검증
    func testVOY216MenuStillCoversOnlyMetadataColumnsWithoutSeparateTagsColumn() {
        let model = EntryViewLayoutColumnsMenuModel(visibleColumns: EntryListColumn.defaultVisibleColumns)
        let columns = model.toggleItems.map(\.column)

        XCTAssertTrue(columns.contains(.application))
        XCTAssertTrue(columns.contains(.dateAdded))
        XCTAssertTrue(columns.contains(.dateCreated))
        XCTAssertTrue(columns.contains(.dateLastOpened))
        XCTAssertFalse(columns.contains(where: { $0.rawValue == "tags" }))
    }

    /// VOY-216: 정규화 이후 메타데이터 컬럼이 기본 비노출 상태를 유지하는지 검증
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
