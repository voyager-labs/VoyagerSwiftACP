import ComposableArchitecture
import Foundation
@testable import Voyager
import XCTest

@MainActor
final class FileManagerRecentTagRoutingTests: XCTestCase {
    func testContentFeatureRoutesRecentsNavigationToLoadRecentItems() async {
        var initialState = FileManagerContentState()
        initialState.entryViewLayout.showHiddenFiles = false

        let store = TestStore(initialState: initialState) {
            FileManagerContentFeature()
        }

        await store.send(.applyNavigationState(.recents))
        await store.receive(\.entryViewLayout.entryOperations.setCollectionMode) {
            $0.entryOperations.loadingContext.isCollectionMode = false
            $0.syncComposerCollectionState()
        }
        await store.receive(\.entryViewLayout.entryOperations.loadRecentItems)
    }

    func testContentFeatureRoutesTagNavigationToLoadTagItems() async {
        var initialState = FileManagerContentState()
        initialState.entryViewLayout.showHiddenFiles = true

        let store = TestStore(initialState: initialState) {
            FileManagerContentFeature()
        }

        await store.send(.applyNavigationState(.tags("Work")))
        await store.receive(\.entryViewLayout.entryOperations.setCollectionMode) {
            $0.entryOperations.loadingContext.isCollectionMode = false
            $0.syncComposerCollectionState()
        }
        await store.receive(\.entryViewLayout.entryOperations.loadTagItems)
    }

    func testWindowNavigationRoutesSidebarRecentsAndTagActions() async {
        let store = TestStore(initialState: FileManagerWindowState()) {
            FileManagerWindowNavigationReducer()
        }

        await store.send(.sidebar(.showRecents))
        await store.receive(\.navigation.view.showRecents)

        await store.send(.sidebar(.showTag(Tag(name: "Work", colorCode: 4))))
        await store.receive(\.navigation.view.showTag)
    }

    func testSyncSidebarSelectionKeepsRecentsAndTagSelectionParity() {
        var state = FileManagerWindowState()

        state.content.navigation.navigationState = .recents
        syncSidebarSelection(state: &state, computerName: "Mac")
        XCTAssertEqual(state.sidebar.selectedSidebarItem, "Recents")

        state.content.navigation.navigationState = .tags("Work")
        syncSidebarSelection(state: &state, computerName: "Mac")
        XCTAssertEqual(state.sidebar.selectedSidebarItem, "Work")
    }
}
