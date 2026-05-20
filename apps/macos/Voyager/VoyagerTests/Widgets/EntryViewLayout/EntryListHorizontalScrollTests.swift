import AppKit
@testable import Voyager
import XCTest

@MainActor
/// 가로 스크롤 동작 회귀를 검증하는 테스트 모음이다.
final class EntryListHorizontalScrollTests: XCTestCase {
    /// 가로 스크롤 동작 회귀를 방지한다.
    func testEntryListViewEnablesHorizontalScrollingConfiguration() {
        let view = EntryListView(frame: NSRect(x: 0, y: 0, width: 480, height: 320))

        XCTAssertTrue(view.scrollView.hasHorizontalScroller)
        XCTAssertEqual(view.tableView.columnAutoresizingStyle, .noColumnAutoresizing)
        XCTAssertFalse(view.tableView.autoresizesOutlineColumn)
    }

    /// 컬럼 상태 회귀를 방지한다.
    func testResizingDoesNotAutoFitColumnsToViewportWidth() {
        let view = EntryListView(frame: NSRect(x: 0, y: 0, width: 1000, height: 320))
        view.layoutSubtreeIfNeeded()

        let nameId = NSUserInterfaceItemIdentifier(EntryListColumn.name.rawValue)
        let kindId = NSUserInterfaceItemIdentifier(EntryListColumn.kind.rawValue)

        guard let nameColumn = view.tableView.tableColumn(withIdentifier: nameId) else {
            XCTFail("Missing name column")
            return
        }
        guard let kindColumn = view.tableView.tableColumn(withIdentifier: kindId) else {
            XCTFail("Missing kind column")
            return
        }

        nameColumn.width = 800
        kindColumn.width = 300

        let nameWidthBefore = nameColumn.width
        let kindWidthBefore = kindColumn.width

        view.frame = NSRect(x: 0, y: 0, width: 320, height: 320)
        view.layoutSubtreeIfNeeded()

        XCTAssertEqual(nameColumn.width, nameWidthBefore, accuracy: 0.5)
        XCTAssertEqual(kindColumn.width, kindWidthBefore, accuracy: 0.5)
    }
}
