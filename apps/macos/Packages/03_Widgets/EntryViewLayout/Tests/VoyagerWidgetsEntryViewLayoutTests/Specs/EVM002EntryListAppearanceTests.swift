import AppKit
@testable import VoyagerWidgetsEntryViewLayout
import XCTest

@MainActor
final class EVM002EntryListAppearanceTests: XCTestCase {
    func testEntryListDisablesAlternatingRowColors() {
        let view = EntryListView(frame: .zero)

        XCTAssertFalse(view.tableView.usesAlternatingRowBackgroundColors)
    }

    func testMaterialAppearanceUpdatesHeaderAndGroupOpacities() {
        let view = EntryListView(frame: .zero)

        view.updateMaterialAppearance(
            headerMaterial: .hudWindow,
            headerBlendingMode: .behindWindow,
            headerAlphaValue: 0.6,
            groupRowLightOpacity: 0.035,
            groupRowDarkOpacity: 0.065,
        )

        XCTAssertEqual(view.scrollView.headerMaterial, .hudWindow)
        XCTAssertEqual(view.scrollView.headerBlendingMode, .behindWindow)
        XCTAssertEqual(view.scrollView.headerAlphaValue, 0.6)
        XCTAssertEqual(view.tableView.groupRowLightOpacity, 0.035)
        XCTAssertEqual(view.tableView.groupRowDarkOpacity, 0.065)
    }
}
