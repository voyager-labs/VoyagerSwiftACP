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
            refreshBlockingReason: .notStale,
        )

        XCTAssertTrue(state.showsUnsavedIndicator)
        XCTAssertFalse(state.showsStaleIndicator)
        XCTAssertFalse(state.showsRefreshAffordance)
        XCTAssertFalse(state.isRefreshEnabled)
        XCTAssertEqual(state.refreshBlockingReason, .notStale)
    }

    func testStaleOnlyShowsStaleIndicator() {
        let state = ToolbarCollectionStatusViewState(
            isCollectionMode: true,
            openedCollectionURLExists: true,
            isOpenedCollectionDirty: false,
            isOpenedCollectionStale: true,
            refreshBlockingReason: nil,
        )

        XCTAssertFalse(state.showsUnsavedIndicator)
        XCTAssertTrue(state.showsStaleIndicator)
        XCTAssertTrue(state.showsRefreshAffordance)
        XCTAssertTrue(state.isRefreshEnabled)
        XCTAssertNil(state.refreshBlockingReason)
    }

    func testDirtyAndStaleShowBothIndicators() {
        let state = ToolbarCollectionStatusViewState(
            isCollectionMode: true,
            openedCollectionURLExists: true,
            isOpenedCollectionDirty: true,
            isOpenedCollectionStale: true,
            refreshBlockingReason: .dirtyCollection,
        )

        XCTAssertTrue(state.showsUnsavedIndicator)
        XCTAssertTrue(state.showsStaleIndicator)
        XCTAssertFalse(state.showsRefreshAffordance)
        XCTAssertFalse(state.isRefreshEnabled)
        XCTAssertEqual(state.refreshBlockingReason, .dirtyCollection)
    }

    func testMissingCollectionPrerequisitesDisableRefreshAffordance() {
        let state = ToolbarCollectionStatusViewState(
            isCollectionMode: true,
            openedCollectionURLExists: true,
            isOpenedCollectionDirty: false,
            isOpenedCollectionStale: true,
            refreshBlockingReason: .missingBaseline,
        )

        XCTAssertTrue(state.showsStaleIndicator)
        XCTAssertFalse(state.showsRefreshAffordance)
        XCTAssertFalse(state.isRefreshEnabled)
        XCTAssertEqual(state.refreshBlockingReason, .missingBaseline)
    }

    func testNonCollectionShowsNoIndicators() {
        let state = ToolbarCollectionStatusViewState(
            isCollectionMode: false,
            openedCollectionURLExists: false,
            isOpenedCollectionDirty: true,
            isOpenedCollectionStale: true,
            refreshBlockingReason: .notInCollectionMode,
        )

        XCTAssertFalse(state.showsUnsavedIndicator)
        XCTAssertFalse(state.showsStaleIndicator)
        XCTAssertFalse(state.showsRefreshAffordance)
        XCTAssertFalse(state.isRefreshEnabled)
        XCTAssertEqual(state.refreshBlockingReason, .notInCollectionMode)
    }
}
