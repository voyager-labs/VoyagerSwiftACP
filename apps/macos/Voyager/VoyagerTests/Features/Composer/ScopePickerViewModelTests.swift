@testable import Voyager
import XCTest

@MainActor
final class ScopePickerViewModelTests: XCTestCase {
    func testSectionsInlineExceptionsUnderCurrentScopes() {
        let state = ComposerScopeEditorState(
            selection: .explicit(
                bases: [ComposerScopeBase(path: "/Users/me/Documents"), ComposerScopeBase(path: "/Users/me/Desktop")],
                exceptions: [
                    ComposerScopeException(path: "/Users/me/Documents/Secrets"),
                    ComposerScopeException(path: "/Users/me/Documents/Archive"),
                ],
            ),
            listState: .defaultCandidates,
            isPresented: true,
            queryText: "",
            editingPath: "/Users/me/Documents",
            candidateItems: [
                ComposerScopeEditorCandidateItem(path: "/Users/me/Documents", name: "Documents", iconName: "folder"),
                ComposerScopeEditorCandidateItem(path: "/Users/me/Downloads", name: "Downloads", iconName: "folder"),
            ],
        )

        let sections = state.sections()

        XCTAssertEqual(sections.map(\.kind.id), ["current-scopes", "addable-default"])
        XCTAssertEqual(sections.first?.id, "current-scopes")
        XCTAssertEqual(sections[0].items.map(\.id), [
            "current-/Users/me/Documents",
            "exception-/Users/me/Documents-/Users/me/Documents/Secrets",
            "exception-/Users/me/Documents-/Users/me/Documents/Archive",
            "current-/Users/me/Desktop",
        ])

        guard case let .currentScope(firstCurrent) = sections[0].items[0] else {
            return XCTFail("expected current scope item")
        }
        XCTAssertTrue(firstCurrent.isEditingTarget)
        XCTAssertEqual(firstCurrent.exceptionCount, 2)
        XCTAssertEqual(firstCurrent.exceptionSummaryText, "2 exceptions")

        guard case let .exceptionScope(firstException) = sections[0].items[1] else {
            return XCTFail("expected first inline exception item")
        }
        XCTAssertEqual(firstException.path, "/Users/me/Documents/Secrets")
        XCTAssertEqual(firstException.owningBasePath, "/Users/me/Documents")

        guard case let .currentScope(secondCurrent) = sections[0].items[3] else {
            return XCTFail("expected second current scope item")
        }
        XCTAssertEqual(secondCurrent.base.path, "/Users/me/Desktop")
        XCTAssertEqual(secondCurrent.exceptionCount, 0)
        XCTAssertNil(secondCurrent.exceptionSummaryText)

        XCTAssertEqual(sections[1].items.count, 1)
        guard case let .addableCandidate(candidate) = sections[1].items.first else {
            return XCTFail("expected addable candidate")
        }
        XCTAssertEqual(candidate.path, "/Users/me/Downloads")
    }

    func testRootOnlyShowsSuggestionsWithoutCurrentScopesSection() {
        let state = ComposerScopeEditorState(
            selection: .rootOnly,
            listState: .defaultCandidates,
            isPresented: true,
            queryText: "",
            candidateItems: [
                ComposerScopeEditorCandidateItem(path: "/Users/me/Documents", name: "Documents", iconName: "folder"),
            ],
        )

        let sections = state.sections()

        XCTAssertEqual(sections.map(\.kind.id), ["addable-default"])
        XCTAssertFalse(sections.flatMap(\.items).contains { $0.id.contains("exception-") })
    }

    func testNoResultsSectionKeepsCurrentScopesVisibleWithoutExceptionPlaceholder() {
        let state = ComposerScopeEditorState(
            selection: .explicit(
                bases: [ComposerScopeBase(path: "/Users/me/Documents")],
                exceptions: [],
            ),
            listState: .noResults(query: "docs"),
            isPresented: true,
            queryText: "docs",
            editingPath: nil,
            candidateItems: [],
        )

        let sections = state.sections()

        XCTAssertEqual(sections.map(\.kind.id), ["current-scopes", "addable-empty-docs"])
        XCTAssertEqual(sections[0].items.count, 1)
        XCTAssertEqual(sections[1].items.count, 0)
        XCTAssertEqual(sections[1].kind.id, "addable-empty-docs")
        XCTAssertFalse(sections.flatMap(\.items).contains { $0.id.contains("exception-") })
    }

    func testCandidateSelectionIntentExcludesDescendantWhenEditingBase() {
        let state = ComposerScopeEditorState(
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
            state.candidateSelectionIntent(for: "/Users/me/Documents/Secrets/"),
            .exclude(path: "/Users/me/Documents/Secrets"),
        )
    }

    func testCandidateSelectionIntentReplacesWhenEditingNonDescendantOrExactFolderMode() {
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

        let exactFolderState = ComposerScopeEditorState(
            selection: .explicit(
                bases: [ComposerScopeBase(path: "/Users/me/Documents")],
                exceptions: [],
            ),
            includeSubfolders: false,
            isPresented: true,
            editingPath: "/Users/me/Documents",
            entryMode: .edit,
        )

        XCTAssertEqual(
            exactFolderState.candidateSelectionIntent(for: "/Users/me/Documents/Secrets"),
            .replace(oldPath: "/Users/me/Documents", newPath: "/Users/me/Documents/Secrets"),
        )
    }
}
