@testable import Voyager
import XCTest

@MainActor
final class ScopePickerViewModelTests: XCTestCase {
    func testSectionsInlineExceptionsUnderCurrentScopes() {
        var state = ComposerScopeEditorState(
            selection: .explicit(
                bases: [ComposerScopeBase(path: "/Users/me/Documents"), ComposerScopeBase(path: "/Users/me/Desktop")],
                exceptions: [ComposerScopeException(path: "/Users/me/Documents/Secrets")],
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
        guard case .currentScopes? = sections.first?.kind else {
            return XCTFail("expected current scopes section")
        }
        XCTAssertEqual(sections.first?.id, "current-scopes")

        guard case let .currentScope(firstCurrent)? = sections[0].items.first else {
            return XCTFail("expected current scope item")
        }
        XCTAssertTrue(firstCurrent.isEditingTarget)

        guard case let .exceptionScope(exception)? = sections[0].items[1] else {
            return XCTFail("expected inline exception item")
        }
        XCTAssertEqual(exception.path, "/Users/me/Documents/Secrets")
        XCTAssertEqual(exception.owningBasePath, "/Users/me/Documents")

        XCTAssertEqual(sections[1].items.count, 1)
        guard case let .addableCandidate(candidate) = sections[1].items.first else {
            return XCTFail("expected addable candidate")
        }
        XCTAssertEqual(candidate.path, "/Users/me/Downloads")
    }

    func testNoResultsSectionKeepsCurrentScopesVisible() {
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
        XCTAssertEqual(sections[1].items.count, 0)
        XCTAssertEqual(sections[1].kind.id, "addable-empty-docs")
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
