@testable import Voyager
import XCTest

@MainActor
final class ComposerScopeEditorListStateTests: XCTestCase {
    func testScopeEditorListStateDisplayCopyMatchesRCLSearchStates() {
        XCTAssertEqual(
            ComposerScopeEditorListState.defaultCandidates.candidateSectionTitle,
            "Suggestions",
        )
        XCTAssertEqual(
            ComposerScopeEditorListState.childFolders(parentPath: "/Users/me/Documents").candidateSectionTitle,
            "Subfolders",
        )
        XCTAssertEqual(
            ComposerScopeEditorListState.searchResults(query: "docs").candidateSectionTitle,
            "Search Results for \"docs\"",
        )

        let noResultsState = ComposerScopeEditorListState.noResults(query: "docs")
        XCTAssertEqual(noResultsState.candidateSectionTitle, "No Results for \"docs\"")
        XCTAssertEqual(noResultsState.emptyStateMessage, "No directories found for \"docs\".")
        XCTAssertEqual(
            noResultsState.emptyStateRecoveryMessage,
            "Try another search or clear the search to return to the previous list.",
        )
    }

    func testScopeEditorListStateSearchResultsHasNoEmptyCopyWhileLoading() {
        let defaultState = ComposerScopeEditorListState.defaultCandidates
        XCTAssertNil(defaultState.emptyStateMessage)
        XCTAssertNil(defaultState.emptyStateRecoveryMessage)

        let searchResultsState = ComposerScopeEditorListState.searchResults(query: "docs")
        XCTAssertNil(searchResultsState.emptyStateMessage)
        XCTAssertNil(searchResultsState.emptyStateRecoveryMessage)

        let childFoldersState = ComposerScopeEditorListState.childFolders(parentPath: "/Users/me/Documents")
        XCTAssertEqual(childFoldersState.emptyStateMessage, "No subfolders found.")
        XCTAssertNil(childFoldersState.emptyStateRecoveryMessage)
    }
}
