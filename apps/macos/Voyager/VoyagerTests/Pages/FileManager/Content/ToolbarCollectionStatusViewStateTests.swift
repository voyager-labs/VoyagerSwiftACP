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
        )

        XCTAssertTrue(state.showsUnsavedIndicator)
        XCTAssertFalse(state.showsStaleIndicator)
    }

    func testStaleOnlyShowsStaleIndicator() {
        let state = ToolbarCollectionStatusViewState(
            isCollectionMode: true,
            openedCollectionURLExists: true,
            isOpenedCollectionDirty: false,
            isOpenedCollectionStale: true,
        )

        XCTAssertFalse(state.showsUnsavedIndicator)
        XCTAssertTrue(state.showsStaleIndicator)
    }

    func testDirtyAndStaleShowBothIndicators() {
        let state = ToolbarCollectionStatusViewState(
            isCollectionMode: true,
            openedCollectionURLExists: true,
            isOpenedCollectionDirty: true,
            isOpenedCollectionStale: true,
        )

        XCTAssertTrue(state.showsUnsavedIndicator)
        XCTAssertTrue(state.showsStaleIndicator)
    }

    func testNonCollectionShowsNoIndicators() {
        let state = ToolbarCollectionStatusViewState(
            isCollectionMode: false,
            openedCollectionURLExists: false,
            isOpenedCollectionDirty: true,
            isOpenedCollectionStale: true,
        )

        XCTAssertFalse(state.showsUnsavedIndicator)
        XCTAssertFalse(state.showsStaleIndicator)
    }
}
