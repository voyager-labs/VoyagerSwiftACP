@testable import Voyager
import XCTest

@MainActor
final class ScopePickerViewModelTests: XCTestCase {
    func testSectionsSeparateCurrentScopesExceptionAndCandidates() {
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

        let sections = state.sections(editingPath: state.editingPath)

        XCTAssertEqual(sections.map(\.kind.id), ["current-scopes", "exception-slot", "addable-default"])
        guard case .currentScopes? = sections.first?.kind else {
            return XCTFail("expected current scopes section")
        }
        XCTAssertEqual(sections.first?.id, "current-scopes")

        guard case let .currentScope(firstCurrent)? = sections[0].items.first else {
            return XCTFail("expected current scope item")
        }
        XCTAssertTrue(firstCurrent.isEditingTarget)

        guard case let .exceptionSlot(exceptionSlot)? = sections[1].items.first else {
            return XCTFail("expected exception slot item")
        }
        if case let .exceptionPresent(count) = exceptionSlot {
            XCTAssertEqual(count, 1)
        } else {
            XCTFail("expected exception present state")
        }

        XCTAssertEqual(sections[2].items.count, 1)
        guard case let .addableCandidate(candidate) = sections[2].items.first else {
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

        let sections = state.sections(editingPath: nil)

        XCTAssertEqual(sections.map(\.kind.id), ["current-scopes", "exception-slot", "addable-empty-docs"])
        XCTAssertEqual(sections[2].items.count, 0)
        XCTAssertEqual(sections[2].kind.id, "addable-empty-docs")
    }
}
