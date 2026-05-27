import Foundation
@testable import Voyager
import VoyagerEntitiesCollection
@testable import VoyagerPagesFileManager
import XCTest

/// 툴바 리프레시 버튼 가시성 계약이 stale/비 stale 경계에 맞는지 검증한다.
@MainActor
final class ToolbarViewRefreshVisibilityTests: XCTestCase {
    /// testToolbarRefreshButtonUsesCollectionStatusVisibilityGate 시나리오가 FileManager 계약을 위반하지 않음을 검증한다.
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

    /// testToolbarRefreshButtonStaysHiddenOutsideStaleCollectionContext 시나리오가 FileManager 계약을 위반하지 않음을 검증한다.
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

    /// testToolbarRefreshButtonHidesWhenStaleIsNotResolvable 시나리오가 FileManager 계약을 위반하지 않음을 검증한다.
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
