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

    func testActiveCloseRestoresFallbackTabSession() async {
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
            activeTabID: directoryID,
            previousActiveTabID: homeID,
            recentlyClosed: nil,
        )
        state.content = directoryContent
        state.tabContentStates = [homeID: homeContent, directoryID: directoryContent]
        state.syncContentTabSidebarItems()

        let store = TestStore(initialState: state) {
            FileManagerFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
        }
        // KCF: FileManagerFeature의 routing reducer가 non-exhaustive side effect를 수행함
        store.exhaustivity = .off

        await store.send(.contentTabs(.close(directoryID)))

        XCTAssertEqual(store.state.contentTabs.activeTabID, homeID)
        XCTAssertEqual(store.state.content.navigation.currentPath, homePath)
        XCTAssertNil(store.state.tabContentStates[directoryID])
        XCTAssertEqual(store.state.tabContentStates[homeID]?.navigation.currentPath, homePath)
        await store.finish()
    }

    /// CTM-005-independent_content_tab_session: inactive tab close 시 active tab session에 영향 없음
    /// inactive tab을 닫을 때 active tab의 content session이 보존되는지 검증한다.
    /// - 검증 내용: activeTabID 불변, content 불변, tabContentStates에서 closed tab session만 제거됨
    /// - 사전 조건: 두 content tab이 있고 active tab이 A(home)
    /// - 기대 결과: activeTabID == A, content.currentPath == A session 경로, tabContentStates[B] == nil
    func testInactiveCloseRemovesOnlyClosedTabSession() async {
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
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
        }
        // KCF: FileManagerFeature의 routing reducer가 non-exhaustive side effect를 수행함
        store.exhaustivity = .off

        await store.send(.contentTabs(.close(directoryID)))

        XCTAssertEqual(store.state.contentTabs.activeTabID, homeID)
        XCTAssertEqual(store.state.content.navigation.currentPath, homePath)
        XCTAssertNil(store.state.tabContentStates[directoryID])
        XCTAssertEqual(store.state.tabContentStates[homeID]?.navigation.currentPath, homePath)
        await store.finish()
    }

    /// CTM-005-independent_content_tab_session: 마지막 content tab close 시 window close 요청을 발생시킴
    /// 단일 active tab을 닫으면 tab reducer는 Home reset을 유지하고, window routing은 실제 window close를 요청한다.
    /// - 검증 내용: close 후 `.closeWindow` action 수신
    /// - 사전 조건: 단일 Directory tab이 active 상태
    /// - 기대 결과: window close effect가 발생함
    func testLastTabCloseRequestsWindowClose() async {
        let directoryID = ContentTabID()
        var state = FileManagerFeature.State()
        state.contentTabs = ContentTabState(
            tabs: [ContentTabItem(
                id: directoryID,
                page: .directory,
                anchor: .directory(path: "/Users/test/Desktop"),
                isPinned: false,
                title: "Desktop",
                iconName: "folder",
            )],
            activeTabID: directoryID,
            recentlyClosed: nil,
        )
        state.syncContentTabSidebarItems()

        let store = TestStore(initialState: state) {
            FileManagerFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
        }
        // KCF: closeWindow action 이후 NSApp close side effect는 여기서 검증하지 않음
        store.exhaustivity = .off

        await store.send(.contentTabs(.close(directoryID)))
        await store.receive(\.closeWindow)
        await store.finish()
    }

    func testRestoringCollectionTabReappliesClosedNavigationRoute() async {
        let homeID = ContentTabID()
        let collectionID = ContentTabID()
        let collectionURL = URL(fileURLWithPath: "/tmp/voyager/collections/restored.voycoll")
        let collectionContext = CollectionContext(query: "kind:document", scopes: [], conditions: [])
        let collectionRoute = ContentPageNavigationRoute.collection(.init(
            kind: .file(url: collectionURL, name: "restored"),
            context: collectionContext,
            sortKey: .name,
            sortOrder: .ascending,
            viewLayout: .list,
        ))
        var collectionContent = FileManagerContentFeature.State()
        collectionContent.navigation.navigationState = collectionRoute
        var homeContent = FileManagerContentFeature.State()
        homeContent.navigation.navigationState = .home

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
                    id: collectionID,
                    page: .collection,
                    anchor: .collectionFile(url: collectionURL),
                    isPinned: false,
                    title: "restored",
                    iconName: "rectangle.stack",
                ),
            ],
            activeTabID: collectionID,
            recentlyClosed: nil,
        )
        state.content = collectionContent
        state.tabContentStates = [
            homeID: homeContent,
            collectionID: collectionContent,
        ]
        state.syncContentTabSidebarItems()

        let store = TestStore(initialState: state) {
            FileManagerFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
        }
        store.exhaustivity = .off

        await store.send(.contentTabs(.close(collectionID)))
        XCTAssertEqual(store.state.contentTabs.activeTabID, homeID)
        XCTAssertEqual(store.state.content.navigation.navigationState, .home)

        await store.send(.contentTabs(.restore))
        await store.receive(\.content.internal.applyNavigationState)
        await store.receive(\.navigation.internal.navigateToCollection)
        await store.receive(\.content.collection.navigationStateApplied)

        guard let restoredID = store.state.contentTabs.activeTabID else {
            XCTFail("restore should activate the restored collection tab")
            return
        }
        XCTAssertNotEqual(restoredID, homeID)
        XCTAssertEqual(store.state.contentTabs.tabs[id: restoredID]?.anchor, .collectionFile(url: collectionURL))
        XCTAssertEqual(store.state.content.navigation.navigationState, collectionRoute)
        XCTAssertEqual(store.state.content.collection.collectionSession.document?.url, collectionURL)
        XCTAssertEqual(store.state.content.collection.collectionContext, collectionContext)
        XCTAssertEqual(store.state.tabContentStates[restoredID]?.navigation.navigationState, collectionRoute)
        XCTAssertNil(store.state.recentlyClosedNavigationRoute)
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

    // MARK: - CTM-444-collection_dirty_close

    /// CTM-444-collection_dirty_close: dirty active collection close가 unsaved alert를 표시하고 pendingContentTabClose를 설정
    /// isCollectionMode와 canSaveCollection이 true인 active collection tab에서 close 요청 시 alert가 발생하고 pending 상태가 설정되는지
    /// 검증한다.
    /// - 검증 내용: pendingContentTabClose 설정, contentTabCloseAlertResponse 수신
    /// - 사전 조건: active tab이 dirty collection mode
    /// - 기대 결과: pendingContentTabClose가 tabID로 설정되고, cancel 응답 후 pending 해제
    func testDirtyActiveCollectionCloseShowsAlert() async {
        let tabID = ContentTabID()
        let content = makeDirtyCollectionContent()

        var state = FileManagerFeature.State()
        state.contentTabs = ContentTabState(
            tabs: [ContentTabItem(
                id: tabID,
                page: .collection,
                anchor: .collectionFile(url: URL(fileURLWithPath: "/tmp/test.voycoll")),
                isPinned: false,
                title: "Collection",
                iconName: "rectangle.stack",
            )],
            activeTabID: tabID,
            recentlyClosed: nil,
        )
        state.content = content
        state.tabContentStates = [tabID: content]
        state.syncContentTabSidebarItems()

        let store = makeTestStore(state: state, alertChoice: .cancel)

        await store.send(.closeContentTabRequested(tabID))
        XCTAssertNotNil(store.state.pendingContentTabClose)
        XCTAssertEqual(store.state.pendingContentTabClose?.tabID, tabID)
        await store.receive(\.contentTabCloseAlertResponse)
        XCTAssertNil(store.state.pendingContentTabClose)
        await store.finish()
    }

    /// CTM-444-collection_dirty_close: save 성공 후 dirty collection tab이 정상 닫힘
    /// pending 상태에서 saveCompleted(.success) 수신 시 pending 해제와 함께 tab이 닫히는지 검증한다.
    /// - 검증 내용: pendingContentTabClose 해제, tab tabContentStates에서 제거
    /// - 사전 조건: pendingContentTabClose가 설정된 dirty collection tab (2 tabs, non-last)
    /// - 기대 결과: pending이 nil, tab 제거, active tab이 otherID로 전환
    func testDirtyActiveCollectionSaveSuccessClosesTab() async {
        let tabID = ContentTabID()
        let otherID = ContentTabID()
        let content = makeDirtyCollectionContent()

        var otherContent = FileManagerContentFeature.State()
        otherContent.navigation.seedInitialFolderPath("/Users/test/Other")

        var state = FileManagerFeature.State()
        state.contentTabs = ContentTabState(
            tabs: [
                ContentTabItem(
                    id: tabID,
                    page: .collection,
                    anchor: .collectionFile(url: URL(fileURLWithPath: "/tmp/test.voycoll")),
                    isPinned: false,
                    title: "Collection",
                    iconName: "rectangle.stack",
                ),
                ContentTabItem(
                    id: otherID,
                    page: .home,
                    anchor: .homeDefault,
                    isPinned: false,
                    title: "Home",
                    iconName: "house",
                ),
            ],
            activeTabID: tabID,
            recentlyClosed: nil,
        )
        state.content = content
        state.tabContentStates = [tabID: content, otherID: otherContent]
        state.pendingContentTabClose = PendingContentTabClose(tabID: tabID)
        state.syncContentTabSidebarItems()

        let store = makeTestStore(state: state)

        let completion = CollectionSaveCompletion(
            url: URL(fileURLWithPath: "/tmp/test.voycoll"),
            file: VoyagerCollectionFile(
                id: "test-id",
                name: "test",
                createdAt: Date(timeIntervalSince1970: 1_234_567_890),
                updatedAt: Date(timeIntervalSince1970: 1_234_567_890),
                query: "",
                scopes: [],
                conditions: [],
                snapshot: nil,
                snapshotMeta: nil,
                appVersion: nil,
            ),
            savedContext: nil,
        )

        await store.send(.content(.collection(.saveCompleted(.success(completion)))))
        await store.receive(\.contentTabs)

        XCTAssertNil(store.state.pendingContentTabClose)
        XCTAssertNil(store.state.tabContentStates[tabID])
        XCTAssertNotEqual(store.state.contentTabs.activeTabID, tabID)
        await store.finish()
    }

    /// CTM-444-collection_dirty_close: save 실패 시 tab이 유지됨
    /// pending 상태에서 saveCompleted(.failure) 수신 시 pending만 해제되고 tab은 닫히지 않는지 검증한다.
    /// - 검증 내용: pendingContentTabClose 해제, tab 유지
    /// - 사전 조건: pendingContentTabClose가 설정된 dirty collection tab
    /// - 기대 결과: pending이 nil이지만 tab은 contentTabs에 그대로 존재
    func testDirtyActiveCollectionSaveFailurePreservesTab() async {
        let tabID = ContentTabID()
        let content = makeDirtyCollectionContent()

        var state = FileManagerFeature.State()
        state.contentTabs = ContentTabState(
            tabs: [ContentTabItem(
                id: tabID,
                page: .collection,
                anchor: .collectionFile(url: URL(fileURLWithPath: "/tmp/test.voycoll")),
                isPinned: false,
                title: "Collection",
                iconName: "rectangle.stack",
            )],
            activeTabID: tabID,
            recentlyClosed: nil,
        )
        state.content = content
        state.tabContentStates = [tabID: content]
        state.pendingContentTabClose = PendingContentTabClose(tabID: tabID)
        state.syncContentTabSidebarItems()

        let store = makeTestStore(state: state)

        let error = NSError(domain: "test", code: 0, userInfo: nil)
        await store.send(.content(.collection(.saveCompleted(.failure(error)))))

        XCTAssertNotNil(store.state.pendingContentTabClose)

        let feedback = CollectionSaveFeedback(
            stage: .saveFailed,
            category: .saveFailed,
            title: "Save Failed",
            message: "Unable to save collection.",
            isRetryable: true,
        )
        await store.send(.content(.collection(.delegate(.saveFeedback(feedback)))))

        XCTAssertNil(store.state.pendingContentTabClose)
        XCTAssertNotNil(store.state.contentTabs.tabs[id: tabID])
        XCTAssertEqual(store.state.content.composer.transientFeedback?.category, .saveFailed)
        await store.finish()
    }

    /// CTM-444-collection_dirty_close: discard 선택 시 dirty collection tab이 닫힘
    /// alert에서 discard 선택 시 tab이 정상 닫히는지 검증한다.
    /// - 검증 내용: contentTabCloseAlertResponse(.discard) 수신 후 tab 제거
    /// - 사전 조건: active tab이 dirty collection mode (2 tabs, non-last)
    /// - 기대 결과: tab이 tabContentStates에서 제거됨
    func testDirtyActiveCollectionDiscardClosesTab() async {
        let tabID = ContentTabID()
        let otherID = ContentTabID()
        let content = makeDirtyCollectionContent()

        var otherContent = FileManagerContentFeature.State()
        otherContent.navigation.seedInitialFolderPath("/Users/test/Other")

        var state = FileManagerFeature.State()
        state.contentTabs = ContentTabState(
            tabs: [
                ContentTabItem(
                    id: tabID,
                    page: .collection,
                    anchor: .collectionFile(url: URL(fileURLWithPath: "/tmp/test.voycoll")),
                    isPinned: false,
                    title: "Collection",
                    iconName: "rectangle.stack",
                ),
                ContentTabItem(
                    id: otherID,
                    page: .home,
                    anchor: .homeDefault,
                    isPinned: false,
                    title: "Home",
                    iconName: "house",
                ),
            ],
            activeTabID: tabID,
            recentlyClosed: nil,
        )
        state.content = content
        state.tabContentStates = [tabID: content, otherID: otherContent]
        state.syncContentTabSidebarItems()

        let store = makeTestStore(state: state, alertChoice: .discard)

        await store.send(.closeContentTabRequested(tabID))
        await store.receive(\.contentTabCloseAlertResponse)

        // discard handler: .content(.view(.discardCollectionChanges)) + .contentTabs(.close(tabID))
        XCTAssertNil(store.state.pendingContentTabClose)
        await store.receive(\.contentTabs)
        XCTAssertNil(store.state.tabContentStates[tabID])
        XCTAssertNotEqual(store.state.contentTabs.activeTabID, tabID)
        await store.finish()
    }

    /// CTM-444-collection_dirty_close: cancel 선택 시 tab이 유지됨
    /// alert에서 cancel 선택 시 tab이 닫히지 않고 그대로 유지되는지 검증한다.
    /// - 검증 내용: contentTabCloseAlertResponse(.cancel) 수신 후 tab 유지
    /// - 사전 조건: active tab이 dirty collection mode
    /// - 기대 결과: tab이 contentTabs에 그대로 존재, recentlyClosed nil
    func testDirtyActiveCollectionCancelPreservesTab() async {
        let tabID = ContentTabID()
        let content = makeDirtyCollectionContent()

        var state = FileManagerFeature.State()
        state.contentTabs = ContentTabState(
            tabs: [ContentTabItem(
                id: tabID,
                page: .collection,
                anchor: .collectionFile(url: URL(fileURLWithPath: "/tmp/test.voycoll")),
                isPinned: false,
                title: "Collection",
                iconName: "rectangle.stack",
            )],
            activeTabID: tabID,
            recentlyClosed: nil,
        )
        state.content = content
        state.tabContentStates = [tabID: content]
        state.syncContentTabSidebarItems()

        let store = makeTestStore(state: state, alertChoice: .cancel)

        await store.send(.closeContentTabRequested(tabID))
        await store.receive(\.contentTabCloseAlertResponse)

        XCTAssertNil(store.state.pendingContentTabClose)
        XCTAssertNotNil(store.state.contentTabs.tabs[id: tabID])
        XCTAssertNil(store.state.contentTabs.recentlyClosed)
        await store.finish()
    }

    /// CTM-444-collection_dirty_close: clean collection tab은 alert 없이 바로 닫힘
    /// isCollectionMode는 true지만 canSaveCollection이 false인 tab에서 close 요청 시 alert를 건너뛰고 바로 닫히는지 검증한다.
    /// - 검증 내용: pendingContentTabClose가 설정되지 않고 tab이 바로 닫힘
    /// - 사전 조건: collection mode이지만 clean 상태 (canSaveCollection == false), 2 tabs
    /// - 기대 결과: pending 미설정, tab 제거
    func testCleanCollectionBypassesAlert() async {
        let tabID = ContentTabID()
        let otherID = ContentTabID()

        // collection mode지만 collectionContext == nil → canSaveCollection == false
        var content = FileManagerContentFeature.State()
        content.entryViewLayout.isCollectionMode = true

        var otherContent = FileManagerContentFeature.State()
        otherContent.navigation.seedInitialFolderPath("/Users/test/Other")

        var state = FileManagerFeature.State()
        state.contentTabs = ContentTabState(
            tabs: [
                ContentTabItem(
                    id: tabID,
                    page: .collection,
                    anchor: .collectionFile(url: URL(fileURLWithPath: "/tmp/test.voycoll")),
                    isPinned: false,
                    title: "Collection",
                    iconName: "rectangle.stack",
                ),
                ContentTabItem(
                    id: otherID,
                    page: .home,
                    anchor: .homeDefault,
                    isPinned: false,
                    title: "Home",
                    iconName: "house",
                ),
            ],
            activeTabID: tabID,
            recentlyClosed: nil,
        )
        state.content = content
        state.tabContentStates = [tabID: content, otherID: otherContent]
        state.syncContentTabSidebarItems()

        let store = makeTestStore(state: state)

        await store.send(.closeContentTabRequested(tabID))

        // clean bypass → reducer가 .send(.contentTabs(.close(tabID))) 반환
        XCTAssertNil(store.state.pendingContentTabClose)
        await store.receive(\.contentTabs)
        XCTAssertNil(store.state.tabContentStates[tabID])
        XCTAssertNotEqual(store.state.contentTabs.activeTabID, tabID)
        await store.finish()
    }

    /// CTM-444-collection_dirty_close: non-collection tab은 alert 없이 바로 닫힘
    /// isCollectionMode가 false인 일반 tab에서 close 요청 시 alert 없이 바로 닫히는지 검증한다.
    /// - 검증 내용: pendingContentTabClose가 설정되지 않고 tab이 바로 닫힘
    /// - 사전 조건: non-collection tab, 2 tabs
    /// - 기대 결과: pending 미설정, tab 제거
    func testNonCollectionBypassesAlert() async {
        let tabID = ContentTabID()
        let otherID = ContentTabID()

        var state = FileManagerFeature.State()
        state.contentTabs = ContentTabState(
            tabs: [
                ContentTabItem(
                    id: tabID,
                    page: .home,
                    anchor: .homeDefault,
                    isPinned: false,
                    title: "Home",
                    iconName: "house",
                ),
                ContentTabItem(
                    id: otherID,
                    page: .directory,
                    anchor: .directory(path: "/Users/test/Other"),
                    isPinned: false,
                    title: "Other",
                    iconName: "folder",
                ),
            ],
            activeTabID: tabID,
            recentlyClosed: nil,
        )
        state.syncContentTabSidebarItems()

        let store = makeTestStore(state: state)

        await store.send(.closeContentTabRequested(tabID))

        // non-collection bypass → reducer가 .send(.contentTabs(.close(tabID))) 반환
        XCTAssertNil(store.state.pendingContentTabClose)
        await store.receive(\.contentTabs)
        XCTAssertNil(store.state.tabContentStates[tabID])
        XCTAssertNotEqual(store.state.contentTabs.activeTabID, tabID)
        await store.finish()
    }

    /// CTM-444-collection_dirty_close: inactive dirty collection tab close도 alert를 표시
    /// active tab이 아닌 inactive tab이 dirty collection 상태일 때도 close 요청이 alert를 발생시키는지 검증한다.
    /// - 검증 내용: pendingContentTabClose가 inactive tabID로 설정, active tab은 영향 없음
    /// - 사전 조건: active tab(home) + inactive tab(dirty collection)
    /// - 기대 결과: pending이 inactive tabID로 설정, active tab session 보존
    func testInactiveDirtyCollectionCloseShowsAlert() async {
        let activeID = ContentTabID()
        let inactiveID = ContentTabID()
        let homePath = "/Users/test/Home"
        let dirtyContent = makeDirtyCollectionContent()

        var homeContent = FileManagerContentFeature.State()
        homeContent.navigation.seedInitialFolderPath(homePath)

        var state = FileManagerFeature.State()
        state.contentTabs = ContentTabState(
            tabs: [
                ContentTabItem(
                    id: activeID,
                    page: .home,
                    anchor: .homeDefault,
                    isPinned: false,
                    title: "Home",
                    iconName: "house",
                ),
                ContentTabItem(
                    id: inactiveID,
                    page: .collection,
                    anchor: .collectionFile(url: URL(fileURLWithPath: "/tmp/test.voycoll")),
                    isPinned: false,
                    title: "Collection",
                    iconName: "rectangle.stack",
                ),
            ],
            activeTabID: activeID,
            recentlyClosed: nil,
        )
        state.content = homeContent
        state.tabContentStates = [activeID: homeContent, inactiveID: dirtyContent]
        state.syncContentTabSidebarItems()

        let store = makeTestStore(state: state, alertChoice: .cancel)

        await store.send(.closeContentTabRequested(inactiveID))
        XCTAssertNotNil(store.state.pendingContentTabClose)
        XCTAssertEqual(store.state.pendingContentTabClose?.tabID, inactiveID)

        // active tab은 영향 없음
        XCTAssertEqual(store.state.contentTabs.activeTabID, activeID)
        XCTAssertEqual(store.state.tabContentStates[activeID]?.navigation.currentPath, homePath)
        await store.receive(\.contentTabCloseAlertResponse)
        await store.finish()
    }

    /// CTM-444-collection_dirty_close: inactive dirty collection Save 성공은 대상 탭을 저장한 뒤 닫음
    /// inactive tab의 dirty state를 기준으로 alert를 띄운 뒤 Save continuation이 active content가 아니라 target tab content를 대상으로
    /// 수행되는지 검증한다.
    func testInactiveDirtyCollectionSaveSuccessClosesTargetTab() async {
        let activeID = ContentTabID()
        let inactiveID = ContentTabID()
        let homePath = "/Users/test/Home"
        let dirtyContent = makeDirtyCollectionContent()

        var homeContent = FileManagerContentFeature.State()
        homeContent.navigation.seedInitialFolderPath(homePath)

        var state = FileManagerFeature.State()
        state.contentTabs = ContentTabState(
            tabs: [
                ContentTabItem(
                    id: activeID,
                    page: .home,
                    anchor: .homeDefault,
                    isPinned: false,
                    title: "Home",
                    iconName: "house",
                ),
                ContentTabItem(
                    id: inactiveID,
                    page: .collection,
                    anchor: .collectionFile(url: URL(fileURLWithPath: "/tmp/test.voycoll")),
                    isPinned: false,
                    title: "Collection",
                    iconName: "rectangle.stack",
                ),
            ],
            activeTabID: activeID,
            recentlyClosed: nil,
        )
        state.content = dirtyContent
        state.tabContentStates = [activeID: homeContent, inactiveID: dirtyContent]
        state.pendingContentTabClose = PendingContentTabClose(
            tabID: inactiveID,
            previousActiveTabID: activeID,
            previousActiveContent: homeContent,
            targetContent: dirtyContent,
        )
        state.syncContentTabSidebarItems()

        let store = makeTestStore(state: state, alertChoice: .save)

        let completion = makeSaveCompletion()
        await store.send(.content(.collection(.saveCompleted(.success(completion)))))
        await store.receive(\.contentTabs)

        XCTAssertNil(store.state.pendingContentTabClose)
        XCTAssertEqual(store.state.contentTabs.activeTabID, activeID)
        XCTAssertEqual(store.state.content.navigation.currentPath, homePath)
        XCTAssertNil(store.state.tabContentStates[inactiveID])
        await store.finish()
    }

    /// CTM-444-collection_dirty_close: inactive target 저장 중 tab switch는 target ownership을 오염시키지 않음
    func testInactiveDirtyCollectionSaveInProgressIgnoresTabSwitchUntilCompletion() async {
        let activeID = ContentTabID()
        let inactiveID = ContentTabID()
        let homePath = "/Users/test/Home"
        let dirtyContent = makeDirtyCollectionContent()

        var homeContent = FileManagerContentFeature.State()
        homeContent.navigation.seedInitialFolderPath(homePath)

        var state = FileManagerFeature.State()
        state.contentTabs = ContentTabState(
            tabs: [
                ContentTabItem(
                    id: activeID,
                    page: .home,
                    anchor: .homeDefault,
                    isPinned: false,
                    title: "Home",
                    iconName: "house",
                ),
                ContentTabItem(
                    id: inactiveID,
                    page: .collection,
                    anchor: .collectionFile(url: URL(fileURLWithPath: "/tmp/test.voycoll")),
                    isPinned: false,
                    title: "Collection",
                    iconName: "rectangle.stack",
                ),
            ],
            activeTabID: inactiveID,
            recentlyClosed: nil,
        )
        state.contentTabs.previousActiveTabID = activeID
        state.content = dirtyContent
        state.tabContentStates = [activeID: homeContent, inactiveID: dirtyContent]
        state.pendingContentTabClose = PendingContentTabClose(
            tabID: inactiveID,
            previousActiveTabID: activeID,
            previousActiveContent: homeContent,
            targetContent: dirtyContent,
        )
        state.syncContentTabSidebarItems()

        let store = makeTestStore(state: state, alertChoice: .save)

        XCTAssertEqual(store.state.contentTabs.activeTabID, inactiveID)
        XCTAssertTrue(store.state.content.isCollectionMode)

        await store.send(.contentTabs(.setCurrent(activeID)))

        XCTAssertEqual(store.state.contentTabs.activeTabID, inactiveID)
        XCTAssertTrue(store.state.content.isCollectionMode)
        XCTAssertEqual(store.state.tabContentStates[activeID]?.navigation.currentPath, homePath)

        let completion = makeSaveCompletion()
        await store.send(.content(.collection(.saveCompleted(.success(completion)))))
        await store.receive(\.contentTabs)

        XCTAssertNil(store.state.pendingContentTabClose)
        XCTAssertEqual(store.state.contentTabs.activeTabID, activeID)
        XCTAssertEqual(store.state.content.navigation.currentPath, homePath)
        XCTAssertNil(store.state.tabContentStates[inactiveID])
        await store.finish()
    }

    /// CTM-444-collection_dirty_close: active dirty collection Save가 시작 불가하면 pending을 해제하고 tab을 보존
    func testDirtyActiveCollectionSaveBlockedPreservesTabAndClearsPending() async {
        let tabID = ContentTabID()
        var content = makeDirtyCollectionContent()
        content.collection.isSaving = true

        var state = FileManagerFeature.State()
        state.contentTabs = ContentTabState(
            tabs: [ContentTabItem(
                id: tabID,
                page: .collection,
                anchor: .collectionFile(url: URL(fileURLWithPath: "/tmp/test.voycoll")),
                isPinned: false,
                title: "Collection",
                iconName: "rectangle.stack",
            )],
            activeTabID: tabID,
            recentlyClosed: nil,
        )
        state.content = content
        state.tabContentStates = [tabID: content]
        state.syncContentTabSidebarItems()

        let store = makeTestStore(state: state, alertChoice: .save)

        await store.send(.closeContentTabRequested(tabID))
        await store.receive(\.contentTabCloseAlertResponse)

        XCTAssertNil(store.state.pendingContentTabClose)
        XCTAssertNotNil(store.state.contentTabs.tabs[id: tabID])
        XCTAssertTrue(store.state.content.collection.isSaving)
        await store.finish()
    }

    /// CTM-444-collection_dirty_close: inactive dirty collection Save가 시작 불가하면 active content를 복구하고 대상 tab을 보존
    func testInactiveDirtyCollectionSaveBlockedPreservesTargetTabAndRestoresActiveContent() async {
        let activeID = ContentTabID()
        let inactiveID = ContentTabID()
        let homePath = "/Users/test/Home"
        var dirtyContent = makeDirtyCollectionContent()
        dirtyContent.composer.isLoadingSearch = true

        var homeContent = FileManagerContentFeature.State()
        homeContent.navigation.seedInitialFolderPath(homePath)

        var state = FileManagerFeature.State()
        state.contentTabs = ContentTabState(
            tabs: [
                ContentTabItem(
                    id: activeID,
                    page: .home,
                    anchor: .homeDefault,
                    isPinned: false,
                    title: "Home",
                    iconName: "house",
                ),
                ContentTabItem(
                    id: inactiveID,
                    page: .collection,
                    anchor: .collectionFile(url: URL(fileURLWithPath: "/tmp/test.voycoll")),
                    isPinned: false,
                    title: "Collection",
                    iconName: "rectangle.stack",
                ),
            ],
            activeTabID: activeID,
            recentlyClosed: nil,
        )
        state.content = homeContent
        state.tabContentStates = [activeID: homeContent, inactiveID: dirtyContent]
        state.syncContentTabSidebarItems()

        let store = makeTestStore(state: state, alertChoice: .save)

        await store.send(.closeContentTabRequested(inactiveID))
        await store.receive(\.contentTabCloseAlertResponse)

        XCTAssertNil(store.state.pendingContentTabClose)
        XCTAssertEqual(store.state.contentTabs.activeTabID, activeID)
        XCTAssertEqual(store.state.content.navigation.currentPath, homePath)
        XCTAssertNotNil(store.state.contentTabs.tabs[id: inactiveID])
        XCTAssertNotNil(store.state.tabContentStates[inactiveID])
        await store.finish()
    }

    /// CTM-444-collection_dirty_close: active dirty collection Save panel 취소는 pending을 해제하고 tab을 보존
    func testDirtyActiveCollectionSavePanelCancelClearsPendingAndPreservesTab() async {
        let tabID = ContentTabID()
        let content = makeDirtyCollectionContent()

        var state = FileManagerFeature.State()
        state.contentTabs = ContentTabState(
            tabs: [ContentTabItem(
                id: tabID,
                page: .collection,
                anchor: .collectionFile(url: URL(fileURLWithPath: "/tmp/test.voycoll")),
                isPinned: false,
                title: "Collection",
                iconName: "rectangle.stack",
            )],
            activeTabID: tabID,
            recentlyClosed: nil,
        )
        state.content = content
        state.tabContentStates = [tabID: content]
        state.pendingContentTabClose = PendingContentTabClose(tabID: tabID)
        state.syncContentTabSidebarItems()

        let store = makeTestStore(state: state)

        await store.send(.content(.collection(.savePanelResponse(nil))))

        XCTAssertNil(store.state.pendingContentTabClose)
        XCTAssertNotNil(store.state.contentTabs.tabs[id: tabID])
        XCTAssertEqual(store.state.contentTabs.activeTabID, tabID)
        await store.finish()
    }

    /// CTM-444-collection_dirty_close: inactive dirty collection Save panel 취소는 active content를 복구하고 대상 탭을 보존
    func testInactiveDirtyCollectionSavePanelCancelRestoresActiveContentAndPreservesTargetTab() async {
        let activeID = ContentTabID()
        let inactiveID = ContentTabID()
        let homePath = "/Users/test/Home"
        let dirtyContent = makeDirtyCollectionContent()

        var homeContent = FileManagerContentFeature.State()
        homeContent.navigation.seedInitialFolderPath(homePath)

        var state = FileManagerFeature.State()
        state.contentTabs = ContentTabState(
            tabs: [
                ContentTabItem(
                    id: activeID,
                    page: .home,
                    anchor: .homeDefault,
                    isPinned: false,
                    title: "Home",
                    iconName: "house",
                ),
                ContentTabItem(
                    id: inactiveID,
                    page: .collection,
                    anchor: .collectionFile(url: URL(fileURLWithPath: "/tmp/test.voycoll")),
                    isPinned: false,
                    title: "Collection",
                    iconName: "rectangle.stack",
                ),
            ],
            activeTabID: activeID,
            recentlyClosed: nil,
        )
        state.content = dirtyContent
        state.tabContentStates = [activeID: homeContent, inactiveID: dirtyContent]
        state.pendingContentTabClose = PendingContentTabClose(
            tabID: inactiveID,
            previousActiveTabID: activeID,
            previousActiveContent: homeContent,
            targetContent: dirtyContent,
        )
        state.syncContentTabSidebarItems()

        let store = makeTestStore(state: state)

        await store.send(.content(.collection(.savePanelResponse(nil))))

        XCTAssertNil(store.state.pendingContentTabClose)
        XCTAssertEqual(store.state.contentTabs.activeTabID, activeID)
        XCTAssertEqual(store.state.content.navigation.currentPath, homePath)
        XCTAssertNotNil(store.state.contentTabs.tabs[id: inactiveID])
        XCTAssertNotNil(store.state.tabContentStates[inactiveID])
        await store.finish()
    }

    func testInactiveDirtyCollectionSaveFailurePreservesTargetTabAndRestoresActiveContent() async {
        let activeID = ContentTabID()
        let inactiveID = ContentTabID()
        let homePath = "/Users/test/Home"
        let dirtyContent = makeDirtyCollectionContent()

        var homeContent = FileManagerContentFeature.State()
        homeContent.navigation.seedInitialFolderPath(homePath)

        var state = FileManagerFeature.State()
        state.contentTabs = ContentTabState(
            tabs: [
                ContentTabItem(
                    id: activeID,
                    page: .home,
                    anchor: .homeDefault,
                    isPinned: false,
                    title: "Home",
                    iconName: "house",
                ),
                ContentTabItem(
                    id: inactiveID,
                    page: .collection,
                    anchor: .collectionFile(url: URL(fileURLWithPath: "/tmp/test.voycoll")),
                    isPinned: false,
                    title: "Collection",
                    iconName: "rectangle.stack",
                ),
            ],
            activeTabID: activeID,
            recentlyClosed: nil,
        )
        state.content = homeContent
        state.tabContentStates = [activeID: homeContent, inactiveID: dirtyContent]
        state.syncContentTabSidebarItems()

        let store = makeTestStore(state: state, alertChoice: .save)

        await store.send(.closeContentTabRequested(inactiveID))
        await store.receive(\.contentTabCloseAlertResponse)
        await store.send(.content(.collection(.saveCompleted(.failure(NSError(domain: "test", code: 0))))))

        XCTAssertNil(store.state.pendingContentTabClose)
        XCTAssertEqual(store.state.contentTabs.activeTabID, activeID)
        XCTAssertEqual(store.state.content.navigation.currentPath, homePath)
        XCTAssertNotNil(store.state.contentTabs.tabs[id: inactiveID])
        guard let inactiveContent = store.state.tabContentStates[inactiveID] else {
            XCTFail("inactive tab content should remain after save failure")
            return
        }
        XCTAssertEqual(inactiveContent.composer.transientFeedback?.stage, .save)
        XCTAssertNotNil(inactiveContent.composer.transientFeedback?.category)
        await store.finish()
    }

    /// CTM-444-collection_dirty_close: inactive dirty collection Discard는 active content를 건드리지 않고 대상 탭만 닫음
    func testInactiveDirtyCollectionDiscardClosesTargetTabWithoutMutatingActiveContent() async {
        let activeID = ContentTabID()
        let inactiveID = ContentTabID()
        let homePath = "/Users/test/Home"
        let dirtyContent = makeDirtyCollectionContent()

        var homeContent = FileManagerContentFeature.State()
        homeContent.navigation.seedInitialFolderPath(homePath)

        var state = FileManagerFeature.State()
        state.contentTabs = ContentTabState(
            tabs: [
                ContentTabItem(
                    id: activeID,
                    page: .home,
                    anchor: .homeDefault,
                    isPinned: false,
                    title: "Home",
                    iconName: "house",
                ),
                ContentTabItem(
                    id: inactiveID,
                    page: .collection,
                    anchor: .collectionFile(url: URL(fileURLWithPath: "/tmp/test.voycoll")),
                    isPinned: false,
                    title: "Collection",
                    iconName: "rectangle.stack",
                ),
            ],
            activeTabID: activeID,
            recentlyClosed: nil,
        )
        state.content = homeContent
        state.tabContentStates = [activeID: homeContent, inactiveID: dirtyContent]
        state.syncContentTabSidebarItems()

        let store = makeTestStore(state: state, alertChoice: .discard)

        await store.send(.closeContentTabRequested(inactiveID))
        await store.receive(\.contentTabCloseAlertResponse)

        XCTAssertEqual(store.state.contentTabs.activeTabID, activeID)
        XCTAssertEqual(store.state.content.navigation.currentPath, homePath)
        await store.receive(\.contentTabs)
        XCTAssertNil(store.state.tabContentStates[inactiveID])
        await store.finish()
    }

    /// CTM-444-collection_dirty_close: 복원된 비활성 tab에 content snapshot이 없어도 clean close는 진행
    func testRestoredInactiveTabWithoutContentStateCanClose() async {
        let activeID = ContentTabID()
        let inactiveID = ContentTabID()

        var homeContent = FileManagerContentFeature.State()
        homeContent.navigation.seedInitialFolderPath("/Users/test/Home")

        var state = FileManagerFeature.State()
        state.contentTabs = ContentTabState(
            tabs: [
                ContentTabItem(
                    id: activeID,
                    page: .home,
                    anchor: .homeDefault,
                    isPinned: false,
                    title: "Home",
                    iconName: "house",
                ),
                ContentTabItem(
                    id: inactiveID,
                    page: .directory,
                    anchor: .directory(path: "/Users/test/Restored"),
                    isPinned: false,
                    title: "Restored",
                    iconName: "folder",
                ),
            ],
            activeTabID: activeID,
            recentlyClosed: nil,
        )
        state.content = homeContent
        state.tabContentStates = [activeID: homeContent]
        state.syncContentTabSidebarItems()

        let store = makeTestStore(state: state)

        await store.send(.closeContentTabRequested(inactiveID))
        await store.receive(\.contentTabs)

        XCTAssertNil(store.state.contentTabs.tabs[id: inactiveID])
        XCTAssertEqual(store.state.contentTabs.activeTabID, activeID)
        XCTAssertEqual(store.state.content.navigation.currentPath, "/Users/test/Home")
        await store.finish()
    }

    /// CTM-444-collection_dirty_close: 중복 close 요청은 무시됨
    /// pendingContentTabClose가 설정된 상태에서 closeContentTabRequested가 duplicate guard에 의해 무시되는지 검증한다.
    /// - 검증 내용: pending 상태에서 요청은 no-op, pending 유지
    /// - 사전 조건: dirty collection tab, pendingContentTabClose 직접 설정 (alert effect 없음)
    /// - 기대 결과: 요청 후에도 pending 유지, tab 그대로 존재
    func testDuplicateCloseWhilePendingIsNoOp() async {
        let tabID = ContentTabID()
        let otherTabID = ContentTabID()
        let content = makeDirtyCollectionContent()

        var otherContent = FileManagerContentFeature.State()
        otherContent.navigation.seedInitialFolderPath("/Users/test/Other")

        var state = FileManagerFeature.State()
        state.contentTabs = ContentTabState(
            tabs: [
                ContentTabItem(
                    id: tabID,
                    page: .collection,
                    anchor: .collectionFile(url: URL(fileURLWithPath: "/tmp/test.voycoll")),
                    isPinned: false,
                    title: "Collection",
                    iconName: "rectangle.stack",
                ),
                ContentTabItem(
                    id: otherTabID,
                    page: .home,
                    anchor: .homeDefault,
                    isPinned: false,
                    title: "Home",
                    iconName: "house",
                ),
            ],
            activeTabID: tabID,
            recentlyClosed: nil,
        )
        state.content = content
        state.tabContentStates = [tabID: content, otherTabID: otherContent]
        // pending을 직접 설정 → alert 없이 duplicate guard만 검증
        state.pendingContentTabClose = PendingContentTabClose(tabID: tabID)
        state.syncContentTabSidebarItems()

        let store = makeTestStore(state: state)

        // 같은 tabID로 중복 요청 → guard가 .none 반환 (pending 유지)
        await store.send(.closeContentTabRequested(tabID))
        XCTAssertNotNil(store.state.pendingContentTabClose)
        XCTAssertEqual(store.state.pendingContentTabClose?.tabID, tabID)

        // 다른 tabID로 요청해도 guard가 막음
        await store.send(.closeContentTabRequested(otherTabID))
        XCTAssertNotNil(store.state.pendingContentTabClose)
        XCTAssertEqual(store.state.pendingContentTabClose?.tabID, tabID)

        // tab은 그대로 유지
        XCTAssertNotNil(store.state.contentTabs.tabs[id: tabID])
        await store.finish()
    }

    /// CTM-444-collection_dirty_close: pending close 중 직접 navigation 요청은 무시됨
    /// 저장 완료 전 외부 coordinator/toolbar가 navigation view action을 보내도 target content를 변경하지 않는지 검증한다.
    func testPendingDirtyCollectionCloseIgnoresDirectNavigationUntilCompletion() async {
        let tabID = ContentTabID()
        let closingPath = "/Users/test/Closing"
        var content = makeDirtyCollectionContent()
        content.navigation.seedInitialFolderPath(closingPath)

        var state = FileManagerFeature.State()
        state.contentTabs = ContentTabState(
            tabs: [ContentTabItem(
                id: tabID,
                page: .collection,
                anchor: .collectionFile(url: URL(fileURLWithPath: "/tmp/test.voycoll")),
                isPinned: false,
                title: "Collection",
                iconName: "rectangle.stack",
            )],
            activeTabID: tabID,
            recentlyClosed: nil,
        )
        state.content = content
        state.tabContentStates = [tabID: content]
        state.pendingContentTabClose = PendingContentTabClose(tabID: tabID)
        state.syncContentTabSidebarItems()

        let store = TestStore(initialState: state) {
            FileManagerFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
        }

        await store.send(.navigation(.view(.navigateToPath("/Users/test/Other"))))

        XCTAssertEqual(store.state.content.navigation.currentPath, closingPath)
        XCTAssertEqual(store.state.pendingContentTabClose?.tabID, tabID)
        await store.finish()
    }

    /// CTM-444-collection_dirty_close: pending close 중 sidebar navigation은 무시됨
    /// Sidebar location 선택이 저장 중인 closing target의 navigation state를 오염시키지 않는지 검증한다.
    func testPendingDirtyCollectionCloseIgnoresSidebarNavigationUntilCompletion() async {
        let tabID = ContentTabID()
        let closingPath = "/Users/test/Closing"
        let otherLocation = SidebarItems.LocationItem(
            name: "Other",
            url: URL(fileURLWithPath: "/Users/test/Other"),
            iconName: "folder",
        )
        var content = makeDirtyCollectionContent()
        content.navigation.seedInitialFolderPath(closingPath)

        var state = FileManagerFeature.State()
        state.contentTabs = ContentTabState(
            tabs: [ContentTabItem(
                id: tabID,
                page: .collection,
                anchor: .collectionFile(url: URL(fileURLWithPath: "/tmp/test.voycoll")),
                isPinned: false,
                title: "Collection",
                iconName: "rectangle.stack",
            )],
            activeTabID: tabID,
            recentlyClosed: nil,
        )
        state.content = content
        state.tabContentStates = [tabID: content]
        state.sidebar.locations = [otherLocation]
        state.pendingContentTabClose = PendingContentTabClose(tabID: tabID)
        state.syncContentTabSidebarItems()

        let store = TestStore(initialState: state) {
            FileManagerFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
        }

        await store.send(.sidebar(.delegate(.openLocation(otherLocation))))

        XCTAssertEqual(store.state.content.navigation.currentPath, closingPath)
        XCTAssertEqual(store.state.pendingContentTabClose?.tabID, tabID)
        await store.finish()
    }

    /// CTM-444-collection_dirty_close: pending close 중 toolbar history command는 무시됨
    /// Back/Forward 계열 command가 저장 중인 closing target에 pending navigation을 만들지 않는지 검증한다.
    func testPendingDirtyCollectionCloseIgnoresToolbarNavigationCommandUntilCompletion() async {
        let tabID = ContentTabID()
        let closingPath = "/Users/test/Closing"
        var content = makeDirtyCollectionContent()
        content.navigation.seedInitialFolderPath(closingPath)

        var state = FileManagerFeature.State()
        state.contentTabs = ContentTabState(
            tabs: [ContentTabItem(
                id: tabID,
                page: .collection,
                anchor: .collectionFile(url: URL(fileURLWithPath: "/tmp/test.voycoll")),
                isPinned: false,
                title: "Collection",
                iconName: "rectangle.stack",
            )],
            activeTabID: tabID,
            recentlyClosed: nil,
        )
        state.content = content
        state.tabContentStates = [tabID: content]
        state.pendingContentTabClose = PendingContentTabClose(tabID: tabID)
        state.syncContentTabSidebarItems()

        let store = TestStore(initialState: state) {
            FileManagerFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
        }

        await store.send(.request(.goBack))

        XCTAssertEqual(store.state.content.navigation.currentPath, closingPath)
        XCTAssertEqual(store.state.pendingContentTabClose?.tabID, tabID)
        await store.finish()
    }

    /// CTM-444-collection_dirty_close: 단일 dirty collection tab close 시 Cancel/Discard 전환
    /// 마지막 tab이 dirty collection인 경우 Cancel/Discard 각각의 결과를 검증한다.
    /// Cancel: collection 유지. Discard: close.
    /// - 검증 내용: Cancel → tab 유지, Discard → close
    /// - 사전 조건: 단일 dirty collection tab
    /// - 기대 결과: Cancel은 tab 유지, Discard는 tab 제거 or home reset
    func testLastDirtyCollectionTabPromptBeforeReset() async {
        // Cancel flow: alert cancel → tab preserved
        do {
            let tabID = ContentTabID()
            let content = makeDirtyCollectionContent()

            var state = FileManagerFeature.State()
            state.contentTabs = ContentTabState(
                tabs: [ContentTabItem(
                    id: tabID,
                    page: .collection,
                    anchor: .collectionFile(url: URL(fileURLWithPath: "/tmp/test.voycoll")),
                    isPinned: false,
                    title: "Collection",
                    iconName: "rectangle.stack",
                )],
                activeTabID: tabID,
                recentlyClosed: nil,
            )
            state.content = content
            state.tabContentStates = [tabID: content]
            state.syncContentTabSidebarItems()

            let store = makeTestStore(state: state, alertChoice: .cancel)

            await store.send(.closeContentTabRequested(tabID))
            await store.receive(\.contentTabCloseAlertResponse)

            XCTAssertNil(store.state.pendingContentTabClose)
            XCTAssertNotNil(store.state.contentTabs.tabs[id: tabID])
            await store.finish()
        }

        // Discard flow: alert discard → tab closed (last tab)
        do {
            let tabID = ContentTabID()
            let content = makeDirtyCollectionContent()

            var state = FileManagerFeature.State()
            state.contentTabs = ContentTabState(
                tabs: [ContentTabItem(
                    id: tabID,
                    page: .collection,
                    anchor: .collectionFile(url: URL(fileURLWithPath: "/tmp/test.voycoll")),
                    isPinned: false,
                    title: "Collection",
                    iconName: "rectangle.stack",
                )],
                activeTabID: tabID,
                recentlyClosed: nil,
            )
            state.content = content
            state.tabContentStates = [tabID: content]
            state.syncContentTabSidebarItems()

            let store = makeTestStore(state: state, alertChoice: .discard)

            await store.send(.closeContentTabRequested(tabID))
            await store.receive(\.contentTabCloseAlertResponse)

            XCTAssertNil(store.state.pendingContentTabClose)
            await store.finish()
        }
    }

    /// CTM-444-collection_dirty_close: pinned dirty collection tab은 alert 없이 바로 close
    /// isPinned == true인 dirty collection tab은 dirty check를 건너뛰고 바로 close action을 보내는지 검증한다.
    /// - 검증 내용: pendingContentTabClose 미설정, alert 미발생
    /// - 사전 조건: pinned + dirty collection tab (2 tabs, non-last)
    /// - 기대 결과: pending이 nil, tab 제거
    func testPinnedDirtyCollectionTabUnpinsWithoutAlert() async {
        let tabID = ContentTabID()
        let otherID = ContentTabID()
        let content = makeDirtyCollectionContent()

        var otherContent = FileManagerContentFeature.State()
        otherContent.navigation.seedInitialFolderPath("/Users/test/Other")

        var state = FileManagerFeature.State()
        state.contentTabs = ContentTabState(
            tabs: [
                ContentTabItem(
                    id: tabID,
                    page: .collection,
                    anchor: .collectionFile(url: URL(fileURLWithPath: "/tmp/test.voycoll")),
                    isPinned: true,
                    title: "Collection",
                    iconName: "rectangle.stack",
                ),
                ContentTabItem(
                    id: otherID,
                    page: .home,
                    anchor: .homeDefault,
                    isPinned: false,
                    title: "Home",
                    iconName: "house",
                ),
            ],
            activeTabID: tabID,
            recentlyClosed: nil,
        )
        state.content = content
        state.tabContentStates = [tabID: content, otherID: otherContent]
        state.syncContentTabSidebarItems()

        // alertChoice는 중요하지 않음 → pinned bypass이므로 alert client가 호출되지 않음
        let store = makeTestStore(state: state, alertChoice: .save)

        await store.send(.closeContentTabRequested(tabID))

        // pinned bypass: alert 없이 바로 .send(.contentTabs(.close(tabID)))
        // pinned tab의 close는 unpin 처리 → tab은 유지되지만 isPinned = false
        XCTAssertNil(store.state.pendingContentTabClose)
        await store.receive(\.contentTabs)
        // tab은 유지 (unpin만 됨)
        XCTAssertNotNil(store.state.contentTabs.tabs[id: tabID])
        XCTAssertEqual(store.state.contentTabs.tabs[id: tabID]?.isPinned, false)
        await store.finish()
    }
}

// MARK: - Helpers

private extension CTM005IndependentContentTabSessionTests {
    func makeDirtyCollectionContent() -> FileManagerContentFeature.State {
        var content = FileManagerContentFeature.State()
        content.entryViewLayout.isCollectionMode = true
        content.collection.collectionContext = CollectionContext(
            query: "current",
            scopes: ["/tmp"],
            conditions: [],
        )
        content.collection.collectionSession.metadata.baseline = .init(
            context: CollectionContext(
                query: "baseline",
                scopes: ["/tmp"],
                conditions: [],
            ),
        )
        return content
    }

    func makeSaveCompletion() -> CollectionSaveCompletion {
        CollectionSaveCompletion(
            url: URL(fileURLWithPath: "/tmp/test.voycoll"),
            file: VoyagerCollectionFile(
                id: "test-id",
                name: "test",
                createdAt: Date(timeIntervalSince1970: 1_234_567_890),
                updatedAt: Date(timeIntervalSince1970: 1_234_567_890),
                query: "",
                scopes: [],
                conditions: [],
                snapshot: nil,
                snapshotMeta: nil,
                appVersion: nil,
            ),
            savedContext: nil,
        )
    }

    func makeTestStore(
        state: FileManagerFeature.State,
        alertChoice: CollectionNavigationChoice? = nil,
    ) -> TestStore<FileManagerFeature.State, FileManagerWindowAction> {
        let store = TestStore(initialState: state) {
            FileManagerFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
            $0.collectionAlertClient = .init(
                showUnsavedNavigationAlert: { alertChoice ?? .save },
                showCollectionOpenErrorAlert: { _, _ in },
            )
        }
        // 통합 window reducer 테스트는 close 요청이 content/sidebar child action을 함께 방출하므로
        // 각 시나리오에서 검증하는 핵심 상태 변화만 명시적으로 확인한다.
        store.exhaustivity = .off
        return store
    }
}
