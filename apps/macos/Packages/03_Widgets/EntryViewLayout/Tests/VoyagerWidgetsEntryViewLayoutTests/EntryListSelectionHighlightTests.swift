import AppKit
@testable import VoyagerWidgetsEntryViewLayout
import XCTest

@MainActor
final class EntryListSelectionHighlightTests: XCTestCase {
    /// 리스트 선택 row가 key-command focus 전환에도 inactive gray 강조 상태로 내려가지 않는지 검증
    func testSelectionRowViewKeepsEmphasizedSelection() {
        let rowView = EntryListSelectionRowView()

        rowView.isEmphasized = false

        XCTAssertTrue(rowView.isEmphasized)
    }

    /// 리스트 선택 row가 AppKit 기본 회색 inactive 선택 대신 accent 선택 배경을 직접 그릴 수 있는지 검증
    func testSelectionRowViewUsesRegularHighlightStyle() {
        let rowView = EntryListSelectionRowView()

        rowView.selectionHighlightStyle = .regular

        XCTAssertEqual(rowView.selectionHighlightStyle, .regular)
    }
}
