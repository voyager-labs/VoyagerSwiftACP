import Foundation
@testable import Voyager
import XCTest

@MainActor
final class ScopePickerTreeNoResultsTests: XCTestCase {
    func testNoResultsTreeRowsKeepDirectRowsVisibleWhileListStateRemainsNoResults() {
        let state = ComposerScopeEditorState(
            selection: .explicit(
                bases: [ComposerScopeBase(path: "/Users/me/Documents")],
                exceptions: [ComposerScopeException(path: "/Users/me/Documents/Secrets")],
            ),
            listState: .noResults(query: "docs"),
            isPresented: true,
            queryText: "docs",
            candidateItems: [],
            treeNeighborhoodSeedItems: [],
        )

        let rows = state.treeRows(neighborhoodSeedItems: state.treeNeighborhoodSeedItems)

        XCTAssertEqual(rows.map(\.path), [
            "/Users/me/Documents",
            "/Users/me/Documents/Secrets",
        ])
        XCTAssertEqual(state.listState.emptyStateMessage, "No directories found for \"docs\".")
        XCTAssertEqual(state.listState.emptyStateRecoveryMessage, "Try a different path or remove filters.")
    }
}
