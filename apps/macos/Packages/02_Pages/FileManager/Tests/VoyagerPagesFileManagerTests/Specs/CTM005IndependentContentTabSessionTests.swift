import ComposableArchitecture
import Foundation
import VoyagerEntitiesCollection
import VoyagerFeaturesContentPageNavigation
@testable import VoyagerPagesFileManager
import XCTest

@MainActor
final class CTM005IndependentContentTabSessionTests: XCTestCase {
    // MARK: - CTM-005-independent_content_tab_session

    func testSwitchingTabsRestoresContentSessionAndRestartsFolderWatcher() async {
        let homeID = ContentTabID()
        let directoryID = ContentTabID()
        let homePath = "/Users/test/HomeSession"
        let directoryPath = "/Users/test/Desktop"
        let changedPath = "\(directoryPath)/Changed.txt"
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
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
            $0.entryWatchingClient.startWatchingDirectory = { url in
                XCTAssertEqual(url.path, directoryPath)
                return AsyncStream { continuation in
                    continuation.yield([changedPath])
                    continuation.finish()
                }
            }
        }
        store.exhaustivity = .off

        await store.send(.contentTabs(.setCurrent(directoryID)))

        XCTAssertEqual(store.state.content.navigation.currentPath, directoryPath)
        XCTAssertEqual(store.state.tabContentStates[homeID]?.navigation.currentPath, homePath)
        await store.receive(\.content.externalFileSystemChanged, [changedPath])
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
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
            $0.entryWatchingClient.startWatchingDirectory = { _ in
                AsyncStream { continuation in
                    continuation.finish()
                }
            }
        }
        store.exhaustivity = .off

        await store.send(.contentTabs(.setCurrent(downloadsID)))
        XCTAssertEqual(store.state.sidebar.selectedSidebarItem, "Downloads")

        await store.send(.contentTabs(.setCurrent(projectsID)))
        XCTAssertEqual(store.state.sidebar.selectedSidebarItem, "Projects")

        await store.finish()
    }

    func testSwitchingTabsClearsInFlightComposerStateBeforeSavingPreviousSession() async {
        let searchID = UUID()
        let filtersID = UUID()
        let homeID = ContentTabID()
        let directoryID = ContentTabID()
        let directoryPath = "/Users/test/Documents"
        var homeContent = FileManagerContentFeature.State()
        homeContent.composer.isLoadingSearch = true
        homeContent.composer.isLoadingFilters = true
        homeContent.composer.isFilteringInFlight = true
        homeContent.composer.activeSearchRequestID = searchID
        homeContent.composer.activeFiltersRequestID = filtersID
        homeContent.composer.pendingSearchQuery = "tag:important"
        homeContent.composer.queryRenderPhase = .searching
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
                    title: "Documents",
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
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
            $0.entryWatchingClient.startWatchingDirectory = { _ in
                AsyncStream { continuation in
                    continuation.finish()
                }
            }
        }
        store.exhaustivity = .off

        await store.send(.contentTabs(.setCurrent(directoryID)))

        guard let savedHomeComposer = store.state.tabContentStates[homeID]?.composer else {
            XCTFail("Expected previous tab content session to be saved")
            return
        }
        XCTAssertFalse(savedHomeComposer.isLoadingSearch)
        XCTAssertFalse(savedHomeComposer.isLoadingFilters)
        XCTAssertFalse(savedHomeComposer.isFilteringInFlight)
        XCTAssertNil(savedHomeComposer.activeSearchRequestID)
        XCTAssertNil(savedHomeComposer.activeFiltersRequestID)
        XCTAssertNil(savedHomeComposer.pendingSearchQuery)
        XCTAssertEqual(savedHomeComposer.queryRenderPhase, .idle)
        await store.finish()
    }

    func testSwitchingTagTabNamedRecentsPreservesTagRouteKind() async {
        let homeID = ContentTabID()
        let tagID = ContentTabID()
        let tagName = "Recents"
        var tagContent = FileManagerContentFeature.State()
        tagContent.navigation.navigationState = .tags(tagName)
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
                    id: tagID,
                    page: .collection,
                    anchor: .virtualCollection(id: tagName),
                    isPinned: false,
                    title: tagName,
                    iconName: "folder",
                ),
            ],
            activeTabID: homeID,
            recentlyClosed: nil,
        )
        state.tabContentStates = [tagID: tagContent]
        state.syncContentTabSidebarItems()

        let store = TestStore(initialState: state) {
            FileManagerFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
        }
        store.exhaustivity = .off

        await store.send(.contentTabs(.setCurrent(tagID)))
        await store.receive(\.content.internal.applyNavigationState)

        XCTAssertEqual(store.state.content.navigation.navigationState, .tags(tagName))
        XCTAssertNotEqual(store.state.content.navigation.navigationState, .recents)
        await store.finish()
    }

    func testOpeningNewContentTabClearsEntryLoadingStateBeforeSavingPreviousSession() async {
        let homeID = ContentTabID()
        let existingPath = "/Users/test/Loading"
        var existingContent = FileManagerContentFeature.State()
        existingContent.navigation.seedInitialFolderPath(existingPath)
        existingContent.entryViewLayout.entryOperations.isLoading = true
        existingContent.entryViewLayout.entryOperations.isReloading = true
        var state = FileManagerFeature.State()
        state.contentTabs = ContentTabState(
            tabs: [ContentTabItem(
                id: homeID,
                page: .directory,
                anchor: .directory(path: existingPath),
                isPinned: false,
                title: "Loading",
                iconName: "folder",
            )],
            activeTabID: homeID,
            recentlyClosed: nil,
        )
        state.content = existingContent
        state.tabContentStates = [homeID: existingContent]
        state.syncContentTabSidebarItems()

        let store = TestStore(initialState: state) {
            FileManagerFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
        }
        store.exhaustivity = .off

        await store.send(.contentTabs(.open(.homeDefault)))

        let savedEntryOperations = store.state.tabContentStates[homeID]?.entryViewLayout.entryOperations
        XCTAssertFalse(savedEntryOperations?.isLoading ?? true)
        XCTAssertFalse(savedEntryOperations?.isReloading ?? true)
        XCTAssertNotEqual(store.state.contentTabs.activeTabID, homeID)
        await store.finish()
    }

    func testOpeningNewContentTabAppliesWindowContextToFreshContent() async {
        let homeID = ContentTabID()
        let windowID = UUID()
        var existingContent = FileManagerContentFeature.State()
        existingContent.entryViewLayout.mode = .grid
        existingContent.entryViewLayout.showHiddenFiles = true
        existingContent.entryViewLayout.listIconSize = 18
        existingContent.entryViewLayout.gridIconSize = 96
        existingContent.entryViewLayout.entryOperations.windowID = windowID
        existingContent.composer.cancellationOwnerID = windowID
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
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
        }
        store.exhaustivity = .off

        await store.send(.contentTabs(.open(.homeDefault)))

        XCTAssertNotEqual(store.state.contentTabs.activeTabID, homeID)
        XCTAssertEqual(store.state.content.entryViewLayout.entryOperations.windowID, windowID)
        XCTAssertEqual(store.state.content.composer.cancellationOwnerID, windowID)
        XCTAssertEqual(store.state.content.entryViewLayout.mode, .grid)
        XCTAssertTrue(store.state.content.entryViewLayout.showHiddenFiles)
        XCTAssertEqual(store.state.content.entryViewLayout.listIconSize, 18)
        XCTAssertEqual(store.state.content.entryViewLayout.gridIconSize, 96)
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
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
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
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
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
