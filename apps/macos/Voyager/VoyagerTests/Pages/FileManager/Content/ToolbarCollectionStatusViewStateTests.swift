import Foundation
@testable import Voyager
import VoyagerEntitiesCollection
@testable import VoyagerPagesFileManager
import XCTest

/// 툴바 collection 상태 표시가 window/content 상태 계약을 어기지 않음을 검증한다.
@MainActor
final class ToolbarCollectionStatusViewStateTests: XCTestCase {
    /// testDirtyOnlyShowsUnsavedIndicator 시나리오가 FileManager 계약을 위반하지 않음을 검증한다.
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

    /// testStaleOnlyShowsStaleIndicator 시나리오가 FileManager 계약을 위반하지 않음을 검증한다.
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

    /// testDirtyAndStaleShowBothIndicators 시나리오가 FileManager 계약을 위반하지 않음을 검증한다.
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

    /// testMissingCollectionPrerequisitesDisableRefreshAffordance 시나리오가 FileManager 계약을 위반하지 않음을 검증한다.
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

    /// testNonCollectionShowsNoIndicators 시나리오가 FileManager 계약을 위반하지 않음을 검증한다.
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
