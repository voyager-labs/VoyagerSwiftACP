import ComposableArchitecture
import Foundation
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

    /// CTM-005-independent_content_tab_session: active tab close 시 fallback tab의 저장된 session으로 복원됨
    /// active tab 닫힘으로 인해 fallback tab의 FileManagerContent session이 올바르게 복원되는지 검증한다.
    /// - 검증 내용: close 후 activeTabID == fallback, content.navigation == fallback tab의 session 경로
    /// - 사전 조건: 두 content tab이 서로 다른 경로를 가진 session을 보유, active tab이 B(directory)
    /// - 기대 결과: activeTabID == A, content.currentPath == A session 경로, closed tab session(tabContentStates[B]) == nil
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
        }
        // KCF: closeWindow action 이후 NSApp close side effect는 여기서 검증하지 않음
        store.exhaustivity = .off

        await store.send(.contentTabs(.close(directoryID)))
        await store.receive(\.closeWindow)
        await store.finish()
    }
}
