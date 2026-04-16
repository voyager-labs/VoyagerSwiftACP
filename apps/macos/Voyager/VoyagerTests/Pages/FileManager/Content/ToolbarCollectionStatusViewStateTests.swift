import Foundation
@testable import Voyager
import XCTest

@MainActor
final class ToolbarCollectionStatusViewStateTests: XCTestCase {
    func testDirtyOnlyShowsUnsavedIndicator() {
        let state = ToolbarCollectionStatusViewState(
            isCollectionMode: true,
            openedCollectionURLExists: true,
            isOpenedCollectionDirty: true,
            isOpenedCollectionStale: false,
            canRefreshStaleCollection: false,
        )

        XCTAssertTrue(state.showsUnsavedIndicator)
        XCTAssertFalse(state.showsStaleIndicator)
        XCTAssertFalse(state.showsRefreshAffordance)
        XCTAssertFalse(state.isRefreshEnabled)
    }

    func testStaleOnlyShowsStaleIndicator() {
        let state = ToolbarCollectionStatusViewState(
            isCollectionMode: true,
            openedCollectionURLExists: true,
            isOpenedCollectionDirty: false,
            isOpenedCollectionStale: true,
            canRefreshStaleCollection: true,
        )

        XCTAssertFalse(state.showsUnsavedIndicator)
        XCTAssertTrue(state.showsStaleIndicator)
        XCTAssertTrue(state.showsRefreshAffordance)
        XCTAssertTrue(state.isRefreshEnabled)
    }

    func testDirtyAndStaleShowBothIndicators() {
        let state = ToolbarCollectionStatusViewState(
            isCollectionMode: true,
            openedCollectionURLExists: true,
            isOpenedCollectionDirty: true,
            isOpenedCollectionStale: true,
            canRefreshStaleCollection: false,
        )

        XCTAssertTrue(state.showsUnsavedIndicator)
        XCTAssertTrue(state.showsStaleIndicator)
        XCTAssertTrue(state.showsRefreshAffordance)
        XCTAssertFalse(state.isRefreshEnabled)
    }

    func testMissingCollectionPrerequisitesDisableRefreshAffordance() {
        let state = ToolbarCollectionStatusViewState(
            isCollectionMode: true,
            openedCollectionURLExists: true,
            isOpenedCollectionDirty: false,
            isOpenedCollectionStale: true,
            canRefreshStaleCollection: false,
        )

        XCTAssertTrue(state.showsRefreshAffordance)
        XCTAssertFalse(state.isRefreshEnabled)
    }

    func testNonCollectionShowsNoIndicators() {
        let state = ToolbarCollectionStatusViewState(
            isCollectionMode: false,
            openedCollectionURLExists: false,
            isOpenedCollectionDirty: true,
            isOpenedCollectionStale: true,
            canRefreshStaleCollection: false,
        )

        XCTAssertFalse(state.showsUnsavedIndicator)
        XCTAssertFalse(state.showsStaleIndicator)
        XCTAssertFalse(state.showsRefreshAffordance)
        XCTAssertFalse(state.isRefreshEnabled)
    }
}
