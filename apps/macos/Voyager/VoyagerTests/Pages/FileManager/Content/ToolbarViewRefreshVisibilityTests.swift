import Foundation
@testable import Voyager
import XCTest

@MainActor
final class ToolbarViewRefreshVisibilityTests: XCTestCase {
    func testToolbarRefreshButtonUsesCollectionStatusVisibilityGate() {
        let status = ToolbarCollectionStatusViewState(
            isCollectionMode: true,
            openedCollectionURLExists: true,
            isOpenedCollectionDirty: false,
            isOpenedCollectionStale: true,
            canRefreshStaleCollection: true,
        )

        XCTAssertTrue(showsToolbarRefreshButton(status))
        XCTAssertTrue(isToolbarRefreshButtonEnabled(status))
    }

    func testToolbarRefreshButtonStaysHiddenOutsideStaleCollectionContext() {
        let status = ToolbarCollectionStatusViewState(
            isCollectionMode: false,
            openedCollectionURLExists: false,
            isOpenedCollectionDirty: false,
            isOpenedCollectionStale: true,
            canRefreshStaleCollection: false,
        )

        XCTAssertFalse(showsToolbarRefreshButton(status))
        XCTAssertFalse(isToolbarRefreshButtonEnabled(status))
    }

    func testToolbarRefreshButtonCanBeVisibleButDisabled() {
        let status = ToolbarCollectionStatusViewState(
            isCollectionMode: true,
            openedCollectionURLExists: true,
            isOpenedCollectionDirty: true,
            isOpenedCollectionStale: true,
            canRefreshStaleCollection: false,
        )

        XCTAssertTrue(showsToolbarRefreshButton(status))
        XCTAssertFalse(isToolbarRefreshButtonEnabled(status))
    }
}
