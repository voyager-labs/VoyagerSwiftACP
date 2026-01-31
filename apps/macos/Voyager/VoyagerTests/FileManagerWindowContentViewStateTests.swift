@testable import Voyager
import XCTest

@MainActor
final class FileManagerWindowContentViewStateTests: XCTestCase {
    func testViewStateMapsFromFileManagerState() {
        var state = FileManagerFeature.State()
        state.composer.isPresented = true
        state.favorites = [
            SidebarUtils.FavoriteItem(
                name: "Home",
                url: URL(fileURLWithPath: "/Users/demo"),
                iconName: "house",
            ),
        ]
        state.backHistory = [
            FileManagerFeature.HistoryEntry(
                navigationState: .folder("/tmp"),
                sidebarItemName: "Temp",
                composerState: .init(),
            ),
            FileManagerFeature.HistoryEntry(
                navigationState: .tags("Work"),
                sidebarItemName: "Work",
                composerState: .init(),
            ),
        ]
        state.entries.isCollectionMode = true
        let context = CollectionContext(query: "Report", scopes: ["/tmp"], conditions: [])
        state.collectionContext = context
        state.openedCollectionBaseline = FileManagerFeature.CollectionBaseline(
            context: context,
            sortKey: .name,
            sortOrder: .ascending,
            viewLayout: .list,
        )
        state.viewLayout = .grid
        state.entries.isListView = false
        state.openedCollectionURL = nil

        let viewState = FileManagerWindowContentViewState(state: state)

        XCTAssertTrue(viewState.isComposerPresented)
        XCTAssertEqual(viewState.favorites, [
            ScopeFavoriteItem(
                name: "Home",
                url: URL(fileURLWithPath: "/Users/demo"),
                iconName: "house",
            ),
        ])
        XCTAssertEqual(viewState.historyPaths, ["/tmp"])
        XCTAssertTrue(viewState.isDiscardEnabled)
        XCTAssertTrue(viewState.canSaveCollection)
        XCTAssertTrue(viewState.isTemporaryCollection)
    }
}
