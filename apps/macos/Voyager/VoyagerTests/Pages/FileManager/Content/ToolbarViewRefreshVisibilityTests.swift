import Foundation
@testable import Voyager
import VoyagerEntitiesCollection
@testable import VoyagerPagesFileManager
import XCTest

@MainActor
final class ToolbarViewRefreshVisibilityTests: XCTestCase {
    func testToolbarRefreshButtonUsesCollectionStatusVisibilityGate() {
        let status = ToolbarCollectionStatusViewState(
            isCollectionMode: true,
            openedCollectionURLExists: true,
            isOpenedCollectionDirty: false,
            isOpenedCollectionStale: true,
            refreshBlockingReason: nil,
        )

        XCTAssertFalse(showsToolbarRefreshButton(status, isTitleAreaHovered: false))
        XCTAssertTrue(showsToolbarRefreshButton(status, isTitleAreaHovered: true))
        XCTAssertTrue(isToolbarRefreshButtonEnabled(status))
    }

    func testToolbarRefreshButtonStaysHiddenOutsideStaleCollectionContext() {
        let status = ToolbarCollectionStatusViewState(
            isCollectionMode: false,
            openedCollectionURLExists: false,
            isOpenedCollectionDirty: false,
            isOpenedCollectionStale: true,
            refreshBlockingReason: .notInCollectionMode,
        )

        XCTAssertFalse(showsToolbarRefreshButton(status, isTitleAreaHovered: false))
        XCTAssertFalse(showsToolbarRefreshButton(status, isTitleAreaHovered: true))
        XCTAssertFalse(isToolbarRefreshButtonEnabled(status))
    }

    func testToolbarRefreshButtonHidesWhenStaleIsNotResolvable() {
        let status = ToolbarCollectionStatusViewState(
            isCollectionMode: true,
            openedCollectionURLExists: true,
            isOpenedCollectionDirty: true,
            isOpenedCollectionStale: true,
            refreshBlockingReason: .dirtyCollection,
        )

        XCTAssertFalse(showsToolbarRefreshButton(status, isTitleAreaHovered: false))
        XCTAssertFalse(showsToolbarRefreshButton(status, isTitleAreaHovered: true))
        XCTAssertFalse(isToolbarRefreshButtonEnabled(status))
    }
}
