import AppKit
@testable import VoyagerWidgetsEntryViewLayout
import XCTest

@MainActor
final class EntryListHorizontalScrollTests: XCTestCase {
    /// 리스트 뷰가 가로 스크롤을 유지하도록 테이블 설정을 고정하는지 검증
    ///
    /// - 검증 내용: 가로 스크롤바 활성화, 컬럼 자동 리사이즈 비활성화
    /// - 회귀 방지: 긴 열 이름이나 넓은 컬럼이 강제로 축소되는 문제 방지
    func testEntryListViewEnablesHorizontalScrollingConfiguration() {
        let view = EntryListView(frame: NSRect(x: 0, y: 0, width: 480, height: 320))

        XCTAssertTrue(view.scrollView.hasHorizontalScroller)
        XCTAssertEqual(view.tableView.columnAutoresizingStyle, .noColumnAutoresizing)
        XCTAssertFalse(view.tableView.autoresizesOutlineColumn)
    }

    /// 뷰 폭이 바뀌어도 컬럼 폭을 뷰포트에 맞춰 자동 재조정하지 않는지 검증
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
