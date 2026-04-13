import AppKit
@testable import Voyager
@testable import VoyagerWidgetsEntryViewLayout
import XCTest

@MainActor
final class EntryViewLayoutDragStateClearTests: XCTestCase {
    func testClearsInternalDragStateWhenSessionEndsWithNonEmptyOperation() {
        let after = EntryViewLayoutDragStateClearRuleSet.clearedDragPaths(
            afterSessionEndWith: .copy,
            currentPaths: ["/tmp/a.txt"],
        )

        XCTAssertTrue(after.isEmpty)
    }

    func testClearsInternalDragStateWhenSessionEndsWithEmptyOperation() {
        let after = EntryViewLayoutDragStateClearRuleSet.clearedDragPaths(
            afterSessionEndWith: [],
            currentPaths: ["/tmp/a.txt"],
        )

        XCTAssertTrue(after.isEmpty)
    }

    func testNextDragIsNotTreatedAsInternalAfterStateCleared() {
        let cleared = EntryViewLayoutDragStateClearRuleSet.clearedDragPaths(
            afterSessionEndWith: .move,
            currentPaths: ["/tmp/a.txt"],
        )

        XCTAssertFalse(EntryViewLayoutDragStateClearRuleSet.isInternalDrag(paths: cleared))
    }
}
