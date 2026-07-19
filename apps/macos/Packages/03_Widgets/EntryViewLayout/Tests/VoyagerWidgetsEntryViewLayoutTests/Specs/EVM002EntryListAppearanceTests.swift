import AppKit
@testable import VoyagerWidgetsEntryViewLayout
import XCTest

@MainActor
final class EVM002EntryListAppearanceTests: XCTestCase {
    func testEntryListDisablesAlternatingRowColors() {
        let view = EntryListView(frame: .zero)

        XCTAssertFalse(view.tableView.usesAlternatingRowBackgroundColors)
    }
}
