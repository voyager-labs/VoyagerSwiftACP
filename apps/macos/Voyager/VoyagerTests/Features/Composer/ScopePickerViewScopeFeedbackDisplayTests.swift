import Foundation
@testable import Voyager
import XCTest

@MainActor
final class ScopePickerViewScopeFeedbackDisplayTests: XCTestCase {
    func testScopeFeedbackDisplayAddsBaseCopy() {
        let selection: ComposerScopeSelection = .explicit(
            bases: [ComposerScopeBase(path: "/Users/me/Documents")],
            exceptions: [],
        )
        let feedback = makeFeedback(
            origin: .addBase,
            beforeSelection: .rootOnly,
            beforeIncludeSubfolders: true,
            afterSelection: selection,
            afterIncludeSubfolders: true,
        )
        let state = makeDisplayState(
            selection: selection,
            includeSubfolders: true,
            historyCount: feedback.historyDepthAfterCommit,
            redoCount: feedback.redoDepthAfterCommit,
            feedback: feedback,
        )

        guard let display = state.lastScopeChangeFeedbackDisplay else {
            return XCTFail("expected scope feedback display")
        }

        XCTAssertEqual(display.title, "Scope updated to Documents")
        XCTAssertEqual(display.message, "Include subfolders")
        XCTAssertEqual(display.phaseLabel, "Applied")
        XCTAssertTrue(display.showsUndo)
        XCTAssertFalse(display.showsRedo)
        XCTAssertFalse(display.isFailure)
        XCTAssertFalse(display.isDelayed)
    }

    func testScopeFeedbackDisplayHandlesDelayedIncludeSubfoldersCopy() {
        let selection: ComposerScopeSelection = .explicit(
            bases: [ComposerScopeBase(path: "/Users/me/Documents")],
            exceptions: [],
        )
        let feedback = makeFeedback(
            origin: .includeSubfolders,
            beforeSelection: selection,
            beforeIncludeSubfolders: true,
            afterSelection: selection,
            afterIncludeSubfolders: false,
            phase: .delayed,
        )
        let state = makeDisplayState(
            selection: selection,
            includeSubfolders: false,
            historyCount: feedback.historyDepthAfterCommit,
            redoCount: feedback.redoDepthAfterCommit,
            feedback: feedback,
        )

        guard let display = state.lastScopeChangeFeedbackDisplay else {
            return XCTFail("expected delayed scope feedback display")
        }

        XCTAssertEqual(display.title, "Limited to this folder")
        XCTAssertEqual(display.message, "Scope change is still applying")
        XCTAssertEqual(display.phaseLabel, "Applying")
        XCTAssertFalse(display.isFailure)
        XCTAssertTrue(display.isDelayed)
    }

    func testScopeFeedbackDisplayHandlesRemoveCopy() {
        let removedSelection: ComposerScopeSelection = .rootOnly
        let feedback = makeFeedback(
            origin: .removeBase,
            beforeSelection: .explicit(
                bases: [ComposerScopeBase(path: "/Users/me/Documents")],
                exceptions: [],
            ),
            beforeIncludeSubfolders: true,
            afterSelection: removedSelection,
            afterIncludeSubfolders: true,
        )
        let state = makeDisplayState(
            selection: removedSelection,
            includeSubfolders: true,
            historyCount: feedback.historyDepthAfterCommit,
            redoCount: feedback.redoDepthAfterCommit,
            feedback: feedback,
        )

        guard let display = state.lastScopeChangeFeedbackDisplay else {
            return XCTFail("expected remove scope feedback display")
        }

        XCTAssertEqual(display.title, "Removed Documents from scope")
    }

    func testScopeFeedbackDisplayHandlesExcludeFailureCopy() {
        let selection: ComposerScopeSelection = .explicit(
            bases: [ComposerScopeBase(path: "/Users/me/Documents")],
            exceptions: [ComposerScopeException(path: "/Users/me/Documents/Secrets")],
        )
        let feedback = makeFeedback(
            origin: .exclude,
            beforeSelection: .explicit(
                bases: [ComposerScopeBase(path: "/Users/me/Documents")],
                exceptions: [],
            ),
            beforeIncludeSubfolders: true,
            afterSelection: selection,
            afterIncludeSubfolders: true,
            phase: .failed,
        )
        let state = makeDisplayState(
            selection: selection,
            includeSubfolders: true,
            historyCount: feedback.historyDepthAfterCommit,
            redoCount: feedback.redoDepthAfterCommit,
            feedback: feedback,
        )

        guard let display = state.lastScopeChangeFeedbackDisplay else {
            return XCTFail("expected failed scope feedback display")
        }

        XCTAssertEqual(display.title, "Excluded Secrets from Documents")
        XCTAssertEqual(display.message, "Scope change could not be fully applied. Current selection was kept.")
        XCTAssertEqual(display.phaseLabel, "Failed")
        XCTAssertTrue(display.isFailure)
        XCTAssertFalse(display.isDelayed)
    }

    func testScopeFeedbackDisplayHandlesRestoreCopy() {
        let selection: ComposerScopeSelection = .explicit(
            bases: [ComposerScopeBase(path: "/Users/me/Documents")],
            exceptions: [],
        )
        let feedback = makeFeedback(
            origin: .restore,
            beforeSelection: .explicit(
                bases: [ComposerScopeBase(path: "/Users/me/Documents")],
                exceptions: [ComposerScopeException(path: "/Users/me/Documents/Secrets")],
            ),
            beforeIncludeSubfolders: true,
            afterSelection: selection,
            afterIncludeSubfolders: true,
        )
        let state = makeDisplayState(
            selection: selection,
            includeSubfolders: true,
            historyCount: feedback.historyDepthAfterCommit,
            redoCount: feedback.redoDepthAfterCommit,
            feedback: feedback,
        )

        guard let display = state.lastScopeChangeFeedbackDisplay else {
            return XCTFail("expected restore scope feedback display")
        }

        XCTAssertEqual(display.title, "Restored Secrets")
    }

    func testScopeFeedbackDisplayCoversFailureAndRedoCopy() {
        let addedSelection: ComposerScopeSelection = .explicit(
            bases: [ComposerScopeBase(path: "/Users/me/Documents")],
            exceptions: [],
        )
        let feedback = makeFeedback(
            origin: .addBase,
            beforeSelection: .rootOnly,
            beforeIncludeSubfolders: true,
            afterSelection: addedSelection,
            afterIncludeSubfolders: true,
        )

        let visibleState = makeDisplayState(
            selection: addedSelection,
            includeSubfolders: true,
            historyCount: feedback.historyDepthAfterCommit,
            redoCount: feedback.redoDepthAfterCommit,
            feedback: feedback,
        )

        guard let visibleDisplay = visibleState.lastScopeChangeFeedbackDisplay else {
            return XCTFail("expected visible scope feedback display")
        }

        XCTAssertTrue(visibleDisplay.showsUndo)
        XCTAssertFalse(visibleDisplay.showsRedo)

        var undoneState = makeDisplayState(
            selection: .rootOnly,
            includeSubfolders: true,
            historyCount: 0,
            redoCount: 1,
            feedback: feedback,
        )
        undoneState.redoHistory = [makeSnapshot(selection: addedSelection, includeSubfolders: true)]

        guard let undoneDisplay = undoneState.lastScopeChangeFeedbackDisplay else {
            return XCTFail("expected undone scope feedback display")
        }

        XCTAssertFalse(undoneDisplay.showsUndo)
        XCTAssertTrue(undoneDisplay.showsRedo)
    }

    func testScopeFeedbackDisplayHidesRedoWhenNextRedoIsNotScopeChange() {
        let addedSelection: ComposerScopeSelection = .explicit(
            bases: [ComposerScopeBase(path: "/Users/me/Documents")],
            exceptions: [],
        )
        let feedback = makeFeedback(
            origin: .addBase,
            beforeSelection: .rootOnly,
            beforeIncludeSubfolders: true,
            afterSelection: addedSelection,
            afterIncludeSubfolders: true,
        )
        var state = makeDisplayState(
            selection: .rootOnly,
            includeSubfolders: true,
            historyCount: 0,
            redoCount: 2,
            feedback: feedback,
        )
        state.redoHistory = [
            makeSnapshot(selection: addedSelection, includeSubfolders: true),
            makeSnapshot(selection: .rootOnly, includeSubfolders: true),
        ]

        guard let display = state.lastScopeChangeFeedbackDisplay else {
            return XCTFail("expected undone scope feedback display")
        }

        XCTAssertFalse(display.showsUndo)
        XCTAssertFalse(display.showsRedo)
    }

    private func makeDisplayState(
        selection: ComposerScopeSelection,
        includeSubfolders: Bool,
        historyCount: Int,
        redoCount: Int,
        feedback: ComposerScopeChangeFeedback,
    ) -> ComposerState {
        var state = ComposerState()
        state.scopeEditor.selection = selection
        state.scopeEditor.includeSubfolders = includeSubfolders
        state.history = Array(
            repeating: makeSnapshot(selection: selection, includeSubfolders: includeSubfolders),
            count: historyCount,
        )
        state.redoHistory = Array(
            repeating: makeSnapshot(selection: selection, includeSubfolders: includeSubfolders),
            count: redoCount,
        )
        state.lastScopeChangeFeedback = feedback
        return state
    }

    private func makeFeedback(
        origin: ComposerScopeChangeFeedbackOrigin,
        beforeSelection: ComposerScopeSelection,
        beforeIncludeSubfolders: Bool,
        afterSelection: ComposerScopeSelection,
        afterIncludeSubfolders: Bool,
        phase: ComposerScopeChangeFeedbackPhase = .visible,
        historyDepthAfterCommit: Int = 1,
        redoDepthAfterCommit: Int = 0,
    ) -> ComposerScopeChangeFeedback {
        ComposerScopeChangeFeedback(
            id: UUID(),
            beforeScope: ComposerScopeSnapshot(
                scopeSelection: beforeSelection,
                includeSubfolders: beforeIncludeSubfolders,
            ),
            afterScope: ComposerScopeSnapshot(
                scopeSelection: afterSelection,
                includeSubfolders: afterIncludeSubfolders,
            ),
            origin: origin,
            phase: phase,
            pendingResultRequest: nil,
            historyDepthAfterCommit: historyDepthAfterCommit,
            redoDepthAfterCommit: redoDepthAfterCommit,
        )
    }

    private func makeSnapshot(
        selection: ComposerScopeSelection,
        includeSubfolders: Bool,
    ) -> FilterSnapshot {
        FilterSnapshot(
            scopeSelection: selection,
            conditions: [],
            conditionDisplayByKey: [:],
            includeSubfolders: includeSubfolders,
        )
    }
}
