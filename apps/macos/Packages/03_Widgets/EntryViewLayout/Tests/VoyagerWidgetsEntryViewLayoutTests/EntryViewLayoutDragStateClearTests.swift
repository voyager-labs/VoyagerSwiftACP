import AppKit
@testable import VoyagerWidgetsEntryViewLayout
import XCTest

@MainActor
final class EntryViewLayoutDragStateClearTests: XCTestCase {
    func testClearsInternalDragStateWhenSessionEndsWithNonEmptyOperation() {
        // .copy intentionally preserves paths (highlight persists until file op completes);
        // use .move to verify non-copy operations clear immediately.
        let after = EntryViewLayoutDragStateClearRuleSet.clearedDragPaths(
            afterSessionEndWith: .move,
            currentPaths: ["/tmp/a.txt"]
        )

        XCTAssertTrue(after.isEmpty)
    }

    func testCopyOperationPreservesDragPathsUntilCompletion() {
        // .copy defers clearing so the highlight persists during the async file operation.
        let after = EntryViewLayoutDragStateClearRuleSet.clearedDragPaths(
            afterSessionEndWith: .copy,
            currentPaths: ["/tmp/a.txt"]
        )

        XCTAssertFalse(after.isEmpty, "Copy operations should preserve drag paths for highlight persistence")
    }

    func testClearsInternalDragStateWhenSessionEndsWithEmptyOperation() {
        let after = EntryViewLayoutDragStateClearRuleSet.clearedDragPaths(
            afterSessionEndWith: [],
            currentPaths: ["/tmp/a.txt"]
        )

        XCTAssertTrue(after.isEmpty)
    }

    func testNextDragIsNotTreatedAsInternalAfterStateCleared() {
        let cleared = EntryViewLayoutDragStateClearRuleSet.clearedDragPaths(
            afterSessionEndWith: .move,
            currentPaths: ["/tmp/a.txt"]
        )

        XCTAssertFalse(EntryViewLayoutDragStateClearRuleSet.isInternalDrag(paths: cleared))
    }
}
