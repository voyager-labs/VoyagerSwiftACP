import ComposableArchitecture
import Foundation
import VoyagerEntitiesCollection
import VoyagerFeaturesContentPageNavigation
@testable import VoyagerPagesFileManager
import XCTest

@MainActor
final class CTM005IndependentContentTabSessionTests: XCTestCase {
    // MARK: - CTM-005-independent_content_tab_session

    func testSwitchingTabsSwapsStoredFileManagerContentSessionWithoutNavigationEffects() async {
        let homeID = ContentTabID()
        let directoryID = ContentTabID()
        let homePath = "/Users/test/HomeSession"
        let directoryPath = "/Users/test/Desktop"
        var homeContent = FileManagerContentFeature.State()
        homeContent.navigation.seedInitialFolderPath(homePath)
        var directoryContent = FileManagerContentFeature.State()
        directoryContent.navigation.seedInitialFolderPath(directoryPath)
        var state = FileManagerFeature.State()
        state.contentTabs = ContentTabState(
            tabs: [
                ContentTabItem(
                    id: homeID,
                    page: .home,
                    anchor: .homeDefault,
                    isPinned: false,
                    title: "Home",
                    iconName: "house",
                ),
                ContentTabItem(
                    id: directoryID,
                    page: .directory,
                    anchor: .directory(path: directoryPath),
                    isPinned: false,
                    title: "Desktop",
                    iconName: "folder",
                ),
            ],
            activeTabID: homeID,
            recentlyClosed: nil,
        )
        state.content = homeContent
        state.tabContentStates = [homeID: homeContent, directoryID: directoryContent]
        state.syncContentTabSidebarItems()

        let store = TestStore(initialState: state) {
            FileManagerFeature()
        }

        await store.send(.contentTabs(.setCurrent(directoryID))) {
            $0.contentTabs.previousActiveTabID = homeID
            $0.contentTabs.activeTabID = directoryID
            $0.tabContentStates[homeID] = homeContent
            $0.content = directoryContent
            $0.sidebar.contentTabSidebarItems = ContentTabProjection.sidebarItems(from: $0.contentTabs)
        }

        XCTAssertEqual(store.state.content.navigation.currentPath, directoryPath)
        XCTAssertEqual(store.state.tabContentStates[homeID]?.navigation.currentPath, homePath)

        await store.send(.contentTabs(.setCurrent(homeID))) {
            $0.contentTabs.previousActiveTabID = directoryID
            $0.contentTabs.activeTabID = homeID
            $0.tabContentStates[directoryID] = directoryContent
            $0.content = homeContent
            $0.sidebar.contentTabSidebarItems = ContentTabProjection.sidebarItems(from: $0.contentTabs)
        }

        XCTAssertEqual(store.state.content.navigation.currentPath, homePath)
        XCTAssertEqual(store.state.tabContentStates[directoryID]?.navigation.currentPath, directoryPath)
        await store.finish()
    }

    func testSwitchingDirectoryTabsSyncsLegacySidebarSelectionFromRestoredSession() async {
        let projectsID = ContentTabID()
        let downloadsID = ContentTabID()
        let projectsPath = "/Users/test/Projects"
        let downloadsPath = "/Users/test/Downloads"
        var projectsContent = FileManagerContentFeature.State()
        projectsContent.navigation.seedInitialFolderPath(projectsPath)
        var downloadsContent = FileManagerContentFeature.State()
        downloadsContent.navigation.seedInitialFolderPath(downloadsPath)
        var state = FileManagerFeature.State()
        state.contentTabs = ContentTabState(
            tabs: [
                ContentTabItem(
                    id: projectsID,
                    page: .directory,
                    anchor: .directory(path: projectsPath),
                    isPinned: false,
                    title: "Projects",
                    iconName: "folder",
                ),
                ContentTabItem(
                    id: downloadsID,
                    page: .directory,
                    anchor: .directory(path: downloadsPath),
                    isPinned: false,
                    title: "Downloads",
                    iconName: "arrow.down.circle",
                ),
            ],
            activeTabID: projectsID,
            recentlyClosed: nil,
        )
        state.content = projectsContent
        state.tabContentStates = [projectsID: projectsContent, downloadsID: downloadsContent]
        state.sidebar.favorites = [
            SidebarItems.FavoriteItem(
                name: "Projects",
                url: URL(fileURLWithPath: projectsPath),
                iconName: "folder",
            ),
            SidebarItems.FavoriteItem(
                name: "Downloads",
                url: URL(fileURLWithPath: downloadsPath),
                iconName: "arrow.down.circle",
            ),
        ]
        state.sidebar.selectedSidebarItem = "Projects"
        state.syncContentTabSidebarItems()
        let store = TestStore(initialState: state) {
            FileManagerFeature()
        }

        await store.send(.contentTabs(.setCurrent(downloadsID))) {
            $0.contentTabs.previousActiveTabID = projectsID
            $0.contentTabs.activeTabID = downloadsID
            $0.tabContentStates[projectsID] = projectsContent
            $0.content = downloadsContent
            $0.sidebar.contentTabSidebarItems = ContentTabProjection.sidebarItems(from: $0.contentTabs)
            $0.sidebar.selectedSidebarItem = "Downloads"
        }

        await store.send(.contentTabs(.setCurrent(projectsID))) {
            $0.contentTabs.previousActiveTabID = downloadsID
            $0.contentTabs.activeTabID = projectsID
            $0.tabContentStates[downloadsID] = downloadsContent
            $0.content = projectsContent
            $0.sidebar.contentTabSidebarItems = ContentTabProjection.sidebarItems(from: $0.contentTabs)
            $0.sidebar.selectedSidebarItem = "Projects"
        }

        await store.finish()
    }

    func testOpeningNewContentTabSavesPreviousSessionAndCreatesFreshHomeSession() async {
        let homeID = ContentTabID()
        let existingPath = "/Users/test/Existing"
        var existingContent = FileManagerContentFeature.State()
        existingContent.navigation.seedInitialFolderPath(existingPath)
        var state = FileManagerFeature.State()
        state.contentTabs = ContentTabState(
            tabs: [ContentTabItem(
                id: homeID,
                page: .home,
                anchor: .homeDefault,
                isPinned: false,
                title: "Home",
                iconName: "house",
            )],
            activeTabID: homeID,
            recentlyClosed: nil,
        )
        state.content = existingContent
        state.tabContentStates = [homeID: existingContent]
        state.syncContentTabSidebarItems()

        let store = TestStore(initialState: state) {
            FileManagerFeature()
        }
        // 새 ContentTabID는 reducer 내부에서 생성되므로 결과 invariant를 직접 검증한다.
        store.exhaustivity = .off

        await store.send(.contentTabs(.open(.homeDefault)))

        XCTAssertEqual(store.state.contentTabs.tabs.count, 2)
        XCTAssertEqual(store.state.tabContentStates[homeID]?.navigation.currentPath, existingPath)
        XCTAssertNotEqual(store.state.contentTabs.activeTabID, homeID)
        await store.finish()
    }

    func testRestoringDirectoryTabInitializesContentSessionFromRestoredAnchor() async {
        let homeID = ContentTabID()
        let currentPath = "/Users/test/Current"
        let restoredPath = "/Users/test/Restored"
        var currentContent = FileManagerContentFeature.State()
        currentContent.navigation.seedInitialFolderPath(currentPath)
        var state = FileManagerFeature.State()
        state.contentTabs = ContentTabState(
            tabs: [ContentTabItem(
                id: homeID,
                page: .home,
                anchor: .homeDefault,
                isPinned: false,
                title: "Home",
                iconName: "house",
            )],
            activeTabID: homeID,
            recentlyClosed: ClosedContentTabSnapshot(
                page: .directory,
                anchor: .directory(path: restoredPath),
                wasPinned: false,
                closedAt: Date(timeIntervalSince1970: 1_234_567_890),
            ),
        )
        state.content = currentContent
        state.tabContentStates = [homeID: currentContent]
        state.syncContentTabSidebarItems()

        let store = TestStore(initialState: state) {
            FileManagerFeature()
        }
        // restore는 reducer 내부에서 새 ContentTabID를 생성하므로 결과 invariant를 검증한다.
        store.exhaustivity = .off

        await store.send(.contentTabs(.restore))

        guard let activeTabID = store.state.contentTabs.activeTabID else {
            XCTFail("restore should activate a restored tab")
            return
        }
        XCTAssertNotEqual(activeTabID, homeID)
        XCTAssertEqual(store.state.contentTabs.tabs[id: activeTabID]?.anchor, .directory(path: restoredPath))
        XCTAssertEqual(store.state.content.navigation.currentPath, restoredPath)
        XCTAssertEqual(store.state.tabContentStates[homeID]?.navigation.currentPath, currentPath)
        XCTAssertEqual(store.state.tabContentStates[activeTabID]?.navigation.currentPath, restoredPath)
        await store.finish()
    }

    func testHomeRouteNewFolderCommandDoesNotRunPathDependentOperation() async {
        var state = FileManagerFeature.State()
        state.content.navigation.navigationState = .home
        state.contentTabs.tabs[id: state.contentTabs.activeTabID ?? ContentTabID()]?.anchor = .homeDefault
        state.syncContentTabSidebarItems()

        let store = TestStore(initialState: state) {
            FileManagerFeature()
        }
        store.exhaustivity = .off

        await store.send(.request(.newFolder))

        XCTAssertEqual(store.state.content.navigation.navigationState, .home)
        if case .folder = store.state.content.navigation.navigationState {
            XCTFail("Home route should not expose a filesystem directory for path-dependent commands")
        }
        await store.finish()
    }

    func testInternalApplyCollectionNavigationSyncsActiveContentTabAnchor() async {
        let tabID = ContentTabID()
        let collectionURL = URL(fileURLWithPath: "/tmp/voyager/collections/spec.voycoll")
        let navigationState = ContentPageNavigationRoute.collection(.init(
            kind: .file(url: collectionURL, name: "spec"),
            context: CollectionContext(query: "", scopes: [], conditions: []),
            sortKey: .name,
            sortOrder: .ascending,
            viewLayout: .list,
        ))
        var state = FileManagerFeature.State()
        state.contentTabs = ContentTabState(
            tabs: [ContentTabItem(
                id: tabID,
                page: .directory,
                anchor: .directory(path: "/Users/test/Documents"),
                isPinned: false,
                title: "Documents",
                iconName: "folder",
            )],
            activeTabID: tabID,
            recentlyClosed: nil,
        )
        state.syncContentTabSidebarItems()

        let store = TestStore(initialState: state) {
            FileManagerFeature()
        }
        store.exhaustivity = .off

        await store.send(.navigation(.internal(.setNavigationState(navigationState)))) {
            $0.content.navigation.navigationState = navigationState
        }
        await store.send(.content(.internal(.applyNavigationState(navigationState))))
        await store.receive(\.contentTabs) {
            $0.contentTabs.tabs[id: tabID]?.anchor = .collectionFile(url: collectionURL)
            $0.contentTabs.tabs[id: tabID]?.page = .collection
            $0.contentTabs.tabs[id: tabID]?.title = "spec"
            $0.contentTabs.tabs[id: tabID]?.iconName = "rectangle.stack"
            $0.sidebar.contentTabSidebarItems = ContentTabProjection.sidebarItems(from: $0.contentTabs)
        }

        XCTAssertEqual(store.state.content.navigation.navigationState, navigationState)
        XCTAssertEqual(store.state.contentTabs.tabs[id: tabID]?.anchor, .collectionFile(url: collectionURL))
        XCTAssertEqual(store.state.contentTabs.tabs[id: tabID]?.page, .collection)
        await store.finish()
    }
}
