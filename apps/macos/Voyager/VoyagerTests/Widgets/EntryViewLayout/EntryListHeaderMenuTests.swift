import AppKit
@testable import Voyager
import XCTest

/// 정렬/헤더/메뉴 동작 회귀를 검증하는 테스트 모음이다.
@MainActor
final class EntryListHeaderMenuTests: XCTestCase {
    /// 메뉴 동작 회귀를 방지한다.
    func testMenuMatchesModelToggleItemsAndResetItem() {
        let model = EntryViewLayoutColumnsMenuModel(visibleColumns: [.name, .size])
        let headerView = EntryListHeaderView()
        let menu = headerView.makeMenu(model: model)

        XCTAssertEqual(menu.items.count, model.toggleItems.count + 2)
        XCTAssertTrue(menu.items[model.toggleItems.count].isSeparatorItem)

        for (index, toggle) in model.toggleItems.enumerated() {
            let menuItem = menu.items[index]
            XCTAssertEqual(menuItem.title, toggle.title)
            XCTAssertEqual(
                menuItem.state,
                toggle.isChecked ? NSControl.StateValue.on : NSControl.StateValue.off,
            )
            XCTAssertEqual(menuItem.isEnabled, toggle.isEnabled)
        }

        let resetItem = menu.items[model.toggleItems.count + 1]
        XCTAssertEqual(resetItem.title, model.resetItem.title)
        XCTAssertEqual(resetItem.isEnabled, model.resetItem.isEnabled)
    }

    /// 메뉴 동작 회귀를 방지한다.
    func testRequiredNameColumnMenuItemIsDisabledAndChecked() {
        let model = EntryViewLayoutColumnsMenuModel(visibleColumns: [.dateModified])
        let headerView = EntryListHeaderView()
        let menu = headerView.makeMenu(model: model)

        let nameItem = menu.items.first { $0.title == EntryListColumn.name.title }
        XCTAssertNotNil(nameItem)
        guard let nameItem else { return }
        XCTAssertEqual(nameItem.state, NSControl.StateValue.on)
        XCTAssertFalse(nameItem.isEnabled)
    }

    /// 컬럼 상태 회귀를 방지한다.
    func testToggleClickSendsSetListColumnVisibility() {
        let model = EntryViewLayoutColumnsMenuModel(visibleColumns: [.name])
        let headerView = EntryListHeaderView()
        var sentActions: [EntryViewLayoutAction] = []
        headerView.send = { sentActions.append($0) }

        let menu = headerView.makeMenu(model: model)
        guard let kindItem = menu.items.first(where: { $0.title == EntryListColumn.kind.title }) else {
            XCTFail("Expected Kind menu item")
            return
        }
        XCTAssertEqual(kindItem.state, NSControl.StateValue.off)
        XCTAssertTrue(kindItem.isEnabled)

        guard let target = kindItem.target as AnyObject? else {
            XCTFail("Expected Kind item target")
            return
        }
        guard let action = kindItem.action else {
            XCTFail("Expected Kind item action")
            return
        }
        _ = target.perform(action, with: kindItem)

        XCTAssertEqual(sentActions.count, 1)
        guard let first = sentActions.first else { return }
        guard case let .internal(.setListColumnVisibility(column, isVisible)) = first else {
            XCTFail("Expected setListColumnVisibility")
            return
        }
        XCTAssertEqual(column, .kind)
        XCTAssertTrue(isVisible)
    }

    /// 컬럼 상태 회귀를 방지한다.
    func testRequiredNameColumnCannotBeHiddenEvenIfHandlerIsInvoked() {
        let model = EntryViewLayoutColumnsMenuModel(visibleColumns: [.dateModified])
        let headerView = EntryListHeaderView()
        var sentActions: [EntryViewLayoutAction] = []
        headerView.send = { sentActions.append($0) }

        let menu = headerView.makeMenu(model: model)
        guard let nameItem = menu.items.first(where: { $0.title == EntryListColumn.name.title }) else {
            XCTFail("Expected Name menu item")
            return
        }
        XCTAssertEqual(nameItem.state, NSControl.StateValue.on)
        XCTAssertFalse(nameItem.isEnabled)

        nameItem.isEnabled = true
        guard let target = nameItem.target as AnyObject? else {
            XCTFail("Expected Name item target")
            return
        }
        guard let action = nameItem.action else {
            XCTFail("Expected Name item action")
            return
        }
        _ = target.perform(action, with: nameItem)
        XCTAssertTrue(sentActions.isEmpty)
    }

    /// 컬럼 상태 회귀를 방지한다.
    func testResetClickSendsResetListVisibleColumns() {
        let model = EntryViewLayoutColumnsMenuModel(visibleColumns: [.name])
        let headerView = EntryListHeaderView()
        var sentActions: [EntryViewLayoutAction] = []
        headerView.send = { sentActions.append($0) }

        let menu = headerView.makeMenu(model: model)
        guard let resetItem = menu.items.first(where: { $0.title == model.resetItem.title }) else {
            XCTFail("Expected Reset menu item")
            return
        }
        XCTAssertEqual(resetItem.title, model.resetItem.title)
        XCTAssertTrue(resetItem.isEnabled)

        guard let target = resetItem.target as AnyObject? else {
            XCTFail("Expected Reset item target")
            return
        }
        guard let action = resetItem.action else {
            XCTFail("Expected Reset item action")
            return
        }
        _ = target.perform(action, with: resetItem)

        XCTAssertEqual(sentActions.count, 1)
        guard let first = sentActions.first else { return }
        guard case .internal(.resetListVisibleColumns) = first else {
            XCTFail("Expected resetListVisibleColumns")
            return
        }
    }

    /// 태그 표시/가시성 회귀를 방지한다.
    func testVOY216MenuDoesNotExposeSeparateTagsColumn() {
        let model = EntryViewLayoutColumnsMenuModel(visibleColumns: EntryListColumn.defaultVisibleColumns)
        let headerView = EntryListHeaderView()
        let menu = headerView.makeMenu(model: model)

        XCTAssertNil(menu.items.first(where: { $0.title == "Tags" }))
    }

    /// 컬럼 상태 회귀를 방지한다.
    func testVOY216ColumnsRenderConfiguredFallbacks() {
        XCTAssertEqual(EntryListColumn.application.title, "Application")
        XCTAssertEqual(EntryListColumn.dateAdded.title, "Date Added")
        XCTAssertEqual(EntryListColumn.dateCreated.title, "Date Created")
        XCTAssertEqual(EntryListColumn.dateLastOpened.title, "Date Last Opened")
        XCTAssertEqual(EntryListColumn.defaultVisibleColumns, [.name, .dateModified, .size, .kind])
    }
}
