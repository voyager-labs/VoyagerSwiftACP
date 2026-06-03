import Foundation
@testable import Voyager
import XCTest

@MainActor
final class ScopePickerRowActionSemanticsTests: XCTestCase {
    func testCandidateRowActionKindUsesUxContractSymbols() {
        XCTAssertEqual(ScopeEditorCandidateRowActionKind.include.symbolName, "checkmark")
        XCTAssertEqual(ScopeEditorCandidateRowActionKind.replace.symbolName, "checkmark")
        XCTAssertEqual(ScopeEditorCandidateRowActionKind.exclude.symbolName, "minus")
        XCTAssertFalse(ScopeEditorCandidateRowActionKind.include.usesDestructiveStyling)
        XCTAssertFalse(ScopeEditorCandidateRowActionKind.replace.usesDestructiveStyling)
        XCTAssertTrue(ScopeEditorCandidateRowActionKind.exclude.usesDestructiveStyling)
    }

    func testDescendantCandidateIsExcludeIntentNotDirectCurrentRemoval() {
        let state = ComposerScopeEditorState(
            selection: .explicit(
                bases: [ComposerScopeBase(path: "/Users/me/Documents")],
                exceptions: [],
            ),
            includeSubfolders: true,
            listState: .childFolders(parentPath: "/Users/me/Documents"),
            isPresented: true,
            queryText: "",
            editingPath: "/Users/me/Documents",
            candidateItems: [
                ComposerScopeEditorCandidateItem(
                    path: "/Users/me/Documents/Private",
                    name: "Private",
                    iconName: "folder",
                ),
            ],
            entryMode: .edit,
        )

        XCTAssertEqual(
            state.candidateSelectionIntent(for: "/Users/me/Documents/Private"),
            .exclude(path: "/Users/me/Documents/Private"),
        )

        let items = state.sections().flatMap(\.items)
        XCTAssertTrue(items.contains { item in
            if case let .addableCandidate(candidate) = item {
                candidate.path == "/Users/me/Documents/Private"
            } else {
                false
            }
        })
        XCTAssertFalse(items.contains { item in
            if case let .currentScope(currentItem) = item {
                currentItem.base.path == "/Users/me/Documents/Private"
            } else {
                false
            }
        })
    }

    func testCandidateIntentKeepsIncludeReplaceExcludeMeaningsSeparate() {
        let addState = ComposerScopeEditorState(
            selection: .rootOnly,
            includeSubfolders: true,
            isPresented: true,
            entryMode: .add,
        )
        XCTAssertEqual(
            addState.candidateSelectionIntent(for: "/Users/me/Documents"),
            .add(path: "/Users/me/Documents"),
        )

        let editState = ComposerScopeEditorState(
            selection: .explicit(
                bases: [ComposerScopeBase(path: "/Users/me/Documents")],
                exceptions: [],
            ),
            includeSubfolders: true,
            isPresented: true,
            editingPath: "/Users/me/Documents",
            entryMode: .edit,
        )
        XCTAssertEqual(
            editState.candidateSelectionIntent(for: "/Users/me/Desktop"),
            .replace(oldPath: "/Users/me/Documents", newPath: "/Users/me/Desktop"),
        )
        XCTAssertEqual(
            editState.candidateSelectionIntent(for: "/Users/me/Documents/Private"),
            .exclude(path: "/Users/me/Documents/Private"),
        )
    }
}
