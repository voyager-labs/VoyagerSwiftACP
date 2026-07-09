import ComposableArchitecture
import Foundation
import VoyagerEntitiesAi
import VoyagerEntitiesCollection
import VoyagerEntitiesEntry
import VoyagerFeaturesAiChat
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

    /// CTM-005-preserve_independent_content_tab_sessions: pinned Collection tab 전환 시 collection file open 경로 사용
    /// 복원된 pinned Collection tab이 빈 synthetic collection route에 머물지 않고 실제 collection file load/hydration을 시작해야 한다.
    /// - 검증 내용: Home active 상태에서 pinned Collection tab으로 전환하면 openCollectionFile 액션을 수신
    /// - 사전 조건: pinned Collection tab anchor == .collectionFile(url), 해당 tabContentStates 없음
    /// - 기대 결과: collection URL로 navigation.view.openCollectionFile 액션 전송
    func testSwitchingToPinnedCollectionTabOpensCollectionFile() async {
        let homeID = ContentTabID()
        let collectionID = ContentTabID()
        let collectionURL = URL(fileURLWithPath: "/Users/test/Saved.voyagercollection")
        var homeContent = FileManagerContentFeature.State()
        homeContent.navigation.navigationState = .home
        var state = FileManagerFeature.State()
        state.contentTabs = ContentTabState(
            tabs: [
                ContentTabItem(
                    id: collectionID,
                    page: .collection,
                    anchor: .collectionFile(url: collectionURL),
                    isPinned: true,
                    title: "Saved",
                    iconName: "rectangle.stack",
                ),
                ContentTabItem(
                    id: homeID,
                    page: .home,
                    anchor: .homeDefault,
                    isPinned: false,
                    title: "Home",
                    iconName: "house",
                ),
            ],
            activeTabID: homeID,
            recentlyClosed: nil,
            pinnedRecords: [
                collectionID: ContentTabPinnedRecord(
                    id: collectionID.rawValue,
                    page: .collection,
                    anchor: .collectionFile(url: collectionURL),
                    title: "Saved",
                    iconName: "rectangle.stack",
                    pinnedAt: Date(timeIntervalSince1970: 1234),
                ),
            ],
        )
        state.content = homeContent
        state.tabContentStates = [homeID: homeContent]
        state.syncContentTabSidebarItems()
        let store = TestStore(initialState: state) {
            FileManagerFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
        }
        store.exhaustivity = .off

        await store.send(.contentTabs(.setCurrent(collectionID)))
        await store.receive(\.navigation.view.openCollectionFile, collectionURL)
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
        XCTAssertEqual(store.state.contentTabs.activeTabID, downloadsID)
        XCTAssertEqual(
            store.state.sidebar.contentTabSidebarItems.first(where: { $0.id == downloadsID })?.isActive,
            true,
        )

        await store.send(.contentTabs(.setCurrent(projectsID)))
        XCTAssertEqual(store.state.contentTabs.activeTabID, projectsID)
        XCTAssertEqual(store.state.sidebar.contentTabSidebarItems.first(where: { $0.id == projectsID })?.isActive, true)

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
    func testActiveCloseRestoresAiChatTabAndRemovesPromotedBackgroundOwner() async {
        let aiChatID = ContentTabID()
        let directoryID = ContentTabID()
        let aiSessionID = AiChatSessionID(rawValue: UUID())
        let requestLock = makeRequestLock(sessionID: aiSessionID)

        var aiChatContent = FileManagerContentFeature.State()
        aiChatContent.navigation.navigationState = .aiChat(aiSessionID.rawValue.uuidString)
        aiChatContent.aiChat.sessionID = aiSessionID
        aiChatContent.aiChat.sessionStatus = .active
        aiChatContent.aiChat.executionPhase = .processing(requestLock)

        var directoryContent = FileManagerContentFeature.State()
        directoryContent.navigation.seedInitialFolderPath("/Users/test/Desktop")

        var backgroundContent = aiChatContent
        backgroundContent.aiChat.executionPhase = .idle
        backgroundContent.aiChat.backgroundExecutionPhases[requestLock.requestID] = .processing(requestLock)

        var state = FileManagerFeature.State()
        state.contentTabs = ContentTabState(
            tabs: [
                ContentTabItem(
                    id: aiChatID,
                    page: .aiChat,
                    anchor: .aiChat(sessionID: aiSessionID.rawValue.uuidString),
                    isPinned: false,
                    title: "Chat",
                    iconName: "message",
                ),
                ContentTabItem(
                    id: directoryID,
                    page: .directory,
                    anchor: .directory(path: "/Users/test/Desktop"),
                    isPinned: false,
                    title: "Desktop",
                    iconName: "folder",
                ),
            ],
            activeTabID: directoryID,
            previousActiveTabID: aiChatID,
            recentlyClosed: nil,
        )
        state.content = directoryContent
        state.tabContentStates = [aiChatID: aiChatContent, directoryID: directoryContent]
        state.backgroundAiChatStates[aiSessionID] = backgroundContent
        state.syncContentTabSidebarItems()

        let store = TestStore(initialState: state) {
            FileManagerFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
        }
        store.exhaustivity = .off

        await store.send(.contentTabs(.close(directoryID)))

        XCTAssertEqual(store.state.contentTabs.activeTabID, aiChatID)
        XCTAssertEqual(store.state.content.aiChat.executionPhase, .processing(requestLock))
        XCTAssertNil(
            store.state.backgroundAiChatStates[aiSessionID]?.aiChat.backgroundExecutionPhases[requestLock.requestID],
            "restoring the AI Chat tab on close should remove the duplicated background owner",
        )
        XCTAssertNil(store.state.tabContentStates[directoryID])
        await store.finish()
    }

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

    func testInactiveAiChatTabCloseMovesLifecycleOwnerToBackground() async {
        let homeID = ContentTabID()
        let aiChatID = ContentTabID()
        let aiSessionID = AiChatSessionID(rawValue: UUID())
        let providerMessage = AiChatMessage(role: .user, content: "latest provider prompt")
        let preservedMessage = AiChatMessage(role: .user, content: "older preserved prompt")
        let requestLock = makeRequestLock(
            sessionID: aiSessionID,
            requestMessages: [providerMessage],
            persistenceTranscriptHistory: [preservedMessage, providerMessage],
        )

        var homeContent = FileManagerContentFeature.State()
        homeContent.navigation.seedInitialFolderPath("/Users/test/HomeSession")

        var aiChatContent = FileManagerContentFeature.State()
        aiChatContent.navigation.navigationState = .aiChat(aiSessionID.rawValue.uuidString)
        aiChatContent.aiChat.sessionID = aiSessionID
        aiChatContent.aiChat.sessionStatus = .active
        aiChatContent.aiChat.executionPhase = .processing(requestLock)

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
                    id: aiChatID,
                    page: .aiChat,
                    anchor: .aiChat(sessionID: aiSessionID.rawValue.uuidString),
                    isPinned: false,
                    title: "Chat",
                    iconName: "message",
                ),
            ],
            activeTabID: homeID,
            recentlyClosed: nil,
        )
        state.content = homeContent
        state.tabContentStates = [homeID: homeContent, aiChatID: aiChatContent]
        state.syncContentTabSidebarItems()

        let store = TestStore(initialState: state) {
            FileManagerFeature()
        }
        store.exhaustivity = .off

        await store.send(.contentTabs(.close(aiChatID)))

        XCTAssertEqual(store.state.contentTabs.activeTabID, homeID)
        XCTAssertNil(store.state.tabContentStates[aiChatID])
        XCTAssertEqual(
            store.state.backgroundAiChatStates[aiSessionID]?.aiChat.executionPhase,
            .processing(requestLock),
        )
        XCTAssertEqual(store.state.content.navigation.currentPath, "/Users/test/HomeSession")
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

    /// CTM-444-collection_dirty_close: pending close 중 Cmd+P pin toggle은 무시됨
    /// 저장 완료 전 active closing target이 pinned로 바뀌어 close-as-unpin 정책과 충돌하지 않도록 검증한다.
    func testPendingDirtyCollectionCloseIgnoresPinToggleCommandUntilCompletion() async {
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

        await store.send(.request(.toggleActiveContentTabPin))

        XCTAssertEqual(store.state.pendingContentTabClose?.tabID, tabID)
        XCTAssertEqual(store.state.contentTabs.tabs[id: tabID]?.isPinned, false)
        XCTAssertNil(store.state.contentTabs.pinnedRecords[tabID])
        await store.finish()
    }

    /// CTM-444-collection_dirty_close: pending close 중 Sidebar pin/unpin delegate는 무시됨
    /// Sidebar context menu 경로도 저장 중 closing target의 pin 상태를 변경하지 않는지 검증한다.
    func testPendingDirtyCollectionCloseIgnoresSidebarPinActionsUntilCompletion() async {
        let pinnedID = ContentTabID()
        let unpinnedID = ContentTabID()
        let pinnedAnchor: ContentTabPageAnchor = .collectionFile(url: URL(fileURLWithPath: "/tmp/pinned.voycoll"))
        let unpinnedAnchor: ContentTabPageAnchor = .collectionFile(url: URL(fileURLWithPath: "/tmp/unpinned.voycoll"))
        let pinnedRecord = ContentTabPinnedRecord(
            id: pinnedID.rawValue,
            page: .collection,
            anchor: pinnedAnchor,
            title: "Pinned",
            iconName: "rectangle.stack",
            pinnedAt: Date(timeIntervalSince1970: 1_234_567_890),
        )
        let content = makeDirtyCollectionContent()

        var state = FileManagerFeature.State()
        state.contentTabs = ContentTabState(
            tabs: [
                ContentTabItem(
                    id: pinnedID,
                    page: .collection,
                    anchor: pinnedAnchor,
                    isPinned: true,
                    title: "Pinned",
                    iconName: "rectangle.stack",
                ),
                ContentTabItem(
                    id: unpinnedID,
                    page: .collection,
                    anchor: unpinnedAnchor,
                    isPinned: false,
                    title: "Unpinned",
                    iconName: "rectangle.stack",
                ),
            ],
            activeTabID: pinnedID,
            recentlyClosed: nil,
            pinnedRecords: [pinnedID: pinnedRecord],
        )
        state.content = content
        state.tabContentStates = [pinnedID: content]
        state.pendingContentTabClose = PendingContentTabClose(tabID: pinnedID)
        state.syncContentTabSidebarItems()

        let store = makeTestStore(state: state)

        await store.send(.sidebar(.delegate(.unpinContentTab(pinnedID))))
        await store.send(.sidebar(.delegate(.pinContentTab(unpinnedID))))

        XCTAssertEqual(store.state.pendingContentTabClose?.tabID, pinnedID)
        XCTAssertEqual(store.state.contentTabs.tabs[id: pinnedID]?.isPinned, true)
        XCTAssertEqual(store.state.contentTabs.tabs[id: unpinnedID]?.isPinned, false)
        XCTAssertEqual(store.state.contentTabs.pinnedRecords[pinnedID], pinnedRecord)
        XCTAssertNil(store.state.contentTabs.pinnedRecords[unpinnedID])
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

        // pinned tab의 close는 unpin 처리 → tab은 유지되지만 isPinned = false
        XCTAssertNil(store.state.pendingContentTabClose)
        await store.receive(\.contentTabs)
        // tab은 유지 (unpin만 됨)
        XCTAssertNotNil(store.state.contentTabs.tabs[id: tabID])
        XCTAssertEqual(store.state.contentTabs.tabs[id: tabID]?.isPinned, false)
        await store.finish()
    }
}

// MARK: - CTM-005-ai_chat_provider_forwarding

@MainActor
extension CTM005IndependentContentTabSessionTests {
    /// CTM-005-ai_chat_provider_forwarding: Active AI Chat tab이 providerConnectionsUpdated를 ContentPane으로 수신함
    /// .aiChat(sessionID:) anchor를 가진 active tab에서 aiConnectionsFileUpdated action이
    /// content.aiChat.providerConnectionsUpdated로 전달되는지 검증한다.
    /// Inspector가 보이지 않을 때는 Inspector로 전달되지 않는다.
    func testActiveAIChatTabReceivesProviderConnectionsUpdated() async {
        let sessionID = "test-session"
        let aiChatID = ContentTabID()
        let connectionsFile = AIConnectionsFile.empty()
        var state = FileManagerFeature.State()
        state.contentTabs = ContentTabState(
            tabs: [
                ContentTabItem(
                    id: aiChatID,
                    page: .aiChat,
                    anchor: .aiChat(sessionID: sessionID),
                    isPinned: false,
                    title: "AI Chat",
                    iconName: "message",
                ),
            ],
            activeTabID: aiChatID,
            recentlyClosed: nil,
        )
        state.syncContentTabSidebarItems()

        let store = TestStore(initialState: state) {
            FileManagerFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
        }
        store.exhaustivity = .off

        await store.send(.aiConnectionsFileUpdated(connectionsFile))

        // ContentPane AI Chat으로 providerConnectionsUpdated가 전달됨
        await store.receive { action in
            guard case .content(.aiChat(.providerConnectionsUpdated)) = action else { return false }
            return true
        }

        // Inspector는 보이지 않으므로 Inspector로 전달되지 않음
        await store.finish()
    }

    /// CTM-005-ai_chat_provider_forwarding: AI Chat tab switch away/back 시 session이 보존됨
    /// .aiChat tab에서 Home tab으로 전환 후 다시 AI Chat tab으로 돌아왔을 때
    /// tab anchor와 content session이 유지되는지 검증한다.
    /// resyncNavigationStateForActiveContentTab가 .aiChat을 .home으로 매핑하지 않음을 간접 검증한다.
    func testAIChatTabSwitchAwayAndBackPreservesSession() async {
        let sessionID = "test-session"
        let aiChatID = ContentTabID()
        let homeID = ContentTabID()
        let homePath = "/Users/test/Home"

        let aiChatContent = FileManagerContentFeature.State()
        var homeContent = FileManagerContentFeature.State()
        homeContent.navigation.seedInitialFolderPath(homePath)

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
                    id: aiChatID,
                    page: .aiChat,
                    anchor: .aiChat(sessionID: sessionID),
                    isPinned: false,
                    title: "AI Chat",
                    iconName: "message",
                ),
            ],
            activeTabID: aiChatID,
            recentlyClosed: nil,
        )
        state.content = aiChatContent
        state.tabContentStates = [aiChatID: aiChatContent, homeID: homeContent]
        state.syncContentTabSidebarItems()

        let store = TestStore(initialState: state) {
            FileManagerFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
            $0.uuid = .incrementing
            $0.entryWatchingClient.startWatchingDirectory = { _ in
                AsyncStream { continuation in
                    continuation.finish()
                }
            }
        }
        store.exhaustivity = .off

        // AI Chat → Home으로 전환
        await store.send(.contentTabs(.setCurrent(homeID)))
        XCTAssertEqual(store.state.contentTabs.activeTabID, homeID)

        // AI Chat tab metadata가 tabContentStates에 보존됨
        XCTAssertNotNil(store.state.tabContentStates[aiChatID])
        XCTAssertEqual(store.state.contentTabs.tabs[id: aiChatID]?.anchor, .aiChat(sessionID: sessionID))
        XCTAssertEqual(store.state.contentTabs.tabs[id: aiChatID]?.page, .aiChat)

        // Home → AI Chat으로 재전환
        await store.send(.contentTabs(.setCurrent(aiChatID)))

        // AI Chat tab이 active로 복원되고 anchor가 유지됨 (resync가 .home을 overwrite하지 않음)
        XCTAssertEqual(store.state.contentTabs.activeTabID, aiChatID)
        XCTAssertEqual(store.state.contentTabs.tabs[id: aiChatID]?.anchor, .aiChat(sessionID: sessionID))
        XCTAssertEqual(store.state.contentTabs.tabs[id: aiChatID]?.page, .aiChat)
        XCTAssertNotNil(store.state.tabContentStates[aiChatID])
        await store.finish()
    }

    /// CTM-005-ai_chat_provider_forwarding: AI Chat History 탭 복귀 시 sessions route를 보존함
    /// AI Chat tab anchor는 `.aiChat(sessionID:)`만 저장하므로 탭 handoff resync가 복원된 History route를 chat route로 낮추면 안 된다.
    /// - 검증 내용: Home tab에서 AI Chat History tab으로 복귀할 때 `.aiChatSessions(sessionID)` route와 sessions mode가 유지됨
    /// - 사전 조건: AI Chat tab의 저장된 content state가 `.aiChatSessions(sessionID)`이고 현재 active tab은 Home인 상태
    /// - 기대 결과: resync가 `.aiChat(sessionID)`가 아니라 `.aiChatSessions(sessionID)`를 apply하고 AiChat state는 sessions mode를
    /// 유지함
    func testAiChatHistoryTabSwitchAwayAndBackPreservesSessionsRoute() async throws {
        let sessionUUID = try XCTUnwrap(UUID(uuidString: "E621E1F8-C36C-495A-93FC-0C247A3E6E5F"))
        let sessionID = sessionUUID.uuidString
        let aiSessionID = AiChatSessionID(rawValue: sessionUUID)
        let aiChatID = ContentTabID()
        let homeID = ContentTabID()
        let homePath = "/Users/test/Home"

        var aiChatContent = FileManagerContentFeature.State()
        aiChatContent.navigation.navigationState = .aiChatSessions(sessionID)
        aiChatContent.aiChat.mode = .sessions
        aiChatContent.aiChat.sessionID = aiSessionID
        aiChatContent.aiChat.sessionStatus = .active

        var homeContent = FileManagerContentFeature.State()
        homeContent.navigation.seedInitialFolderPath(homePath)

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
                    id: aiChatID,
                    page: .aiChat,
                    anchor: .aiChat(sessionID: sessionID),
                    isPinned: false,
                    title: "AI Chat",
                    iconName: "message",
                ),
            ],
            activeTabID: homeID,
            recentlyClosed: nil,
        )
        state.content = homeContent
        state.tabContentStates = [aiChatID: aiChatContent, homeID: homeContent]
        state.syncContentTabSidebarItems()

        let store = TestStore(initialState: state) {
            FileManagerFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
            $0.uuid = .incrementing
            $0.aiConnectionsFileClient.load = { .empty() }
            $0.entryWatchingClient.startWatchingDirectory = { _ in
                AsyncStream { continuation in
                    continuation.finish()
                }
            }
        }
        // store.exhaustivity = .off: tab handoff는 sidebar/observer 효과를 함께 방출하므로 복원 route와 AiChat mode 불변식만 검증함
        store.exhaustivity = .off

        await store.send(.contentTabs(.setCurrent(aiChatID)))
        XCTAssertEqual(store.state.contentTabs.activeTabID, aiChatID)
        XCTAssertEqual(store.state.content.navigation.navigationState, .aiChatSessions(sessionID))
        XCTAssertEqual(store.state.content.aiChat.mode, .sessions)
        XCTAssertEqual(store.state.content.aiChat.sessionID, aiSessionID)

        await store.receive { action in
            guard case let .content(.internal(.applyNavigationState(.aiChatSessions(receivedSessionID)))) = action
            else {
                return false
            }
            return receivedSessionID == sessionID
        }
        await store.receive { action in
            guard case let .content(.aiChat(.showSessionsForChat(receivedSessionID))) = action else {
                return false
            }
            return receivedSessionID == aiSessionID
        }
        await store.receive { action in
            guard case .content(.aiChat(.providerConnectionsUpdated)) = action else { return false }
            return true
        }

        XCTAssertEqual(store.state.content.navigation.navigationState, .aiChatSessions(sessionID))
        XCTAssertEqual(store.state.content.aiChat.mode, .sessions)
        XCTAssertEqual(store.state.content.aiChat.sessionID, aiSessionID)
        await store.finish()
    }

    /// CTM-005-ai_chat_provider_forwarding: AI Chat 탭을 떠날 때 이전 탭의 in-flight restore 표시를 저장하지 않음
    /// AI Chat 탭 전환 중 효과는 취소되므로 저장되는 이전 탭 state도 restoring/model loading UI 상태를 제거해야 한다.
    /// - 검증 내용: AI Chat tab에서 Home tab으로 전환할 때 저장된 AI Chat state의 restore/draft/model loading 상태 정리
    /// - 사전 조건: active AI Chat tab이 `.restoring` status, streaming draft, pending restore, model loading tracking을 가진
    /// 상태
    /// - 기대 결과: tabContentStates에 저장된 이전 AI Chat state가 idle/active 상태로 정리되고 pending restore/model loading 필드를 비움
    func testAiChatTabSwitchAwayClearsSavedInFlightRestoreState() async throws {
        let sessionUUID = try XCTUnwrap(UUID(uuidString: "E621E1F8-C36C-495A-93FC-0C247A3E6E5F"))
        let restoringUUID = try XCTUnwrap(UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE"))
        let sessionID = sessionUUID.uuidString
        let aiSessionID = AiChatSessionID(rawValue: sessionUUID)
        let restoringSessionID = AiChatSessionID(rawValue: restoringUUID)
        let aiChatID = ContentTabID()
        let homeID = ContentTabID()
        let homePath = "/Users/test/Home"

        var aiChatContent = FileManagerContentFeature.State()
        aiChatContent.navigation.navigationState = .aiChat(sessionID)
        aiChatContent.aiChat.mode = .chat
        aiChatContent.aiChat.sessionID = aiSessionID
        aiChatContent.aiChat.sessionStatus = .restoring
        aiChatContent.aiChat.restoreSessionID = restoringSessionID
        aiChatContent.aiChat.streamingAssistantDraft = "partial response"
        aiChatContent.aiChat.modelListState = .loading
        aiChatContent.aiChat.modelListRequestID = UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")
        aiChatContent.aiChat.modelListProvider = .openai
        aiChatContent.aiChat.modelListProviderOrder = [.openai, .anthropic]
        aiChatContent.aiChat.modelListPendingProviders = [.openai, .anthropic]
        aiChatContent.aiChat.modelListLoadedModelsByProvider = [.openai: []]
        aiChatContent.aiChat.modelListFailedProviders = [
            .anthropic: AiModelListFailure(message: "loading"),
        ]

        var homeContent = FileManagerContentFeature.State()
        homeContent.navigation.seedInitialFolderPath(homePath)

        var state = FileManagerFeature.State()
        state.contentTabs = ContentTabState(
            tabs: [
                ContentTabItem(
                    id: aiChatID,
                    page: .aiChat,
                    anchor: .aiChat(sessionID: sessionID),
                    isPinned: false,
                    title: "AI Chat",
                    iconName: "message",
                ),
                ContentTabItem(
                    id: homeID,
                    page: .home,
                    anchor: .homeDefault,
                    isPinned: false,
                    title: "Home",
                    iconName: "house",
                ),
            ],
            activeTabID: aiChatID,
            recentlyClosed: nil,
        )
        state.content = aiChatContent
        state.tabContentStates = [homeID: homeContent]
        state.syncContentTabSidebarItems()

        let store = TestStore(initialState: state) {
            FileManagerFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
            $0.uuid = .incrementing
            $0.entryWatchingClient.startWatchingDirectory = { _ in
                AsyncStream { continuation in
                    continuation.finish()
                }
            }
        }
        // store.exhaustivity = .off: tab handoff는 watcher/navigation 효과를 함께 방출하므로 저장된 이전 AI Chat state 정리에 집중함
        store.exhaustivity = .off

        await store.send(.contentTabs(.setCurrent(homeID)))
        let savedAiChatState = try XCTUnwrap(store.state.tabContentStates[aiChatID]?.aiChat)
        XCTAssertEqual(savedAiChatState.executionPhase, .idle)
        XCTAssertNil(savedAiChatState.streamingAssistantDraft)
        XCTAssertNil(savedAiChatState.restoreSessionID)
        XCTAssertNil(savedAiChatState.restoreOutcome)
        XCTAssertNil(savedAiChatState.restoreFailure)
        XCTAssertEqual(savedAiChatState.modelListState, .idle)
        XCTAssertNil(savedAiChatState.modelListRequestID)
        XCTAssertNil(savedAiChatState.modelListProvider)
        XCTAssertTrue(savedAiChatState.modelListProviderOrder.isEmpty)
        XCTAssertTrue(savedAiChatState.modelListPendingProviders.isEmpty)
        XCTAssertTrue(savedAiChatState.modelListLoadedModelsByProvider.isEmpty)
        XCTAssertTrue(savedAiChatState.modelListFailedProviders.isEmpty)
        XCTAssertEqual(savedAiChatState.sessionStatus, .active)
        XCTAssertEqual(savedAiChatState.sessionID, aiSessionID)
        await store.finish()
    }

    /// CTM-005-ai_chat_provider_forwarding: AI Chat 탭을 떠날 때 로드 완료된 model catalog를 보존함
    /// AI Chat 탭 전환 중 in-flight loading만 정리하고 이미 로드된 model catalog는 저장된 tab state에 유지해야 한다.
    /// - 검증 내용: loaded modelListState와 catalog tracking이 tabContentStates에 그대로 저장됨
    /// - 사전 조건: active AI Chat tab이 `.loaded` model list와 loaded provider catalog를 가진 상태
    /// - 기대 결과: tab handoff 후 저장된 AI Chat state가 loaded model catalog와 provider metadata를 보존함
    func testAiChatTabSwitchAwayPreservesLoadedModelCatalogState() async throws {
        let sessionUUID = try XCTUnwrap(UUID(uuidString: "E621E1F8-C36C-495A-93FC-0C247A3E6E5F"))
        let requestUUID = try XCTUnwrap(UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB"))
        let sessionID = sessionUUID.uuidString
        let aiSessionID = AiChatSessionID(rawValue: sessionUUID)
        let aiChatID = ContentTabID()
        let homeID = ContentTabID()
        let homePath = "/Users/test/Home"
        let model = AiProviderModel(
            id: AiModelHandle(provider: .openai, rawValue: "gpt-test"),
            provider: .openai,
            rawModelID: "gpt-test",
            displayName: "GPT Test",
            providerDisplayName: "OpenAI",
            thinkingCapability: .unsupported(reason: AiThinkingUnavailableReason(message: "unsupported")),
        )

        var aiChatContent = FileManagerContentFeature.State()
        aiChatContent.navigation.navigationState = .aiChat(sessionID)
        aiChatContent.aiChat.mode = .chat
        aiChatContent.aiChat.sessionID = aiSessionID
        aiChatContent.aiChat.sessionStatus = .active
        aiChatContent.aiChat.modelListState = .loaded([model])
        aiChatContent.aiChat.modelListRequestID = requestUUID
        aiChatContent.aiChat.modelListProvider = .openai
        aiChatContent.aiChat.modelListProviderOrder = [.openai]
        aiChatContent.aiChat.modelListPendingProviders = []
        aiChatContent.aiChat.modelListLoadedModelsByProvider = [.openai: [model]]
        aiChatContent.aiChat.modelListFailedProviders = [:]

        var homeContent = FileManagerContentFeature.State()
        homeContent.navigation.seedInitialFolderPath(homePath)

        var state = FileManagerFeature.State()
        state.contentTabs = ContentTabState(
            tabs: [
                ContentTabItem(
                    id: aiChatID,
                    page: .aiChat,
                    anchor: .aiChat(sessionID: sessionID),
                    isPinned: false,
                    title: "AI Chat",
                    iconName: "message",
                ),
                ContentTabItem(
                    id: homeID,
                    page: .home,
                    anchor: .homeDefault,
                    isPinned: false,
                    title: "Home",
                    iconName: "house",
                ),
            ],
            activeTabID: aiChatID,
            recentlyClosed: nil,
        )
        state.content = aiChatContent
        state.tabContentStates = [homeID: homeContent]
        state.syncContentTabSidebarItems()

        let store = TestStore(initialState: state) {
            FileManagerFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
            $0.uuid = .incrementing
            $0.entryWatchingClient.startWatchingDirectory = { _ in
                AsyncStream { continuation in
                    continuation.finish()
                }
            }
        }
        // store.exhaustivity = .off: tab handoff는 watcher/navigation 효과를 함께 방출하므로 저장된 loaded model catalog 보존만 검증함
        store.exhaustivity = .off

        await store.send(.contentTabs(.setCurrent(homeID)))
        let savedAiChatState = try XCTUnwrap(store.state.tabContentStates[aiChatID]?.aiChat)
        XCTAssertEqual(savedAiChatState.modelListState, .loaded([model]))
        XCTAssertEqual(savedAiChatState.modelListRequestID, requestUUID)
        XCTAssertEqual(savedAiChatState.modelListProvider, .openai)
        XCTAssertEqual(savedAiChatState.modelListProviderOrder, [.openai])
        XCTAssertTrue(savedAiChatState.modelListPendingProviders.isEmpty)
        XCTAssertEqual(savedAiChatState.modelListLoadedModelsByProvider, [.openai: [model]])
        XCTAssertTrue(savedAiChatState.modelListFailedProviders.isEmpty)
        XCTAssertEqual(savedAiChatState.sessionStatus, .active)
        XCTAssertEqual(savedAiChatState.sessionID, aiSessionID)
        await store.finish()
    }

    /// CTM-005-ai_chat_content_pane_inspector_isolation: Inspector Chat이 열려 있으면 ContentPane cancel을 보내지 않음
    /// ContentPane tab handoff state cleanup은 저장 state에만 적용하고 shared AiChat cancel ID로 Inspector Chat 요청을 끊으면 안 된다.
    /// - 검증 내용: Inspector Chat이 열린 상태에서 AI Chat tab을 떠날 때 저장된 ContentPane state는 정리되지만 cancelInFlightWork를 수신하지 않음
    /// - 사전 조건: active AI Chat tab과 열린 Inspector Chat이 동시에 존재하는 상태
    /// - 기대 결과: 이전 AI Chat tabContentStates의 in-flight restore 표시는 정리되고 Inspector Chat은 계속 표시됨
    func testAiChatTabSwitchAwayDoesNotCancelWhenInspectorChatOpen() async throws {
        let sessionUUID = try XCTUnwrap(UUID(uuidString: "E621E1F8-C36C-495A-93FC-0C247A3E6E5F"))
        let restoringUUID = try XCTUnwrap(UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE"))
        let sessionID = sessionUUID.uuidString
        let aiSessionID = AiChatSessionID(rawValue: sessionUUID)
        let restoringSessionID = AiChatSessionID(rawValue: restoringUUID)
        let aiChatID = ContentTabID()
        let homeID = ContentTabID()
        let homePath = "/Users/test/Home"

        var aiChatContent = FileManagerContentFeature.State()
        aiChatContent.navigation.navigationState = .aiChat(sessionID)
        aiChatContent.aiChat.mode = .chat
        aiChatContent.aiChat.sessionID = aiSessionID
        aiChatContent.aiChat.sessionStatus = .restoring
        aiChatContent.aiChat.restoreSessionID = restoringSessionID
        aiChatContent.aiChat.streamingAssistantDraft = "partial response"

        var homeContent = FileManagerContentFeature.State()
        homeContent.navigation.seedInitialFolderPath(homePath)

        var state = FileManagerFeature.State()
        state.contentTabs = ContentTabState(
            tabs: [
                ContentTabItem(
                    id: aiChatID,
                    page: .aiChat,
                    anchor: .aiChat(sessionID: sessionID),
                    isPinned: false,
                    title: "AI Chat",
                    iconName: "message",
                ),
                ContentTabItem(
                    id: homeID,
                    page: .home,
                    anchor: .homeDefault,
                    isPinned: false,
                    title: "Home",
                    iconName: "house",
                ),
            ],
            activeTabID: aiChatID,
            recentlyClosed: nil,
        )
        state.content = aiChatContent
        state.tabContentStates = [homeID: homeContent]
        state.inspector.inspectorVisible = true
        state.inspector.inspectorPaneExists = true
        state.inspector.activeMode = .chat
        state.syncContentTabSidebarItems()

        let store = TestStore(initialState: state) {
            FileManagerFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
            $0.uuid = .incrementing
            $0.entryWatchingClient.startWatchingDirectory = { _ in
                AsyncStream { continuation in
                    continuation.finish()
                }
            }
        }
        // store.exhaustivity = .off: tab handoff는 watcher/navigation 효과를 함께 방출하므로 Inspector가 열린 상태의 저장 state cleanup만
        // 검증함
        store.exhaustivity = .off

        await store.send(.contentTabs(.setCurrent(homeID)))

        let savedAiChatState = try XCTUnwrap(store.state.tabContentStates[aiChatID]?.aiChat)
        XCTAssertEqual(savedAiChatState.executionPhase, .idle)
        XCTAssertNil(savedAiChatState.streamingAssistantDraft)
        XCTAssertNil(savedAiChatState.restoreSessionID)
        XCTAssertEqual(savedAiChatState.sessionStatus, .active)
        XCTAssertFalse(store.state.inspector.inspectorVisible)
        XCTAssertNil(store.state.tabInspectorStates[homeID])
        await store.finish()
    }

    /// Home tab은 Inspector를 지원하지 않고, 디렉토리 tab의 Inspector 상태는 해당 tab으로 돌아올 때 복원된다.
    func testHomeTabHidesInspectorAndDirectoryTabRestoresOwnInspectorState() async {
        let directoryID = ContentTabID()
        let homeID = ContentTabID()
        let inspectorSessionID = AiChatSessionID(rawValue: UUID())
        var directoryContent = FileManagerContentFeature.State()
        directoryContent.navigation.seedInitialFolderPath("/Users/test/Documents")

        var homeContent = FileManagerContentFeature.State()
        homeContent.navigation.navigationState = .home

        var state = FileManagerFeature.State()
        state.contentTabs = ContentTabState(
            tabs: [
                ContentTabItem(
                    id: directoryID,
                    page: .directory,
                    anchor: .directory(path: "/Users/test/Documents"),
                    isPinned: false,
                    title: "Documents",
                    iconName: "folder",
                ),
                ContentTabItem(
                    id: homeID,
                    page: .home,
                    anchor: .homeDefault,
                    isPinned: false,
                    title: "Home",
                    iconName: "house",
                ),
            ],
            activeTabID: directoryID,
            recentlyClosed: nil,
        )
        state.content = directoryContent
        state.tabContentStates = [
            directoryID: directoryContent,
            homeID: homeContent,
        ]
        state.inspector.inspectorVisible = true
        state.inspector.inspectorPaneExists = true
        state.inspector.activeMode = .chat
        state.inspector.aiChat.sessionID = inspectorSessionID
        state.inspector.aiChat.sessionStatus = .active
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

        await store.send(.contentTabs(.setCurrent(homeID)))

        XCTAssertFalse(store.state.inspector.inspectorVisible)
        XCTAssertNil(store.state.tabInspectorStates[homeID])
        XCTAssertEqual(store.state.tabInspectorStates[directoryID]?.inspectorVisible, true)
        XCTAssertEqual(store.state.tabInspectorStates[directoryID]?.inspectorPaneExists, false)
        XCTAssertEqual(store.state.tabInspectorStates[directoryID]?.aiChat.sessionID, inspectorSessionID)

        await store.send(.contentTabs(.setCurrent(directoryID)))

        XCTAssertTrue(store.state.inspector.inspectorVisible)
        XCTAssertFalse(store.state.inspector.inspectorPaneExists)
        XCTAssertEqual(store.state.inspector.activeMode, .chat)
        XCTAssertEqual(store.state.inspector.aiChat.sessionID, inspectorSessionID)
        await store.finish()
    }

    /// Fresh Inspector contextual chat은 nil session setup이어도 provider/model refresh를 반드시 실행한다.
    func testFreshInspectorOpenWithNilSessionLoadsProviderModelsAndEnablesSubmitAfterSelection() async throws {
        let directoryID = ContentTabID()
        let directoryPath = "/Users/test/Desktop"
        let modelHandle = AiModelHandle(provider: .openai, rawValue: "gpt-test")
        let model = AiProviderModel(
            id: modelHandle,
            provider: .openai,
            rawModelID: "gpt-test",
            displayName: "GPT Test",
            providerDisplayName: "OpenAI",
            thinkingCapability: .unsupported(reason: AiThinkingUnavailableReason(message: "unsupported")),
        )
        let credential = StoredCredentialPayload.apiKey(APIKeyCredentialFile(secret: "sk-test"))
        let connectionsFile = AIConnectionsFile(
            updatedAtMs: 1,
            lastUsedProviderId: .openai,
            providers: [
                AiProvider.openai.rawValue: ProviderRecordFile(
                    providerId: .openai,
                    authMethod: .apiKey,
                    credential: credential,
                    snapshot: ProviderSnapshotFile(lastKnownStatus: .connected),
                ),
            ],
        )
        let modelListRequestID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000000"))

        var directoryContent = FileManagerContentFeature.State()
        directoryContent.navigation.seedInitialFolderPath(directoryPath)

        var state = FileManagerFeature.State()
        state.contentTabs = ContentTabState(
            tabs: [
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
            recentlyClosed: nil,
        )
        state.content = directoryContent
        state.tabContentStates = [directoryID: directoryContent]
        state.syncContentTabSidebarItems()

        let setup = FileManagerAiChatContextAdapter.makeAiChatSetupState(content: directoryContent)
        let store = TestStore(initialState: state) {
            FileManagerFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
            $0.uuid = .incrementing
            $0.aiProviderModelListClient = AiProviderModelListClient(loadModels: { provider, receivedCredential in
                XCTAssertEqual(provider, .openai)
                XCTAssertEqual(receivedCredential, credential)
                return [model]
            })
        }
        store.exhaustivity = .off

        await store.send(.inspector(.openChat(setup, connectionsFile))) { state in
            state.inspector.inspectorVisible = true
            state.inspector.activeMode = .chat
        }
        await store.receive(\.inspector.aiChat.setup)
        await store.receive(\.inspector.aiChat.providerConnectionsUpdated)
        await store.receive { action in
            guard case let .inspector(.aiChat(.modelListLoading(requestID, provider, receivedCredential))) = action
            else {
                return false
            }
            return requestID == modelListRequestID
                && provider == .openai
                && receivedCredential == credential
        }
        await store.receive { action in
            guard case let .inspector(.aiChat(.modelListLoaded(requestID, provider, models))) = action else {
                return false
            }
            return requestID == modelListRequestID
                && provider == .openai
                && models == [model]
        }

        await store.send(.inspector(.aiChat(.selectedModelChanged(modelHandle)))) { state in
            state.inspector.aiChat.selectedModelHandle = modelHandle
        }
        await store.send(.inspector(.aiChat(.draftTextChanged("Question from fresh inspector")))) { state in
            state.inspector.aiChat.draftText = "Question from fresh inspector"
        }

        XCTAssertEqual(store.state.inspector.aiChat.modelListState, .loaded([model]))
        XCTAssertEqual(store.state.inspector.aiChat.chatInputDisplayModel.modelLabel, "GPT Test")
        XCTAssertTrue(store.state.inspector.aiChat.canSubmit)
        XCTAssertTrue(store.state.inspector.aiChat.chatInputDisplayModel.canSubmit)
        await store.finish()
    }

    /// CTM-005-ai_chat_provider_forwarding: Inspector가 보이지 않고 active tab이 .aiChat이 아닌 경우 전송 없음
    /// ContentPane과 Inspector 모두 forwarding 조건을 만족하지 않을 때 효과가 발생하지 않는지 검증한다.
    func testNoForwardingWhenInspectorNotOpenAndActiveTabNotAiChat() async {
        let connectionsFile = AIConnectionsFile.empty()
        var state = FileManagerFeature.State()
        state.inspector.inspectorVisible = false
        state.syncContentTabSidebarItems()

        let store = TestStore(initialState: state) {
            FileManagerFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
        }
        store.exhaustivity = .off

        await store.send(.aiConnectionsFileUpdated(connectionsFile))

        // ContentPane AI Chat forwarding이 발생하지 않음
        // Inspector forwarding도 발생하지 않음 (inspectorVisible == false)
        await store.finish()
    }

    /// CTM-005-ai_chat_provider_forwarding: AI Chat tab active + Inspector visible + chat mode인 경우
    /// ContentPane과 Inspector 모두 providerConnectionsUpdated를 수신함
    func testBothContentAndInspectorReceiveWhenAiChatActiveAndInspectorOpen() async {
        let sessionID = "test-session"
        let aiChatID = ContentTabID()
        let connectionsFile = AIConnectionsFile.empty()
        var state = FileManagerFeature.State()
        state.contentTabs = ContentTabState(
            tabs: [
                ContentTabItem(
                    id: aiChatID,
                    page: .aiChat,
                    anchor: .aiChat(sessionID: sessionID),
                    isPinned: false,
                    title: "AI Chat",
                    iconName: "message",
                ),
            ],
            activeTabID: aiChatID,
            recentlyClosed: nil,
        )
        state.inspector.inspectorVisible = true
        state.inspector.inspectorPaneExists = true
        state.inspector.activeMode = .chat
        state.syncContentTabSidebarItems()

        let store = TestStore(initialState: state) {
            FileManagerFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
        }
        store.exhaustivity = .off

        await store.send(.aiConnectionsFileUpdated(connectionsFile))

        // ContentPane AI Chat으로 전달
        await store.receive { action in
            guard case .content(.aiChat(.providerConnectionsUpdated)) = action else { return false }
            return true
        }

        // Inspector AI Chat으로 전달
        await store.receive { action in
            guard case .inspector(.aiChat(.providerConnectionsUpdated)) = action else { return false }
            return true
        }

        await store.finish()
    }
}

// MARK: - CTM-005-ai_chat_content_pane_inspector_isolation

@MainActor
extension CTM005IndependentContentTabSessionTests {
    /// ContentPane AI Chat과 Inspector AI Chat의 state는 독립적으로 동작함
    /// 같은 AiChatFeature.State 타입이지만 content.aiChat과 inspector.aiChat이 완전히 분리되어
    /// 서로의 action이 상대방 state에 영향을 주지 않음을 검증한다.
    /// - 검증 내용: content.aiChat.mode 변경이 inspector.aiChat.mode에 영향을 주지 않음
    /// - 사전 조건: content.aiChat.mode == .chat, inspector.aiChat.mode == .sessions (기본값)
    /// - 기대 결과: content.aiChat.backToSessionsTapped 후 content mode는 .sessions, inspector mode는 .sessions (영향 없음)
    func testContentPaneAiChatAndInspectorAreIsolated() async {
        var state = FileManagerFeature.State()
        state.content.aiChat.mode = .chat
        state.content.aiChat.sessionStatus = .active
        state.content.aiChat.sessionID = AiChatSessionID(rawValue: UUID())
        state.contentTabs = ContentTabState(
            tabs: [ContentTabItem(
                id: ContentTabID(),
                page: .aiChat,
                anchor: .aiChat(sessionID: "test-session"),
                isPinned: false,
                title: "AI Chat",
                iconName: "message",
            )],
            activeTabID: ContentTabID(),
            recentlyClosed: nil,
        )
        state.syncContentTabSidebarItems()

        let store = TestStore(initialState: state) {
            FileManagerFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
            $0.aiChatSessionPersistenceClient.deleteSession = { _ in }
        }
        // KCF: FileManagerFeature의 routing reducer가 non-exhaustive side effect를 수행함
        store.exhaustivity = .off

        let inspectorModeBefore = state.inspector.aiChat.mode

        // When: ContentPane AI Chat에 backToSessionsTapped 전송
        await store.send(.content(.aiChat(.backToSessionsTapped)))

        // Then: ContentPane AI Chat mode가 .sessions로 변경됨
        XCTAssertEqual(store.state.content.aiChat.mode, .sessions)
        // Then: Inspector AI Chat mode는 영향을 받지 않음 (기본값 .sessions 유지)
        XCTAssertEqual(store.state.inspector.aiChat.mode, inspectorModeBefore)
        await store.finish()
    }

    /// ContentPane AI Chat에 .sessionsAppeared 전송 시 mode가 .sessions로 설정되고 session 목록 로드가 시작됨
    /// Inspector AI Chat에는 아무 영향이 없음을 함께 검증한다.
    /// - 검증 내용: content.aiChat.sessionsAppeared 후 content.aiChat.mode == .sessions,
    ///   inspector.aiChat.mode는 변경되지 않음
    /// - 사전 조건: content.aiChat.mode == .chat, inspector.aiChat.mode == .sessions
    /// - 기대 결과: ContentPane만 .sessions로 전환되고 Inspector는 그대로 유지됨
    func testContentPaneSessionsAppearedDoesNotAffectInspector() async {
        var state = FileManagerFeature.State()
        state.content.aiChat.mode = .chat
        state.content.aiChat.sessionStatus = .active
        state.content.aiChat.sessionID = AiChatSessionID(rawValue: UUID())
        state.contentTabs = ContentTabState(
            tabs: [ContentTabItem(
                id: ContentTabID(),
                page: .aiChat,
                anchor: .aiChat(sessionID: "test-session"),
                isPinned: false,
                title: "AI Chat",
                iconName: "message",
            )],
            activeTabID: ContentTabID(),
            recentlyClosed: nil,
        )
        state.syncContentTabSidebarItems()

        let store = TestStore(initialState: state) {
            FileManagerFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
            $0.aiChatSessionPersistenceClient.listSessions = { _, _ in [] }
        }
        store.exhaustivity = .off

        let inspectorModeBefore = state.inspector.aiChat.mode

        await store.send(.content(.aiChat(.sessionsAppeared)))

        XCTAssertEqual(store.state.content.aiChat.mode, .sessions)
        XCTAssertEqual(store.state.inspector.aiChat.mode, inspectorModeBefore)
        await store.finish()
    }
}

// MARK: - CTM-005-ai_chat_mode_switching

@MainActor
extension CTM005IndependentContentTabSessionTests {
    /// ContentPane AI Chat History 버튼이 mode를 .sessions로 전환함
    /// AiChatPageHeaderView에서 .chat mode일 때 History 버튼이 .backToSessionsTapped를 전송하고
    /// mode가 .sessions로 변경됨을 검증한다.
    /// - 검증 내용: .content(.aiChat(.backToSessionsTapped)) 전송 후 content.aiChat.mode == .sessions
    /// - 사전 조건: ContentPane AI Chat mode == .chat
    /// - 기대 결과: mode가 .sessions로 변경됨
    func testAiChatHistoryButtonSwitchesToSessionsMode() async {
        var state = FileManagerFeature.State()
        state.content.aiChat.mode = .chat
        state.content.aiChat.sessionStatus = .active
        state.content.aiChat.sessionID = AiChatSessionID(rawValue: UUID())
        state.contentTabs = ContentTabState(
            tabs: [ContentTabItem(
                id: ContentTabID(),
                page: .aiChat,
                anchor: .aiChat(sessionID: "test-session"),
                isPinned: false,
                title: "AI Chat",
                iconName: "message",
            )],
            activeTabID: ContentTabID(),
            recentlyClosed: nil,
        )
        state.syncContentTabSidebarItems()

        let store = TestStore(initialState: state) {
            FileManagerFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
            $0.aiChatSessionPersistenceClient.deleteSession = { _ in }
        }
        store.exhaustivity = .off

        await store.send(.content(.aiChat(.backToSessionsTapped)))

        XCTAssertEqual(store.state.content.aiChat.mode, .sessions)
        await store.finish()
    }

    /// ContentPane AI Chat History 화면 Back 버튼이 현재 채팅으로 복귀함
    /// AiChatPageHeaderView에서 .sessions mode일 때 Back 버튼이 .returnToChatTapped를 전송하고
    /// 새 session을 만들지 않은 채 기존 sessionID를 유지하며 .chat으로 돌아감을 검증한다.
    /// - 검증 내용: .content(.aiChat(.returnToChatTapped)) 전송 후 content.aiChat.mode == .chat,
    ///   기존 sessionID가 유지되고 restore 상태가 정리됨
    /// - 사전 조건: ContentPane AI Chat mode == .sessions, 기존 sessionID 존재
    /// - 기대 결과: mode가 .chat으로 변경되고 현재 chat session이 유지됨
    func testAiChatBackButtonReturnsToCurrentChatMode() async {
        let sessionID = AiChatSessionID(rawValue: UUID())
        var state = FileManagerFeature.State()
        state.content.aiChat.mode = .sessions
        state.content.aiChat.sessionID = sessionID
        state.content.aiChat.restoreSessionID = sessionID
        state.content.aiChat.sessionStatus = .active
        state.contentTabs = ContentTabState(
            tabs: [ContentTabItem(
                id: ContentTabID(),
                page: .aiChat,
                anchor: .aiChat(sessionID: sessionID.rawValue.uuidString),
                isPinned: false,
                title: "AI Chat",
                iconName: "message",
            )],
            activeTabID: ContentTabID(),
            recentlyClosed: nil,
        )
        state.syncContentTabSidebarItems()

        let store = TestStore(initialState: state) {
            FileManagerFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
        }
        store.exhaustivity = .off

        await store.send(.content(.aiChat(.returnToChatTapped)))

        XCTAssertEqual(store.state.content.aiChat.mode, .chat)
        XCTAssertEqual(store.state.content.aiChat.sessionID, sessionID)
        XCTAssertNil(store.state.content.aiChat.restoreOutcome)
        XCTAssertNil(store.state.content.aiChat.restoreFailure)
        XCTAssertTrue(store.state.content.aiChat.transcriptHistory.isEmpty)
        await store.finish()
    }

    /// CTM-005-ai_chat_mode_switching: AI Chat History route가 composite navigation history에 기록됨
    /// ContentPane AI Chat 내부 History/Chat 전환은 FileManager navigation stack과 분리되지 않아야 한다.
    /// - 검증 내용: `.aiChat` ↔ `.aiChatSessions` route가 같은 Back/Forward stack에 기록되고 재생됨
    /// - 사전 조건: AI Chat tab이 `.aiChat(sessionID)` route로 활성화되어 있고 Home route가 backHistory에 있음
    /// - 기대 결과: History 진입, Back, Forward가 각각 route와 AiChat mode를 시간순으로 복원함
    func testAiChatSessionsRouteParticipatesInCompositeNavigationHistory() async throws {
        let tabID = ContentTabID()
        let sessionUUID = try XCTUnwrap(UUID(uuidString: "E621E1F8-C36C-495A-93FC-0C247A3E6E5F"))
        let sessionID = sessionUUID.uuidString
        let aiSessionID = AiChatSessionID(rawValue: sessionUUID)
        var state = FileManagerFeature.State()
        state.contentTabs = ContentTabState(
            tabs: [ContentTabItem(
                id: tabID,
                page: .aiChat,
                anchor: .aiChat(sessionID: sessionID),
                isPinned: false,
                title: "AI Chat",
                iconName: "message",
            )],
            activeTabID: tabID,
            recentlyClosed: nil,
        )
        state.content.navigation.navigationState = .aiChat(sessionID)
        state.content.navigation.backHistory = [ContentPageNavigationHistorySnapshot(navigationState: .home)]
        state.content.aiChat.mode = .chat
        state.content.aiChat.sessionID = aiSessionID
        state.content.aiChat.sessionStatus = .active
        state.tabContentStates = [tabID: state.content]
        state.syncContentTabSidebarItems()

        let store = TestStore(initialState: state) {
            FileManagerFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
        }
        // store.exhaustivity = .off: navigation delegate와 content bridge 효과가 함께 방출되므로 route/mode 불변식만 검증함
        store.exhaustivity = .off

        await store.send(.navigation(.view(.showAiChatSessions(sessionID))))
        await store.receive { action in
            guard case let .navigation(.internal(.performShowAiChatSessions(receivedSessionID))) = action else {
                return false
            }
            return receivedSessionID == sessionID
        }
        await store.receive { action in
            guard case let .navigation(.delegate(.navigateToState(.aiChatSessions(receivedSessionID)))) = action else {
                return false
            }
            return receivedSessionID == sessionID
        }
        await store.receive { action in
            guard case let .content(.internal(.applyNavigationState(.aiChatSessions(receivedSessionID)))) = action
            else {
                return false
            }
            return receivedSessionID == sessionID
        }
        await store.receive(\.content.aiChat.showSessionsForChat)

        XCTAssertEqual(store.state.content.navigation.navigationState, .aiChatSessions(sessionID))
        XCTAssertEqual(store.state.content.navigation.backHistory.map(\.navigationState), [.home, .aiChat(sessionID)])
        XCTAssertEqual(store.state.content.navigation.forwardHistory.map(\.navigationState), [])
        XCTAssertEqual(store.state.content.aiChat.mode, .sessions)

        await store.send(.navigation(.view(.goBack)))
        await store.receive(\.navigation.internal.performNavigation)
        await store.receive { action in
            guard case let .navigation(.delegate(.navigateToState(.aiChat(receivedSessionID)))) = action else {
                return false
            }
            return receivedSessionID == sessionID
        }
        await store.receive { action in
            guard case let .content(.internal(.applyNavigationState(.aiChat(receivedSessionID)))) = action else {
                return false
            }
            return receivedSessionID == sessionID
        }
        await store.receive { action in
            guard case let .content(.aiChat(.routeToChatSession(receivedSessionID))) = action else {
                return false
            }
            return receivedSessionID == aiSessionID
        }

        XCTAssertEqual(store.state.content.navigation.backHistory.map(\.navigationState), [.home])
        XCTAssertEqual(
            store.state.content.navigation.forwardHistory.map(\.navigationState),
            [.aiChatSessions(sessionID)],
        )
        XCTAssertEqual(store.state.content.aiChat.mode, .chat)

        await store.send(.navigation(.view(.goForward)))
        await store.receive(\.navigation.internal.performNavigation)
        await store.receive { action in
            guard case let .navigation(.delegate(.navigateToState(.aiChatSessions(receivedSessionID)))) = action else {
                return false
            }
            return receivedSessionID == sessionID
        }
        await store.receive { action in
            guard case let .content(.internal(.applyNavigationState(.aiChatSessions(receivedSessionID)))) = action
            else {
                return false
            }
            return receivedSessionID == sessionID
        }
        await store.receive(\.content.aiChat.showSessionsForChat)

        XCTAssertEqual(store.state.content.navigation.navigationState, .aiChatSessions(sessionID))
        XCTAssertEqual(store.state.content.navigation.backHistory.map(\.navigationState), [.home, .aiChat(sessionID)])
        XCTAssertEqual(store.state.content.navigation.forwardHistory.map(\.navigationState), [])
        XCTAssertEqual(store.state.content.aiChat.mode, .sessions)
        await store.finish()
    }

    /// CTM-005-ai_chat_mode_switching: AI Chat History route 복원 중 늦은 selected session restore를 무시함
    /// AI Chat History로 돌아온 뒤 이전 selected session restore가 늦게 도착해도 화면이 selected chat으로 되돌아가지 않아야 한다.
    /// - 검증 내용: stale restoreOutcome 처리 후 mode/sessionID/transcript 불변
    /// - 사전 조건: `.aiChatSessions(current)` route와 selected session restore가 pending인 상태
    /// - 기대 결과: `.sessions` mode와 current sessionID를 유지하고 selected session transcript를 적용하지 않음
    func testAiChatSessionsRouteCancelsPendingSelectedSessionRestore() async throws {
        let currentSessionID = try AiChatSessionID(
            rawValue: XCTUnwrap(UUID(uuidString: "11111111-1111-1111-1111-111111111111")),
        )
        let selectedSessionID = try AiChatSessionID(
            rawValue: XCTUnwrap(UUID(uuidString: "22222222-2222-2222-2222-222222222222")),
        )
        let selectedSnapshot = AiChatSessionSnapshot(
            sessionID: selectedSessionID,
            status: .active,
            provider: nil,
            model: nil,
            transcriptHistory: [AiChatMessage(role: .assistant, content: "selected session")],
            updatedAtMs: 2,
        )

        var state = FileManagerFeature.State()
        state.content.aiChat.mode = .sessions
        state.content.aiChat.sessionID = currentSessionID
        state.content.aiChat.restoreSessionID = selectedSessionID
        state.content.aiChat.sessionList.selectedSessionID = selectedSessionID
        state.content.aiChat.sessionList.allRows = [
            AiChatSessionSummary(
                sessionID: selectedSessionID,
                title: "Selected session",
                messageCount: 1,
                provider: nil,
                model: nil,
                createdAtMs: 1,
                updatedAtMs: 2,
                status: .active,
            ),
        ]
        state.content.aiChat.sessionList.rows = state.content.aiChat.sessionList.allRows
        state.content.navigation.navigationState = .aiChatSessions(
            currentSessionID.rawValue.uuidString,
        )

        let store = TestStore(initialState: state) {
            FileManagerFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
        }
        // store.exhaustivity = .off: FileManagerFeature는 navigation/content delegate 효과를 함께 방출하므로 AiChat 상태 불변식만 검증함
        store.exhaustivity = .off

        await store.send(.content(.aiChat(.showSessionsTapped))) { state in
            state.content.aiChat.mode = .sessions
            state.content.aiChat.restoreSessionID = nil
            state.content.aiChat.restoreOutcome = nil
            state.content.aiChat.restoreFailure = nil
        }

        await store.send(.content(.aiChat(.restoreOutcome(
            requestedSessionID: selectedSessionID,
            .restored(snapshot: selectedSnapshot),
            restoreFailure: nil,
        ))))

        XCTAssertEqual(store.state.content.aiChat.mode, .sessions)
        XCTAssertEqual(store.state.content.aiChat.sessionID, currentSessionID)
        XCTAssertNotEqual(store.state.content.aiChat.sessionID, selectedSessionID)
        XCTAssertTrue(store.state.content.aiChat.transcriptHistory.isEmpty)
        await store.finish()
    }

    /// CTM-005-ai_chat_mode_switching: History route 복원 후 Return to chat이 route session으로 돌아감
    /// `.aiChatSessions(current)` route replay는 stale selected session이 아니라 route의 current session을 AiChat 상태에 반영해야 한다.
    /// - 검증 내용: route replay 후 Return to chat navigation이 current sessionID로 `.aiChat` route를 생성함
    /// - 사전 조건: AiChat state에는 selected sessionID가 남아 있고 navigation route는 `.aiChatSessions(current)`인 상태
    /// - 기대 결과: AiChat state/session route가 selected session이 아닌 current session으로 복원됨
    func testAiChatSessionsRouteReplayReturnToChatUsesRouteSession() async throws {
        let currentUUID = try XCTUnwrap(UUID(uuidString: "11111111-1111-1111-1111-111111111111"))
        let selectedUUID = try XCTUnwrap(UUID(uuidString: "22222222-2222-2222-2222-222222222222"))
        let currentSessionID = currentUUID.uuidString
        let currentAiSessionID = AiChatSessionID(rawValue: currentUUID)
        let selectedAiSessionID = AiChatSessionID(rawValue: selectedUUID)

        var state = FileManagerFeature.State()
        state.content.navigation.navigationState = .aiChatSessions(currentSessionID)
        state.content.aiChat.mode = .sessions
        state.content.aiChat.sessionID = selectedAiSessionID
        state.content.aiChat.restoreSessionID = selectedAiSessionID
        state.content.aiChat.sessionList.selectedSessionID = selectedAiSessionID

        let store = TestStore(initialState: state) {
            FileManagerFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
        }
        // store.exhaustivity = .off: navigation bridge는 parent delegate 경로를 함께 방출하므로 route replay 후 AiChat route
        // anchor만 검증함
        store.exhaustivity = .off

        await store.send(.content(.internal(.applyNavigationState(.aiChatSessions(currentSessionID)))))
        await store.receive(\.content.aiChat.showSessionsForChat) { state in
            state.content.aiChat.mode = .sessions
            state.content.aiChat.sessionID = currentAiSessionID
            state.content.aiChat.restoreSessionID = nil
            state.content.aiChat.restoreOutcome = nil
            state.content.aiChat.restoreFailure = nil
            state.content.aiChat.sessionList.selectedSessionID = currentAiSessionID
        }

        XCTAssertEqual(store.state.content.aiChat.sessionID, currentAiSessionID)
        XCTAssertNotEqual(store.state.content.aiChat.sessionID, selectedAiSessionID)

        await store.send(.navigation(.view(.showAiChat(currentSessionID))))
        await store.receive { action in
            guard case let .navigation(.internal(.performShowAiChat(receivedSessionID))) = action else {
                return false
            }
            return receivedSessionID == currentSessionID
        }
        await store.receive { action in
            guard case let .navigation(.delegate(.navigateToState(.aiChat(receivedSessionID)))) = action else {
                return false
            }
            return receivedSessionID == currentSessionID
        }
        await store.receive { action in
            guard case let .content(.internal(.applyNavigationState(.aiChat(receivedSessionID)))) = action else {
                return false
            }
            return receivedSessionID == currentSessionID
        }
        await store.receive(\.content.aiChat.routeToChatSession) { state in
            state.content.aiChat.mode = .chat
        }

        XCTAssertEqual(store.state.content.navigation.navigationState, .aiChat(currentSessionID))
        XCTAssertEqual(store.state.content.aiChat.sessionID, currentAiSessionID)
        await store.finish()
    }

    /// CTM-005-ai_chat_mode_switching: History 화면 New Chat 성공 후 active tab anchor를 새 session으로 갱신함
    /// History 화면에서 New Chat 생성이 완료되면 parent navigation과 ContentTab anchor가 새 session route를 기준으로 갱신되어야 한다.
    /// - 검증 내용: `.newChatCreated` 후 `.showAiChat(newSessionID)`와 active tab `.aiChat(newSessionID)` anchor 갱신
    /// - 사전 조건: active AI Chat tab이 `.aiChatSessions(oldSessionID)` route와 old tab anchor를 가진 상태
    /// - 기대 결과: 새 session route가 Back/Forward 및 tab handoff의 기준 anchor가 됨
    func testAiChatHistoryNewChatCreatedUpdatesRouteAndActiveTabAnchor() async throws {
        let oldUUID = try XCTUnwrap(UUID(uuidString: "11111111-1111-1111-1111-111111111111"))
        let newUUID = try XCTUnwrap(UUID(uuidString: "33333333-3333-3333-3333-333333333333"))
        let oldSessionID = oldUUID.uuidString
        let newSessionID = newUUID.uuidString
        let oldAiSessionID = AiChatSessionID(rawValue: oldUUID)
        let newAiSessionID = AiChatSessionID(rawValue: newUUID)
        let tabID = ContentTabID()
        let snapshot = AiChatSessionSnapshot(
            sessionID: newAiSessionID,
            status: .idle,
            provider: nil,
            model: nil,
            transcriptHistory: [],
            updatedAtMs: 2,
        )

        var state = FileManagerFeature.State()
        state.contentTabs = ContentTabState(
            tabs: [ContentTabItem(
                id: tabID,
                page: .aiChat,
                anchor: .aiChat(sessionID: oldSessionID),
                isPinned: false,
                title: "AI Chat",
                iconName: "message",
            )],
            activeTabID: tabID,
            recentlyClosed: nil,
        )
        state.content.navigation.navigationState = .aiChatSessions(oldSessionID)
        state.content.aiChat.mode = .sessions
        state.content.aiChat.sessionID = oldAiSessionID
        state.content.aiChat.sessionStatus = .active
        state.tabContentStates = [tabID: state.content]
        state.syncContentTabSidebarItems()

        let store = TestStore(initialState: state) {
            FileManagerFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
        }
        // store.exhaustivity = .off: newChatCreated는 parent delegate와 navigation bridge 효과를 연쇄 방출하므로 route/anchor 결과만
        // 검증함
        store.exhaustivity = .off

        await store.send(.content(.aiChat(.newChatCreated(snapshot)))) { state in
            state.content.aiChat.mode = .chat
            state.content.aiChat.sessionID = newAiSessionID
            state.content.aiChat.emptyDraftSessionID = newAiSessionID
            state.content.aiChat.restoreSessionID = newAiSessionID
            state.content.aiChat.sessionList.selectedSessionID = newAiSessionID
        }
        await store.receive { action in
            guard case let .content(.delegate(.aiChatSessionCreated(receivedSessionID))) = action else { return false }
            return receivedSessionID == newAiSessionID
        }
        await store.receive { action in
            guard case let .navigation(.view(.showAiChat(receivedSessionID))) = action else { return false }
            return receivedSessionID == newSessionID
        }
        await store.receive { action in
            guard case let .contentTabs(.updateActivePageAnchor(receivedTabID, .aiChat(receivedSessionID))) = action
            else {
                return false
            }
            return receivedTabID == tabID && receivedSessionID == newSessionID
        }
        await store.receive { action in
            guard case let .navigation(.internal(.performShowAiChat(receivedSessionID))) = action else {
                return false
            }
            return receivedSessionID == newSessionID
        }
        await store.receive { action in
            guard case let .navigation(.delegate(.navigateToState(.aiChat(receivedSessionID)))) = action else {
                return false
            }
            return receivedSessionID == newSessionID
        }
        await store.receive { action in
            guard case let .content(.internal(.applyNavigationState(.aiChat(receivedSessionID)))) = action else {
                return false
            }
            return receivedSessionID == newSessionID
        }
        await store.receive { action in
            guard case let .content(.aiChat(.routeToChatSession(receivedSessionID))) = action else {
                return false
            }
            return receivedSessionID == newAiSessionID
        }

        XCTAssertEqual(store.state.contentTabs.tabs[id: tabID]?.anchor, .aiChat(sessionID: newSessionID))
        XCTAssertEqual(store.state.content.navigation.navigationState, .aiChat(newSessionID))
        XCTAssertEqual(store.state.content.aiChat.sessionID, newAiSessionID)
        await store.finish()
    }

    /// CTM-005-ai_chat_mode_switching: selected session restore 실패 시 History route를 유지함
    /// History row 선택 후 restore가 실패하면 실패한 session을 ContentPageNavigation `.aiChat(sessionID)` route로 확정하지 않아야 한다.
    /// - 검증 내용: restore failure 처리 후 navigation route와 active tab anchor가 기존 History 기준으로 유지됨
    /// - 사전 조건: `.aiChatSessions(current)` route에서 selected session restore가 pending인 상태
    /// - 기대 결과: `.sessions` mode와 `.aiChatSessions(current)` route를 유지하고 session list error만 표시함
    func testAiChatSelectedSessionRestoreFailureKeepsSessionsRoute() async throws {
        let tabID = ContentTabID()
        let currentUUID = try XCTUnwrap(UUID(uuidString: "11111111-1111-1111-1111-111111111111"))
        let selectedUUID = try XCTUnwrap(UUID(uuidString: "22222222-2222-2222-2222-222222222222"))
        let currentSessionID = currentUUID.uuidString
        let currentAiSessionID = AiChatSessionID(rawValue: currentUUID)
        let selectedAiSessionID = AiChatSessionID(rawValue: selectedUUID)

        var state = FileManagerFeature.State()
        state.contentTabs = ContentTabState(
            tabs: [ContentTabItem(
                id: tabID,
                page: .aiChat,
                anchor: .aiChat(sessionID: currentSessionID),
                isPinned: false,
                title: "AI Chat",
                iconName: "message",
            )],
            activeTabID: tabID,
            recentlyClosed: nil,
        )
        state.content.navigation.navigationState = .aiChatSessions(currentSessionID)
        state.content.aiChat.mode = .sessions
        state.content.aiChat.sessionID = currentAiSessionID
        state.content.aiChat.sessionStatus = .active
        state.content.aiChat.restoreSessionID = selectedAiSessionID
        state.content.aiChat.sessionList.selectedSessionID = selectedAiSessionID
        state.tabContentStates = [tabID: state.content]
        state.syncContentTabSidebarItems()

        let store = TestStore(initialState: state) {
            FileManagerFeature()
        }
        // store.exhaustivity = .off: 실패 restore는 parent navigation delegate를 방출하지 않는 불변식만 검증함
        store.exhaustivity = .off

        await store.send(.content(.aiChat(.restoreOutcome(
            requestedSessionID: selectedAiSessionID,
            .failed(reason: .missingRecord),
            restoreFailure: .missingRecord,
        )))) { state in
            state.content.aiChat.sessionList.selectedSessionID = nil
            state.content.aiChat.sessionList.errorMessage = "That chat is no longer available."
        }

        XCTAssertEqual(store.state.content.navigation.navigationState, .aiChatSessions(currentSessionID))
        XCTAssertEqual(store.state.contentTabs.tabs[id: tabID]?.anchor, .aiChat(sessionID: currentSessionID))
        XCTAssertEqual(store.state.content.aiChat.mode, .sessions)
        XCTAssertEqual(store.state.content.aiChat.sessionID, currentAiSessionID)
        await store.finish()
    }

    /// CTM-005-ai_chat_mode_switching: AI Chat History에서 selected session restore 성공 후 route가 기록됨
    /// session row 선택은 restore를 먼저 완료하고 성공한 session만 ContentPageNavigation `.aiChat(sessionID)` route로 확정해야 한다.
    /// - 검증 내용: selected session restore 성공 후 Back/Back이 selected chat → History → 이전 chat 순서로 복원됨
    /// - 사전 조건: `.aiChatSessions(current)` route와 이전 `.aiChat(current)` history가 있는 상태
    /// - 기대 결과: restore 성공 전에는 sessions route를 유지하고, 성공 후 selected session route와 sessions route가 history에 시간순으로 남음
    func testAiChatSelectedSessionRouteParticipatesInCompositeNavigationHistory() async throws {
        let tabID = ContentTabID()
        let currentUUID = try XCTUnwrap(UUID(uuidString: "E621E1F8-C36C-495A-93FC-0C247A3E6E5F"))
        let selectedUUID = try XCTUnwrap(UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE"))
        let currentSessionID = currentUUID.uuidString
        let selectedSessionID = selectedUUID.uuidString
        let currentAiSessionID = AiChatSessionID(rawValue: currentUUID)
        let selectedAiSessionID = AiChatSessionID(rawValue: selectedUUID)
        let selectedSnapshot = AiChatSessionSnapshot(
            sessionID: selectedAiSessionID,
            status: .active,
            provider: nil,
            model: nil,
            transcriptHistory: [AiChatMessage(role: .user, content: "selected")],
            updatedAtMs: 2,
        )
        var state = FileManagerFeature.State()
        state.contentTabs = ContentTabState(
            tabs: [ContentTabItem(
                id: tabID,
                page: .aiChat,
                anchor: .aiChat(sessionID: currentSessionID),
                isPinned: false,
                title: "AI Chat",
                iconName: "message",
            )],
            activeTabID: tabID,
            recentlyClosed: nil,
        )
        state.content.navigation.navigationState = .aiChatSessions(currentSessionID)
        state.content.navigation.backHistory = [
            ContentPageNavigationHistorySnapshot(navigationState: .home),
            ContentPageNavigationHistorySnapshot(navigationState: .aiChat(currentSessionID)),
        ]
        state.content.aiChat.mode = .sessions
        state.content.aiChat.sessionID = currentAiSessionID
        state.content.aiChat.sessionStatus = .active
        state.content.aiChat.sessionList.allRows = [
            AiChatSessionSummary(
                sessionID: selectedAiSessionID,
                title: "Selected session",
                messageCount: 1,
                provider: nil,
                model: nil,
                createdAtMs: 1,
                updatedAtMs: 2,
                status: .active,
            ),
        ]
        state.content.aiChat.sessionList.rows = state.content.aiChat.sessionList.allRows
        state.tabContentStates = [tabID: state.content]
        state.syncContentTabSidebarItems()

        let store = TestStore(initialState: state) {
            FileManagerFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
            $0.uuid = .incrementing
            $0.aiChatSessionPersistenceClient.loadSession = { sessionID in
                sessionID == selectedAiSessionID ? selectedSnapshot : nil
            }
        }
        // store.exhaustivity = .off: selected session restore 성공 delegate와 navigation delegate가 함께 방출되므로 composite
        // route 순서만 검증함
        store.exhaustivity = .off

        await store.send(.content(.aiChat(.sessionRowTapped(selectedAiSessionID)))) { state in
            state.content.aiChat.mode = .sessions
            state.content.aiChat.restoreSessionID = selectedAiSessionID
            state.content.aiChat.sessionList.selectedSessionID = selectedAiSessionID
        }

        XCTAssertEqual(store.state.content.navigation.navigationState, .aiChatSessions(currentSessionID))

        await store.receive(\.content.aiChat.restoreOutcome)
        XCTAssertEqual(store.state.content.aiChat.mode, .chat)
        XCTAssertEqual(store.state.content.aiChat.sessionID, selectedAiSessionID)
        XCTAssertEqual(store.state.content.aiChat.sessionStatus, .active)
        XCTAssertEqual(store.state.content.aiChat.restoreSessionID, selectedAiSessionID)
        XCTAssertEqual(store.state.content.aiChat.restoreOutcome, .restored(snapshot: selectedSnapshot))
        XCTAssertNil(store.state.content.aiChat.restoreFailure)
        XCTAssertEqual(store.state.content.aiChat.transcriptHistory, selectedSnapshot.transcriptHistory)
        XCTAssertNil(store.state.content.aiChat.emptyDraftSessionID)
        XCTAssertNil(store.state.content.aiChat.sessionList.errorMessage)
        await store.receive { action in
            guard case let .content(.delegate(.aiChatSessionRestored(receivedSessionID))) = action else { return false }
            return receivedSessionID == selectedAiSessionID
        }
        await store.receive { action in
            guard case let .navigation(.view(.showAiChat(receivedSessionID))) = action else { return false }
            return receivedSessionID == selectedSessionID
        }
        await store.receive { action in
            guard case let .contentTabs(.updateActivePageAnchor(receivedTabID, .aiChat(receivedSessionID))) = action
            else {
                return false
            }
            return receivedTabID == tabID && receivedSessionID == selectedSessionID
        }
        await store.receive { action in
            guard case let .navigation(.internal(.performShowAiChat(receivedSessionID))) = action else {
                return false
            }
            return receivedSessionID == selectedSessionID
        }
        await store.receive { action in
            guard case let .navigation(.delegate(.navigateToState(.aiChat(receivedSessionID)))) = action else {
                return false
            }
            return receivedSessionID == selectedSessionID
        }
        await store.receive { action in
            guard case let .content(.internal(.applyNavigationState(.aiChat(receivedSessionID)))) = action else {
                return false
            }
            return receivedSessionID == selectedSessionID
        }
        await store.receive { action in
            guard case let .content(.aiChat(.routeToChatSession(receivedSessionID))) = action else {
                return false
            }
            return receivedSessionID == selectedAiSessionID
        }

        XCTAssertEqual(store.state.content.navigation.navigationState, .aiChat(selectedSessionID))
        XCTAssertEqual(
            store.state.content.navigation.backHistory.map(\.navigationState),
            [.home, .aiChat(currentSessionID), .aiChatSessions(currentSessionID)],
        )
        XCTAssertEqual(store.state.content.navigation.forwardHistory.map(\.navigationState), [])

        await store.send(.navigation(.view(.goBack)))
        await store.receive(\.navigation.internal.performNavigation)
        await store.receive { action in
            guard case let .navigation(.delegate(.navigateToState(.aiChatSessions(receivedSessionID)))) = action else {
                return false
            }
            return receivedSessionID == currentSessionID
        }
        await store.receive { action in
            guard case let .content(.internal(.applyNavigationState(.aiChatSessions(receivedSessionID)))) = action
            else {
                return false
            }
            return receivedSessionID == currentSessionID
        }
        await store.receive(\.content.aiChat.showSessionsForChat)

        XCTAssertEqual(store.state.content.navigation.navigationState, .aiChatSessions(currentSessionID))
        XCTAssertEqual(
            store.state.content.navigation.backHistory.map(\.navigationState),
            [.home, .aiChat(currentSessionID)],
        )
        XCTAssertEqual(
            store.state.content.navigation.forwardHistory.map(\.navigationState),
            [.aiChat(selectedSessionID)],
        )
        XCTAssertEqual(store.state.content.aiChat.mode, .sessions)

        // 기존 세션에서 목록으로 돌아온 뒤 다시 Back하면 route에 저장된 직전 새 채팅으로 복귀해야 한다.
        await store.send(.navigation(.view(.goBack)))
        await store.receive(\.navigation.internal.performNavigation)
        await store.receive { action in
            guard case let .navigation(.delegate(.navigateToState(.aiChat(receivedSessionID)))) = action else {
                return false
            }
            return receivedSessionID == currentSessionID
        }
        await store.receive { action in
            guard case let .content(.internal(.applyNavigationState(.aiChat(receivedSessionID)))) = action else {
                return false
            }
            return receivedSessionID == currentSessionID
        }
        await store.receive { action in
            guard case let .content(.aiChat(.routeToChatSession(receivedSessionID))) = action else {
                return false
            }
            return receivedSessionID == currentAiSessionID
        }

        XCTAssertEqual(store.state.content.navigation.navigationState, .aiChat(currentSessionID))
        XCTAssertEqual(store.state.content.navigation.backHistory.map(\.navigationState), [.home])
        XCTAssertEqual(
            store.state.content.navigation.forwardHistory.map(\.navigationState),
            [.aiChat(selectedSessionID), .aiChatSessions(currentSessionID)],
        )
        XCTAssertEqual(store.state.content.aiChat.mode, .chat)
        XCTAssertEqual(store.state.content.aiChat.sessionID, currentAiSessionID)
        await store.finish()
    }

    /// CTM-005-ai_chat_mode_switching: 진행 중인 현재 세션 row 선택 시 Chat route로 승격됨
    /// History에서 현재 실행 중인 세션을 다시 선택하는 shortcut도 parent navigation anchor를 `.aiChat`으로 확정해야 한다.
    /// - 검증 내용: current processing session tap이 restore 성공과 동일한 route/anchor 갱신 체인을 방출함
    /// - 사전 조건: `.aiChatSessions(current)` route와 processing 상태의 현재 AI Chat 세션
    /// - 기대 결과: Chat mode 전환 후 active tab anchor와 navigation state가 `.aiChat(current)`로 승격
    func testAiChatProcessingSessionTapPromotesRouteFromSessionsToChat() async throws {
        let tabID = ContentTabID()
        let currentUUID = try XCTUnwrap(UUID(uuidString: "E621E1F8-C36C-495A-93FC-0C247A3E6E5F"))
        let currentSessionID = currentUUID.uuidString
        let currentAiSessionID = AiChatSessionID(rawValue: currentUUID)
        let modelHandle = AiModelHandle(provider: .openai, rawValue: "gpt-4.1-mini")
        let catalogRow = AiModelCatalogRow(
            handle: modelHandle,
            displayName: "GPT-4.1 Mini",
            authMethod: .apiKey,
            sortOrder: 10,
        )
        let requestID =
            try AiChatRequestID(rawValue: XCTUnwrap(UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")))
        let runID = try AiChatRunID(rawValue: XCTUnwrap(UUID(uuidString: "BBBBBBBB-CCCC-DDDD-EEEE-FFFFFFFFFFFF")))
        let requestContext = AiChatRequestContextSnapshot(
            sessionID: currentAiSessionID,
            requestID: requestID,
            runID: runID,
            provider: .openai,
            model: modelHandle,
            selectedModel: AiProviderModel(
                id: modelHandle,
                provider: .openai,
                rawModelID: "gpt-4.1-mini",
                displayName: "GPT-4.1 Mini",
                providerDisplayName: "OpenAI",
                thinkingCapability: .unknown(reason: .init(message: "Not loaded")),
            ),
            selectedModelRow: catalogRow,
            sessionStatus: .active,
            promptSummary: "continue",
            submittedAtMs: 1234,
        )
        let request = AiChatRequest(
            context: requestContext,
            messages: [AiChatMessage(role: .user, content: "continue")],
        )
        let requestLock = AiChatRequestLock(
            kind: .submit,
            requestID: requestID,
            runID: runID,
            context: requestContext,
            request: request,
            selectedModelHandle: modelHandle,
            selectedModelRow: catalogRow,
            assistantReplacementIndex: nil,
        )

        var state = FileManagerFeature.State()
        state.contentTabs = ContentTabState(
            tabs: [ContentTabItem(
                id: tabID,
                page: .aiChat,
                anchor: .aiChat(sessionID: currentSessionID),
                isPinned: false,
                title: "AI Chat",
                iconName: "message",
            )],
            activeTabID: tabID,
            recentlyClosed: nil,
        )
        state.content.navigation.navigationState = .aiChatSessions(currentSessionID)
        state.content.aiChat.mode = .sessions
        state.content.aiChat.sessionID = currentAiSessionID
        state.content.aiChat.sessionStatus = .active
        state.content.aiChat.executionPhase = .processing(requestLock)
        state.content.aiChat.sessionList.allRows = [
            AiChatSessionSummary(
                sessionID: currentAiSessionID,
                title: "Current session",
                messageCount: 1,
                provider: .openai,
                model: modelHandle,
                createdAtMs: 1,
                updatedAtMs: 2,
                status: .active,
            ),
        ]
        state.content.aiChat.sessionList.rows = state.content.aiChat.sessionList.allRows
        state.tabContentStates = [tabID: state.content]
        state.syncContentTabSidebarItems()

        let store = TestStore(initialState: state) {
            FileManagerFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
            $0.uuid = .incrementing
        }
        store.exhaustivity = .off

        await store.send(.content(.aiChat(.sessionRowTapped(currentAiSessionID)))) { state in
            state.content.aiChat.mode = .chat
        }
        await store.receive { action in
            guard case let .content(.delegate(.aiChatSessionRestored(receivedSessionID))) = action else { return false }
            return receivedSessionID == currentAiSessionID
        }
        await store.receive { action in
            guard case let .navigation(.view(.showAiChat(receivedSessionID))) = action else { return false }
            return receivedSessionID == currentSessionID
        }
        await store.receive { action in
            guard case let .contentTabs(.updateActivePageAnchor(receivedTabID, .aiChat(receivedSessionID))) = action
            else { return false }
            return receivedTabID == tabID && receivedSessionID == currentSessionID
        }
        await store.receive { action in
            guard case let .navigation(.internal(.performShowAiChat(receivedSessionID))) = action else { return false }
            return receivedSessionID == currentSessionID
        }
        await store.receive { action in
            guard case let .navigation(.delegate(.navigateToState(.aiChat(receivedSessionID)))) = action else {
                return false
            }
            return receivedSessionID == currentSessionID
        }
        await store.receive { action in
            guard case let .content(.internal(.applyNavigationState(.aiChat(receivedSessionID)))) = action else {
                return false
            }
            return receivedSessionID == currentSessionID
        }
        await store.receive(\.content.entryViewLayout.internal.clearCollectionPresentation)
        await store.receive(\.content.entryViewLayout.internal.applyClearSelection)
        await store.receive(\.content.entryViewLayout.entryOperations.loading.itemsLoaded)
        await store.receive { action in
            guard case let .content(.aiChat(.routeToChatSession(receivedSessionID))) = action else { return false }
            return receivedSessionID == currentAiSessionID
        }

        XCTAssertEqual(store.state.content.navigation.navigationState, .aiChat(currentSessionID))
        XCTAssertEqual(store.state.contentTabs.tabs[id: tabID]?.anchor, .aiChat(sessionID: currentSessionID))
        XCTAssertEqual(store.state.content.aiChat.mode, .chat)
        XCTAssertEqual(store.state.content.aiChat.executionPhase, .processing(requestLock))
        await store.finish()
    }

    /// ContentPane AI Chat Settings 버튼 delegate가 Window delegate까지 전달됨
    /// provider 미연결 empty state의 Open Settings 버튼은 AiChatFeature delegate를 거쳐
    /// FileManagerContentFeature와 WindowCommandRoutingReducer를 통과해야 실제 Settings를 연다.
    /// - 검증 내용: .content(.aiChat(.openSettingsTapped)) 전송 후 .delegate(.openAISettings) 수신
    /// - 기대 결과: ContentPane AI Chat에서도 Inspector Chat과 동일하게 Settings 열기 delegate가 전파됨
    func testContentPaneAiChatOpenSettingsRoutesToWindowDelegate() async {
        var state = FileManagerFeature.State()
        state.content.aiChat.mode = .chat
        state.contentTabs = ContentTabState(
            tabs: [ContentTabItem(
                id: ContentTabID(),
                page: .aiChat,
                anchor: .aiChat(sessionID: "test-session"),
                isPinned: false,
                title: "AI Chat",
                iconName: "message",
            )],
            activeTabID: ContentTabID(),
            recentlyClosed: nil,
        )
        state.syncContentTabSidebarItems()

        let store = TestStore(initialState: state) {
            FileManagerFeature()
        }
        store.exhaustivity = .off

        await store.send(.content(.aiChat(.openSettingsTapped)))
        await store.receive { action in
            guard case .content(.delegate(.openAISettings)) = action else { return false }
            return true
        }
        await store.receive { action in
            guard case .delegate(.openAISettings) = action else { return false }
            return true
        }
        await store.finish()
    }

    /// 저장된 content state가 없는 AI Chat tab은 첫 렌더 전에 .chat mode로 초기화된다.
    /// 기본 AiChatState(.sessions)가 먼저 렌더링되면 History/No Sessions 화면이 순간 노출되므로,
    /// missing tab state 복원 경로에서 ContentPane AI Chat을 즉시 채팅 화면으로 맞춘다.
    func testSwitchingToNewAiChatTabInitializesChatModeBeforeRender() async {
        let homeID = ContentTabID()
        let aiChatID = ContentTabID()
        let sessionID = "new-ai-chat-tab-session"
        var homeContent = FileManagerContentFeature.State()
        homeContent.navigation.seedInitialFolderPath("/Users/test/Home")

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
                    id: aiChatID,
                    page: .aiChat,
                    anchor: .aiChat(sessionID: sessionID),
                    isPinned: false,
                    title: "AI Chat",
                    iconName: "message",
                ),
            ],
            activeTabID: homeID,
            recentlyClosed: nil,
        )
        state.content = homeContent
        state.tabContentStates = [homeID: homeContent]
        state.syncContentTabSidebarItems()

        let store = TestStore(initialState: state) {
            FileManagerFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
            $0.uuid = .incrementing
            $0.entryWatchingClient.startWatchingDirectory = { _ in
                AsyncStream { continuation in
                    continuation.finish()
                }
            }
        }
        store.exhaustivity = .off

        await store.send(.contentTabs(.setCurrent(aiChatID)))

        XCTAssertEqual(store.state.content.aiChat.mode, .chat)
        XCTAssertEqual(
            store.state.tabContentStates[aiChatID]?.navigation.navigationState,
            .aiChat(sessionID),
            "AI Chat tab restore must expose an AI Chat navigation route before render",
        )
        XCTAssertEqual(store.state.tabContentStates[aiChatID]?.aiChat.mode, .chat)
        XCTAssertEqual(store.state.contentTabs.tabs[id: aiChatID]?.anchor, .aiChat(sessionID: sessionID))
        await store.finish()
    }

    /// AI Chat tab은 Inspector를 지원하지 않으므로 active Inspector projection을 숨긴다.
    func testSwitchingToAiChatTabHidesOpenInspectorChat() async {
        let homeID = ContentTabID()
        let aiChatID = ContentTabID()
        var homeContent = FileManagerContentFeature.State()
        homeContent.navigation.seedInitialFolderPath("/Users/test/Home")

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
                    id: aiChatID,
                    page: .aiChat,
                    anchor: .aiChat(sessionID: "inspector-close-session"),
                    isPinned: false,
                    title: "AI Chat",
                    iconName: "message",
                ),
            ],
            activeTabID: homeID,
            recentlyClosed: nil,
        )
        state.content = homeContent
        state.tabContentStates = [homeID: homeContent]
        state.inspector.inspectorVisible = true
        state.inspector.inspectorPaneExists = true
        state.inspector.activeMode = .chat
        state.syncContentTabSidebarItems()

        let store = TestStore(initialState: state) {
            FileManagerFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
            $0.uuid = .incrementing
            $0.entryWatchingClient.startWatchingDirectory = { _ in
                AsyncStream { continuation in
                    continuation.finish()
                }
            }
        }
        store.exhaustivity = .off

        await store.send(.contentTabs(.setCurrent(aiChatID)))

        XCTAssertFalse(store.state.inspector.inspectorVisible)
        XCTAssertNil(store.state.tabInspectorStates[aiChatID])
        XCTAssertEqual(store.state.content.aiChat.mode, .chat)
        await store.finish()
    }

    /// CTM-005-ai_chat_provider_forwarding: navigation replay로 AI Chat route가 복원될 때 Inspector Chat을 닫음
    /// Back/Forward replay는 tab handoff를 거치지 않고 active tab anchor만 갱신하므로 Inspector Chat close를 anchor sync 경로에서 보장해야
    /// 한다.
    /// - 검증 내용: `.aiChat` navigation delegate가 active tab anchor를 갱신하기 전에 Inspector Chat close를 방출함
    /// - 사전 조건: Home tab에서 Inspector Chat이 열린 상태로 `.aiChat(sessionID)` route replay가 들어옴
    /// - 기대 결과: Inspector Chat이 닫히고 active tab anchor가 AI Chat session으로 갱신됨
    func testAiChatNavigationReplayClosesOpenInspectorChat() async {
        let homeID = ContentTabID()
        let sessionID = "inspector-replay-session"
        var homeContent = FileManagerContentFeature.State()
        homeContent.navigation.seedInitialFolderPath("/Users/test/Home")

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
            ],
            activeTabID: homeID,
            recentlyClosed: nil,
        )
        state.content = homeContent
        state.inspector.inspectorVisible = true
        state.inspector.inspectorPaneExists = true
        state.inspector.activeMode = .chat
        state.syncContentTabSidebarItems()

        let store = TestStore(initialState: state) {
            FileManagerFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
            $0.uuid = .incrementing
        }
        store.exhaustivity = .off

        await store.send(.navigation(.delegate(.navigateToState(.aiChat(sessionID)))))
        await store.receive { action in
            guard case .inspector(.closeChat) = action else { return false }
            return true
        } assert: { state in
            state.inspector.inspectorVisible = false
        }
        await store.receive { action in
            guard case let .contentTabs(.updateActivePageAnchor(receivedTabID, .aiChat(receivedSessionID))) = action
            else { return false }
            return receivedTabID == homeID && receivedSessionID == sessionID
        }
        await store.receive { action in
            guard case let .content(.internal(.applyNavigationState(.aiChat(receivedSessionID)))) = action
            else { return false }
            return receivedSessionID == sessionID
        }
        XCTAssertEqual(store.state.contentTabs.tabs[id: homeID]?.anchor, .aiChat(sessionID: sessionID))
        XCTAssertFalse(store.state.inspector.inspectorVisible)
        await store.finish()
    }

    /// .aiChat route로 전환된 tab은 navigation/entry chrome을 표시하지 않음
    /// FileManagerContentPaneView에서 .aiChat anchor는 homeDefault나 directory/collection과 달리
    /// ToolbarView/ContentPageView/BreadcrumbBarView를 렌더링하지 않고 AiChatPageView만 렌더링한다.
    /// resyncNavigationStateForActiveContentTab가 .aiChat을 .home으로 매핑하지 않음을 간접 검증한다.
    /// - 검증 내용: .aiChat tab 전환 후 content.navigation.navigationState가 .home으로 reset되지 않고
    ///   tab anchor가 .aiChat을 유지함
    /// - 사전 조건: Directory anchor tab에서 .aiChat tab으로 전환
    /// - 기대 결과: AI Chat tab anchor 유지, navigation state가 .home으로 overwrite되지 않음
    func testAiChatRouteHidesFolderChrome() async {
        let aiChatID = ContentTabID()
        let homeID = ContentTabID()
        let sessionID = "chrome-test-session"

        var aiChatContent = FileManagerContentFeature.State()
        aiChatContent.aiChat.mode = .chat
        aiChatContent.aiChat.sessionID = AiChatSessionID(rawValue: UUID())
        aiChatContent.aiChat.sessionStatus = .active

        var homeContent = FileManagerContentFeature.State()
        homeContent.navigation.seedInitialFolderPath("/Users/test/Home")

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
                    id: aiChatID,
                    page: .aiChat,
                    anchor: .aiChat(sessionID: sessionID),
                    isPinned: false,
                    title: "AI Chat",
                    iconName: "message",
                ),
            ],
            activeTabID: homeID,
            recentlyClosed: nil,
        )
        state.content = homeContent
        state.tabContentStates = [homeID: homeContent, aiChatID: aiChatContent]
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

        // Home → AI Chat tab으로 전환
        await store.send(.contentTabs(.setCurrent(aiChatID)))

        // .aiChat tab anchor 유지 (resync가 .home으로 overwrite하지 않음)
        XCTAssertEqual(store.state.contentTabs.activeTabID, aiChatID)
        XCTAssertEqual(store.state.contentTabs.tabs[id: aiChatID]?.anchor, .aiChat(sessionID: sessionID))
        XCTAssertEqual(store.state.contentTabs.tabs[id: aiChatID]?.page, .aiChat)

        // resyncNavigationStateForActiveContentTab가 .aiChat에 대해 nil을 반환하므로
        // navigation state가 directory/home path로 overwrite되지 않음
        guard let restoredAiChatContent = store.state.tabContentStates[aiChatID] else {
            XCTFail("AI Chat tab content should be preserved in tabContentStates")
            return
        }
        XCTAssertEqual(restoredAiChatContent.aiChat.mode, .chat)
        XCTAssertEqual(restoredAiChatContent.aiChat.sessionStatus, .active)
        XCTAssertNotNil(restoredAiChatContent.aiChat.sessionID)
        await store.finish()
    }

    func testActiveAiChatPageCloseDoesNotCancelGeneration() async throws {
        let aiChatTabID = ContentTabID()
        let homeTabID = ContentTabID()
        let sessionUUID = try XCTUnwrap(UUID(uuidString: "E621E1F8-C36C-495A-93FC-0C247A3E6E5F"))
        let sessionID = sessionUUID.uuidString
        let aiSessionID = AiChatSessionID(rawValue: sessionUUID)
        let modelHandle = AiModelHandle(provider: .openai, rawValue: "gpt-4.1-mini")
        let catalogRow = AiModelCatalogRow(
            handle: modelHandle,
            displayName: "GPT-4.1 Mini",
            authMethod: .apiKey,
            sortOrder: 10,
        )
        let requestID = try AiChatRequestID(
            rawValue: XCTUnwrap(UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")),
        )
        let runID = try AiChatRunID(
            rawValue: XCTUnwrap(UUID(uuidString: "BBBBBBBB-CCCC-DDDD-EEEE-FFFFFFFFFFFF")),
        )
        let requestContext = AiChatRequestContextSnapshot(
            sessionID: aiSessionID,
            requestID: requestID,
            runID: runID,
            provider: .openai,
            model: modelHandle,
            selectedModel: AiProviderModel(
                id: modelHandle,
                provider: .openai,
                rawModelID: "gpt-4.1-mini",
                displayName: "GPT-4.1 Mini",
                providerDisplayName: "OpenAI",
                thinkingCapability: .unknown(reason: .init(message: "Not loaded")),
            ),
            selectedModelRow: catalogRow,
            sessionStatus: .active,
            promptSummary: "test",
            submittedAtMs: 0,
        )
        let request = AiChatRequest(
            context: requestContext,
            messages: [AiChatMessage(role: .user, content: "test")],
        )
        let requestLock = AiChatRequestLock(
            kind: .submit,
            requestID: requestID,
            runID: runID,
            context: requestContext,
            request: request,
            selectedModelHandle: modelHandle,
            selectedModelRow: catalogRow,
            assistantReplacementIndex: nil,
        )

        var aiChatContent = FileManagerContentFeature.State()
        aiChatContent.navigation.navigationState = .aiChat(sessionID)
        aiChatContent.aiChat.mode = .chat
        aiChatContent.aiChat.sessionID = aiSessionID
        aiChatContent.aiChat.sessionStatus = .active
        aiChatContent.aiChat.executionPhase = .processing(requestLock)

        var homeContent = FileManagerContentFeature.State()
        homeContent.navigation.seedInitialFolderPath("/Users/test/Home")

        var state = FileManagerFeature.State()
        state.contentTabs = ContentTabState(
            tabs: [
                ContentTabItem(
                    id: aiChatTabID,
                    page: .aiChat,
                    anchor: .aiChat(sessionID: sessionID),
                    isPinned: false,
                    title: "AI Chat",
                    iconName: "sparkles",
                ),
                ContentTabItem(
                    id: homeTabID,
                    page: .home,
                    anchor: .homeDefault,
                    isPinned: false,
                    title: "Home",
                    iconName: "house",
                ),
            ],
            activeTabID: aiChatTabID,
            recentlyClosed: nil,
        )
        state.content = aiChatContent
        state.tabContentStates = [homeTabID: homeContent]
        state.syncContentTabSidebarItems()

        let store = TestStore(initialState: state) {
            FileManagerFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
            $0.uuid = .incrementing
            $0.entryWatchingClient.startWatchingDirectory = { _ in
                AsyncStream { continuation in
                    continuation.finish()
                }
            }
        }
        store.exhaustivity = .off

        await store.send(.contentTabs(.close(aiChatTabID)))

        await store.receive(\.content.internal.applyNavigationState)

        await store.skipReceivedActions()
        await store.finish()

        let savedBackgroundState = store.state.backgroundAiChatStates[aiSessionID]
        XCTAssertNotNil(savedBackgroundState, "processing AI Chat state should be saved to background")
        XCTAssertEqual(savedBackgroundState?.aiChat.executionPhase, .processing(requestLock))
    }
}

@MainActor
extension CTM005IndependentContentTabSessionTests {
    func testInspectorClosePreservesInspectorGenerationWhileContentAiChatIsProcessing() async {
        let contentSessionID = AiChatSessionID(rawValue: UUID())
        let inspectorSessionID = AiChatSessionID(rawValue: UUID())
        let contentLock = makeRequestLock(sessionID: contentSessionID)
        let inspectorLock = makeRequestLock(sessionID: inspectorSessionID)

        var contentState = FileManagerContentFeature.State()
        contentState.aiChat.sessionID = contentSessionID
        contentState.aiChat.sessionStatus = .active
        contentState.aiChat.executionPhase = .processing(contentLock)

        var state = FileManagerFeature.State()
        state.content = contentState
        state.inspector.inspectorVisible = true
        state.inspector.inspectorPaneExists = true
        state.inspector.activeMode = .chat
        state.inspector.aiChat.sessionID = inspectorSessionID
        state.inspector.aiChat.sessionStatus = .active
        state.inspector.aiChat.executionPhase = .processing(inspectorLock)
        state.inspector.aiChat.lockedModelHandle = inspectorLock.selectedModelHandle

        let homeID = ContentTabID()
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
        state.syncContentTabSidebarItems()

        let store = TestStore(initialState: state) {
            FileManagerFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
        }
        store.exhaustivity = .off

        await store.send(.inspector(.closeChat)) { state in
            state.inspector.inspectorVisible = false
        }

        XCTAssertTrue(store.state.content.aiChat.executionPhase.isProcessing)
        XCTAssertEqual(store.state.content.aiChat.sessionID, contentSessionID)
        XCTAssertEqual(store.state.inspector.aiChat.executionPhase, .processing(inspectorLock))
        XCTAssertEqual(store.state.inspector.aiChat.sessionID, inspectorSessionID)
        XCTAssertEqual(store.state.inspector.aiChat.lockedModelHandle, inspectorLock.selectedModelHandle)

        await store.finish()
    }

    func testExplicitCancelTappedCancelsContentAiChatGeneration() async {
        let contentSessionID = AiChatSessionID(rawValue: UUID())
        let contentLock = makeRequestLock(sessionID: contentSessionID)

        var contentState = FileManagerContentFeature.State()
        contentState.aiChat.sessionID = contentSessionID
        contentState.aiChat.sessionStatus = .active
        contentState.aiChat.executionPhase = .processing(contentLock)
        contentState.aiChat.lockedModelHandle = contentLock.selectedModelHandle

        var state = FileManagerFeature.State()
        state.content = contentState

        let homeID = ContentTabID()
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
        state.syncContentTabSidebarItems()

        let store = TestStore(initialState: state) {
            FileManagerFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
        }
        store.exhaustivity = .off

        await store.send(.content(.aiChat(.cancelTapped)))

        guard case .cancelled = store.state.content.aiChat.executionPhase else {
            XCTFail(
                "Expected cancelled execution phase after cancelTapped, got \(store.state.content.aiChat.executionPhase)",
            )
            return
        }
        XCTAssertNil(store.state.content.aiChat.lockedModelHandle)
        XCTAssertNil(store.state.content.aiChat.streamingAssistantDraft)

        await store.finish()
    }

    func testContentPaneCancelDoesNotRemoveBackgroundAiChatState() async {
        let homeTabID = ContentTabID()
        let aiSessionID = AiChatSessionID(rawValue: UUID())
        let requestLock = makeRequestLock(sessionID: aiSessionID)

        var backgroundContent = FileManagerContentFeature.State()
        backgroundContent.aiChat.sessionID = aiSessionID
        backgroundContent.aiChat.sessionStatus = .active
        backgroundContent.aiChat.executionPhase = .processing(requestLock)
        backgroundContent.aiChat.lockedModelHandle = requestLock.selectedModelHandle

        var homeContent = FileManagerContentFeature.State()
        homeContent.navigation.seedInitialFolderPath("/Users/test/Home")

        var state = FileManagerFeature.State()
        state.contentTabs = ContentTabState(
            tabs: [
                ContentTabItem(
                    id: homeTabID,
                    page: .home,
                    anchor: .homeDefault,
                    isPinned: false,
                    title: "Home",
                    iconName: "house",
                ),
            ],
            activeTabID: homeTabID,
            recentlyClosed: nil,
        )
        state.content = homeContent
        state.tabContentStates = [homeTabID: homeContent]
        state.backgroundAiChatStates[aiSessionID] = backgroundContent
        state.syncContentTabSidebarItems()

        let store = TestStore(initialState: state) {
            FileManagerFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
            $0.uuid = .incrementing
        }
        store.exhaustivity = .off

        await store.send(.content(.aiChat(.cancelInFlightWork)))

        XCTAssertNotNil(store.state.backgroundAiChatStates[aiSessionID])
        XCTAssertEqual(
            store.state.backgroundAiChatStates[aiSessionID]?.aiChat.executionPhase,
            .processing(requestLock),
        )
        await store.finish()
    }

    func testClosedAiChatFinalEventSavesSnapshotThroughBackgroundState() async {
        let aiChatTabID = ContentTabID()
        let homeTabID = ContentTabID()
        let aiSessionID = AiChatSessionID(rawValue: UUID())
        let requestLock = makeRequestLock(sessionID: aiSessionID)
        let savedSnapshots = LockIsolated<[AiChatSessionSnapshot]>([])

        var aiChatContent = FileManagerContentFeature.State()
        aiChatContent.aiChat.sessionID = aiSessionID
        aiChatContent.aiChat.sessionStatus = .active
        aiChatContent.aiChat.executionPhase = .processing(requestLock)
        aiChatContent.aiChat.lockedModelHandle = requestLock.selectedModelHandle
        aiChatContent.aiChat.transcriptHistory = [
            AiChatMessage(role: .user, content: "test"),
        ]

        let homeContent = FileManagerContentFeature.State()

        var state = FileManagerFeature.State()
        state.contentTabs = ContentTabState(
            tabs: [
                ContentTabItem(
                    id: aiChatTabID,
                    page: .aiChat,
                    anchor: .aiChat(sessionID: aiSessionID.rawValue.uuidString),
                    isPinned: false,
                    title: "AI Chat",
                    iconName: "message",
                ),
                ContentTabItem(
                    id: homeTabID,
                    page: .home,
                    anchor: .homeDefault,
                    isPinned: false,
                    title: "Home",
                    iconName: "house",
                ),
            ],
            activeTabID: aiChatTabID,
            recentlyClosed: nil,
        )
        state.content = aiChatContent
        state.tabContentStates = [homeTabID: homeContent]
        state.syncContentTabSidebarItems()

        let store: TestStore<FileManagerFeature.State, FileManagerWindowAction> = TestStore(initialState: state) {
            FileManagerFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
            $0.uuid = .incrementing
            $0.entryWatchingClient.startWatchingDirectory = { _ in
                AsyncStream { continuation in
                    continuation.finish()
                }
            }
            $0.aiChatSessionPersistenceClient.saveSession = { snapshot in
                savedSnapshots.withValue { $0.append(snapshot) }
                return snapshot
            }
        }
        store.exhaustivity = .off

        await store.send(.contentTabs(.close(aiChatTabID)))
        await store.receive(\.content.internal.applyNavigationState)
        await store.skipReceivedActions()

        XCTAssertNotNil(store.state.backgroundAiChatStates[aiSessionID])
        XCTAssertTrue(store.state.content.aiChat.sessionList.rows.isEmpty)

        let response = AiChatResponse(
            context: requestLock.context,
            assistantMessage: AiChatMessage(role: .assistant, content: "done"),
            completedAtMs: 1_234_567_891_000,
        )

        await store.send(.content(.aiChat(.executionEvent(.final(response: response)))))

        await store.receive { action in
            guard case let .backgroundAiChatSnapshotPersisted(snapshot) = action else { return false }
            let summary = AiChatSessionSummary(snapshot: snapshot)
            return summary.sessionID == aiSessionID
        } assert: { state in
            state.backgroundAiChatStates.removeValue(forKey: aiSessionID)
        }

        await store.finish()

        let snapshots = savedSnapshots.value
        XCTAssertEqual(snapshots.count, 1)
        XCTAssertEqual(snapshots.first?.sessionID, aiSessionID)
        XCTAssertEqual(snapshots.first?.transcriptHistory.map(\.content), ["test", "done"])
        XCTAssertFalse(store.state.content.aiChat.sessionList.rows.contains { $0.sessionID == aiSessionID })
        XCTAssertNil(store.state.backgroundAiChatStates[aiSessionID])
    }

    func testClosingAiChatTabPreservesBackgroundExecutionPhasesAndHandlesFinalEvent() async {
        let aiChatTabID = ContentTabID()
        let homeTabID = ContentTabID()
        let aiSessionID = AiChatSessionID(rawValue: UUID())
        let requestLock = makeRequestLock(sessionID: aiSessionID)
        let savedSnapshots = LockIsolated<[AiChatSessionSnapshot]>([])

        var aiChatContent = FileManagerContentFeature.State()
        aiChatContent.aiChat.sessionID = aiSessionID
        aiChatContent.aiChat.sessionStatus = .active
        aiChatContent.aiChat.executionPhase = .idle
        aiChatContent.aiChat.backgroundExecutionPhases[requestLock.requestID] = .processing(requestLock)
        aiChatContent.aiChat.lockedModelHandle = requestLock.selectedModelHandle
        aiChatContent.aiChat.transcriptHistory = [
            AiChatMessage(role: .user, content: "test"),
        ]

        let homeContent = FileManagerContentFeature.State()

        var state = FileManagerFeature.State()
        state.contentTabs = ContentTabState(
            tabs: [
                ContentTabItem(
                    id: aiChatTabID,
                    page: .aiChat,
                    anchor: .aiChat(sessionID: aiSessionID.rawValue.uuidString),
                    isPinned: false,
                    title: "AI Chat",
                    iconName: "message",
                ),
                ContentTabItem(
                    id: homeTabID,
                    page: .home,
                    anchor: .homeDefault,
                    isPinned: false,
                    title: "Home",
                    iconName: "house",
                ),
            ],
            activeTabID: aiChatTabID,
            recentlyClosed: nil,
        )
        state.content = aiChatContent
        state.tabContentStates = [homeTabID: homeContent]
        state.syncContentTabSidebarItems()

        let store: TestStore<FileManagerFeature.State, FileManagerWindowAction> = TestStore(initialState: state) {
            FileManagerFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
            $0.uuid = .incrementing
            $0.entryWatchingClient.startWatchingDirectory = { _ in
                AsyncStream { continuation in
                    continuation.finish()
                }
            }
            $0.aiChatSessionPersistenceClient.saveSession = { snapshot in
                savedSnapshots.withValue { $0.append(snapshot) }
                return snapshot
            }
        }
        store.exhaustivity = .off

        await store.send(.contentTabs(.close(aiChatTabID)))
        await store.receive(\.content.internal.applyNavigationState)
        await store.skipReceivedActions()

        let backgroundState = store.state.backgroundAiChatStates[aiSessionID]
        XCTAssertNotNil(backgroundState)
        XCTAssertEqual(backgroundState?.aiChat.executionPhase, .idle)
        XCTAssertEqual(
            backgroundState?.aiChat.backgroundExecutionPhases[requestLock.requestID],
            .processing(requestLock),
        )

        let response = AiChatResponse(
            context: requestLock.context,
            assistantMessage: AiChatMessage(role: .assistant, content: "done"),
            completedAtMs: 1_234_567_891_000,
        )

        await store.send(.content(.aiChat(.executionEvent(.final(response: response)))))

        await store.receive { action in
            guard case let .backgroundAiChatSnapshotPersisted(snapshot) = action else { return false }
            let summary = AiChatSessionSummary(snapshot: snapshot)
            return summary.sessionID == aiSessionID
        } assert: { state in
            state.backgroundAiChatStates.removeValue(forKey: aiSessionID)
        }

        await store.finish()

        let snapshots = savedSnapshots.value
        XCTAssertEqual(snapshots.count, 1)
        XCTAssertEqual(snapshots.first?.sessionID, aiSessionID)
        XCTAssertEqual(snapshots.first?.transcriptHistory.map(\.content), ["test", "done"])
        XCTAssertFalse(store.state.content.aiChat.sessionList.rows.contains { $0.sessionID == aiSessionID })
        XCTAssertNil(store.state.backgroundAiChatStates[aiSessionID])
    }

    func testLateBackgroundSnapshotDoesNotOverwriteNewerActiveTranscript() async {
        let sessionID = AiChatSessionID(rawValue: UUID())
        let backgroundLock = makeRequestLock(sessionID: sessionID)
        let activeLock = makeRequestLock(sessionID: sessionID).recordingTerminal(
            at: 1_234_567_893_000,
            failure: nil,
            wasCancelled: false,
        )
        let staleBackgroundSummary = AiChatSessionSummary(
            sessionID: sessionID,
            title: "Background R1",
            preview: "R1 done",
            messageCount: 2,
            provider: backgroundLock.context.provider,
            model: backgroundLock.context.model,
            createdAtMs: 1_234_567_891_000,
            updatedAtMs: 1_234_567_891_000,
            status: .active,
        )
        let activeSummary = AiChatSessionSummary(
            sessionID: sessionID,
            title: "Active R2",
            preview: "R2 done",
            messageCount: 3,
            provider: activeLock.context.provider,
            model: activeLock.context.model,
            createdAtMs: 1_234_567_893_000,
            updatedAtMs: 1_234_567_893_000,
            status: .active,
        )

        var activeContent = FileManagerContentFeature.State()
        activeContent.aiChat.sessionID = sessionID
        activeContent.aiChat.mode = .chat
        activeContent.aiChat.sessionStatus = .active
        activeContent.aiChat.transcriptHistory = [
            AiChatMessage(role: .user, content: "R1 question"),
            AiChatMessage(role: .user, content: "R2 question"),
            AiChatMessage(role: .assistant, content: "R2 done"),
        ]
        activeContent.aiChat.executionPhase = .completed(activeLock)
        activeContent.aiChat.sessionList = AiChatSessionListState(
            allRows: [activeSummary],
            selectedSessionID: sessionID,
        )

        var backgroundContent = FileManagerContentFeature.State()
        backgroundContent.aiChat.sessionID = sessionID
        backgroundContent.aiChat.mode = .chat
        backgroundContent.aiChat.sessionStatus = .active
        backgroundContent.aiChat.transcriptHistory = [
            AiChatMessage(role: .user, content: "R1 question"),
            AiChatMessage(role: .assistant, content: "R1 done"),
        ]
        backgroundContent.aiChat.executionPhase = .completed(backgroundLock)

        var state = FileManagerFeature.State()
        state.content = activeContent
        state.backgroundAiChatStates[sessionID] = backgroundContent

        let store: TestStore<FileManagerFeature.State, FileManagerWindowAction> = TestStore(initialState: state) {
            FileManagerFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_893))
            $0.uuid = .incrementing
        }
        store.exhaustivity = .off

        await store.send(.backgroundAiChat(.sessionSnapshotSaved(
            staleBackgroundSummary,
            snapshot: nil,
            requestID: nil,
            runID: nil,
        )))
        await store.finish()

        XCTAssertEqual(store.state.content.aiChat.transcriptHistory.map(\.content), [
            "R1 question",
            "R2 question",
            "R2 done",
        ])
        XCTAssertEqual(store.state.content.aiChat.executionPhase, .completed(activeLock))
        XCTAssertEqual(store.state.content.aiChat.sessionList.allRows.first?.messageCount, 3)
        XCTAssertEqual(store.state.content.aiChat.sessionList.allRows.first?.preview, "R2 done")
        XCTAssertNil(store.state.backgroundAiChatStates[sessionID])
    }

    func testBackgroundFinalSnapshotRefreshUsesFinalTranscript() async {
        let sessionID = AiChatSessionID(rawValue: UUID())
        let requestLock = makeRequestLock(sessionID: sessionID).recordingCustomTitle("Renamed background")
        let savedSnapshots = LockIsolated<[AiChatSessionSnapshot]>([])

        var activeContent = FileManagerContentFeature.State()
        activeContent.aiChat.sessionID = sessionID
        activeContent.aiChat.mode = .chat
        activeContent.aiChat.sessionStatus = .active
        activeContent.aiChat.transcriptHistory = [
            AiChatMessage(role: .user, content: "test"),
        ]
        activeContent.aiChat.sessionList = AiChatSessionListState(
            allRows: [AiChatSessionSummary(
                sessionID: sessionID,
                title: "Active",
                preview: "test",
                messageCount: 1,
                provider: requestLock.context.provider,
                model: requestLock.context.model,
                createdAtMs: 1_234_567_890_000,
                updatedAtMs: 1_234_567_890_000,
                status: .active,
            )],
            selectedSessionID: sessionID,
        )

        var backgroundContent = FileManagerContentFeature.State()
        backgroundContent.aiChat.sessionID = sessionID
        backgroundContent.aiChat.mode = .chat
        backgroundContent.aiChat.sessionStatus = .active
        backgroundContent.aiChat.transcriptHistory = []
        backgroundContent.aiChat.backgroundExecutionPhases[requestLock.requestID] = .processing(requestLock)

        var state = FileManagerFeature.State()
        state.content = activeContent
        state.backgroundAiChatStates[sessionID] = backgroundContent

        let store: TestStore<FileManagerFeature.State, FileManagerWindowAction> = TestStore(initialState: state) {
            FileManagerFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_891))
            $0.uuid = .incrementing
            $0.aiChatSessionPersistenceClient.saveSession = { snapshot in
                savedSnapshots.withValue { $0.append(snapshot) }
                return snapshot
            }
        }
        store.exhaustivity = .off

        let assistantMessage = AiChatMessage(role: .assistant, content: "done")
        let response = AiChatResponse(
            context: requestLock.context,
            assistantMessage: assistantMessage,
            completedAtMs: 1_234_567_891_000,
        )
        let expectedTranscript = [
            AiChatMessage(role: .user, content: "test"),
            assistantMessage,
        ]
        let expectedSnapshot = AiChatSessionSnapshot(
            sessionID: sessionID,
            status: .active,
            customTitle: "Renamed background",
            provider: requestLock.context.provider,
            model: requestLock.context.model,
            selectedModelRow: requestLock.selectedModelRow,
            selectedThinking: requestLock.context.selectedThinking,
            transcriptHistory: expectedTranscript,
            lastRequestID: requestLock.requestID,
            lastRunID: requestLock.runID,
            lastRequestContext: requestLock.context.requestContext,
            updatedAtMs: 1_234_567_891_000,
        )
        let expectedSummary = AiChatSessionSummary(snapshot: expectedSnapshot)

        await store.send(.backgroundAiChat(.executionEvent(.final(response: response))))
        await store.receive { action in
            guard case let .backgroundAiChatSnapshotPersisted(snapshot) = action else { return false }
            let summary = AiChatSessionSummary(snapshot: snapshot)
            return summary == expectedSummary
        } assert: { state in
            state.content.aiChat.currentSessionCustomTitle = "Renamed background"
            state.content.aiChat.transcriptHistory = expectedTranscript
            state.content.aiChat.sessionList.allRows = [expectedSummary]
            state.content.aiChat.sessionList.rows = [expectedSummary]
            state.content.aiChat.sessionList.selectedSessionID = sessionID
            state.backgroundAiChatStates.removeValue(forKey: sessionID)
        }
        await store.finish()

        XCTAssertEqual(savedSnapshots.value.first?.transcriptHistory.map(\.content), ["test", "done"])
        XCTAssertEqual(savedSnapshots.value.first?.customTitle, "Renamed background")
        XCTAssertEqual(store.state.content.aiChat.transcriptHistory.map(\.content), ["test", "done"])
        XCTAssertEqual(store.state.content.aiChat.sessionList.allRows.first?.title, "Renamed background")
        XCTAssertEqual(store.state.content.aiChat.currentSessionCustomTitle, "Renamed background")
        XCTAssertNil(store.state.backgroundAiChatStates[sessionID])
    }

    func testAiChatTabSwitchPreservesForegroundOwnerUnderLockSession() async {
        let aiChatTabID = ContentTabID()
        let homeTabID = ContentTabID()
        let ownerSessionID = AiChatSessionID(rawValue: UUID())
        let routeSessionID = AiChatSessionID(rawValue: UUID())
        let requestLock = makeRequestLock(sessionID: ownerSessionID)

        var aiChatContent = FileManagerContentFeature.State()
        aiChatContent.aiChat.sessionID = routeSessionID
        aiChatContent.aiChat.sessionStatus = .active
        aiChatContent.aiChat.mode = .chat
        aiChatContent.aiChat.executionPhase = .processing(requestLock)
        aiChatContent.aiChat.lockedModelHandle = requestLock.selectedModelHandle
        aiChatContent.aiChat.transcriptHistory = requestLock.request.messages

        let homeContent = FileManagerContentFeature.State()

        var state = FileManagerFeature.State()
        state.contentTabs = ContentTabState(
            tabs: [
                ContentTabItem(
                    id: aiChatTabID,
                    page: .aiChat,
                    anchor: .aiChat(sessionID: routeSessionID.rawValue.uuidString),
                    isPinned: false,
                    title: "AI Chat",
                    iconName: "message",
                ),
                ContentTabItem(
                    id: homeTabID,
                    page: .home,
                    anchor: .homeDefault,
                    isPinned: false,
                    title: "Home",
                    iconName: "house",
                ),
            ],
            activeTabID: aiChatTabID,
            recentlyClosed: nil,
        )
        state.content = aiChatContent
        state.tabContentStates = [homeTabID: homeContent]
        state.syncContentTabSidebarItems()

        let store: TestStore<FileManagerFeature.State, FileManagerWindowAction> = TestStore(initialState: state) {
            FileManagerFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
            $0.uuid = .incrementing
        }
        store.exhaustivity = .off

        await store.send(.contentTabs(.setCurrent(homeTabID)))
        await store.skipReceivedActions()

        XCTAssertNil(store.state.backgroundAiChatStates[routeSessionID])
        XCTAssertEqual(
            store.state.backgroundAiChatStates[ownerSessionID]?.aiChat.executionPhase,
            .processing(requestLock),
        )
    }

    func testAiChatTabSwitchPreservesBackgroundRequestOwner() async {
        let aiChatTabID = ContentTabID()
        let homeTabID = ContentTabID()
        let aiSessionID = AiChatSessionID(rawValue: UUID())
        let requestLock = makeRequestLock(sessionID: aiSessionID)

        var aiChatContent = FileManagerContentFeature.State()
        aiChatContent.aiChat.sessionID = aiSessionID
        aiChatContent.aiChat.sessionStatus = .active
        aiChatContent.aiChat.mode = .chat
        aiChatContent.aiChat.executionPhase = .processing(requestLock)
        aiChatContent.aiChat.lockedModelHandle = requestLock.selectedModelHandle
        aiChatContent.aiChat.transcriptHistory = requestLock.request.messages

        let homeContent = FileManagerContentFeature.State()

        var state = FileManagerFeature.State()
        state.contentTabs = ContentTabState(
            tabs: [
                ContentTabItem(
                    id: aiChatTabID,
                    page: .aiChat,
                    anchor: .aiChat(sessionID: aiSessionID.rawValue.uuidString),
                    isPinned: false,
                    title: "AI Chat",
                    iconName: "message",
                ),
                ContentTabItem(
                    id: homeTabID,
                    page: .home,
                    anchor: .homeDefault,
                    isPinned: false,
                    title: "Home",
                    iconName: "house",
                ),
            ],
            activeTabID: aiChatTabID,
            recentlyClosed: nil,
        )
        state.content = aiChatContent
        state.tabContentStates = [homeTabID: homeContent]
        state.syncContentTabSidebarItems()

        let store: TestStore<FileManagerFeature.State, FileManagerWindowAction> = TestStore(initialState: state) {
            FileManagerFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
            $0.uuid = .incrementing
        }
        store.exhaustivity = .off

        await store.send(.contentTabs(.setCurrent(homeTabID)))
        await store.skipReceivedActions()

        XCTAssertEqual(
            store.state.backgroundAiChatStates[aiSessionID]?.aiChat.executionPhase,
            .processing(requestLock),
        )
        XCTAssertEqual(
            store.state.tabContentStates[aiChatTabID]?.aiChat.executionPhase,
            .processing(requestLock),
        )
        XCTAssertNotEqual(store.state.content.aiChat.sessionID, aiSessionID)

        await store.send(.contentTabs(.setCurrent(aiChatTabID)))
        await store.skipReceivedActions()

        XCTAssertEqual(store.state.content.aiChat.executionPhase, .processing(requestLock))
        XCTAssertNil(store.state.backgroundAiChatStates[aiSessionID])
        await store.finish()
    }

    func testAddBackgroundAiChatStateMergesExistingSameSessionOwner() {
        let aiSessionID = AiChatSessionID(rawValue: UUID())
        let existingLock = makeRequestLock(sessionID: aiSessionID)
        let newLock = makeRequestLock(sessionID: aiSessionID)
        let finalSnapshot = AiChatSessionSnapshot(
            sessionID: aiSessionID,
            status: .active,
            provider: nil,
            model: nil,
            transcriptHistory: [
                AiChatMessage(role: .user, content: "old"),
                AiChatMessage(role: .assistant, content: "done"),
            ],
            updatedAtMs: 1_234_567_890_000,
        )
        let existingOwner = existingLock.recordingFinalSnapshot(finalSnapshot)

        var existingContent = FileManagerContentFeature.State()
        existingContent.aiChat.sessionID = aiSessionID
        existingContent.aiChat.executionPhase = .completed(existingOwner)

        var newContent = FileManagerContentFeature.State()
        newContent.aiChat.sessionID = aiSessionID
        newContent.aiChat.executionPhase = .processing(newLock)

        var state = FileManagerFeature.State()
        state.backgroundAiChatStates[aiSessionID] = existingContent
        state.addBackgroundAiChatState(sessionID: aiSessionID, state: newContent)

        XCTAssertEqual(
            state.backgroundAiChatStates[aiSessionID]?.aiChat.executionPhase,
            .processing(newLock),
        )
        XCTAssertEqual(
            state.backgroundAiChatStates[aiSessionID]?.aiChat.backgroundExecutionPhases[existingLock.requestID],
            .completed(existingOwner),
        )
    }

    func testBackgroundSnapshotPersistedRemovesOnlyMatchingRequestOwner() async {
        let sessionID = AiChatSessionID(rawValue: UUID())
        let oldLock = makeRequestLock(sessionID: sessionID)
        let newLock = makeRequestLock(sessionID: sessionID)
        let oldSnapshot = AiChatSessionSnapshot(
            sessionID: sessionID,
            status: .active,
            provider: nil,
            model: nil,
            transcriptHistory: [
                AiChatMessage(role: .user, content: "old"),
                AiChatMessage(role: .assistant, content: "old done"),
            ],
            lastRequestID: oldLock.requestID,
            lastRunID: oldLock.runID,
            lastRequestContext: oldLock.context.requestContext,
            updatedAtMs: 1_234_567_890_000,
        )
        let newSnapshot = AiChatSessionSnapshot(
            sessionID: sessionID,
            status: .active,
            provider: nil,
            model: nil,
            transcriptHistory: [
                AiChatMessage(role: .user, content: "new"),
                AiChatMessage(role: .assistant, content: "new done"),
            ],
            lastRequestID: newLock.requestID,
            lastRunID: newLock.runID,
            lastRequestContext: newLock.context.requestContext,
            updatedAtMs: 1_234_567_891_000,
        )
        let oldOwner = oldLock.recordingFinalSnapshot(oldSnapshot)
        let newOwner = newLock.recordingFinalSnapshot(newSnapshot)

        var backgroundContent = FileManagerContentFeature.State()
        backgroundContent.aiChat.sessionID = sessionID
        backgroundContent.aiChat.executionPhase = .persistenceRecovery(oldOwner, .unknown)
        backgroundContent.aiChat.backgroundExecutionPhases[newLock.requestID] = .completed(newOwner)

        var state = FileManagerFeature.State()
        state.backgroundAiChatStates[sessionID] = backgroundContent

        let store: TestStore<FileManagerFeature.State, FileManagerWindowAction> = TestStore(initialState: state) {
            FileManagerFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_891))
            $0.uuid = .incrementing
        }
        store.exhaustivity = .off

        await store.send(.backgroundAiChatSnapshotPersisted(newSnapshot))
        await store.finish()

        XCTAssertEqual(
            store.state.backgroundAiChatStates[sessionID]?.aiChat.executionPhase,
            .persistenceRecovery(oldOwner, .unknown),
        )
        XCTAssertNil(store.state.backgroundAiChatStates[sessionID]?.aiChat.backgroundExecutionPhases[newLock.requestID])
        XCTAssertNotNil(store.state.backgroundAiChatStates[sessionID])
    }

    func testAddBackgroundAiChatStatePreservesExistingPendingResolver() throws {
        let aiSessionID = AiChatSessionID(rawValue: UUID())
        let oldLock = makeRequestLock(sessionID: aiSessionID)
        let newLock = makeRequestLock(sessionID: aiSessionID)
        let oldModel = try XCTUnwrap(oldLock.context.selectedModel)
        let newModel = try XCTUnwrap(newLock.context.selectedModel)
        let oldResolutionID = UUID()
        let newResolutionID = UUID()

        func pendingRequest(
            resolutionID: UUID,
            lock: AiChatRequestLock,
            selectedModel: AiProviderModel,
        ) -> AiChatPendingRequestStart {
            AiChatPendingRequestStart(
                resolutionID: resolutionID,
                kind: .submit,
                sessionID: aiSessionID,
                selectedModel: selectedModel,
                selectedRow: lock.selectedModelRow,
                preparedRequest: AiChatPreparedRequest(
                    prompt: "test",
                    messages: lock.request.messages,
                    assistantReplacementIndex: nil,
                    historyTruncation: AiChatHistoryTruncationMetadata(
                        includedMessageCount: lock.request.messages.count,
                        excludedMessageCount: 0,
                        budget: 24000,
                        truncationReason: nil,
                    ),
                ),
            )
        }

        var existingContent = FileManagerContentFeature.State()
        existingContent.aiChat.sessionID = aiSessionID
        existingContent.aiChat.pendingRequestStart = pendingRequest(
            resolutionID: oldResolutionID,
            lock: oldLock,
            selectedModel: oldModel,
        )

        var newContent = FileManagerContentFeature.State()
        newContent.aiChat.sessionID = aiSessionID
        newContent.aiChat.pendingRequestStart = pendingRequest(
            resolutionID: newResolutionID,
            lock: newLock,
            selectedModel: newModel,
        )

        var state = FileManagerFeature.State()
        state.backgroundAiChatStates[aiSessionID] = existingContent
        state.addBackgroundAiChatState(sessionID: aiSessionID, state: newContent)

        XCTAssertEqual(
            state.backgroundAiChatStates[aiSessionID]?.aiChat.pendingRequestStart?.resolutionID,
            newResolutionID,
        )
        XCTAssertEqual(
            state.backgroundAiChatStates[aiSessionID]?.aiChat.backgroundPendingRequestStarts[oldResolutionID]?
                .resolutionID,
            oldResolutionID,
        )
    }

    func testBackgroundPendingResolverStartsRequestWhenNewPendingExistsForSameSession() async throws {
        let aiSessionID = AiChatSessionID(rawValue: UUID())
        let oldLock = makeRequestLock(sessionID: aiSessionID)
        let newLock = makeRequestLock(sessionID: aiSessionID)
        let oldModel = try XCTUnwrap(oldLock.context.selectedModel)
        let newModel = try XCTUnwrap(newLock.context.selectedModel)
        let oldResolutionID = UUID()
        let newResolutionID = UUID()

        func pendingRequest(
            resolutionID: UUID,
            lock: AiChatRequestLock,
            selectedModel: AiProviderModel,
        ) -> AiChatPendingRequestStart {
            AiChatPendingRequestStart(
                resolutionID: resolutionID,
                kind: .submit,
                sessionID: aiSessionID,
                selectedModel: selectedModel,
                selectedRow: lock.selectedModelRow,
                preparedRequest: AiChatPreparedRequest(
                    prompt: "test",
                    messages: lock.request.messages,
                    assistantReplacementIndex: nil,
                    historyTruncation: AiChatHistoryTruncationMetadata(
                        includedMessageCount: lock.request.messages.count,
                        excludedMessageCount: 0,
                        budget: 24000,
                        truncationReason: nil,
                    ),
                ),
            )
        }

        var backgroundContent = FileManagerContentFeature.State()
        backgroundContent.aiChat.sessionID = aiSessionID
        backgroundContent.aiChat.sessionStatus = .active
        backgroundContent.aiChat.modelListState = .loaded([oldModel, newModel])
        backgroundContent.aiChat.selectedModelHandle = newModel.id
        backgroundContent.aiChat.pendingRequestStart = pendingRequest(
            resolutionID: newResolutionID,
            lock: newLock,
            selectedModel: newModel,
        )
        backgroundContent.aiChat.backgroundPendingRequestStarts[oldResolutionID] = pendingRequest(
            resolutionID: oldResolutionID,
            lock: oldLock,
            selectedModel: oldModel,
        )

        var state = FileManagerFeature.State()
        state.content = FileManagerContentFeature.State()
        state.backgroundAiChatStates[aiSessionID] = backgroundContent

        let store = TestStore(initialState: state) {
            FileManagerFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
            $0.uuid = .incrementing
            $0.aiChatExecutionClient.execute = { _, _ in
                AsyncStream { continuation in
                    continuation.finish()
                }
            }
        }
        store.exhaustivity = .off

        let resolvedContext = AiChatResolvedRequestContext(
            currentContext: .init(),
            addedAttachments: [],
            parts: [],
        )
        await store.send(.content(.aiChat(.requestContextResolved(oldResolutionID, resolvedContext)))) { state in
            if case .processing = state.backgroundAiChatStates[aiSessionID]?.aiChat.executionPhase {
            } else {
                XCTFail("background pending resolver should start the matching request")
            }
            XCTAssertNil(state.backgroundAiChatStates[aiSessionID]?.aiChat.pendingRequestStart)
            XCTAssertEqual(
                state.backgroundAiChatStates[aiSessionID]?.aiChat.backgroundPendingRequestStarts[newResolutionID]?
                    .resolutionID,
                newResolutionID,
            )
            XCTAssertNil(state.backgroundAiChatStates[aiSessionID]?.aiChat
                .backgroundPendingRequestStarts[oldResolutionID])
        }

        await store.skipReceivedActions()
        await store.finish()
    }

    func testAiChatTabSwitchStoresPendingRequestUnderPendingSessionID() async throws {
        let aiChatTabID = ContentTabID()
        let homeTabID = ContentTabID()
        let pendingSessionID = AiChatSessionID(rawValue: UUID())
        let visibleSessionID = AiChatSessionID(rawValue: UUID())
        let requestLock = makeRequestLock(sessionID: pendingSessionID)
        let selectedModel = try XCTUnwrap(requestLock.context.selectedModel)
        let resolutionID = UUID()
        let pendingRequest = AiChatPendingRequestStart(
            resolutionID: resolutionID,
            kind: .submit,
            sessionID: pendingSessionID,
            selectedModel: selectedModel,
            selectedRow: requestLock.selectedModelRow,
            preparedRequest: AiChatPreparedRequest(
                prompt: "test",
                messages: requestLock.request.messages,
                assistantReplacementIndex: nil,
                historyTruncation: AiChatHistoryTruncationMetadata(
                    includedMessageCount: requestLock.request.messages.count,
                    excludedMessageCount: 0,
                    budget: 24000,
                    truncationReason: nil,
                ),
            ),
        )

        var aiChatContent = FileManagerContentFeature.State()
        aiChatContent.aiChat.sessionID = visibleSessionID
        aiChatContent.aiChat.sessionStatus = .active
        aiChatContent.aiChat.pendingRequestStart = pendingRequest
        aiChatContent.aiChat.modelListState = .loaded([selectedModel])
        aiChatContent.aiChat.selectedModelHandle = selectedModel.id

        var state = FileManagerFeature.State()
        state.contentTabs = ContentTabState(
            tabs: [
                ContentTabItem(
                    id: aiChatTabID,
                    page: .aiChat,
                    anchor: .aiChat(sessionID: visibleSessionID.rawValue.uuidString),
                    isPinned: false,
                    title: "AI Chat",
                    iconName: "message",
                ),
                ContentTabItem(
                    id: homeTabID,
                    page: .home,
                    anchor: .homeDefault,
                    isPinned: false,
                    title: "Home",
                    iconName: "house",
                ),
            ],
            activeTabID: aiChatTabID,
            recentlyClosed: nil,
        )
        state.content = aiChatContent
        state.tabContentStates = [homeTabID: FileManagerContentFeature.State()]
        state.syncContentTabSidebarItems()

        let store: TestStore<FileManagerFeature.State, FileManagerWindowAction> = TestStore(initialState: state) {
            FileManagerFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
            $0.uuid = .incrementing
        }
        store.exhaustivity = .off

        await store.send(.contentTabs(.setCurrent(homeTabID)))
        await store.skipReceivedActions()

        XCTAssertEqual(
            store.state.backgroundAiChatStates[pendingSessionID]?.aiChat.pendingRequestStart?.resolutionID,
            resolutionID,
        )
        XCTAssertNil(store.state.backgroundAiChatStates[visibleSessionID]?.aiChat.pendingRequestStart)
        await store.finish()
    }

    func testAiChatTabSwitchPreservesBackgroundPendingRequestOwner() async throws {
        let aiChatTabID = ContentTabID()
        let homeTabID = ContentTabID()
        let pendingSessionID = AiChatSessionID(rawValue: UUID())
        let visibleSessionID = AiChatSessionID(rawValue: UUID())
        let requestLock = makeRequestLock(sessionID: pendingSessionID)
        let selectedModel = try XCTUnwrap(requestLock.context.selectedModel)
        let resolutionID = UUID()
        let pendingRequest = AiChatPendingRequestStart(
            resolutionID: resolutionID,
            kind: .submit,
            sessionID: pendingSessionID,
            selectedModel: selectedModel,
            selectedRow: requestLock.selectedModelRow,
            preparedRequest: AiChatPreparedRequest(
                prompt: "test",
                messages: requestLock.request.messages,
                assistantReplacementIndex: nil,
                historyTruncation: AiChatHistoryTruncationMetadata(
                    includedMessageCount: requestLock.request.messages.count,
                    excludedMessageCount: 0,
                    budget: 24000,
                    truncationReason: nil,
                ),
            ),
        )

        var aiChatContent = FileManagerContentFeature.State()
        aiChatContent.aiChat.sessionID = visibleSessionID
        aiChatContent.aiChat.sessionStatus = .active
        aiChatContent.aiChat.backgroundPendingRequestStarts[resolutionID] = pendingRequest
        aiChatContent.aiChat.modelListState = .loaded([selectedModel])
        aiChatContent.aiChat.selectedModelHandle = selectedModel.id

        var state = FileManagerFeature.State()
        state.contentTabs = ContentTabState(
            tabs: [
                ContentTabItem(
                    id: aiChatTabID,
                    page: .aiChat,
                    anchor: .aiChat(sessionID: visibleSessionID.rawValue.uuidString),
                    isPinned: false,
                    title: "AI Chat",
                    iconName: "message",
                ),
                ContentTabItem(
                    id: homeTabID,
                    page: .home,
                    anchor: .homeDefault,
                    isPinned: false,
                    title: "Home",
                    iconName: "house",
                ),
            ],
            activeTabID: aiChatTabID,
            recentlyClosed: nil,
        )
        state.content = aiChatContent
        state.tabContentStates = [homeTabID: FileManagerContentFeature.State()]
        state.syncContentTabSidebarItems()

        let store: TestStore<FileManagerFeature.State, FileManagerWindowAction> = TestStore(initialState: state) {
            FileManagerFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
            $0.uuid = .incrementing
        }
        store.exhaustivity = .off

        await store.send(.contentTabs(.setCurrent(homeTabID)))
        await store.skipReceivedActions()

        XCTAssertEqual(
            store.state.backgroundAiChatStates[pendingSessionID]?.aiChat
                .backgroundPendingRequestStarts[resolutionID]?.resolutionID,
            resolutionID,
        )
        XCTAssertNil(store.state.backgroundAiChatStates[visibleSessionID]?.aiChat
            .backgroundPendingRequestStarts[resolutionID])
        await store.finish()
    }

    func testDeleteSessionRemovesBackgroundPendingRequestOwnerFromOtherBackgroundState() async throws {
        let deletedSessionID = AiChatSessionID(rawValue: UUID())
        let preservedSessionID = AiChatSessionID(rawValue: UUID())
        let requestLock = makeRequestLock(sessionID: deletedSessionID)
        let selectedModel = try XCTUnwrap(requestLock.context.selectedModel)
        let resolutionID = UUID()
        let pendingRequest = AiChatPendingRequestStart(
            resolutionID: resolutionID,
            kind: .submit,
            sessionID: deletedSessionID,
            selectedModel: selectedModel,
            selectedRow: requestLock.selectedModelRow,
            preparedRequest: AiChatPreparedRequest(
                prompt: "test",
                messages: requestLock.request.messages,
                assistantReplacementIndex: nil,
                historyTruncation: AiChatHistoryTruncationMetadata(
                    includedMessageCount: requestLock.request.messages.count,
                    excludedMessageCount: 0,
                    budget: 24000,
                    truncationReason: nil,
                ),
            ),
        )

        var backgroundContent = FileManagerContentFeature.State()
        backgroundContent.aiChat.sessionID = preservedSessionID
        backgroundContent.aiChat.sessionStatus = .active
        backgroundContent.aiChat.backgroundPendingRequestStarts[resolutionID] = pendingRequest

        var state = FileManagerFeature.State()
        state.backgroundAiChatStates[preservedSessionID] = backgroundContent

        let store: TestStore<FileManagerFeature.State, FileManagerWindowAction> = TestStore(initialState: state) {
            FileManagerFeature()
        }
        store.exhaustivity = .off

        await store.send(.content(.aiChat(.deleteSessionTapped(deletedSessionID))))
        await store.skipReceivedActions()

        XCTAssertNil(store.state.backgroundAiChatStates[preservedSessionID])
        XCTAssertNil(store.state.backgroundAiChatStates[deletedSessionID])
        await store.finish()
    }

    func testBackgroundSnapshotRefreshAppliesNilCustomTitle() async {
        let sessionID = AiChatSessionID(rawValue: UUID())
        let requestLock = makeRequestLock(sessionID: sessionID).recordingTerminal(
            at: 1_234_567_890_000,
            failure: nil,
            wasCancelled: false,
        )
        let finalSnapshot = AiChatSessionSnapshot(
            sessionID: sessionID,
            status: .active,
            provider: requestLock.context.provider,
            model: requestLock.context.model,
            selectedModelRow: requestLock.selectedModelRow,
            transcriptHistory: requestLock.request.messages + [AiChatMessage(role: .assistant, content: "done")],
            lastRequestID: requestLock.requestID,
            lastRunID: requestLock.runID,
            lastRequestContext: requestLock.context.requestContext,
            updatedAtMs: 1_234_567_890_000,
        )
        var backgroundContent = FileManagerContentFeature.State()
        backgroundContent.aiChat.sessionID = sessionID
        backgroundContent.aiChat.currentSessionCustomTitle = "Old title"
        backgroundContent.aiChat.executionPhase = .completed(requestLock.recordingFinalSnapshot(finalSnapshot))

        var activeContent = FileManagerContentFeature.State()
        activeContent.navigation.navigationState = .aiChat(sessionID.rawValue.uuidString)
        activeContent.aiChat.sessionID = sessionID
        activeContent.aiChat.currentSessionCustomTitle = "Old title"
        activeContent.aiChat.transcriptHistory = requestLock.request.messages

        var state = FileManagerFeature.State()
        state.content = activeContent
        state.backgroundAiChatStates[sessionID] = backgroundContent

        let store: TestStore<FileManagerFeature.State, FileManagerWindowAction> = TestStore(initialState: state) {
            FileManagerFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
            $0.uuid = .incrementing
        }
        store.exhaustivity = .off

        await store.send(.backgroundAiChat(.sessionSnapshotSaved(
            AiChatSessionSummary(snapshot: finalSnapshot),
            snapshot: finalSnapshot,
            requestID: requestLock.requestID,
            runID: requestLock.runID,
        )))

        XCTAssertNil(store.state.content.aiChat.currentSessionCustomTitle)
        XCTAssertEqual(store.state.content.aiChat.transcriptHistory.map(\.content), ["test", "done"])
        await store.finish()
    }

    func testClosedPendingAiChatContextResolutionStartsBackgroundRequest() async throws {
        let aiChatTabID = ContentTabID()
        let homeTabID = ContentTabID()
        let aiSessionID = AiChatSessionID(rawValue: UUID())
        let requestLock = makeRequestLock(sessionID: aiSessionID)
        let selectedModel = try XCTUnwrap(requestLock.context.selectedModel)
        let resolutionID = UUID()
        let pendingRequest = AiChatPendingRequestStart(
            resolutionID: resolutionID,
            kind: .submit,
            sessionID: aiSessionID,
            selectedModel: selectedModel,
            selectedRow: requestLock.selectedModelRow,
            preparedRequest: AiChatPreparedRequest(
                prompt: "test",
                messages: requestLock.request.messages,
                assistantReplacementIndex: nil,
                historyTruncation: AiChatHistoryTruncationMetadata(
                    includedMessageCount: requestLock.request.messages.count,
                    excludedMessageCount: 0,
                    budget: 24000,
                    truncationReason: nil,
                ),
            ),
        )

        var aiChatContent = FileManagerContentFeature.State()
        aiChatContent.aiChat.sessionID = aiSessionID
        aiChatContent.aiChat.sessionStatus = .active
        aiChatContent.aiChat.pendingRequestStart = pendingRequest
        aiChatContent.aiChat.modelListState = .loaded([selectedModel])
        aiChatContent.aiChat.selectedModelHandle = selectedModel.id

        let homeContent = FileManagerContentFeature.State()

        var state = FileManagerFeature.State()
        state.contentTabs = ContentTabState(
            tabs: [
                ContentTabItem(
                    id: aiChatTabID,
                    page: .aiChat,
                    anchor: .aiChat(sessionID: aiSessionID.rawValue.uuidString),
                    isPinned: false,
                    title: "AI Chat",
                    iconName: "message",
                ),
                ContentTabItem(
                    id: homeTabID,
                    page: .home,
                    anchor: .homeDefault,
                    isPinned: false,
                    title: "Home",
                    iconName: "house",
                ),
            ],
            activeTabID: aiChatTabID,
            recentlyClosed: nil,
        )
        state.content = aiChatContent
        state.tabContentStates = [homeTabID: homeContent]
        state.syncContentTabSidebarItems()

        let store: TestStore<FileManagerFeature.State, FileManagerWindowAction> = TestStore(initialState: state) {
            FileManagerFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
            $0.uuid = .incrementing
            $0.entryWatchingClient.startWatchingDirectory = { _ in
                AsyncStream { continuation in
                    continuation.finish()
                }
            }
            $0.aiChatExecutionClient.execute = { _, _ in
                AsyncStream { continuation in
                    continuation.finish()
                }
            }
        }
        store.exhaustivity = .off

        await store.send(.contentTabs(.close(aiChatTabID)))
        await store.skipReceivedActions()

        XCTAssertEqual(
            store.state.backgroundAiChatStates[aiSessionID]?.aiChat.pendingRequestStart?.resolutionID,
            resolutionID,
        )

        let resolvedContext = AiChatResolvedRequestContext(
            currentContext: .init(),
            addedAttachments: [],
            parts: [],
        )
        await store.send(.content(.aiChat(.requestContextResolved(resolutionID, resolvedContext)))) { state in
            state.backgroundAiChatStates[aiSessionID]?.aiChat.pendingRequestStart = nil
            if case .processing = state.backgroundAiChatStates[aiSessionID]?.aiChat.executionPhase {
            } else {
                XCTFail("background AI Chat should start processing after resolver completion")
            }
        }

        await store.skipReceivedActions()
        XCTAssertNotNil(store.state.backgroundAiChatStates[aiSessionID])
        XCTAssertNil(store.state.content.aiChat.pendingRequestStart)
        await store.finish()
    }

    func testBackgroundResolverClearsMatchingPendingCopyFromInactiveTab() async throws {
        let aiChatTabID = ContentTabID()
        let homeTabID = ContentTabID()
        let aiSessionID = AiChatSessionID(rawValue: UUID())
        let requestLock = makeRequestLock(sessionID: aiSessionID)
        let selectedModel = try XCTUnwrap(requestLock.context.selectedModel)
        let resolutionID = UUID()
        let pendingRequest = AiChatPendingRequestStart(
            resolutionID: resolutionID,
            kind: .submit,
            sessionID: aiSessionID,
            selectedModel: selectedModel,
            selectedRow: requestLock.selectedModelRow,
            preparedRequest: AiChatPreparedRequest(
                prompt: "test",
                messages: requestLock.request.messages,
                assistantReplacementIndex: nil,
                historyTruncation: AiChatHistoryTruncationMetadata(
                    includedMessageCount: requestLock.request.messages.count,
                    excludedMessageCount: 0,
                    budget: 24000,
                    truncationReason: nil,
                ),
            ),
        )

        var inactiveContent = FileManagerContentFeature.State()
        inactiveContent.aiChat.sessionID = aiSessionID
        inactiveContent.aiChat.sessionStatus = .active
        inactiveContent.aiChat.pendingRequestStart = pendingRequest
        inactiveContent.aiChat.modelListState = .loaded([selectedModel])
        inactiveContent.aiChat.selectedModelHandle = selectedModel.id

        var backgroundContent = inactiveContent

        var state = FileManagerFeature.State()
        state.contentTabs = ContentTabState(
            tabs: [
                ContentTabItem(
                    id: homeTabID,
                    page: .home,
                    anchor: .homeDefault,
                    isPinned: false,
                    title: "Home",
                    iconName: "house",
                ),
                ContentTabItem(
                    id: aiChatTabID,
                    page: .aiChat,
                    anchor: .aiChat(sessionID: aiSessionID.rawValue.uuidString),
                    isPinned: false,
                    title: "AI Chat",
                    iconName: "message",
                ),
            ],
            activeTabID: homeTabID,
            recentlyClosed: nil,
        )
        state.content = FileManagerContentFeature.State()
        state.tabContentStates[aiChatTabID] = inactiveContent
        state.backgroundAiChatStates[aiSessionID] = backgroundContent
        state.syncContentTabSidebarItems()

        let store: TestStore<FileManagerFeature.State, FileManagerWindowAction> = TestStore(initialState: state) {
            FileManagerFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
            $0.uuid = .incrementing
            $0.aiChatExecutionClient.execute = { _, _ in
                AsyncStream { continuation in
                    continuation.finish()
                }
            }
        }
        store.exhaustivity = .off

        let resolvedContext = AiChatResolvedRequestContext(
            currentContext: .init(),
            addedAttachments: [],
            parts: [],
        )
        await store.send(.content(.aiChat(.requestContextResolved(resolutionID, resolvedContext)))) { state in
            state.tabContentStates[aiChatTabID]?.aiChat.pendingRequestStart = nil
            state.backgroundAiChatStates[aiSessionID]?.aiChat.pendingRequestStart = nil
            if case .processing = state.backgroundAiChatStates[aiSessionID]?.aiChat.executionPhase {
            } else {
                XCTFail("background AI Chat should start processing after resolver completion")
            }
        }

        await store.skipReceivedActions()
        XCTAssertNil(store.state.tabContentStates[aiChatTabID]?.aiChat.pendingRequestStart)
        XCTAssertNil(store.state.backgroundAiChatStates[aiSessionID]?.aiChat.pendingRequestStart)
        XCTAssertNotNil(store.state.backgroundAiChatStates[aiSessionID])
        await store.finish()
    }

    func testInactiveInspectorFindsBackgroundPendingResolver() async throws {
        let homeTabID = ContentTabID()
        let aiChatTabID = ContentTabID()
        let aiSessionID = AiChatSessionID(rawValue: UUID())
        let requestLock = makeRequestLock(sessionID: aiSessionID)
        let selectedModel = try XCTUnwrap(requestLock.context.selectedModel)
        let resolutionID = UUID()
        let pendingRequest = AiChatPendingRequestStart(
            resolutionID: resolutionID,
            kind: .submit,
            sessionID: aiSessionID,
            selectedModel: selectedModel,
            selectedRow: requestLock.selectedModelRow,
            preparedRequest: AiChatPreparedRequest(
                prompt: "test",
                messages: requestLock.request.messages,
                assistantReplacementIndex: nil,
                historyTruncation: AiChatHistoryTruncationMetadata(
                    includedMessageCount: requestLock.request.messages.count,
                    excludedMessageCount: 0,
                    budget: 24000,
                    truncationReason: nil,
                ),
            ),
        )

        var inactiveInspector = FileManagerInspectorFeature.State()
        inactiveInspector.aiChat.sessionID = aiSessionID
        inactiveInspector.aiChat.sessionStatus = .active
        inactiveInspector.aiChat.backgroundPendingRequestStarts[resolutionID] = pendingRequest
        inactiveInspector.aiChat.modelListState = .loaded([selectedModel])
        inactiveInspector.aiChat.selectedModelHandle = selectedModel.id

        var state = FileManagerFeature.State()
        state.contentTabs = ContentTabState(
            tabs: [
                ContentTabItem(
                    id: homeTabID,
                    page: .home,
                    anchor: .homeDefault,
                    isPinned: false,
                    title: "Home",
                    iconName: "house",
                ),
                ContentTabItem(
                    id: aiChatTabID,
                    page: .aiChat,
                    anchor: .aiChat(sessionID: aiSessionID.rawValue.uuidString),
                    isPinned: false,
                    title: "AI Chat",
                    iconName: "message",
                ),
            ],
            activeTabID: homeTabID,
            recentlyClosed: nil,
        )
        state.tabInspectorStates[aiChatTabID] = inactiveInspector
        state.syncContentTabSidebarItems()

        let store: TestStore<FileManagerFeature.State, FileManagerWindowAction> = TestStore(initialState: state) {
            FileManagerFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
            $0.uuid = .incrementing
            $0.aiChatExecutionClient.execute = { _, _ in
                AsyncStream { continuation in
                    continuation.finish()
                }
            }
        }
        store.exhaustivity = .off

        let resolvedContext = AiChatResolvedRequestContext(
            currentContext: .init(),
            addedAttachments: [],
            parts: [],
        )
        await store.send(.inspector(.aiChat(.requestContextResolved(resolutionID, resolvedContext)))) { state in
            state.tabInspectorStates[aiChatTabID]?.aiChat.backgroundPendingRequestStarts
                .removeValue(forKey: resolutionID)
            if case .processing = state.tabInspectorStates[aiChatTabID]?.aiChat.executionPhase {
            } else {
                XCTFail("inactive inspector AI Chat should start processing after parked resolver completion")
            }
        }

        await store.skipReceivedActions()
        XCTAssertNil(store.state.tabInspectorStates[aiChatTabID]?.aiChat.backgroundPendingRequestStarts[resolutionID])
        XCTAssertNotNil(store.state.tabInspectorStates[aiChatTabID])
        await store.finish()
    }

    func testBackgroundPendingResolverStaysParkedWhenAliasStateSessionDiffers() async throws {
        let aliasSessionID = AiChatSessionID(rawValue: UUID())
        let pendingSessionID = AiChatSessionID(rawValue: UUID())
        let requestLock = makeRequestLock(sessionID: pendingSessionID)
        let selectedModel = try XCTUnwrap(requestLock.context.selectedModel)
        let resolutionID = UUID()
        let pendingRequest = AiChatPendingRequestStart(
            resolutionID: resolutionID,
            kind: .submit,
            sessionID: pendingSessionID,
            selectedModel: selectedModel,
            selectedRow: requestLock.selectedModelRow,
            preparedRequest: AiChatPreparedRequest(
                prompt: "test",
                messages: requestLock.request.messages,
                assistantReplacementIndex: nil,
                historyTruncation: AiChatHistoryTruncationMetadata(
                    includedMessageCount: requestLock.request.messages.count,
                    excludedMessageCount: 0,
                    budget: 24000,
                    truncationReason: nil,
                ),
            ),
        )
        var backgroundContent = FileManagerContentFeature.State()
        backgroundContent.aiChat.sessionID = aliasSessionID
        backgroundContent.aiChat.backgroundPendingRequestStarts[resolutionID] = pendingRequest

        var state = FileManagerFeature.State()
        state.backgroundAiChatStates[aliasSessionID] = backgroundContent

        let store = TestStore(initialState: state) {
            FileManagerFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
            $0.uuid = .incrementing
            $0.aiChatExecutionClient.execute = { _, _ in
                AsyncStream { continuation in
                    continuation.finish()
                }
            }
        }
        store.exhaustivity = .off

        let resolvedContext = AiChatResolvedRequestContext(currentContext: .init(), addedAttachments: [], parts: [])
        await store.send(.content(.aiChat(.requestContextResolved(resolutionID, resolvedContext))))
        await store.skipReceivedActions()

        let aiChat = try XCTUnwrap(store.state.backgroundAiChatStates[aliasSessionID]?.aiChat)
        XCTAssertNil(aiChat.pendingRequestStart)
        XCTAssertNil(aiChat.backgroundPendingRequestStarts[resolutionID])
        XCTAssertEqual(aiChat.backgroundExecutionPhases.count, 1)
        guard case let .processing(lock) = aiChat.backgroundExecutionPhases.values.first else {
            XCTFail("parked resolver should start as background processing owner")
            return
        }
        XCTAssertEqual(lock.context.sessionID, pendingSessionID)
    }

    func testBackgroundPendingResolverUsesPendingSessionIDWhenAliasKeyExists() async throws {
        let aiSessionID = AiChatSessionID(rawValue: UUID())
        let aliasSessionID = AiChatSessionID(rawValue: UUID())
        let requestLock = makeRequestLock(sessionID: aiSessionID)
        let aliasLock = makeRequestLock(sessionID: aliasSessionID)
        let selectedModel = try XCTUnwrap(requestLock.context.selectedModel)
        let resolutionID = UUID()
        let pendingRequest = AiChatPendingRequestStart(
            resolutionID: resolutionID,
            kind: .submit,
            sessionID: aiSessionID,
            selectedModel: selectedModel,
            selectedRow: requestLock.selectedModelRow,
            preparedRequest: AiChatPreparedRequest(
                prompt: "test",
                messages: requestLock.request.messages,
                assistantReplacementIndex: nil,
                historyTruncation: AiChatHistoryTruncationMetadata(
                    includedMessageCount: requestLock.request.messages.count,
                    excludedMessageCount: 0,
                    budget: 24000,
                    truncationReason: nil,
                ),
            ),
        )

        var backgroundContent = FileManagerContentFeature.State()
        backgroundContent.aiChat.sessionID = aiSessionID
        backgroundContent.aiChat.sessionStatus = .active
        backgroundContent.aiChat.pendingRequestStart = pendingRequest
        backgroundContent.aiChat.backgroundExecutionPhases[aliasLock.requestID] = .completed(aliasLock)
        backgroundContent.aiChat.modelListState = .loaded([selectedModel])
        backgroundContent.aiChat.selectedModelHandle = selectedModel.id

        var state = FileManagerFeature.State()
        state.backgroundAiChatStates[aiSessionID] = backgroundContent
        state.backgroundAiChatStates[aliasSessionID] = backgroundContent

        let store: TestStore<FileManagerFeature.State, FileManagerWindowAction> = TestStore(initialState: state) {
            FileManagerFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
            $0.uuid = .incrementing
            $0.aiChatExecutionClient.execute = { _, _ in
                AsyncStream { continuation in
                    continuation.finish()
                }
            }
        }
        store.exhaustivity = .off

        let resolvedContext = AiChatResolvedRequestContext(
            currentContext: .init(),
            addedAttachments: [],
            parts: [],
        )
        await store.send(.content(.aiChat(.requestContextResolved(resolutionID, resolvedContext)))) { state in
            state.backgroundAiChatStates[aiSessionID]?.aiChat.pendingRequestStart = nil
            if case .processing = state.backgroundAiChatStates[aiSessionID]?.aiChat.executionPhase {
            } else {
                XCTFail("background AI Chat should route resolver completion to the pending session key")
            }
        }

        await store.skipReceivedActions()
        XCTAssertNil(store.state.backgroundAiChatStates[aiSessionID]?.aiChat.pendingRequestStart)
        XCTAssertEqual(
            store.state.backgroundAiChatStates[aliasSessionID]?.aiChat.pendingRequestStart?.sessionID,
            aiSessionID,
        )
        XCTAssertEqual(
            store.state.backgroundAiChatStates[aliasSessionID]?.aiChat.backgroundExecutionPhases[aliasLock.requestID],
            .completed(aliasLock),
        )
        await store.finish()
    }

    func testCompletedAiChatClosePreservesFinalPersistenceOwner() async {
        let aiChatTabID = ContentTabID()
        let homeTabID = ContentTabID()
        let aiSessionID = AiChatSessionID(rawValue: UUID())
        let requestLock = makeRequestLock(sessionID: aiSessionID)

        var aiChatContent = FileManagerContentFeature.State()
        aiChatContent.aiChat.sessionID = aiSessionID
        aiChatContent.aiChat.sessionStatus = .active
        aiChatContent.aiChat.executionPhase = .completed(requestLock)
        aiChatContent.aiChat.transcriptHistory = [
            AiChatMessage(role: .user, content: "test"),
            AiChatMessage(role: .assistant, content: "done"),
        ]

        let homeContent = FileManagerContentFeature.State()

        var state = FileManagerFeature.State()
        state.contentTabs = ContentTabState(
            tabs: [
                ContentTabItem(
                    id: aiChatTabID,
                    page: .aiChat,
                    anchor: .aiChat(sessionID: aiSessionID.rawValue.uuidString),
                    isPinned: false,
                    title: "AI Chat",
                    iconName: "message",
                ),
                ContentTabItem(
                    id: homeTabID,
                    page: .home,
                    anchor: .homeDefault,
                    isPinned: false,
                    title: "Home",
                    iconName: "house",
                ),
            ],
            activeTabID: aiChatTabID,
            recentlyClosed: nil,
        )
        state.content = aiChatContent
        state.tabContentStates = [homeTabID: homeContent]
        state.syncContentTabSidebarItems()

        let store: TestStore<FileManagerFeature.State, FileManagerWindowAction> = TestStore(initialState: state) {
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

        await store.send(.contentTabs(.close(aiChatTabID)))
        await store.skipReceivedActions()

        XCTAssertEqual(store.state.backgroundAiChatStates[aiSessionID]?.aiChat.executionPhase, .completed(requestLock))

        await store.send(.content(.aiChat(.persistenceFailed(requestLock, .unknown)))) { state in
            state.backgroundAiChatStates[aiSessionID]?.aiChat.executionPhase = .persistenceRecovery(
                requestLock,
                .unknown,
            )
            state.backgroundAiChatStates[aiSessionID]?.aiChat.lastExecutionFailure = .unknown
        }

        XCTAssertNil(store.state.content.aiChat.sessionID)
        XCTAssertEqual(
            store.state.backgroundAiChatStates[aiSessionID]?.aiChat.executionPhase,
            .persistenceRecovery(requestLock, .unknown),
        )
        await store.finish()
    }

    func testBackgroundAiChatFinalSaveRefreshesActiveSameSessionTranscript() async {
        let aiChatTabID = ContentTabID()
        let aiSessionID = AiChatSessionID(rawValue: UUID())
        let requestLock = makeRequestLock(sessionID: aiSessionID)
        let snapshot = AiChatSessionSnapshot(
            sessionID: aiSessionID,
            status: .active,
            provider: .openai,
            model: requestLock.selectedModelHandle,
            transcriptHistory: [
                AiChatMessage(role: .user, content: "test"),
                AiChatMessage(role: .assistant, content: "done"),
            ],
            updatedAtMs: 1_234_567_891_000,
        )
        let summary = AiChatSessionSummary(snapshot: snapshot)

        var activeContent = FileManagerContentFeature.State()
        activeContent.navigation.navigationState = .aiChat(aiSessionID.rawValue.uuidString)
        activeContent.aiChat.mode = .chat
        activeContent.aiChat.sessionID = aiSessionID
        activeContent.aiChat.sessionStatus = .active
        activeContent.aiChat.transcriptHistory = [
            AiChatMessage(role: .user, content: "test"),
        ]

        var backgroundContent = activeContent
        backgroundContent.aiChat.executionPhase = .completed(requestLock)
        backgroundContent.aiChat.transcriptHistory = snapshot.transcriptHistory
        backgroundContent.aiChat.selectedModelHandle = requestLock.selectedModelHandle
        backgroundContent.aiChat.lastRequestContextModelHandle = requestLock.selectedModelHandle

        var state = FileManagerFeature.State()
        state.contentTabs = ContentTabState(
            tabs: [
                ContentTabItem(
                    id: aiChatTabID,
                    page: .aiChat,
                    anchor: .aiChat(sessionID: aiSessionID.rawValue.uuidString),
                    isPinned: false,
                    title: "AI Chat",
                    iconName: "message",
                ),
            ],
            activeTabID: aiChatTabID,
            recentlyClosed: nil,
        )
        state.content = activeContent
        state.tabContentStates = [aiChatTabID: activeContent]
        state.backgroundAiChatStates[aiSessionID] = backgroundContent
        state.syncContentTabSidebarItems()

        let store = TestStore(initialState: state) {
            FileManagerFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
        }
        store.exhaustivity = .off

        await store.send(.backgroundAiChat(.sessionSnapshotSaved(
            summary,
            snapshot: snapshot,
            requestID: requestLock.requestID,
            runID: requestLock.runID,
        ))) { state in
            state.content.aiChat.transcriptHistory = snapshot.transcriptHistory
            state.content.aiChat.executionPhase = .completed(requestLock)
            state.content.aiChat.selectedModelHandle = requestLock.selectedModelHandle
            state.content.aiChat.lastRequestContextModelHandle = requestLock.selectedModelHandle
            state.content.aiChat.sessionList.replaceRow(summary)
            state.content.aiChat.sessionList.selectedSessionID = aiSessionID
            state.tabContentStates[aiChatTabID] = state.content
            state.backgroundAiChatStates.removeValue(forKey: aiSessionID)
        }

        XCTAssertEqual(store.state.content.aiChat.transcriptHistory.map(\.content), ["test", "done"])
        XCTAssertEqual(
            store.state.tabContentStates[aiChatTabID]?.aiChat.transcriptHistory.map(\.content),
            ["test", "done"],
        )
        XCTAssertNil(store.state.backgroundAiChatStates[aiSessionID])
        await store.finish()
    }

    func testBackgroundRequestStartSnapshotUpdatedRefreshesActiveSessionRow() async {
        let aiChatTabID = ContentTabID()
        let aiSessionID = AiChatSessionID(rawValue: UUID())
        let requestLock = makeRequestLock(sessionID: aiSessionID)
        let snapshot = AiChatSessionSnapshot(
            sessionID: aiSessionID,
            status: .active,
            provider: .openai,
            model: requestLock.selectedModelHandle,
            transcriptHistory: requestLock.request.messages,
            lastRequestID: requestLock.requestID,
            lastRunID: requestLock.runID,
            updatedAtMs: 1_234_567_891_000,
        )
        let summary = AiChatSessionSummary(snapshot: snapshot)

        var activeContent = FileManagerContentFeature.State()
        activeContent.navigation.navigationState = .aiChat(aiSessionID.rawValue.uuidString)
        activeContent.aiChat.mode = .chat
        activeContent.aiChat.sessionID = aiSessionID
        activeContent.aiChat.sessionStatus = .active
        activeContent.aiChat.transcriptHistory = []

        var backgroundContent = activeContent
        backgroundContent.aiChat.executionPhase = .processing(requestLock)
        backgroundContent.aiChat.transcriptHistory = requestLock.request.messages
        backgroundContent.aiChat.selectedModelHandle = requestLock.selectedModelHandle
        backgroundContent.aiChat.lastRequestContextModelHandle = requestLock.selectedModelHandle

        var state = FileManagerFeature.State()
        state.contentTabs = ContentTabState(
            tabs: [
                ContentTabItem(
                    id: aiChatTabID,
                    page: .aiChat,
                    anchor: .aiChat(sessionID: aiSessionID.rawValue.uuidString),
                    isPinned: false,
                    title: "AI Chat",
                    iconName: "message",
                ),
            ],
            activeTabID: aiChatTabID,
            recentlyClosed: nil,
        )
        state.content = activeContent
        state.tabContentStates = [aiChatTabID: activeContent]
        state.backgroundAiChatStates[aiSessionID] = backgroundContent
        state.syncContentTabSidebarItems()

        let store = TestStore(initialState: state) {
            FileManagerFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
        }
        store.exhaustivity = .off

        await store.send(.backgroundAiChat(.sessionSnapshotUpdated(
            summary,
            snapshot: snapshot,
            requestID: requestLock.requestID,
            runID: requestLock.runID,
        ))) { state in
            state.content.aiChat.transcriptHistory = requestLock.request.messages
            state.content.aiChat.executionPhase = .processing(requestLock)
            state.content.aiChat.selectedModelHandle = requestLock.selectedModelHandle
            state.content.aiChat.lastRequestContextModelHandle = requestLock.selectedModelHandle
            state.content.aiChat.sessionList.replaceRow(summary)
            state.content.aiChat.sessionList.selectedSessionID = aiSessionID
            state.tabContentStates[aiChatTabID] = state.content
        }

        XCTAssertEqual(store.state.content.aiChat.sessionList.allRows.first?.sessionID, aiSessionID)
        XCTAssertEqual(store.state.content.aiChat.transcriptHistory, requestLock.request.messages)
        XCTAssertEqual(
            store.state.backgroundAiChatStates[aiSessionID]?.aiChat.executionPhase,
            .processing(requestLock),
        )
        await store.finish()
    }

    func testBackgroundFinalSnapshotRefreshesInactiveProcessingCopyWithMatchingOwner() async throws {
        let homeTabID = ContentTabID()
        let aiChatTabID = ContentTabID()
        let aiSessionID = AiChatSessionID(rawValue: UUID())
        let requestLock = makeRequestLock(sessionID: aiSessionID)
        let finalLock = requestLock.recordingFinalSnapshot(AiChatSessionSnapshot(
            sessionID: aiSessionID,
            status: .active,
            provider: .openai,
            model: requestLock.selectedModelHandle,
            transcriptHistory: [
                AiChatMessage(role: .user, content: "test"),
                AiChatMessage(role: .assistant, content: "done"),
            ],
            lastRequestID: requestLock.requestID,
            lastRunID: requestLock.runID,
            updatedAtMs: 1_234_567_891_000,
        ))
        let snapshot = try XCTUnwrap(finalLock.finalSnapshot)
        let summary = AiChatSessionSummary(snapshot: snapshot)

        var homeContent = FileManagerContentFeature.State()
        homeContent.navigation.navigationState = .home

        var inactiveAiChatContent = FileManagerContentFeature.State()
        inactiveAiChatContent.navigation.navigationState = .aiChat(aiSessionID.rawValue.uuidString)
        inactiveAiChatContent.aiChat.mode = .chat
        inactiveAiChatContent.aiChat.sessionID = aiSessionID
        inactiveAiChatContent.aiChat.sessionStatus = .active
        inactiveAiChatContent.aiChat.transcriptHistory = []
        inactiveAiChatContent.aiChat.executionPhase = .processing(requestLock)

        var backgroundContent = inactiveAiChatContent
        backgroundContent.aiChat.executionPhase = .idle
        backgroundContent.aiChat.backgroundExecutionPhases[requestLock.requestID] = .completed(finalLock)

        var state = FileManagerFeature.State()
        state.contentTabs = ContentTabState(
            tabs: [
                ContentTabItem(
                    id: homeTabID,
                    page: .home,
                    anchor: .homeDefault,
                    isPinned: false,
                    title: "Home",
                    iconName: "house",
                ),
                ContentTabItem(
                    id: aiChatTabID,
                    page: .aiChat,
                    anchor: .aiChat(sessionID: aiSessionID.rawValue.uuidString),
                    isPinned: false,
                    title: "AI Chat",
                    iconName: "message",
                ),
            ],
            activeTabID: homeTabID,
            recentlyClosed: nil,
        )
        state.content = homeContent
        state.tabContentStates = [
            homeTabID: homeContent,
            aiChatTabID: inactiveAiChatContent,
        ]
        state.backgroundAiChatStates[aiSessionID] = backgroundContent
        state.syncContentTabSidebarItems()

        let store = TestStore(initialState: state) {
            FileManagerFeature()
        }
        store.exhaustivity = .off

        await store.send(.backgroundAiChat(.sessionSnapshotSaved(
            summary,
            snapshot: snapshot,
            requestID: requestLock.requestID,
            runID: requestLock.runID,
        ))) { state in
            state.tabContentStates[aiChatTabID]?.aiChat.transcriptHistory = snapshot.transcriptHistory
            state.tabContentStates[aiChatTabID]?.aiChat.executionPhase = .completed(finalLock)
            state.tabContentStates[aiChatTabID]?.aiChat.sessionList.replaceRow(summary)
            state.tabContentStates[aiChatTabID]?.aiChat.sessionList.selectedSessionID = aiSessionID
            state.backgroundAiChatStates[aiSessionID]?.aiChat.backgroundExecutionPhases[requestLock.requestID] = nil
        }

        XCTAssertEqual(
            store.state.tabContentStates[aiChatTabID]?.aiChat.transcriptHistory.map(\.content),
            ["test", "done"],
        )
        XCTAssertEqual(
            store.state.tabContentStates[aiChatTabID]?.aiChat.executionPhase,
            .completed(finalLock),
        )
        XCTAssertNil(store.state.backgroundAiChatStates[aiSessionID]?.aiChat
            .backgroundExecutionPhases[requestLock.requestID])
        await store.finish()
    }

    func testActiveFailureDoesNotRefreshContentFromItself() async {
        let aiSessionID = AiChatSessionID(rawValue: UUID())
        let requestLock = makeRequestLock(sessionID: aiSessionID)
        var activeContent = FileManagerContentFeature.State()
        activeContent.aiChat.sessionID = aiSessionID
        activeContent.aiChat.sessionStatus = .active
        activeContent.aiChat.executionPhase = .processing(requestLock)
        activeContent.aiChat.transcriptHistory = requestLock.request.messages
        activeContent.aiChat.streamingAssistantDraft = "partial answer"

        var state = FileManagerFeature.State()
        state.content = activeContent

        let store = TestStore(initialState: state) {
            FileManagerFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
        }
        store.exhaustivity = .off

        await store.send(.content(.aiChat(.executionEvent(.failed(
            context: requestLock.context,
            reason: .network,
        )))))

        let expectedFailedLock = requestLock.recordingTerminal(
            at: 1_234_567_890_000,
            failure: .network,
            wasCancelled: false,
        )
        XCTAssertEqual(store.state.content.aiChat.executionPhase, .failed(expectedFailedLock, .network))
        XCTAssertEqual(store.state.content.aiChat.streamingAssistantDraft, "partial answer")
        XCTAssertEqual(store.state.content.aiChat.transcriptHistory, requestLock.request.messages)
        XCTAssertEqual(store.state.content.aiChat.lastExecutionFailure, .network)
        await store.finish()
    }

    func testBackgroundFailureRefreshesInactiveProcessingCopyWithMatchingOwner() async {
        let homeTabID = ContentTabID()
        let aiChatTabID = ContentTabID()
        let aiSessionID = AiChatSessionID(rawValue: UUID())
        let requestLock = makeRequestLock(sessionID: aiSessionID)

        var homeContent = FileManagerContentFeature.State()
        homeContent.navigation.navigationState = .home

        var inactiveAiChatContent = FileManagerContentFeature.State()
        inactiveAiChatContent.navigation.navigationState = .aiChat(aiSessionID.rawValue.uuidString)
        inactiveAiChatContent.aiChat.mode = .chat
        inactiveAiChatContent.aiChat.sessionID = aiSessionID
        inactiveAiChatContent.aiChat.sessionStatus = .active
        inactiveAiChatContent.aiChat.transcriptHistory = []
        inactiveAiChatContent.aiChat.executionPhase = .processing(requestLock)

        var backgroundContent = inactiveAiChatContent
        backgroundContent.aiChat.executionPhase = .idle
        backgroundContent.aiChat.backgroundExecutionPhases[requestLock.requestID] = .failed(requestLock, .unknown)

        var state = FileManagerFeature.State()
        state.contentTabs = ContentTabState(
            tabs: [
                ContentTabItem(
                    id: homeTabID,
                    page: .home,
                    anchor: .homeDefault,
                    isPinned: false,
                    title: "Home",
                    iconName: "house",
                ),
                ContentTabItem(
                    id: aiChatTabID,
                    page: .aiChat,
                    anchor: .aiChat(sessionID: aiSessionID.rawValue.uuidString),
                    isPinned: false,
                    title: "AI Chat",
                    iconName: "message",
                ),
            ],
            activeTabID: homeTabID,
            recentlyClosed: nil,
        )
        state.content = homeContent
        state.tabContentStates = [
            homeTabID: homeContent,
            aiChatTabID: inactiveAiChatContent,
        ]
        state.backgroundAiChatStates[aiSessionID] = backgroundContent
        state.syncContentTabSidebarItems()

        let store = TestStore(initialState: state) {
            FileManagerFeature()
        }
        store.exhaustivity = .off

        await store.send(.backgroundAiChat(.persistenceFailed(requestLock, .unknown))) { state in
            state.tabContentStates[aiChatTabID]?.aiChat.transcriptHistory = requestLock.persistenceTranscriptHistory
            state.tabContentStates[aiChatTabID]?.aiChat.lastRequestContext = requestLock.context.requestContext
            state.tabContentStates[aiChatTabID]?.aiChat.lastRequestContextModelHandle = requestLock.context.model
            state.tabContentStates[aiChatTabID]?.aiChat.selectedModelHandle = requestLock.context.model
            state.tabContentStates[aiChatTabID]?.aiChat.selectedThinking = requestLock.context.selectedThinking
            state.tabContentStates[aiChatTabID]?.aiChat.transcriptAutoScrollVersion = 1
            state.tabContentStates[aiChatTabID]?.aiChat.executionPhase = .persistenceRecovery(requestLock, .unknown)
            state.tabContentStates[aiChatTabID]?.aiChat.lastExecutionFailure = .unknown
            state.backgroundAiChatStates[aiSessionID]?.aiChat
                .backgroundExecutionPhases[requestLock.requestID] = .persistenceRecovery(
                    requestLock,
                    .unknown,
                )
        }

        XCTAssertEqual(
            store.state.tabContentStates[aiChatTabID]?.aiChat.transcriptHistory,
            requestLock.persistenceTranscriptHistory,
        )
        XCTAssertEqual(
            store.state.tabContentStates[aiChatTabID]?.aiChat.executionPhase,
            .persistenceRecovery(requestLock, .unknown),
        )
        XCTAssertEqual(
            store.state.backgroundAiChatStates[aiSessionID]?.aiChat.backgroundExecutionPhases[requestLock.requestID],
            .persistenceRecovery(requestLock, .unknown),
        )
        await store.finish()
    }

    func testBackgroundRecoveryRefreshesInactiveProcessingCopyWithMatchingOwner() async throws {
        let homeTabID = ContentTabID()
        let aiChatTabID = ContentTabID()
        let aiSessionID = AiChatSessionID(rawValue: UUID())
        let requestLock = makeRequestLock(sessionID: aiSessionID)
        let finalLock = requestLock.recordingFinalSnapshot(AiChatSessionSnapshot(
            sessionID: aiSessionID,
            status: .active,
            provider: .openai,
            model: requestLock.selectedModelHandle,
            transcriptHistory: [
                AiChatMessage(role: .user, content: "test"),
                AiChatMessage(role: .assistant, content: "done"),
            ],
            lastRequestID: requestLock.requestID,
            lastRunID: requestLock.runID,
            lastRequestContext: requestLock.context.requestContext,
            updatedAtMs: 1_234_567_891_000,
        ))
        let finalSnapshot = try XCTUnwrap(finalLock.finalSnapshot)

        var homeContent = FileManagerContentFeature.State()
        homeContent.navigation.navigationState = .home

        var inactiveAiChatContent = FileManagerContentFeature.State()
        inactiveAiChatContent.navigation.navigationState = .aiChat(aiSessionID.rawValue.uuidString)
        inactiveAiChatContent.aiChat.mode = .chat
        inactiveAiChatContent.aiChat.sessionID = aiSessionID
        inactiveAiChatContent.aiChat.sessionStatus = .active
        inactiveAiChatContent.aiChat.transcriptHistory = requestLock.request.messages
        inactiveAiChatContent.aiChat.executionPhase = .processing(requestLock)

        var backgroundContent = inactiveAiChatContent
        backgroundContent.aiChat.executionPhase = .idle
        backgroundContent.aiChat.backgroundExecutionPhases[requestLock.requestID] = .persistenceRecovery(
            finalLock,
            .unknown,
        )

        var state = FileManagerFeature.State()
        state.contentTabs = ContentTabState(
            tabs: [
                ContentTabItem(
                    id: homeTabID,
                    page: .home,
                    anchor: .homeDefault,
                    isPinned: false,
                    title: "Home",
                    iconName: "house",
                ),
                ContentTabItem(
                    id: aiChatTabID,
                    page: .aiChat,
                    anchor: .aiChat(sessionID: aiSessionID.rawValue.uuidString),
                    isPinned: false,
                    title: "AI Chat",
                    iconName: "message",
                ),
            ],
            activeTabID: homeTabID,
            recentlyClosed: nil,
        )
        state.content = homeContent
        state.tabContentStates = [
            homeTabID: homeContent,
            aiChatTabID: inactiveAiChatContent,
        ]
        state.backgroundAiChatStates[aiSessionID] = backgroundContent
        state.syncContentTabSidebarItems()

        let store = TestStore(initialState: state) {
            FileManagerFeature()
        }
        store.exhaustivity = .off

        await store.send(.backgroundAiChat(.persistenceRecoverySucceeded(finalLock))) { state in
            state.tabContentStates[aiChatTabID]?.aiChat.transcriptHistory = finalSnapshot.transcriptHistory
            state.tabContentStates[aiChatTabID]?.aiChat.executionPhase = .completed(finalLock)
            state.tabContentStates[aiChatTabID]?.aiChat.lastExecutionFailure = nil
            state.tabContentStates[aiChatTabID]?.aiChat.currentSessionCustomTitle = finalSnapshot.customTitle
            state.tabContentStates[aiChatTabID]?.aiChat.lastRequestContext = finalSnapshot.lastRequestContext
            state.tabContentStates[aiChatTabID]?.aiChat.lastRequestContextModelHandle = finalSnapshot.model
            state.tabContentStates[aiChatTabID]?.aiChat.selectedModelHandle = finalSnapshot.model
            state.tabContentStates[aiChatTabID]?.aiChat.selectedThinking = finalSnapshot.selectedThinking
            state.backgroundAiChatStates[aiSessionID]?.aiChat.backgroundExecutionPhases[requestLock.requestID] = nil
        }

        XCTAssertEqual(
            store.state.tabContentStates[aiChatTabID]?.aiChat.executionPhase,
            .completed(finalLock),
        )
        XCTAssertEqual(
            store.state.tabContentStates[aiChatTabID]?.aiChat.transcriptHistory.map(\.content),
            ["test", "done"],
        )
        XCTAssertNil(store.state.backgroundAiChatStates[aiSessionID]?.aiChat
            .backgroundExecutionPhases[requestLock.requestID])
        await store.finish()
    }

    func testBackgroundSnapshotRefreshDoesNotCopyUnrelatedExecutionPhase() async {
        let aiChatTabID = ContentTabID()
        let aiSessionID = AiChatSessionID(rawValue: UUID())
        let otherSessionID = AiChatSessionID(rawValue: UUID())
        let requestLock = makeRequestLock(sessionID: aiSessionID)
        let unrelatedLock = makeRequestLock(sessionID: otherSessionID)
        let snapshot = AiChatSessionSnapshot(
            sessionID: aiSessionID,
            status: .active,
            provider: .openai,
            model: requestLock.selectedModelHandle,
            transcriptHistory: [
                AiChatMessage(role: .user, content: "test"),
                AiChatMessage(role: .assistant, content: "done"),
            ],
            lastRequestID: requestLock.requestID,
            lastRunID: requestLock.runID,
            updatedAtMs: 1_234_567_891_000,
        )
        let summary = AiChatSessionSummary(snapshot: snapshot)

        var activeContent = FileManagerContentFeature.State()
        activeContent.navigation.navigationState = .aiChat(aiSessionID.rawValue.uuidString)
        activeContent.aiChat.mode = .chat
        activeContent.aiChat.sessionID = aiSessionID
        activeContent.aiChat.sessionStatus = .active
        activeContent.aiChat.transcriptHistory = [
            AiChatMessage(role: .user, content: "test"),
        ]

        var backgroundContent = activeContent
        backgroundContent.aiChat.executionPhase = .processing(unrelatedLock)
        backgroundContent.aiChat.transcriptHistory = snapshot.transcriptHistory
        backgroundContent.aiChat.backgroundExecutionPhases[requestLock.requestID] = .completed(requestLock)

        var state = FileManagerFeature.State()
        state.contentTabs = ContentTabState(
            tabs: [
                ContentTabItem(
                    id: aiChatTabID,
                    page: .aiChat,
                    anchor: .aiChat(sessionID: aiSessionID.rawValue.uuidString),
                    isPinned: false,
                    title: "AI Chat",
                    iconName: "message",
                ),
            ],
            activeTabID: aiChatTabID,
            recentlyClosed: nil,
        )
        state.content = activeContent
        state.tabContentStates = [aiChatTabID: activeContent]
        state.backgroundAiChatStates[aiSessionID] = backgroundContent
        state.syncContentTabSidebarItems()

        let store = TestStore(initialState: state) {
            FileManagerFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
        }
        store.exhaustivity = .off

        await store.send(.backgroundAiChat(.sessionSnapshotSaved(
            summary,
            snapshot: snapshot,
            requestID: requestLock.requestID,
            runID: requestLock.runID,
        ))) { state in
            state.content.aiChat.transcriptHistory = snapshot.transcriptHistory
            state.content.aiChat.sessionList.replaceRow(summary)
            state.content.aiChat.sessionList.selectedSessionID = aiSessionID
            state.tabContentStates[aiChatTabID] = state.content
            state.backgroundAiChatStates[aiSessionID]?.aiChat.backgroundExecutionPhases[requestLock.requestID] = nil
        }

        XCTAssertEqual(store.state.content.aiChat.transcriptHistory.map(\.content), ["test", "done"])
        XCTAssertEqual(store.state.content.aiChat.executionPhase, .idle)
        XCTAssertEqual(
            store.state.backgroundAiChatStates[aiSessionID]?.aiChat.executionPhase,
            .processing(unrelatedLock),
        )
        XCTAssertNil(store.state.backgroundAiChatStates[aiSessionID]?.aiChat
            .backgroundExecutionPhases[requestLock.requestID])
        await store.finish()
    }

    func testBackgroundAiChatFollowUpKeepsMismatchedRequestOwner() async {
        let aiSessionID = AiChatSessionID(rawValue: UUID())
        let oldLock = makeRequestLock(sessionID: aiSessionID)
        let newLock = makeRequestLock(sessionID: aiSessionID)
        let finalSnapshot = AiChatSessionSnapshot(
            sessionID: aiSessionID,
            status: .active,
            provider: nil,
            model: nil,
            transcriptHistory: [
                AiChatMessage(role: .user, content: "old"),
                AiChatMessage(role: .assistant, content: "done"),
            ],
            updatedAtMs: 1_234_567_890_000,
        )
        let oldRecoveryLock = oldLock.recordingFinalSnapshot(finalSnapshot)
        let newSnapshot = AiChatSessionSnapshot(
            sessionID: aiSessionID,
            status: .active,
            provider: nil,
            model: nil,
            transcriptHistory: [
                AiChatMessage(role: .user, content: "new"),
                AiChatMessage(role: .assistant, content: "done"),
            ],
            lastRequestID: newLock.requestID,
            lastRunID: newLock.runID,
            updatedAtMs: 1_234_567_891_000,
        )
        let newSummary = AiChatSessionSummary(snapshot: newSnapshot)

        var backgroundContent = FileManagerContentFeature.State()
        backgroundContent.aiChat.sessionID = aiSessionID
        backgroundContent.aiChat.executionPhase = .persistenceRecovery(oldRecoveryLock, .unknown)
        backgroundContent.aiChat.lastExecutionFailure = .unknown

        var state = FileManagerFeature.State()
        state.content.aiChat.sessionID = aiSessionID
        state.content.aiChat.sessionStatus = .active
        state.content.aiChat.transcriptHistory = [AiChatMessage(role: .user, content: "active")]
        state.backgroundAiChatStates[aiSessionID] = backgroundContent

        let store = TestStore(initialState: state) {
            FileManagerFeature()
        }
        store.exhaustivity = .off

        await store.send(.backgroundAiChat(.sessionSnapshotSaved(
            newSummary,
            snapshot: newSnapshot,
            requestID: newLock.requestID,
            runID: newLock.runID,
        )))

        XCTAssertEqual(
            store.state.backgroundAiChatStates[aiSessionID]?.aiChat.executionPhase,
            .persistenceRecovery(oldRecoveryLock, .unknown),
        )
        XCTAssertEqual(store.state.content.aiChat.transcriptHistory.map(\.content), ["active"])

        await store.send(.backgroundAiChat(.persistenceRecoverySucceeded(newLock)))

        XCTAssertEqual(
            store.state.backgroundAiChatStates[aiSessionID]?.aiChat.executionPhase,
            .persistenceRecovery(oldRecoveryLock, .unknown),
        )

        await store.finish()

        var mixedBackgroundContent = FileManagerContentFeature.State()
        mixedBackgroundContent.aiChat.sessionID = aiSessionID
        mixedBackgroundContent.aiChat.executionPhase = .persistenceRecovery(oldRecoveryLock, .unknown)
        mixedBackgroundContent.aiChat.backgroundExecutionPhases[newLock.requestID] = .completed(newLock)

        var mixedState = FileManagerFeature.State()
        mixedState.backgroundAiChatStates[aiSessionID] = mixedBackgroundContent

        let mixedStore = TestStore(initialState: mixedState) {
            FileManagerFeature()
        }
        mixedStore.exhaustivity = .off

        await mixedStore.send(.backgroundAiChat(.persistenceRecoverySucceeded(newLock)))

        XCTAssertEqual(
            mixedStore.state.backgroundAiChatStates[aiSessionID]?.aiChat.executionPhase,
            .persistenceRecovery(oldRecoveryLock, .unknown),
        )
        XCTAssertNil(mixedStore.state.backgroundAiChatStates[aiSessionID]?.aiChat
            .backgroundExecutionPhases[newLock.requestID])
        XCTAssertNotNil(mixedStore.state.backgroundAiChatStates[aiSessionID])
        await mixedStore.finish()
    }

    func testBackgroundAiChatDeleteSessionRemovesClosedOwner() async {
        let aiSessionID = AiChatSessionID(rawValue: UUID())
        let otherSessionID = AiChatSessionID(rawValue: UUID())
        let requestLock = makeRequestLock(sessionID: aiSessionID)

        var backgroundContent = FileManagerContentFeature.State()
        backgroundContent.aiChat.sessionID = aiSessionID
        backgroundContent.aiChat.sessionStatus = .active
        backgroundContent.aiChat.executionPhase = .persistenceRecovery(requestLock, .unknown)
        backgroundContent.aiChat.lastExecutionFailure = .unknown

        var state = FileManagerFeature.State()
        state.content.aiChat.sessionID = otherSessionID
        state.content.aiChat.mode = .sessions
        state.backgroundAiChatStates[aiSessionID] = backgroundContent

        let store = TestStore(initialState: state) {
            FileManagerFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
            $0.aiChatSessionPersistenceClient.deleteSession = { _ in }
        }
        store.exhaustivity = .off

        await store.send(.content(.aiChat(.deleteSessionTapped(aiSessionID)))) { state in
            state.backgroundAiChatStates.removeValue(forKey: aiSessionID)
        }
        await store.finish()

        XCTAssertNil(store.state.backgroundAiChatStates[aiSessionID])
    }

    func testBackgroundAiChatFinalSaveRefreshesInactiveSameSessionTabSnapshot() async {
        let homeTabID = ContentTabID()
        let aiChatTabID = ContentTabID()
        let aiSessionID = AiChatSessionID(rawValue: UUID())
        let requestLock = makeRequestLock(sessionID: aiSessionID)
        let snapshot = AiChatSessionSnapshot(
            sessionID: aiSessionID,
            status: .active,
            provider: .openai,
            model: requestLock.selectedModelHandle,
            transcriptHistory: [
                AiChatMessage(role: .user, content: "test"),
                AiChatMessage(role: .assistant, content: "done"),
            ],
            updatedAtMs: 1_234_567_891_000,
        )
        let summary = AiChatSessionSummary(snapshot: snapshot)

        var homeContent = FileManagerContentFeature.State()
        homeContent.navigation.seedInitialFolderPath("/Users/test/Home")

        var staleAiChatContent = FileManagerContentFeature.State()
        staleAiChatContent.navigation.navigationState = .aiChat(aiSessionID.rawValue.uuidString)
        staleAiChatContent.aiChat.mode = .chat
        staleAiChatContent.aiChat.sessionID = aiSessionID
        staleAiChatContent.aiChat.sessionStatus = .active
        staleAiChatContent.aiChat.transcriptHistory = [
            AiChatMessage(role: .user, content: "test"),
        ]

        var backgroundContent = staleAiChatContent
        backgroundContent.aiChat.executionPhase = .completed(requestLock)
        backgroundContent.aiChat.transcriptHistory = snapshot.transcriptHistory
        backgroundContent.aiChat.selectedModelHandle = requestLock.selectedModelHandle
        backgroundContent.aiChat.lastRequestContextModelHandle = requestLock.selectedModelHandle

        var state = FileManagerFeature.State()
        state.contentTabs = ContentTabState(
            tabs: [
                ContentTabItem(
                    id: homeTabID,
                    page: .home,
                    anchor: .homeDefault,
                    isPinned: false,
                    title: "Home",
                    iconName: "house",
                ),
                ContentTabItem(
                    id: aiChatTabID,
                    page: .aiChat,
                    anchor: .aiChat(sessionID: aiSessionID.rawValue.uuidString),
                    isPinned: false,
                    title: "AI Chat",
                    iconName: "message",
                ),
            ],
            activeTabID: homeTabID,
            recentlyClosed: nil,
        )
        state.content = homeContent
        state.tabContentStates = [
            homeTabID: homeContent,
            aiChatTabID: staleAiChatContent,
        ]
        state.backgroundAiChatStates[aiSessionID] = backgroundContent
        state.syncContentTabSidebarItems()

        let store = TestStore(initialState: state) {
            FileManagerFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
        }
        store.exhaustivity = .off

        await store.send(.backgroundAiChat(.sessionSnapshotSaved(
            summary,
            snapshot: snapshot,
            requestID: requestLock.requestID,
            runID: requestLock.runID,
        ))) { state in
            var refreshedAiChatContent = staleAiChatContent
            refreshedAiChatContent.aiChat.transcriptHistory = snapshot.transcriptHistory
            refreshedAiChatContent.aiChat.transcriptAutoScrollVersion += 1
            refreshedAiChatContent.aiChat.executionPhase = .completed(requestLock)
            refreshedAiChatContent.aiChat.selectedModelHandle = requestLock.selectedModelHandle
            refreshedAiChatContent.aiChat.lastRequestContextModelHandle = requestLock.selectedModelHandle
            refreshedAiChatContent.aiChat.sessionList.replaceRow(summary)
            refreshedAiChatContent.aiChat.sessionList.selectedSessionID = aiSessionID
            state.tabContentStates[aiChatTabID] = refreshedAiChatContent
            state.backgroundAiChatStates.removeValue(forKey: aiSessionID)
        }

        XCTAssertNil(store.state.content.aiChat.sessionID)
        XCTAssertEqual(
            store.state.tabContentStates[aiChatTabID]?.aiChat.transcriptHistory.map(\.content),
            ["test", "done"],
        )
        XCTAssertEqual(
            store.state.tabContentStates[aiChatTabID]?.aiChat.executionPhase,
            .completed(requestLock),
        )
        XCTAssertNil(store.state.backgroundAiChatStates[aiSessionID])
        await store.finish()
    }

    func testBackgroundInspectorPendingContextResolutionStartsRequest() async throws {
        let inspectorSessionID = AiChatSessionID(rawValue: UUID())
        let requestLock = makeRequestLock(sessionID: inspectorSessionID)
        let selectedModel = try XCTUnwrap(requestLock.context.selectedModel)
        let resolutionID = UUID()
        let pendingRequest = AiChatPendingRequestStart(
            resolutionID: resolutionID,
            kind: .submit,
            sessionID: inspectorSessionID,
            selectedModel: selectedModel,
            selectedRow: requestLock.selectedModelRow,
            preparedRequest: AiChatPreparedRequest(
                prompt: "test",
                messages: requestLock.request.messages,
                assistantReplacementIndex: nil,
                historyTruncation: AiChatHistoryTruncationMetadata(
                    includedMessageCount: requestLock.request.messages.count,
                    excludedMessageCount: 0,
                    budget: 24000,
                    truncationReason: nil,
                ),
            ),
        )

        var backgroundInspector = FileManagerInspectorFeature.State()
        backgroundInspector.inspectorVisible = true
        backgroundInspector.activeMode = .chat
        backgroundInspector.aiChat.sessionID = inspectorSessionID
        backgroundInspector.aiChat.sessionStatus = .active
        backgroundInspector.aiChat.pendingRequestStart = pendingRequest
        backgroundInspector.aiChat.modelListState = .loaded([selectedModel])
        backgroundInspector.aiChat.selectedModelHandle = selectedModel.id

        var state = FileManagerFeature.State()
        state.backgroundInspectorAiChatStates[inspectorSessionID] = backgroundInspector.tabSnapshot()

        let store: TestStore<FileManagerFeature.State, FileManagerWindowAction> = TestStore(initialState: state) {
            FileManagerFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
            $0.uuid = .incrementing
            $0.aiChatExecutionClient.execute = { _, _ in
                AsyncStream { continuation in
                    continuation.finish()
                }
            }
        }
        store.exhaustivity = .off

        let resolvedContext = AiChatResolvedRequestContext(
            currentContext: .init(),
            addedAttachments: [],
            parts: [],
        )
        await store.send(.inspector(.aiChat(.requestContextResolved(resolutionID, resolvedContext)))) { state in
            state.backgroundInspectorAiChatStates[inspectorSessionID]?.aiChat.pendingRequestStart = nil
            if case .processing = state.backgroundInspectorAiChatStates[inspectorSessionID]?.aiChat.executionPhase {
            } else {
                XCTFail("background Inspector AI Chat should start processing after resolver completion")
            }
        }

        await store.skipReceivedActions()
        XCTAssertNotNil(store.state.backgroundInspectorAiChatStates[inspectorSessionID])
        XCTAssertNil(store.state.inspector.aiChat.pendingRequestStart)
        await store.finish()
    }

    func testBackgroundInspectorPendingResolverUsesPendingSessionIDWhenAliasKeyExists() async throws {
        let inspectorSessionID = AiChatSessionID(rawValue: UUID())
        let aliasSessionID = AiChatSessionID(rawValue: UUID())
        let requestLock = makeRequestLock(sessionID: inspectorSessionID)
        let aliasLock = makeRequestLock(sessionID: aliasSessionID)
        let selectedModel = try XCTUnwrap(requestLock.context.selectedModel)
        let resolutionID = UUID()
        let pendingRequest = AiChatPendingRequestStart(
            resolutionID: resolutionID,
            kind: .submit,
            sessionID: inspectorSessionID,
            selectedModel: selectedModel,
            selectedRow: requestLock.selectedModelRow,
            preparedRequest: AiChatPreparedRequest(
                prompt: "test",
                messages: requestLock.request.messages,
                assistantReplacementIndex: nil,
                historyTruncation: AiChatHistoryTruncationMetadata(
                    includedMessageCount: requestLock.request.messages.count,
                    excludedMessageCount: 0,
                    budget: 24000,
                    truncationReason: nil,
                ),
            ),
        )

        var backgroundInspector = FileManagerInspectorFeature.State()
        backgroundInspector.inspectorVisible = true
        backgroundInspector.activeMode = .chat
        backgroundInspector.aiChat.sessionID = inspectorSessionID
        backgroundInspector.aiChat.sessionStatus = .active
        backgroundInspector.aiChat.pendingRequestStart = pendingRequest
        backgroundInspector.aiChat.backgroundExecutionPhases[aliasLock.requestID] = .completed(aliasLock)
        backgroundInspector.aiChat.modelListState = .loaded([selectedModel])
        backgroundInspector.aiChat.selectedModelHandle = selectedModel.id

        var state = FileManagerFeature.State()
        state.backgroundInspectorAiChatStates[inspectorSessionID] = backgroundInspector.tabSnapshot()
        state.backgroundInspectorAiChatStates[aliasSessionID] = backgroundInspector.tabSnapshot()

        let store: TestStore<FileManagerFeature.State, FileManagerWindowAction> = TestStore(initialState: state) {
            FileManagerFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
            $0.uuid = .incrementing
            $0.aiChatExecutionClient.execute = { _, _ in
                AsyncStream { continuation in
                    continuation.finish()
                }
            }
        }
        store.exhaustivity = .off

        let resolvedContext = AiChatResolvedRequestContext(
            currentContext: .init(),
            addedAttachments: [],
            parts: [],
        )
        await store.send(.inspector(.aiChat(.requestContextResolved(resolutionID, resolvedContext)))) { state in
            state.backgroundInspectorAiChatStates[inspectorSessionID]?.aiChat.pendingRequestStart = nil
            if case .processing = state.backgroundInspectorAiChatStates[inspectorSessionID]?.aiChat.executionPhase {
            } else {
                XCTFail("background Inspector AI Chat should route resolver completion to the pending session key")
            }
        }

        await store.skipReceivedActions()
        XCTAssertNil(store.state.backgroundInspectorAiChatStates[inspectorSessionID]?.aiChat.pendingRequestStart)
        XCTAssertEqual(
            store.state.backgroundInspectorAiChatStates[aliasSessionID]?.aiChat.pendingRequestStart?.sessionID,
            inspectorSessionID,
        )
        XCTAssertEqual(
            store.state.backgroundInspectorAiChatStates[aliasSessionID]?.aiChat
                .backgroundExecutionPhases[aliasLock.requestID],
            .completed(aliasLock),
        )
        await store.finish()
    }

    func testInactiveInspectorPendingContextResolutionStartsRequest() async throws {
        let homeTabID = ContentTabID()
        let directoryTabID = ContentTabID()
        let inspectorSessionID = AiChatSessionID(rawValue: UUID())
        let requestLock = makeRequestLock(sessionID: inspectorSessionID)
        let selectedModel = try XCTUnwrap(requestLock.context.selectedModel)
        let resolutionID = UUID()
        let pendingRequest = AiChatPendingRequestStart(
            resolutionID: resolutionID,
            kind: .submit,
            sessionID: inspectorSessionID,
            selectedModel: selectedModel,
            selectedRow: requestLock.selectedModelRow,
            preparedRequest: AiChatPreparedRequest(
                prompt: "test",
                messages: requestLock.request.messages,
                assistantReplacementIndex: nil,
                historyTruncation: AiChatHistoryTruncationMetadata(
                    includedMessageCount: requestLock.request.messages.count,
                    excludedMessageCount: 0,
                    budget: 24000,
                    truncationReason: nil,
                ),
            ),
        )

        var inactiveInspector = FileManagerInspectorFeature.State()
        inactiveInspector.inspectorVisible = true
        inactiveInspector.activeMode = .chat
        inactiveInspector.aiChat.sessionID = inspectorSessionID
        inactiveInspector.aiChat.sessionStatus = .active
        inactiveInspector.aiChat.pendingRequestStart = pendingRequest
        inactiveInspector.aiChat.modelListState = .loaded([selectedModel])
        inactiveInspector.aiChat.selectedModelHandle = selectedModel.id

        var state = FileManagerFeature.State()
        state.contentTabs = ContentTabState(
            tabs: [
                ContentTabItem(
                    id: homeTabID,
                    page: .home,
                    anchor: .homeDefault,
                    isPinned: false,
                    title: "Home",
                    iconName: "house",
                ),
                ContentTabItem(
                    id: directoryTabID,
                    page: .directory,
                    anchor: .directory(path: "/Users/test/Documents"),
                    isPinned: false,
                    title: "Documents",
                    iconName: "folder",
                ),
            ],
            activeTabID: homeTabID,
            recentlyClosed: nil,
        )
        state.tabInspectorStates[directoryTabID] = inactiveInspector.tabSnapshot()
        state.syncContentTabSidebarItems()

        let store: TestStore<FileManagerFeature.State, FileManagerWindowAction> = TestStore(initialState: state) {
            FileManagerFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
            $0.uuid = .incrementing
            $0.aiChatExecutionClient.execute = { _, _ in
                AsyncStream { continuation in
                    continuation.finish()
                }
            }
        }
        store.exhaustivity = .off

        let resolvedContext = AiChatResolvedRequestContext(
            currentContext: .init(),
            addedAttachments: [],
            parts: [],
        )
        await store.send(.inspector(.aiChat(.requestContextResolved(resolutionID, resolvedContext)))) { state in
            state.tabInspectorStates[directoryTabID]?.aiChat.pendingRequestStart = nil
            if case .processing = state.tabInspectorStates[directoryTabID]?.aiChat.executionPhase {
            } else {
                XCTFail("inactive Inspector AI Chat should start processing after resolver completion")
            }
        }

        await store.skipReceivedActions()
        XCTAssertNil(store.state.inspector.aiChat.pendingRequestStart)
        await store.finish()
    }

    func testClosingInspectorTabPreservesBackgroundExecutionPhases() async {
        let directoryTabID = ContentTabID()
        let homeTabID = ContentTabID()
        let inspectorSessionID = AiChatSessionID(rawValue: UUID())
        let requestLock = makeRequestLock(sessionID: inspectorSessionID)

        var directoryContent = FileManagerContentFeature.State()
        directoryContent.navigation.seedInitialFolderPath("/Users/test/Documents")

        var homeContent = FileManagerContentFeature.State()
        homeContent.navigation.seedInitialFolderPath("/Users/test/Home")

        var state = FileManagerFeature.State()
        state.contentTabs = ContentTabState(
            tabs: [
                ContentTabItem(
                    id: directoryTabID,
                    page: .directory,
                    anchor: .directory(path: "/Users/test/Documents"),
                    isPinned: false,
                    title: "Documents",
                    iconName: "folder",
                ),
                ContentTabItem(
                    id: homeTabID,
                    page: .home,
                    anchor: .homeDefault,
                    isPinned: false,
                    title: "Home",
                    iconName: "house",
                ),
            ],
            activeTabID: directoryTabID,
            recentlyClosed: nil,
        )
        state.content = directoryContent
        state.tabContentStates = [
            directoryTabID: directoryContent,
            homeTabID: homeContent,
        ]
        state.inspector.inspectorVisible = true
        state.inspector.activeMode = .chat
        state.inspector.aiChat.sessionID = nil
        state.inspector.aiChat.executionPhase = .idle
        state.inspector.aiChat.backgroundExecutionPhases[requestLock.requestID] = .processing(requestLock)
        state.syncActiveTabInspectorState()
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

        await store.send(.contentTabs(.close(directoryTabID)))
        await store.receive(\.content.internal.applyNavigationState)
        await store.skipReceivedActions()

        let backgroundInspector = store.state.backgroundInspectorAiChatStates[inspectorSessionID]
        XCTAssertNotNil(backgroundInspector)
        XCTAssertEqual(
            backgroundInspector?.aiChat.backgroundExecutionPhases[requestLock.requestID],
            .processing(requestLock),
        )
        XCTAssertNil(backgroundInspector?.aiChat.sessionID)
        await store.finish()
    }

    func testClosedInspectorTabFinalEventSavesSnapshotThroughBackgroundState() async {
        let directoryTabID = ContentTabID()
        let homeTabID = ContentTabID()
        let inspectorSessionID = AiChatSessionID(rawValue: UUID())
        let requestLock = makeRequestLock(sessionID: inspectorSessionID)
        let savedSnapshots = LockIsolated<[AiChatSessionSnapshot]>([])

        var directoryContent = FileManagerContentFeature.State()
        directoryContent.navigation.seedInitialFolderPath("/Users/test/Documents")

        var homeContent = FileManagerContentFeature.State()
        homeContent.navigation.seedInitialFolderPath("/Users/test/Home")

        var state = FileManagerFeature.State()
        state.contentTabs = ContentTabState(
            tabs: [
                ContentTabItem(
                    id: directoryTabID,
                    page: .directory,
                    anchor: .directory(path: "/Users/test/Documents"),
                    isPinned: false,
                    title: "Documents",
                    iconName: "folder",
                ),
                ContentTabItem(
                    id: homeTabID,
                    page: .home,
                    anchor: .homeDefault,
                    isPinned: false,
                    title: "Home",
                    iconName: "house",
                ),
            ],
            activeTabID: directoryTabID,
            recentlyClosed: nil,
        )
        state.content = directoryContent
        state.tabContentStates = [
            directoryTabID: directoryContent,
            homeTabID: homeContent,
        ]
        state.inspector.inspectorVisible = true
        state.inspector.activeMode = .chat
        state.inspector.aiChat.sessionID = inspectorSessionID
        state.inspector.aiChat.sessionStatus = .active
        state.inspector.aiChat.executionPhase = .processing(requestLock)
        state.inspector.aiChat.lockedModelHandle = requestLock.selectedModelHandle
        state.inspector.aiChat.transcriptHistory = [
            AiChatMessage(role: .user, content: "test"),
        ]
        state.syncActiveTabInspectorState()
        state.syncContentTabSidebarItems()

        let store = TestStore(initialState: state) {
            FileManagerFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
            $0.uuid = .incrementing
            $0.entryWatchingClient.startWatchingDirectory = { _ in
                AsyncStream { continuation in
                    continuation.finish()
                }
            }
            $0.aiChatSessionPersistenceClient.saveSession = { snapshot in
                savedSnapshots.withValue { $0.append(snapshot) }
                return snapshot
            }
        }
        store.exhaustivity = .off

        await store.send(.contentTabs(.close(directoryTabID)))
        await store.receive(\.content.internal.applyNavigationState)
        await store.skipReceivedActions()

        XCTAssertNotNil(store.state.backgroundInspectorAiChatStates[inspectorSessionID])
        XCTAssertEqual(
            store.state.backgroundInspectorAiChatStates[inspectorSessionID]?.aiChat.executionPhase,
            .processing(requestLock),
        )

        let response = AiChatResponse(
            context: requestLock.context,
            assistantMessage: AiChatMessage(role: .assistant, content: "done"),
            completedAtMs: 1_234_567_891_000,
        )

        await store.send(.inspector(.aiChat(.executionEvent(.final(response: response)))))

        await store.receive { action in
            guard case let .backgroundInspectorAiChatSnapshotPersisted(snapshot) = action else { return false }
            let summary = AiChatSessionSummary(snapshot: snapshot)
            return summary.sessionID == inspectorSessionID
        } assert: { state in
            state.backgroundInspectorAiChatStates.removeValue(forKey: inspectorSessionID)
        }

        await store.finish()

        let snapshots = savedSnapshots.value
        XCTAssertEqual(snapshots.count, 1)
        XCTAssertEqual(snapshots.first?.sessionID, inspectorSessionID)
        XCTAssertEqual(snapshots.first?.transcriptHistory.map(\.content), ["test", "done"])
        XCTAssertNil(store.state.backgroundInspectorAiChatStates[inspectorSessionID])
    }

    func testInactiveInspectorFinalSaveRefreshesTabInspectorSnapshot() async {
        let homeTabID = ContentTabID()
        let directoryTabID = ContentTabID()
        let inspectorSessionID = AiChatSessionID(rawValue: UUID())
        let requestLock = makeRequestLock(sessionID: inspectorSessionID)
        let savedSnapshots = LockIsolated<[AiChatSessionSnapshot]>([])

        var homeContent = FileManagerContentFeature.State()
        homeContent.navigation.seedInitialFolderPath("/Users/test/Home")

        var directoryContent = FileManagerContentFeature.State()
        directoryContent.navigation.seedInitialFolderPath("/Users/test/Documents")

        var inactiveInspector = FileManagerInspectorFeature.State()
        inactiveInspector.inspectorVisible = true
        inactiveInspector.activeMode = .chat
        inactiveInspector.aiChat.sessionID = inspectorSessionID
        inactiveInspector.aiChat.sessionStatus = .active
        inactiveInspector.aiChat.executionPhase = .processing(requestLock)
        inactiveInspector.aiChat.lockedModelHandle = requestLock.selectedModelHandle
        inactiveInspector.aiChat.transcriptHistory = [
            AiChatMessage(role: .user, content: "test"),
        ]

        var state = FileManagerFeature.State()
        state.contentTabs = ContentTabState(
            tabs: [
                ContentTabItem(
                    id: homeTabID,
                    page: .home,
                    anchor: .homeDefault,
                    isPinned: false,
                    title: "Home",
                    iconName: "house",
                ),
                ContentTabItem(
                    id: directoryTabID,
                    page: .directory,
                    anchor: .directory(path: "/Users/test/Documents"),
                    isPinned: false,
                    title: "Documents",
                    iconName: "folder",
                ),
            ],
            activeTabID: homeTabID,
            recentlyClosed: nil,
        )
        state.content = homeContent
        state.tabContentStates = [
            homeTabID: homeContent,
            directoryTabID: directoryContent,
        ]
        state.tabInspectorStates[directoryTabID] = inactiveInspector.tabSnapshot()
        state.syncContentTabSidebarItems()

        let store: TestStore<FileManagerFeature.State, FileManagerWindowAction> = TestStore(initialState: state) {
            FileManagerFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
            $0.aiChatSessionPersistenceClient.saveSession = { snapshot in
                savedSnapshots.withValue { $0.append(snapshot) }
                return snapshot
            }
        }
        store.exhaustivity = .off

        let response = AiChatResponse(
            context: requestLock.context,
            assistantMessage: AiChatMessage(role: .assistant, content: "done"),
            completedAtMs: 1_234_567_891_000,
        )

        await store.send(.inspector(.aiChat(.executionEvent(.final(response: response)))))

        let savedSnapshot = savedSnapshots.value.first
        XCTAssertEqual(savedSnapshot?.sessionID, inspectorSessionID)
        XCTAssertEqual(savedSnapshot?.transcriptHistory.map(\.content), ["test", "done"])

        await store.receive { action in
            guard case let .backgroundInspectorAiChat(.sessionSnapshotSaved(summary, snapshot, requestID, runID)) =
                action
            else {
                return false
            }
            return summary.sessionID == inspectorSessionID
                && snapshot?.sessionID == inspectorSessionID
                && requestID == requestLock.requestID
                && runID == requestLock.runID
        }

        XCTAssertNil(store.state.backgroundInspectorAiChatStates[inspectorSessionID])
        XCTAssertEqual(
            store.state.tabInspectorStates[directoryTabID]?.aiChat.transcriptHistory.map(\.content),
            ["test", "done"],
        )
        await store.finish()
    }

    func testBackgroundInspectorFinalSaveRefreshesInactiveSameSessionInspectorSnapshot() async {
        let homeTabID = ContentTabID()
        let directoryTabID = ContentTabID()
        let inspectorSessionID = AiChatSessionID(rawValue: UUID())
        let requestLock = makeRequestLock(sessionID: inspectorSessionID)
        let snapshot = AiChatSessionSnapshot(
            sessionID: inspectorSessionID,
            status: .active,
            provider: .openai,
            model: requestLock.selectedModelHandle,
            transcriptHistory: [
                AiChatMessage(role: .user, content: "test"),
                AiChatMessage(role: .assistant, content: "done"),
            ],
            updatedAtMs: 1_234_567_891_000,
        )
        let summary = AiChatSessionSummary(snapshot: snapshot)

        var homeContent = FileManagerContentFeature.State()
        homeContent.navigation.seedInitialFolderPath("/Users/test/Home")

        var directoryContent = FileManagerContentFeature.State()
        directoryContent.navigation.seedInitialFolderPath("/Users/test/Documents")

        var staleInspector = FileManagerInspectorFeature.State()
        staleInspector.inspectorVisible = true
        staleInspector.activeMode = .chat
        staleInspector.aiChat.sessionID = inspectorSessionID
        staleInspector.aiChat.sessionStatus = .active
        staleInspector.aiChat.transcriptHistory = [
            AiChatMessage(role: .user, content: "test"),
        ]

        var backgroundInspector = staleInspector
        backgroundInspector.aiChat.executionPhase = .completed(requestLock)
        backgroundInspector.aiChat.transcriptHistory = snapshot.transcriptHistory
        backgroundInspector.aiChat.selectedModelHandle = requestLock.selectedModelHandle
        backgroundInspector.aiChat.lastRequestContextModelHandle = requestLock.selectedModelHandle

        var state = FileManagerFeature.State()
        state.contentTabs = ContentTabState(
            tabs: [
                ContentTabItem(
                    id: homeTabID,
                    page: .home,
                    anchor: .homeDefault,
                    isPinned: false,
                    title: "Home",
                    iconName: "house",
                ),
                ContentTabItem(
                    id: directoryTabID,
                    page: .directory,
                    anchor: .directory(path: "/Users/test/Documents"),
                    isPinned: false,
                    title: "Documents",
                    iconName: "folder",
                ),
            ],
            activeTabID: homeTabID,
            recentlyClosed: nil,
        )
        state.content = homeContent
        state.tabContentStates = [
            homeTabID: homeContent,
            directoryTabID: directoryContent,
        ]
        state.tabInspectorStates[directoryTabID] = staleInspector.tabSnapshot()
        state.backgroundInspectorAiChatStates[inspectorSessionID] = backgroundInspector.tabSnapshot()
        state.syncContentTabSidebarItems()

        let store: TestStore<FileManagerFeature.State, FileManagerWindowAction> = TestStore(initialState: state) {
            FileManagerFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
        }
        store.exhaustivity = .off

        await store.send(.backgroundInspectorAiChat(.sessionSnapshotSaved(
            summary,
            snapshot: snapshot,
            requestID: requestLock.requestID,
            runID: requestLock.runID,
        ))) { state in
            var refreshedInspector = staleInspector.tabSnapshot()
            refreshedInspector.aiChat.transcriptHistory = snapshot.transcriptHistory
            refreshedInspector.aiChat.transcriptAutoScrollVersion += 1
            refreshedInspector.aiChat.executionPhase = .completed(requestLock)
            refreshedInspector.aiChat.selectedModelHandle = requestLock.selectedModelHandle
            refreshedInspector.aiChat.lastRequestContextModelHandle = requestLock.selectedModelHandle
            refreshedInspector.aiChat.sessionList.replaceRow(summary)
            refreshedInspector.aiChat.sessionList.selectedSessionID = inspectorSessionID
            refreshedInspector.aiChat.sessionList.unreadCompletedSessionIDs.insert(inspectorSessionID)
            state.tabInspectorStates[directoryTabID] = refreshedInspector
            state.backgroundInspectorAiChatStates.removeValue(forKey: inspectorSessionID)
        }

        XCTAssertNil(store.state.inspector.aiChat.sessionID)
        XCTAssertEqual(
            store.state.tabInspectorStates[directoryTabID]?.aiChat.transcriptHistory.map(\.content),
            ["test", "done"],
        )
        XCTAssertEqual(
            store.state.tabInspectorStates[directoryTabID]?.aiChat.executionPhase,
            .completed(requestLock),
        )
        XCTAssertNil(store.state.backgroundInspectorAiChatStates[inspectorSessionID])
        await store.finish()
    }

    func testInactiveInspectorEventBypassesMismatchedBackgroundInspectorOwner() async {
        let homeTabID = ContentTabID()
        let directoryTabID = ContentTabID()
        let inspectorSessionID = AiChatSessionID(rawValue: UUID())
        let staleLock = makeRequestLock(sessionID: inspectorSessionID)
        let requestLock = makeRequestLock(sessionID: inspectorSessionID)
        let failedLock = requestLock.recordingTerminal(
            at: 1_234_567_890_000,
            failure: .network,
            wasCancelled: false,
        )

        var inactiveInspector = FileManagerInspectorFeature.State()
        inactiveInspector.inspectorVisible = true
        inactiveInspector.activeMode = .chat
        inactiveInspector.aiChat.sessionID = inspectorSessionID
        inactiveInspector.aiChat.sessionStatus = .active
        inactiveInspector.aiChat.backgroundExecutionPhases[requestLock.requestID] = .processing(requestLock)

        var staleBackgroundInspector = FileManagerInspectorFeature.State()
        staleBackgroundInspector.inspectorVisible = true
        staleBackgroundInspector.activeMode = .chat
        staleBackgroundInspector.aiChat.sessionID = inspectorSessionID
        staleBackgroundInspector.aiChat.sessionStatus = .active
        staleBackgroundInspector.aiChat.executionPhase = .completed(staleLock)

        var state = FileManagerFeature.State()
        state.contentTabs = ContentTabState(
            tabs: [
                ContentTabItem(
                    id: homeTabID,
                    page: .home,
                    anchor: .homeDefault,
                    isPinned: false,
                    title: "Home",
                    iconName: "house",
                ),
                ContentTabItem(
                    id: directoryTabID,
                    page: .directory,
                    anchor: .directory(path: "/Users/test/Documents"),
                    isPinned: false,
                    title: "Documents",
                    iconName: "folder",
                ),
            ],
            activeTabID: homeTabID,
            recentlyClosed: nil,
        )
        state.tabInspectorStates[directoryTabID] = inactiveInspector.tabSnapshot()
        state.backgroundInspectorAiChatStates[inspectorSessionID] = staleBackgroundInspector.tabSnapshot()
        state.syncContentTabSidebarItems()

        let store: TestStore<FileManagerFeature.State, FileManagerWindowAction> = TestStore(initialState: state) {
            FileManagerFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
        }
        store.exhaustivity = .off

        await store.send(.inspector(.aiChat(.executionEvent(.failed(
            context: requestLock.context,
            reason: .network,
        ))))) { state in
            state.tabInspectorStates[directoryTabID]?.aiChat.backgroundExecutionPhases[requestLock.requestID] = .failed(
                failedLock,
                .network,
            )
        }

        XCTAssertEqual(
            store.state.tabInspectorStates[directoryTabID]?.aiChat.backgroundExecutionPhases[requestLock.requestID],
            .failed(failedLock, .network),
        )
        XCTAssertEqual(
            store.state.backgroundInspectorAiChatStates[inspectorSessionID]?.aiChat.executionPhase,
            .completed(staleLock),
        )
        await store.finish()
    }

    func testBackgroundInspectorSnapshotSavedUsesSavedSnapshotPayload() async {
        let homeTabID = ContentTabID()
        let directoryTabID = ContentTabID()
        let inspectorSessionID = AiChatSessionID(rawValue: UUID())
        let visibleSessionID = AiChatSessionID(rawValue: UUID())
        let requestLock = makeRequestLock(sessionID: inspectorSessionID)
        let snapshot = AiChatSessionSnapshot(
            sessionID: inspectorSessionID,
            status: .active,
            provider: nil,
            model: nil,
            transcriptHistory: [
                AiChatMessage(role: .user, content: "test"),
                AiChatMessage(role: .assistant, content: "done"),
            ],
            lastRequestID: requestLock.requestID,
            lastRunID: requestLock.runID,
            updatedAtMs: 1_234_567_891_000,
        )
        let summary = AiChatSessionSummary(snapshot: snapshot)

        var staleInspector = FileManagerInspectorFeature.State()
        staleInspector.inspectorVisible = true
        staleInspector.activeMode = .chat
        staleInspector.aiChat.sessionID = inspectorSessionID
        staleInspector.aiChat.sessionStatus = .active
        staleInspector.aiChat.transcriptHistory = [AiChatMessage(role: .user, content: "stale")]

        var backgroundInspector = FileManagerInspectorFeature.State()
        backgroundInspector.inspectorVisible = true
        backgroundInspector.activeMode = .chat
        backgroundInspector.aiChat.sessionID = visibleSessionID
        backgroundInspector.aiChat.sessionStatus = .active
        backgroundInspector.aiChat.transcriptHistory = [AiChatMessage(role: .user, content: "visible")]
        backgroundInspector.aiChat.backgroundExecutionPhases[requestLock.requestID] = .completed(requestLock)

        var state = FileManagerFeature.State()
        state.contentTabs = ContentTabState(
            tabs: [
                ContentTabItem(
                    id: homeTabID,
                    page: .home,
                    anchor: .homeDefault,
                    isPinned: false,
                    title: "Home",
                    iconName: "house",
                ),
                ContentTabItem(
                    id: directoryTabID,
                    page: .directory,
                    anchor: .directory(path: "/Users/test/Documents"),
                    isPinned: false,
                    title: "Documents",
                    iconName: "folder",
                ),
            ],
            activeTabID: homeTabID,
            recentlyClosed: nil,
        )
        state.tabInspectorStates[directoryTabID] = staleInspector.tabSnapshot()
        state.backgroundInspectorAiChatStates[inspectorSessionID] = backgroundInspector.tabSnapshot()

        let store: TestStore<FileManagerFeature.State, FileManagerWindowAction> = TestStore(initialState: state) {
            FileManagerFeature()
        }
        store.exhaustivity = .off

        await store.send(.backgroundInspectorAiChat(.sessionSnapshotSaved(
            summary,
            snapshot: snapshot,
            requestID: requestLock.requestID,
            runID: requestLock.runID,
        )))

        XCTAssertEqual(
            store.state.tabInspectorStates[directoryTabID]?.aiChat.transcriptHistory.map(\.content),
            ["test", "done"],
        )
        XCTAssertNotEqual(
            store.state.tabInspectorStates[directoryTabID]?.aiChat.transcriptHistory.map(\.content),
            ["visible"],
        )
        await store.finish()
    }

    func testCompletedAiChatPageCloseDoesNotCancelFinalPersistence() async {
        let aiChatTabID = ContentTabID()
        let homeTabID = ContentTabID()
        let aiSessionID = AiChatSessionID(rawValue: UUID())
        let requestLock = makeRequestLock(sessionID: aiSessionID)

        var aiChatContent = FileManagerContentFeature.State()
        aiChatContent.aiChat.sessionID = aiSessionID
        aiChatContent.aiChat.sessionStatus = .active
        aiChatContent.aiChat.executionPhase = .completed(requestLock)
        aiChatContent.aiChat.transcriptHistory = [
            AiChatMessage(role: .user, content: "test"),
            AiChatMessage(role: .assistant, content: "done"),
        ]

        let homeContent = FileManagerContentFeature.State()

        var state = FileManagerFeature.State()
        state.contentTabs = ContentTabState(
            tabs: [
                ContentTabItem(
                    id: aiChatTabID,
                    page: .aiChat,
                    anchor: .aiChat(sessionID: aiSessionID.rawValue.uuidString),
                    isPinned: false,
                    title: "AI Chat",
                    iconName: "message",
                ),
                ContentTabItem(
                    id: homeTabID,
                    page: .home,
                    anchor: .homeDefault,
                    isPinned: false,
                    title: "Home",
                    iconName: "house",
                ),
            ],
            activeTabID: aiChatTabID,
            recentlyClosed: nil,
        )
        state.content = aiChatContent
        state.tabContentStates = [homeTabID: homeContent]
        state.syncContentTabSidebarItems()

        let store = TestStore(initialState: state) {
            FileManagerFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
            $0.uuid = .incrementing
            $0.entryWatchingClient.startWatchingDirectory = { _ in
                AsyncStream { continuation in
                    continuation.finish()
                }
            }
        }
        store.exhaustivity = .off

        await store.send(.contentTabs(.close(aiChatTabID)))
        await store.receive(\.content.internal.applyNavigationState)
        await store.skipReceivedActions()
        await store.finish()

        guard let backgroundContent = store.state.backgroundAiChatStates[aiSessionID] else {
            XCTFail("Expected completed AI Chat state to remain in background")
            return
        }
        XCTAssertEqual(backgroundContent.aiChat.executionPhase, .completed(requestLock))
    }

    func testPersistenceRecoveryAiChatPageClosePreservesFinalSnapshotOwner() async {
        let aiChatTabID = ContentTabID()
        let homeTabID = ContentTabID()
        let aiSessionID = AiChatSessionID(rawValue: UUID())
        let finalSnapshot = AiChatSessionSnapshot(
            sessionID: aiSessionID,
            status: .active,
            provider: nil,
            model: nil,
            selectedModelRow: nil,
            selectedThinking: nil,
            transcriptHistory: [
                AiChatMessage(role: .user, content: "test"),
                AiChatMessage(role: .assistant, content: "done"),
            ],
            lastRequestID: nil,
            lastRunID: nil,
            lastRequestContext: nil,
            updatedAtMs: 1_234_567_890_000,
        )
        let requestLock = makeRequestLock(sessionID: aiSessionID)
            .recordingFinalSnapshot(finalSnapshot)

        var aiChatContent = FileManagerContentFeature.State()
        aiChatContent.aiChat.sessionID = aiSessionID
        aiChatContent.aiChat.sessionStatus = .active
        aiChatContent.aiChat.executionPhase = .persistenceRecovery(requestLock, .unknown)
        aiChatContent.aiChat.lastExecutionFailure = .unknown
        aiChatContent.aiChat.transcriptHistory = [
            AiChatMessage(role: .user, content: "test"),
        ]

        let homeContent = FileManagerContentFeature.State()

        var state = FileManagerFeature.State()
        state.contentTabs = ContentTabState(
            tabs: [
                ContentTabItem(
                    id: aiChatTabID,
                    page: .aiChat,
                    anchor: .aiChat(sessionID: aiSessionID.rawValue.uuidString),
                    isPinned: false,
                    title: "AI Chat",
                    iconName: "message",
                ),
                ContentTabItem(
                    id: homeTabID,
                    page: .home,
                    anchor: .homeDefault,
                    isPinned: false,
                    title: "Home",
                    iconName: "house",
                ),
            ],
            activeTabID: aiChatTabID,
            recentlyClosed: nil,
        )
        state.content = aiChatContent
        state.tabContentStates = [homeTabID: homeContent]
        state.syncContentTabSidebarItems()

        let store = TestStore(initialState: state) {
            FileManagerFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
            $0.uuid = .incrementing
            $0.entryWatchingClient.startWatchingDirectory = { _ in
                AsyncStream { continuation in
                    continuation.finish()
                }
            }
        }
        store.exhaustivity = .off

        await store.send(.contentTabs(.close(aiChatTabID)))
        await store.receive(\.content.internal.applyNavigationState)
        await store.skipReceivedActions()
        await store.finish()

        guard let backgroundContent = store.state.backgroundAiChatStates[aiSessionID] else {
            XCTFail("Expected persistence recovery AI Chat state to remain in background")
            return
        }
        XCTAssertEqual(
            backgroundContent.aiChat.executionPhase,
            .persistenceRecovery(requestLock, .unknown),
        )
        XCTAssertEqual(
            backgroundContent.aiChat.executionPhase.lock?.finalSnapshot?.transcriptHistory.map(\.content),
            ["test", "done"],
        )
    }

    func testAiChatDeleteSucceededRefreshesAllOpenCopies() async throws {
        let aiSessionID = AiChatSessionID(rawValue: UUID())
        let activeTabID = ContentTabID()
        let inactiveTabID = ContentTabID()
        let requestLock = makeRequestLock(sessionID: aiSessionID)
        let parkedSessionID = AiChatSessionID(rawValue: UUID())
        let parkedRequestLock = makeRequestLock(sessionID: parkedSessionID)
        let parkedResolutionID = UUID()
        let parkedPendingRequest = try AiChatPendingRequestStart(
            resolutionID: parkedResolutionID,
            kind: .submit,
            sessionID: parkedSessionID,
            selectedModel: XCTUnwrap(parkedRequestLock.context.selectedModel),
            selectedRow: parkedRequestLock.context.selectedModelRow,
            preparedRequest: AiChatPreparedRequest(
                prompt: "parked",
                messages: [AiChatMessage(role: .user, content: "parked")],
                assistantReplacementIndex: nil,
                historyTruncation: .init(
                    includedMessageCount: 1,
                    excludedMessageCount: 0,
                    budget: 200_000,
                    truncationReason: nil,
                ),
            ),
        )
        let snapshot = AiChatSessionSnapshot(
            sessionID: aiSessionID,
            status: .active,
            customTitle: "Delete me",
            provider: nil,
            model: nil,
            selectedModelRow: nil,
            selectedThinking: nil,
            transcriptHistory: [],
            lastRequestID: nil,
            lastRunID: nil,
            lastRequestContext: nil,
            updatedAtMs: 1,
        )
        let summary = AiChatSessionSummary(snapshot: snapshot)

        func aiChatState() -> AiChatFeature.State {
            var aiChat = AiChatFeature.State(
                sessionList: .init(allRows: [summary]),
                sessionID: aiSessionID,
                currentSessionCustomTitle: "Delete me",
                executionPhase: .processing(requestLock),
            )
            aiChat.restoreSessionID = aiSessionID
            aiChat.restoreOutcome = .restored(snapshot: snapshot)
            aiChat.sessionStatus = .active
            aiChat.backgroundPendingRequestStarts[parkedResolutionID] = parkedPendingRequest
            aiChat.backgroundExecutionPhases[parkedRequestLock.requestID] = .processing(parkedRequestLock)
            return aiChat
        }

        var activeContent = FileManagerContentFeature.State()
        activeContent.aiChat = aiChatState()
        var inactiveContent = FileManagerContentFeature.State()
        inactiveContent.aiChat = aiChatState()
        var activeInspector = FileManagerInspectorFeature.State()
        activeInspector.aiChat = aiChatState()
        var inactiveInspector = FileManagerInspectorFeature.State()
        inactiveInspector.aiChat = aiChatState()
        var backgroundContent = FileManagerContentFeature.State()
        backgroundContent.aiChat = aiChatState()
        var backgroundInspector = FileManagerInspectorFeature.State()
        backgroundInspector.aiChat = aiChatState()

        var state = FileManagerFeature.State()
        state.contentTabs = ContentTabState(
            tabs: [
                ContentTabItem(
                    id: activeTabID,
                    page: .aiChat,
                    anchor: .aiChat(sessionID: aiSessionID.rawValue.uuidString),
                    isPinned: false,
                    title: "Active",
                    iconName: "sparkles",
                ),
                ContentTabItem(
                    id: inactiveTabID,
                    page: .aiChat,
                    anchor: .aiChat(sessionID: aiSessionID.rawValue.uuidString),
                    isPinned: false,
                    title: "Inactive",
                    iconName: "sparkles",
                ),
            ],
            activeTabID: activeTabID,
        )
        state.tabContentStates[activeTabID] = activeContent
        state.tabContentStates[inactiveTabID] = inactiveContent
        state.content = activeContent
        state.tabInspectorStates[activeTabID] = activeInspector
        state.tabInspectorStates[inactiveTabID] = inactiveInspector
        state.inspector = activeInspector
        state.backgroundAiChatStates[aiSessionID] = backgroundContent
        state.backgroundInspectorAiChatStates[aiSessionID] = backgroundInspector.tabSnapshot()

        let store = TestStore(initialState: state) {
            FileManagerFeature()
        }
        store.exhaustivity = .off

        await store.send(.content(.aiChat(.sessionDeleteSucceeded(aiSessionID)))) { state in
            state.content.aiChat.applyDeletedSessionExpectation(sessionID: aiSessionID)
            state.tabContentStates[activeTabID]?.aiChat.applyDeletedSessionExpectation(sessionID: aiSessionID)
            state.tabContentStates[inactiveTabID]?.aiChat.applyDeletedSessionExpectation(sessionID: aiSessionID)
            state.inspector.aiChat.applyDeletedSessionExpectation(sessionID: aiSessionID)
            state.tabInspectorStates[activeTabID]?.aiChat.applyDeletedSessionExpectation(sessionID: aiSessionID)
            state.tabInspectorStates[inactiveTabID]?.aiChat.applyDeletedSessionExpectation(sessionID: aiSessionID)
            state.backgroundAiChatStates[aiSessionID] = nil
            state.backgroundInspectorAiChatStates[aiSessionID] = nil
        }

        XCTAssertTrue(store.state.content.aiChat.sessionList.deletedSessionIDs.contains(aiSessionID))
        XCTAssertFalse(store.state.content.aiChat.sessionList.allRows.contains { $0.sessionID == aiSessionID })
        XCTAssertTrue(store.state.tabContentStates[inactiveTabID]?.aiChat.sessionList.deletedSessionIDs
            .contains(aiSessionID) == true)
        XCTAssertFalse(store.state.tabContentStates[inactiveTabID]?.aiChat.sessionList.allRows
            .contains { $0.sessionID == aiSessionID } ?? true)
        XCTAssertNil(store.state.content.aiChat.sessionID)
        XCTAssertEqual(store.state.content.aiChat.transcriptHistory, [])
        XCTAssertEqual(store.state.content.aiChat.draftText, "")
        XCTAssertNil(store.state.content.aiChat.selectedModelHandle)
        XCTAssertNil(store.state.tabContentStates[inactiveTabID]?.aiChat.sessionID)
        XCTAssertEqual(store.state.tabContentStates[inactiveTabID]?.aiChat.transcriptHistory, [])
        XCTAssertEqual(store.state.tabContentStates[inactiveTabID]?.aiChat.draftText, "")
        XCTAssertNil(store.state.backgroundAiChatStates[aiSessionID])
        XCTAssertNil(store.state.backgroundInspectorAiChatStates[aiSessionID])
        XCTAssertEqual(
            store.state.content.aiChat.backgroundPendingRequestStarts[parkedResolutionID],
            parkedPendingRequest,
        )
        XCTAssertEqual(
            store.state.content.aiChat.backgroundExecutionPhases[parkedRequestLock.requestID],
            .processing(parkedRequestLock),
        )
        XCTAssertEqual(
            store.state.tabContentStates[inactiveTabID]?.aiChat.backgroundPendingRequestStarts[parkedResolutionID],
            parkedPendingRequest,
        )
    }

    func testAiChatRenameRefreshesAllOpenCopiesCustomTitle() async {
        let aiSessionID = AiChatSessionID(rawValue: UUID())
        let activeTabID = ContentTabID()
        let inactiveTabID = ContentTabID()
        let requestLock = makeRequestLock(sessionID: aiSessionID)
        let staleLock = requestLock.recordingCustomTitle("Stale title")
        let renamedLock = requestLock.recordingCustomTitle("Renamed everywhere")
        let oldSnapshot = AiChatSessionSnapshot(
            sessionID: aiSessionID,
            status: .active,
            customTitle: "Stale title",
            provider: nil,
            model: nil,
            selectedModelRow: nil,
            selectedThinking: nil,
            transcriptHistory: [],
            lastRequestID: nil,
            lastRunID: nil,
            lastRequestContext: nil,
            updatedAtMs: 1,
        )
        let renamedSnapshot = AiChatSessionSnapshot(
            sessionID: aiSessionID,
            status: .active,
            customTitle: "Renamed everywhere",
            provider: nil,
            model: nil,
            selectedModelRow: nil,
            selectedThinking: nil,
            transcriptHistory: [],
            lastRequestID: nil,
            lastRunID: nil,
            lastRequestContext: nil,
            updatedAtMs: 2,
        )
        let oldSummary = AiChatSessionSummary(snapshot: oldSnapshot)
        let renamedSummary = AiChatSessionSummary(snapshot: renamedSnapshot)

        func aiChatState() -> AiChatFeature.State {
            var aiChat = AiChatFeature.State(
                sessionList: .init(allRows: [oldSummary]),
                sessionID: aiSessionID,
                currentSessionCustomTitle: "Stale title",
                executionPhase: .processing(staleLock),
            )
            aiChat.sessionStatus = .active
            return aiChat
        }

        var activeContent = FileManagerContentFeature.State()
        activeContent.aiChat = aiChatState()
        var inactiveContent = FileManagerContentFeature.State()
        inactiveContent.aiChat = aiChatState()
        var activeInspector = FileManagerInspectorFeature.State()
        activeInspector.aiChat = aiChatState()
        var inactiveInspector = FileManagerInspectorFeature.State()
        inactiveInspector.aiChat = aiChatState()
        var backgroundContent = FileManagerContentFeature.State()
        backgroundContent.aiChat = aiChatState()
        var backgroundInspector = FileManagerInspectorFeature.State()
        backgroundInspector.aiChat = aiChatState()

        var state = FileManagerFeature.State()
        state.contentTabs = ContentTabState(
            tabs: [
                ContentTabItem(
                    id: activeTabID,
                    page: .aiChat,
                    anchor: .aiChat(sessionID: aiSessionID.rawValue.uuidString),
                    isPinned: false,
                    title: "AI Chat",
                    iconName: "message",
                ),
                ContentTabItem(
                    id: inactiveTabID,
                    page: .aiChat,
                    anchor: .aiChat(sessionID: aiSessionID.rawValue.uuidString),
                    isPinned: false,
                    title: "AI Chat",
                    iconName: "message",
                ),
            ],
            activeTabID: activeTabID,
            recentlyClosed: nil,
        )
        state.content = activeContent
        state.tabContentStates[inactiveTabID] = inactiveContent
        state.inspector = activeInspector
        state.tabInspectorStates[inactiveTabID] = inactiveInspector
        state.backgroundAiChatStates[aiSessionID] = backgroundContent
        state.backgroundInspectorAiChatStates[aiSessionID] = backgroundInspector

        let store = TestStore(initialState: state) {
            FileManagerFeature()
        }
        store.exhaustivity = .off

        await store.send(.content(.aiChat(.sessionRenameSucceeded(
            renamedSummary,
            customTitle: "Renamed everywhere",
        ))))

        XCTAssertEqual(store.state.content.aiChat.currentSessionCustomTitle, "Renamed everywhere")
        XCTAssertEqual(store.state.content.aiChat.executionPhase, .processing(renamedLock))
        XCTAssertEqual(
            store.state.tabContentStates[inactiveTabID]?.aiChat.currentSessionCustomTitle,
            "Renamed everywhere",
        )
        XCTAssertEqual(store.state.tabContentStates[inactiveTabID]?.aiChat.executionPhase, .processing(renamedLock))
        XCTAssertEqual(store.state.inspector.aiChat.currentSessionCustomTitle, "Renamed everywhere")
        XCTAssertEqual(store.state.inspector.aiChat.executionPhase, .processing(renamedLock))
        XCTAssertEqual(
            store.state.tabInspectorStates[inactiveTabID]?.aiChat.currentSessionCustomTitle,
            "Renamed everywhere",
        )
        XCTAssertEqual(store.state.tabInspectorStates[inactiveTabID]?.aiChat.executionPhase, .processing(renamedLock))
        XCTAssertEqual(store.state.backgroundAiChatStates[aiSessionID]?.aiChat.executionPhase, .processing(renamedLock))
        XCTAssertEqual(
            store.state.backgroundInspectorAiChatStates[aiSessionID]?.aiChat.executionPhase,
            .processing(renamedLock),
        )
        XCTAssertEqual(store.state.content.aiChat.sessionList.allRows.first, renamedSummary)
        XCTAssertEqual(store.state.tabContentStates[inactiveTabID]?.aiChat.sessionList.allRows.first, renamedSummary)
        await store.finish()
    }

    func testBackgroundAiChatRenameRefreshesClosedOwnerCustomTitle() async {
        let aiSessionID = AiChatSessionID(rawValue: UUID())
        let finalSnapshot = AiChatSessionSnapshot(
            sessionID: aiSessionID,
            status: .active,
            provider: nil,
            model: nil,
            selectedModelRow: nil,
            selectedThinking: nil,
            transcriptHistory: [
                AiChatMessage(role: .user, content: "test"),
                AiChatMessage(role: .assistant, content: "done"),
            ],
            lastRequestID: nil,
            lastRunID: nil,
            lastRequestContext: nil,
            updatedAtMs: 1_234_567_890_000,
        )
        let requestLock = makeRequestLock(sessionID: aiSessionID)
            .recordingFinalSnapshot(finalSnapshot)
        var backgroundContent = FileManagerContentFeature.State()
        backgroundContent.aiChat.sessionID = aiSessionID
        backgroundContent.aiChat.executionPhase = .completed(requestLock)

        var renamedSnapshot = finalSnapshot
        renamedSnapshot = AiChatSessionSnapshot(
            sessionID: aiSessionID,
            status: .active,
            customTitle: "Renamed while closed",
            provider: finalSnapshot.provider,
            model: finalSnapshot.model,
            selectedModelRow: finalSnapshot.selectedModelRow,
            selectedThinking: finalSnapshot.selectedThinking,
            transcriptHistory: finalSnapshot.transcriptHistory,
            lastRequestID: finalSnapshot.lastRequestID,
            lastRunID: finalSnapshot.lastRunID,
            lastRequestContext: finalSnapshot.lastRequestContext,
            updatedAtMs: finalSnapshot.updatedAtMs,
        )
        let renamedSummary = AiChatSessionSummary(snapshot: renamedSnapshot)
        let expectedLock = requestLock.recordingCustomTitle("Renamed while closed")

        var state = FileManagerFeature.State()
        state.backgroundAiChatStates[aiSessionID] = backgroundContent

        let store = TestStore(initialState: state) {
            FileManagerFeature()
        }
        store.exhaustivity = .off

        await store.send(.content(.aiChat(.sessionRenameSucceeded(
            renamedSummary,
            customTitle: "Renamed while closed",
        ))))

        XCTAssertEqual(
            store.state.backgroundAiChatStates[aiSessionID]?.aiChat.executionPhase,
            .completed(expectedLock),
        )
        XCTAssertEqual(
            store.state.backgroundAiChatStates[aiSessionID]?.aiChat.executionPhase.lock?.finalSnapshot?.customTitle,
            "Renamed while closed",
        )
        await store.finish()
    }

    func testBackgroundAiChatRecoveryRetryFailedKeepsClosedOwner() async {
        let aiSessionID = AiChatSessionID(rawValue: UUID())
        let finalSnapshot = AiChatSessionSnapshot(
            sessionID: aiSessionID,
            status: .active,
            provider: nil,
            model: nil,
            selectedModelRow: nil,
            selectedThinking: nil,
            transcriptHistory: [
                AiChatMessage(role: .user, content: "test"),
                AiChatMessage(role: .assistant, content: "done"),
            ],
            lastRequestID: nil,
            lastRunID: nil,
            lastRequestContext: nil,
            updatedAtMs: 1_234_567_890_000,
        )
        let requestLock = makeRequestLock(sessionID: aiSessionID)
            .recordingFinalSnapshot(finalSnapshot)
        var backgroundContent = FileManagerContentFeature.State()
        backgroundContent.aiChat.sessionID = aiSessionID
        backgroundContent.aiChat.executionPhase = .persistenceRecovery(requestLock, .unknown)
        backgroundContent.aiChat.lastExecutionFailure = .unknown

        var state = FileManagerFeature.State()
        state.backgroundAiChatStates[aiSessionID] = backgroundContent

        let store = TestStore(initialState: state) {
            FileManagerFeature()
        }
        store.exhaustivity = .off

        await store.send(.backgroundAiChat(.persistenceRecoveryRetryFailed(requestLock, .unknown)))

        XCTAssertEqual(
            store.state.backgroundAiChatStates[aiSessionID]?.aiChat.executionPhase,
            .persistenceRecovery(requestLock, .unknown),
        )
        XCTAssertEqual(
            store.state.backgroundAiChatStates[aiSessionID]?.aiChat.executionPhase.lock?.finalSnapshot?
                .transcriptHistory.map(\.content),
            ["test", "done"],
        )
        await store.finish()
    }

    func testBackgroundAiChatPersistenceFailedRefreshesActiveRecovery() async {
        let aiSessionID = AiChatSessionID(rawValue: UUID())
        let finalSnapshot = AiChatSessionSnapshot(
            sessionID: aiSessionID,
            status: .active,
            provider: nil,
            model: nil,
            transcriptHistory: [
                AiChatMessage(role: .user, content: "test"),
                AiChatMessage(role: .assistant, content: "done"),
            ],
            updatedAtMs: 1_234_567_890_000,
        )
        let requestLock = makeRequestLock(sessionID: aiSessionID)
            .recordingFinalSnapshot(finalSnapshot)

        var activeContent = FileManagerContentFeature.State()
        activeContent.aiChat.sessionID = aiSessionID
        activeContent.aiChat.sessionStatus = .active
        activeContent.aiChat.executionPhase = .idle
        activeContent.aiChat.transcriptHistory = [AiChatMessage(role: .user, content: "test")]

        var backgroundContent = FileManagerContentFeature.State()
        backgroundContent.aiChat.sessionID = aiSessionID
        backgroundContent.aiChat.sessionStatus = .active
        backgroundContent.aiChat.backgroundExecutionPhases[requestLock.requestID] = .completed(requestLock)

        var state = FileManagerFeature.State()
        state.content = activeContent
        state.backgroundAiChatStates[aiSessionID] = backgroundContent

        let store = TestStore(initialState: state) {
            FileManagerFeature()
        }
        store.exhaustivity = .off

        await store.send(.backgroundAiChat(.persistenceFailed(requestLock, .unknown)))

        XCTAssertEqual(
            store.state.backgroundAiChatStates[aiSessionID]?.aiChat.backgroundExecutionPhases[requestLock.requestID],
            .persistenceRecovery(requestLock, .unknown),
        )
        XCTAssertEqual(store.state.content.aiChat.executionPhase, .persistenceRecovery(requestLock, .unknown))
        XCTAssertEqual(store.state.content.aiChat.lastExecutionFailure, .unknown)
        await store.finish()
    }

    func testBackgroundAiChatDeleteSessionCancelsOnlyMatchingSessionOwner() async {
        let deletedSessionID = AiChatSessionID(rawValue: UUID())
        let preservedSessionID = AiChatSessionID(rawValue: UUID())
        let deletedLock = makeRequestLock(sessionID: deletedSessionID)
        let preservedLock = makeRequestLock(sessionID: preservedSessionID)

        var backgroundContent = FileManagerContentFeature.State()
        backgroundContent.aiChat.sessionID = deletedSessionID
        backgroundContent.aiChat.sessionStatus = .active
        backgroundContent.aiChat.executionPhase = .persistenceRecovery(deletedLock, .unknown)
        backgroundContent.aiChat.backgroundExecutionPhases[preservedLock.requestID] = .processing(preservedLock)

        var state = FileManagerFeature.State()
        state.content.aiChat.sessionID = AiChatSessionID(rawValue: UUID())
        state.backgroundAiChatStates[deletedSessionID] = backgroundContent
        state.backgroundAiChatStates[preservedSessionID] = backgroundContent

        let store = TestStore(initialState: state) {
            FileManagerFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
            $0.aiChatSessionPersistenceClient.deleteSession = { _ in }
        }
        store.exhaustivity = .off

        await store.send(.content(.aiChat(.deleteSessionTapped(deletedSessionID)))) { state in
            state.backgroundAiChatStates.removeValue(forKey: deletedSessionID)
        }
        XCTAssertEqual(
            store.state.backgroundAiChatStates[preservedSessionID]?.aiChat
                .backgroundExecutionPhases[preservedLock.requestID],
            .processing(preservedLock),
        )
        await store.finish()
    }

    func testInactiveInspectorBackgroundRecoverySucceededRefreshesContentSession() async {
        let activeTabID = ContentTabID()
        let inactiveTabID = ContentTabID()
        let aiSessionID = AiChatSessionID(rawValue: UUID())
        let inspectorVisibleSessionID = AiChatSessionID(rawValue: UUID())
        let finalSnapshot = AiChatSessionSnapshot(
            sessionID: aiSessionID,
            status: .active,
            provider: nil,
            model: nil,
            transcriptHistory: [
                AiChatMessage(role: .user, content: "test"),
                AiChatMessage(role: .assistant, content: "done"),
            ],
            updatedAtMs: 1_234_567_890_000,
        )
        let requestLock = makeRequestLock(sessionID: aiSessionID)
            .recordingFinalSnapshot(finalSnapshot)

        var content = FileManagerContentFeature.State()
        content.aiChat.sessionID = aiSessionID
        content.aiChat.sessionStatus = .active
        content.aiChat.transcriptHistory = [AiChatMessage(role: .user, content: "test")]
        content.aiChat.executionPhase = .idle

        var inactiveInspector = FileManagerInspectorFeature.State()
        inactiveInspector.aiChat.sessionID = inspectorVisibleSessionID
        inactiveInspector.aiChat.sessionStatus = .active
        inactiveInspector.aiChat.backgroundExecutionPhases[requestLock.requestID] = .persistenceRecovery(
            requestLock,
            .unknown,
        )

        var state = FileManagerFeature.State()
        state.contentTabs = ContentTabState(
            tabs: [
                ContentTabItem(
                    id: activeTabID,
                    page: .home,
                    anchor: .homeDefault,
                    isPinned: false,
                    title: "Home",
                    iconName: "house",
                ),
                ContentTabItem(
                    id: inactiveTabID,
                    page: .directory,
                    anchor: .directory(path: "/tmp/inactive"),
                    isPinned: false,
                    title: "Inactive",
                    iconName: "folder",
                ),
            ],
            activeTabID: activeTabID,
            recentlyClosed: nil,
        )
        var staleBackgroundInspector = FileManagerInspectorFeature.State()
        let staleLock = makeRequestLock(sessionID: aiSessionID)
        staleBackgroundInspector.aiChat.sessionID = aiSessionID
        staleBackgroundInspector.aiChat.sessionStatus = .active
        staleBackgroundInspector.aiChat.backgroundExecutionPhases[staleLock.requestID] = .persistenceRecovery(
            staleLock,
            .unknown,
        )

        state.content = content
        state.tabInspectorStates[inactiveTabID] = inactiveInspector.tabSnapshot()
        state.backgroundInspectorAiChatStates[aiSessionID] = staleBackgroundInspector.tabSnapshot()

        let store = TestStore(initialState: state) {
            FileManagerFeature()
        }
        store.exhaustivity = .off

        await store.send(.inspector(.aiChat(.persistenceRecoverySucceeded(requestLock))))

        XCTAssertEqual(
            store.state.tabInspectorStates[inactiveTabID]?.aiChat.backgroundExecutionPhases[requestLock.requestID],
            .completed(requestLock),
        )
        XCTAssertEqual(store.state.content.aiChat.executionPhase, .completed(requestLock))
        XCTAssertEqual(store.state.content.aiChat.transcriptHistory.map(\.content), ["test", "done"])
        XCTAssertEqual(
            store.state.backgroundInspectorAiChatStates[aiSessionID]?.aiChat
                .backgroundExecutionPhases[staleLock.requestID],
            .persistenceRecovery(staleLock, .unknown),
        )
        await store.finish()
    }

    func testActiveInspectorBackgroundRecoverySucceededRefreshesContentSession() async {
        let aiSessionID = AiChatSessionID(rawValue: UUID())
        let inspectorVisibleSessionID = AiChatSessionID(rawValue: UUID())
        let finalSnapshot = AiChatSessionSnapshot(
            sessionID: aiSessionID,
            status: .active,
            provider: nil,
            model: nil,
            transcriptHistory: [
                AiChatMessage(role: .user, content: "test"),
                AiChatMessage(role: .assistant, content: "done"),
            ],
            updatedAtMs: 1_234_567_890_000,
        )
        let requestLock = makeRequestLock(sessionID: aiSessionID)
            .recordingFinalSnapshot(finalSnapshot)

        var content = FileManagerContentFeature.State()
        content.aiChat.sessionID = aiSessionID
        content.aiChat.sessionStatus = .active
        content.aiChat.transcriptHistory = [AiChatMessage(role: .user, content: "test")]
        content.aiChat.executionPhase = .idle

        var inspector = FileManagerInspectorFeature.State()
        inspector.aiChat.sessionID = inspectorVisibleSessionID
        inspector.aiChat.sessionStatus = .active
        inspector.aiChat.backgroundExecutionPhases[requestLock.requestID] = .persistenceRecovery(
            requestLock,
            .unknown,
        )

        var state = FileManagerFeature.State()
        state.content = content
        state.inspector = inspector

        let store = TestStore(initialState: state) {
            FileManagerFeature()
        }
        store.exhaustivity = .off

        await store.send(.inspector(.aiChat(.persistenceRecoverySucceeded(requestLock))))

        XCTAssertEqual(
            store.state.inspector.aiChat.backgroundExecutionPhases[requestLock.requestID],
            .completed(requestLock),
        )
        XCTAssertEqual(store.state.content.aiChat.executionPhase, .completed(requestLock))
        XCTAssertEqual(store.state.content.aiChat.transcriptHistory.map(\.content), ["test", "done"])
        await store.finish()
    }

    func testActiveContentBackgroundRecoverySucceededRefreshesInactiveSession() async {
        let activeTabID = ContentTabID()
        let inactiveTabID = ContentTabID()
        let activeSessionID = AiChatSessionID(rawValue: UUID())
        let inactiveSessionID = AiChatSessionID(rawValue: UUID())
        let finalSnapshot = AiChatSessionSnapshot(
            sessionID: inactiveSessionID,
            status: .active,
            provider: nil,
            model: nil,
            transcriptHistory: [
                AiChatMessage(role: .user, content: "test"),
                AiChatMessage(role: .assistant, content: "done"),
            ],
            updatedAtMs: 1_234_567_890_000,
        )
        let requestLock = makeRequestLock(sessionID: inactiveSessionID)
            .recordingFinalSnapshot(finalSnapshot)

        var activeContent = FileManagerContentFeature.State()
        activeContent.aiChat.sessionID = activeSessionID
        activeContent.aiChat.sessionStatus = .active
        activeContent.aiChat.backgroundExecutionPhases[requestLock.requestID] = .persistenceRecovery(
            requestLock,
            .unknown,
        )

        var inactiveContent = FileManagerContentFeature.State()
        inactiveContent.aiChat.sessionID = inactiveSessionID
        inactiveContent.aiChat.sessionStatus = .active
        inactiveContent.aiChat.transcriptHistory = [AiChatMessage(role: .user, content: "test")]
        inactiveContent.aiChat.executionPhase = .idle

        var state = FileManagerFeature.State()
        state.contentTabs = ContentTabState(
            tabs: [
                ContentTabItem(
                    id: activeTabID,
                    page: .aiChat,
                    anchor: .aiChat(sessionID: activeSessionID.rawValue.uuidString),
                    isPinned: false,
                    title: "Active",
                    iconName: "sparkles",
                ),
                ContentTabItem(
                    id: inactiveTabID,
                    page: .aiChat,
                    anchor: .aiChat(sessionID: inactiveSessionID.rawValue.uuidString),
                    isPinned: false,
                    title: "Inactive",
                    iconName: "sparkles",
                ),
            ],
            activeTabID: activeTabID,
            recentlyClosed: nil,
        )
        state.content = activeContent
        state.tabContentStates = [
            activeTabID: activeContent,
            inactiveTabID: inactiveContent,
        ]

        let store = TestStore(initialState: state) {
            FileManagerFeature()
        }
        store.exhaustivity = .off

        await store.send(.content(.aiChat(.persistenceRecoverySucceeded(requestLock))))

        XCTAssertEqual(
            store.state.content.aiChat.backgroundExecutionPhases[requestLock.requestID],
            .completed(requestLock),
        )
        XCTAssertEqual(
            store.state.tabContentStates[inactiveTabID]?.aiChat.executionPhase,
            .completed(requestLock),
        )
        XCTAssertEqual(
            store.state.tabContentStates[inactiveTabID]?.aiChat.transcriptHistory.map(\.content),
            ["test", "done"],
        )
        await store.finish()
    }

    func testBackgroundAiChatRecoverySucceededAppliesFinalSnapshotToActiveSession() async {
        let aiSessionID = AiChatSessionID(rawValue: UUID())
        let finalSnapshot = AiChatSessionSnapshot(
            sessionID: aiSessionID,
            status: .active,
            provider: nil,
            model: nil,
            transcriptHistory: [
                AiChatMessage(role: .user, content: "test"),
                AiChatMessage(role: .assistant, content: "done"),
            ],
            updatedAtMs: 1_234_567_890_000,
        )
        let requestLock = makeRequestLock(sessionID: aiSessionID)
            .recordingFinalSnapshot(finalSnapshot)

        var activeContent = FileManagerContentFeature.State()
        activeContent.aiChat.sessionID = aiSessionID
        activeContent.aiChat.sessionStatus = .active
        activeContent.aiChat.executionPhase = .persistenceRecovery(requestLock, .unknown)
        activeContent.aiChat.lastExecutionFailure = .unknown
        activeContent.aiChat.transcriptHistory = [AiChatMessage(role: .user, content: "test")]

        var backgroundContent = FileManagerContentFeature.State()
        backgroundContent.aiChat.sessionID = aiSessionID
        backgroundContent.aiChat.sessionStatus = .active
        backgroundContent.aiChat.backgroundExecutionPhases[requestLock.requestID] = .persistenceRecovery(
            requestLock,
            .unknown,
        )

        var state = FileManagerFeature.State()
        state.content = activeContent
        state.backgroundAiChatStates[aiSessionID] = backgroundContent

        let store = TestStore(initialState: state) {
            FileManagerFeature()
        }
        store.exhaustivity = .off

        await store.send(.backgroundAiChat(.persistenceRecoverySucceeded(requestLock)))

        XCTAssertNil(store.state.backgroundAiChatStates[aiSessionID])
        XCTAssertEqual(store.state.content.aiChat.executionPhase, .completed(requestLock))
        XCTAssertEqual(store.state.content.aiChat.lastExecutionFailure, nil)
        XCTAssertEqual(store.state.content.aiChat.transcriptHistory.map(\.content), ["test", "done"])
        await store.finish()
    }

    func testBackgroundAiChatFailureKeepsOwnerAndRefreshesActiveSession() async {
        let aiSessionID = AiChatSessionID(rawValue: UUID())
        let otherSessionID = AiChatSessionID(rawValue: UUID())
        let requestLock = makeRequestLock(sessionID: aiSessionID)
        let unrelatedLock = makeRequestLock(sessionID: otherSessionID)
        let unrelatedFailedLock = unrelatedLock.recordingTerminal(
            at: 1_234_567_889_000,
            failure: .unknown,
            wasCancelled: false,
        )
        var activeContent = FileManagerContentFeature.State()
        activeContent.aiChat.sessionID = aiSessionID
        activeContent.aiChat.sessionStatus = .active
        activeContent.aiChat.executionPhase = .idle
        activeContent.aiChat.transcriptHistory = [AiChatMessage(role: .user, content: "test")]

        var backgroundContent = FileManagerContentFeature.State()
        backgroundContent.aiChat.sessionID = aiSessionID
        backgroundContent.aiChat.sessionStatus = .active
        backgroundContent.aiChat.executionPhase = .failed(unrelatedFailedLock, .unknown)
        backgroundContent.aiChat.backgroundExecutionPhases[requestLock.requestID] = .processing(requestLock)

        var state = FileManagerFeature.State()
        state.content = activeContent
        state.backgroundAiChatStates[aiSessionID] = backgroundContent

        let store = TestStore(initialState: state) {
            FileManagerFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
        }
        store.exhaustivity = .off

        await store.send(.backgroundAiChat(.executionEvent(.failed(context: requestLock.context, reason: .network))))

        let expectedFailedLock = requestLock.recordingTerminal(
            at: 1_234_567_890_000,
            failure: .network,
            wasCancelled: false,
        )
        XCTAssertEqual(
            store.state.backgroundAiChatStates[aiSessionID]?.aiChat.backgroundExecutionPhases[requestLock.requestID],
            .failed(expectedFailedLock, .network),
        )
        XCTAssertEqual(
            store.state.backgroundAiChatStates[aiSessionID]?.aiChat.executionPhase,
            .failed(unrelatedFailedLock, .unknown),
        )
        XCTAssertEqual(
            store.state.content.aiChat.executionPhase,
            .failed(expectedFailedLock, .network),
        )
        await store.finish()
    }
}

// MARK: - CTM-005-ai_chat_invalid_session

@MainActor
extension CTM005IndependentContentTabSessionTests {
    /// 존재하지 않는 AI Chat sessionID로 ContentPane이 초기화될 때 빈 새 session으로 fallback됨
    /// ContentPane AI Chat이 restoreSessionID를 가지고 restore를 시도할 때 persistence에 session이 없으면
    /// .restoreOutcome(.newSession)으로 fallback되어 새 빈 session으로 전환됨을 검증한다.
    /// - 검증 내용: .setup 전송 후 sessionStatus가 .restoring이 되었다가,
    ///   restoreOutcome 수신 후 sessionID가 새 ID로 설정되고 restoreFailure가 설정됨
    /// - 사전 조건: aiChatSessionPersistenceClient.loadSession → nil (session 없음)
    /// - 기대 결과: restoreFailure(.missingRecord)가 설정되고 새 빈 session으로 전환됨
    func testInvalidAiChatSessionFallsBackToNewSession() async {
        let originalSessionID = AiChatSessionID(rawValue: UUID())
        let setup = AiChatSetupState(
            restoreSessionID: originalSessionID,
            sessionID: nil,
            sessionStatus: .idle,
            currentContext: .init(summary: "Test context"),
            transcriptHistory: [],
            draftText: "",
            catalogRows: [],
            selectedModelHandle: nil,
            selectedThinking: nil,
            lockedModelHandle: nil,
            lastExecutionFailure: nil,
        )

        var state = FileManagerFeature.State()
        state.content.aiChat.mode = .sessions
        state.contentTabs = ContentTabState(
            tabs: [ContentTabItem(
                id: ContentTabID(),
                page: .aiChat,
                anchor: .aiChat(sessionID: "missing-session"),
                isPinned: false,
                title: "AI Chat",
                iconName: "message",
            )],
            activeTabID: ContentTabID(),
            recentlyClosed: nil,
        )
        state.syncContentTabSidebarItems()

        let store = TestStore(initialState: state) {
            FileManagerFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
            $0.uuid = .incrementing
            $0.aiChatSessionPersistenceClient.loadSession = { _ in nil }
        }
        store.exhaustivity = .off

        await store.send(.content(.aiChat(.setup(setup))))

        // setup에서 restoreSessionID가 있으므로 sessionStatus가 .restoring이 됨
        XCTAssertEqual(store.state.content.aiChat.restoreSessionID, originalSessionID)

        // restoreOutcome이 도착할 때까지 기다림
        await store.receive(\.content.aiChat.restoreOutcome)
        await store.finish()

        // restore failure가 설정되어야 함 (missing record)
        XCTAssertNotNil(store.state.content.aiChat.restoreFailure)
        XCTAssertEqual(store.state.content.aiChat.restoreFailure, .missingRecord)
        // 새 sessionID가 할당되어야 함 (원래 sessionID와 다름)
        XCTAssertNotEqual(store.state.content.aiChat.sessionID, originalSessionID)
        // mode는 .setup에서 변경되지 않음 — .sessions 유지
        XCTAssertEqual(store.state.content.aiChat.mode, .sessions)
        // sessionStatus는 .idle (applyNewSessionSnapshot에서 .idle로 설정)
        XCTAssertEqual(store.state.content.aiChat.sessionStatus, .idle)
        // transcript는 빈 배열
        XCTAssertTrue(store.state.content.aiChat.transcriptHistory.isEmpty)
    }

    /// AI Chat setup에 restoreSessionID가 없으면 restore 없이 session이 바로 설정됨
    /// restore 없이 초기화되는 경우(예: 새 AI Chat 탭) .setup 수신 후
    /// sessionID가 설정되고 sessionStatus가 .idle이며 restore 관련 state가 nil임을 검증한다.
    /// mode는 .setup에서 변경되지 않고 기본값 .sessions를 유지한다 (view가 이후 .newChatTapped로 전환).
    /// - 검증 내용: .setup(restoreSessionID: nil) 전송 후 sessionID가 설정되고
    ///   restoreSessionID == nil, sessionStatus == .idle
    /// - 사전 조건: ContentPane AI Chat에 restoreSessionID 없는 setup 전송
    /// - 기대 결과: restore 없이 session이 설정되고 restore 관련 state는 nil
    func testAiChatSetupWithoutRestoreSetsSessionDirectly() async {
        let sessionID = AiChatSessionID(rawValue: UUID())
        let setup = AiChatSetupState(
            restoreSessionID: nil,
            sessionID: sessionID,
            sessionStatus: .idle,
            currentContext: .init(summary: "Test context"),
            transcriptHistory: [],
            draftText: "",
            catalogRows: [],
            selectedModelHandle: nil,
            selectedThinking: nil,
            lockedModelHandle: nil,
            lastExecutionFailure: nil,
        )

        var state = FileManagerFeature.State()
        state.content.aiChat.mode = .sessions
        state.contentTabs = ContentTabState(
            tabs: [ContentTabItem(
                id: ContentTabID(),
                page: .aiChat,
                anchor: .aiChat(sessionID: "test-session"),
                isPinned: false,
                title: "AI Chat",
                iconName: "message",
            )],
            activeTabID: ContentTabID(),
            recentlyClosed: nil,
        )
        state.syncContentTabSidebarItems()

        let store = TestStore(initialState: state) {
            FileManagerFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
            $0.aiChatSessionPersistenceClient.loadSession = { _ in
                XCTFail("restoreSessionID가 nil이므로 restore가 호출되지 않아야 함")
                return nil
            }
        }
        store.exhaustivity = .off

        await store.send(.content(.aiChat(.setup(setup))))

        XCTAssertEqual(store.state.content.aiChat.sessionID, sessionID)
        XCTAssertNil(store.state.content.aiChat.restoreSessionID)
        XCTAssertNil(store.state.content.aiChat.restoreOutcome)
        XCTAssertNil(store.state.content.aiChat.restoreFailure)
        XCTAssertEqual(store.state.content.aiChat.sessionStatus, .idle)
        // setup에서 mode는 .chat으로 전환되지 않음 — AiChatFeature.setup은 mode를 변경하지 않음
        XCTAssertEqual(store.state.content.aiChat.mode, .sessions)
        await store.finish()
    }
}

@MainActor
extension CTM005IndependentContentTabSessionTests {
    func testRestoringAiChatTabInitializesContentSessionFromRestoredAnchor() async {
        let sessionID = "test-session-123"
        let homeID = ContentTabID()
        let currentPath = "/Users/test/Current"
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
                page: .aiChat,
                anchor: .aiChat(sessionID: sessionID),
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
        store.exhaustivity = .off

        await store.send(.contentTabs(.restore))

        guard let activeTabID = store.state.contentTabs.activeTabID else {
            XCTFail("restore should activate a restored tab")
            return
        }
        XCTAssertNotEqual(activeTabID, homeID)
        XCTAssertEqual(store.state.contentTabs.tabs[id: activeTabID]?.anchor, .aiChat(sessionID: sessionID))
        XCTAssertEqual(store.state.contentTabs.tabs[id: activeTabID]?.page, .aiChat)
        XCTAssertEqual(store.state.content.navigation.navigationState, .aiChat(sessionID))
        XCTAssertEqual(store.state.contentTabs.recentlyClosed, nil)
        guard let restoredContent = store.state.tabContentStates[activeTabID] else {
            XCTFail("restored AI Chat tab should have content state")
            return
        }
        XCTAssertEqual(restoredContent.navigation.navigationState, .aiChat(sessionID))
        await store.finish()
    }

    func testCloseAiChatTabAndReopenSameSessionDoesNotCorruptState() async throws {
        let aiChatTabID = ContentTabID()
        let homeTabID = ContentTabID()
        let sessionUUID = try XCTUnwrap(UUID(uuidString: "E621E1F8-C36C-495A-93FC-0C247A3E6E5F"))
        let sessionID = sessionUUID.uuidString
        let aiSessionID = AiChatSessionID(rawValue: sessionUUID)
        let modelHandle = AiModelHandle(provider: .openai, rawValue: "gpt-4.1-mini")
        let catalogRow = AiModelCatalogRow(
            handle: modelHandle,
            displayName: "GPT-4.1 Mini",
            authMethod: .apiKey,
            sortOrder: 10,
        )
        let requestID = try AiChatRequestID(
            rawValue: XCTUnwrap(UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")),
        )
        let runID = try AiChatRunID(
            rawValue: XCTUnwrap(UUID(uuidString: "BBBBBBBB-CCCC-DDDD-EEEE-FFFFFFFFFFFF")),
        )
        let requestContext = AiChatRequestContextSnapshot(
            sessionID: aiSessionID,
            requestID: requestID,
            runID: runID,
            provider: .openai,
            model: modelHandle,
            selectedModel: AiProviderModel(
                id: modelHandle,
                provider: .openai,
                rawModelID: "gpt-4.1-mini",
                displayName: "GPT-4.1 Mini",
                providerDisplayName: "OpenAI",
                thinkingCapability: .unknown(reason: .init(message: "Not loaded")),
            ),
            selectedModelRow: catalogRow,
            sessionStatus: .active,
            promptSummary: "test",
            submittedAtMs: 0,
        )
        let request = AiChatRequest(
            context: requestContext,
            messages: [AiChatMessage(role: .user, content: "test")],
        )
        let requestLock = AiChatRequestLock(
            kind: .submit,
            requestID: requestID,
            runID: runID,
            context: requestContext,
            request: request,
            selectedModelHandle: modelHandle,
            selectedModelRow: catalogRow,
            assistantReplacementIndex: nil,
        )

        var aiChatContent = FileManagerContentFeature.State()
        aiChatContent.navigation.navigationState = .aiChat(sessionID)
        aiChatContent.aiChat.mode = .chat
        aiChatContent.aiChat.sessionID = aiSessionID
        aiChatContent.aiChat.sessionStatus = .active
        aiChatContent.aiChat.executionPhase = .processing(requestLock)

        var homeContent = FileManagerContentFeature.State()
        homeContent.navigation.seedInitialFolderPath("/Users/test/Home")

        var state = FileManagerFeature.State()
        state.contentTabs = ContentTabState(
            tabs: [
                ContentTabItem(
                    id: aiChatTabID,
                    page: .aiChat,
                    anchor: .aiChat(sessionID: sessionID),
                    isPinned: false,
                    title: "AI Chat",
                    iconName: "sparkles",
                ),
                ContentTabItem(
                    id: homeTabID,
                    page: .home,
                    anchor: .homeDefault,
                    isPinned: false,
                    title: "Home",
                    iconName: "house",
                ),
            ],
            activeTabID: aiChatTabID,
            recentlyClosed: nil,
        )
        state.content = aiChatContent
        state.tabContentStates = [homeTabID: homeContent]
        state.syncContentTabSidebarItems()

        let store = TestStore(initialState: state) {
            FileManagerFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
            $0.uuid = .incrementing
            $0.entryWatchingClient.startWatchingDirectory = { _ in
                AsyncStream { continuation in
                    continuation.finish()
                }
            }
        }
        store.exhaustivity = .off

        await store.send(.contentTabs(.close(aiChatTabID)))

        XCTAssertNil(store.state.contentTabs.tabs[id: aiChatTabID])
        XCTAssertEqual(store.state.contentTabs.recentlyClosed?.anchor, .aiChat(sessionID: sessionID))
        XCTAssertNotNil(store.state.backgroundAiChatStates[aiSessionID])
        XCTAssertEqual(
            store.state.backgroundAiChatStates[aiSessionID]?.aiChat.executionPhase,
            .processing(requestLock),
        )
        XCTAssertEqual(store.state.contentTabs.activeTabID, homeTabID)

        await store.skipReceivedActions()

        await store.send(.contentTabs(.open(.aiChat(sessionID: sessionID))))

        let newAIChatTabs = store.state.contentTabs.tabs.filter { $0.page == .aiChat }
        XCTAssertEqual(newAIChatTabs.count, 1, "should have exactly one AI Chat tab")
        XCTAssertEqual(newAIChatTabs[0].anchor, .aiChat(sessionID: sessionID))
        XCTAssertNotEqual(newAIChatTabs[0].id, aiChatTabID, "reopened tab should get a new ContentTabID")

        XCTAssertEqual(store.state.sidebar.contentTabSidebarItems.count, 2)
        let sidebarAiChatItems = store.state.sidebar.contentTabSidebarItems.filter { $0.pageType == .aiChat }
        XCTAssertEqual(sidebarAiChatItems.count, 1)

        if let newTabID = newAIChatTabs.first?.id {
            let newTabContentState = store.state.tabContentStates[newTabID]
            XCTAssertNotEqual(
                newTabContentState?.aiChat.executionPhase,
                .processing(requestLock),
                "new tab should not inherit the old background processing state",
            )
        }

        XCTAssertEqual(store.state.contentTabs.recentlyClosed?.anchor, .aiChat(sessionID: sessionID))

        await store.skipReceivedActions()
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

    func makeRequestLock(
        sessionID: AiChatSessionID,
        requestMessages: [AiChatMessage] = [AiChatMessage(role: .user, content: "test")],
        persistenceTranscriptHistory: [AiChatMessage]? = nil,
    ) -> AiChatRequestLock {
        let modelHandle = AiModelHandle(provider: .openai, rawValue: "gpt-4.1-mini")
        let catalogRow = AiModelCatalogRow(
            handle: modelHandle,
            displayName: "GPT-4.1 Mini",
            authMethod: .apiKey,
            sortOrder: 10,
        )
        let requestID = AiChatRequestID(rawValue: UUID())
        let runID = AiChatRunID(rawValue: UUID())
        let requestContext = AiChatRequestContextSnapshot(
            sessionID: sessionID,
            requestID: requestID,
            runID: runID,
            provider: .openai,
            model: modelHandle,
            selectedModel: AiProviderModel(
                id: modelHandle,
                provider: .openai,
                rawModelID: "gpt-4.1-mini",
                displayName: "GPT-4.1 Mini",
                providerDisplayName: "OpenAI",
                thinkingCapability: .unknown(reason: .init(message: "Not loaded")),
            ),
            selectedModelRow: catalogRow,
            sessionStatus: .active,
            promptSummary: "test",
            submittedAtMs: 0,
        )
        let request = AiChatRequest(context: requestContext, messages: requestMessages)
        return AiChatRequestLock(
            kind: .submit,
            requestID: requestID,
            runID: runID,
            context: requestContext,
            request: request,
            persistenceTranscriptHistory: persistenceTranscriptHistory,
            selectedModelHandle: modelHandle,
            selectedModelRow: catalogRow,
            assistantReplacementIndex: nil,
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

private extension AiChatFeature.State {
    mutating func applyDeletedSessionExpectation(sessionID deletedSessionID: AiChatSessionID) {
        pendingEmptyDraftDeletionSessionIDs.remove(deletedSessionID)
        sessionList.removeRow(sessionID: deletedSessionID)
        if restoreSessionID == deletedSessionID {
            restoreSessionID = nil
            restoreOutcome = nil
            restoreFailure = nil
        }
        if sessionID == deletedSessionID {
            sessionID = nil
            sessionStatus = .idle
            currentSessionCustomTitle = nil
            transcriptHistory = []
            draftText = ""
            streamingAssistantDraft = nil
            lockedModelHandle = nil
            lastExecutionFailure = nil
            lastRequestContext = nil
            lastRequestContextModelHandle = nil
            addedAttachments = []
            currentContextFolderStructureModes = [:]
            pendingRequestStart = nil
            executionPhase = .idle
            selectedModelHandle = nil
            selectedThinking = nil
            unavailableSelectedModelHandle = nil
        }
        backgroundPendingRequestStarts = backgroundPendingRequestStarts.filter { _, pendingRequestStart in
            pendingRequestStart.sessionID != deletedSessionID
        }
        backgroundExecutionPhases = backgroundExecutionPhases.filter { _, phase in
            phase.lock?.context.sessionID != deletedSessionID
        }
    }
}
