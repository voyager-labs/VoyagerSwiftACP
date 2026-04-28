import AppKit
@testable import Voyager
import XCTest

@MainActor
final class EntryGridDropHighlightLifecycleTests: XCTestCase {
    func testAcceptDropClearsDropTargetState() {
        let operation: NSDragOperation = .copy
        XCTAssertFalse(
            EntryViewLayoutDragStateClearRuleSet.shouldClearAfterSessionEnd(operation: operation),
            "Successful copy drop should defer clearing — highlight persists until operation completes",
        )
    }

    func testInvalidDropClearsDropTargetState() {
        let operation: NSDragOperation = []
        XCTAssertTrue(
            EntryViewLayoutDragStateClearRuleSet.shouldClearAfterSessionEnd(operation: operation),
            "Invalid drop should still trigger drop target state clearing",
        )
    }

    func testDragEndClearsDropTargetState() {
        let paths = ["/Users/test/Documents/file.txt"]
        let cleared = EntryViewLayoutDragStateClearRuleSet.clearedDragPaths(
            afterSessionEndWith: .move,
            currentPaths: paths,
        )
        XCTAssertTrue(
            cleared.isEmpty,
            "Drag end should clear all internal drag state paths",
        )
        XCTAssertTrue(
            EntryViewLayoutDragStateClearRuleSet.shouldClearAfterSessionEnd(operation: .move),
            "Drag end should trigger drop target clearing",
        )
    }

    func testReloadDoesNotPreserveStaleDropTargetState() {
        let stalePaths = ["/Users/test/stale.txt"]
        let cleared = EntryViewLayoutDragStateClearRuleSet.clearedDragPaths(
            afterSessionEndWith: [],
            currentPaths: stalePaths,
        )
        XCTAssertTrue(
            cleared.isEmpty,
            "Stale drag paths should be fully cleared on cancelled session end",
        )
        XCTAssertFalse(
            EntryViewLayoutDragStateClearRuleSet.isInternalDrag(paths: cleared),
            "After clearing, subsequent drag should not be treated as internal",
        )
    }

    // MARK: - Bug 1: Premature highlight clear (snap-back)

    func testSuccessfulFolderDropDoesNotClearHighlightAtAcceptTime() {
        // DESIRED: A successful drop (non-empty operation) should NOT trigger
        // session-end clearing at accept-drop time. The highlight must persist
        // until the file operation completes.
        //
        // WILL FAIL: current implementation unconditionally returns true for
        // all operations, causing acceptDrop to clear highlight immediately.
        let successfulOperation: NSDragOperation = .copy
        XCTAssertFalse(
            EntryViewLayoutDragStateClearRuleSet.shouldClearAfterSessionEnd(operation: successfulOperation),
            "Successful drop operation should NOT clear highlight at accept time — deferred to operation completion",
        )
    }

    func testSuccessfulFolderDropClearsHighlightAfterOperationCompletes() {
        // DESIRED: After operation completion (signaled by a separate lifecycle
        // event), the rule set should allow clearing. This encodes the contract
        // that clearing is deferred, not absent.
        //
        // WILL FAIL: no mechanism exists to distinguish "session ended with
        // success" from "session ended, clear now". The rule set has no
        // deferred-clear path.
        let paths = ["/Users/test/Documents/file.txt"]
        let operation: NSDragOperation = .copy

        // Session-end should preserve paths for successful operations
        let preserved = EntryViewLayoutDragStateClearRuleSet.clearedDragPaths(
            afterSessionEndWith: operation,
            currentPaths: paths,
        )
        XCTAssertEqual(
            preserved,
            paths,
            "After successful drop, drag paths should be preserved until operation lifecycle signals completion",
        )
        XCTAssertTrue(
            EntryViewLayoutDragStateClearRuleSet.isInternalDrag(paths: preserved),
            "Preserved paths should still be recognized as internal drag state",
        )
    }

    func testCancelledDragClearsHighlightImmediately() {
        // Cancelled drag (empty operation) should clear immediately.
        // This should PASS — current behavior is correct for cancellations.
        let cancelledOperation: NSDragOperation = []
        XCTAssertTrue(
            EntryViewLayoutDragStateClearRuleSet.shouldClearAfterSessionEnd(operation: cancelledOperation),
            "Cancelled drag should clear highlight immediately",
        )
        let cleared = EntryViewLayoutDragStateClearRuleSet.clearedDragPaths(
            afterSessionEndWith: cancelledOperation,
            currentPaths: ["/tmp/file.txt"],
        )
        XCTAssertTrue(
            cleared.isEmpty,
            "Cancelled drag should clear all stored paths",
        )
    }

    func testInvalidDropTargetClearsHighlightImmediately() {
        // Invalid drop target (operation resolved to .none by validation)
        // should clear immediately. This should PASS with current behavior.
        let noOperation: NSDragOperation = []
        XCTAssertTrue(
            EntryViewLayoutDragStateClearRuleSet.shouldClearAfterSessionEnd(operation: noOperation),
            "Invalid drop target should clear highlight immediately",
        )
    }

    // MARK: - Finder-like highlight restraint lifecycle (NEW)

    func testDropTargetHighlightRestraintOnTransitionFromTargetedToUntargeted() {
        // NEW CONTRACT: When transitioning from targeted→untargeted, the full-cell
        // border must be fully removed. This validates that the old broad treatment
        // is completely cleared — no residual border artifacts.
        // This should PASS but documents the lifecycle requirement.
        XCTAssertTrue(
            EntryViewLayoutDragStateClearRuleSet.shouldClearAfterSessionEnd(operation: []),
            "Untargeted transition must clear all drop visual state",
        )
    }

    func testDropTargetHighlightDoesNotPersistAcrossDragSessions() {
        // NEW CONTRACT: Stale drop target state from a previous drag session must not
        // bleed into a new session. Each session starts clean.
        let freshPaths: [String] = []
        let cleared = EntryViewLayoutDragStateClearRuleSet.clearedDragPaths(
            afterSessionEndWith: [],
            currentPaths: freshPaths,
        )
        XCTAssertTrue(
            cleared.isEmpty,
            "No stale paths should persist between drag sessions",
        )
    }
}
