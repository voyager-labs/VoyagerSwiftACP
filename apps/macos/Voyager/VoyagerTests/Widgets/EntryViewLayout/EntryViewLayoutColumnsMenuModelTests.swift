@testable import Voyager
import XCTest

@MainActor
final class EntryViewLayoutColumnsMenuModelTests: XCTestCase {
    func testToggleItemsCoverAllEntryListColumns() {
        let model = EntryViewLayoutColumnsMenuModel(visibleColumns: EntryListColumn.defaultVisibleColumns)

        XCTAssertEqual(model.toggleItems.count, EntryListColumn.allCases.count)
        XCTAssertEqual(Set(model.toggleItems.map(\.column)), Set(EntryListColumn.allCases))
    }

    func testRequiredNameColumnIsNotHideable() {
        let model = EntryViewLayoutColumnsMenuModel(visibleColumns: [.dateModified])

        let nameItem = model.toggleItems.first(where: { $0.column == .name })
        XCTAssertNotNil(nameItem)
        XCTAssertEqual(nameItem?.isEnabled, false)
        XCTAssertEqual(nameItem?.isChecked, true)
    }

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

    func testResetItemExists() {
        let model = EntryViewLayoutColumnsMenuModel(visibleColumns: EntryListColumn.defaultVisibleColumns)
        XCTAssertEqual(model.resetItem.title, "Reset Columns")
    }

    func testVOY216MenuStillCoversOnlyMetadataColumnsWithoutSeparateTagsColumn() {
        let model = EntryViewLayoutColumnsMenuModel(visibleColumns: EntryListColumn.defaultVisibleColumns)
        let columns = model.toggleItems.map(\.column)

        XCTAssertTrue(columns.contains(.application))
        XCTAssertTrue(columns.contains(.dateAdded))
        XCTAssertTrue(columns.contains(.dateCreated))
        XCTAssertTrue(columns.contains(.dateLastOpened))
        XCTAssertFalse(columns.contains(where: { $0.rawValue == "tags" }))
    }

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
