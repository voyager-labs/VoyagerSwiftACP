import ComposableArchitecture
import Foundation
@testable import VoyagerPagesFileManager
import XCTest

@MainActor
final class CTM003ActiveContentTabSwitchingTests: XCTestCase {
    // MARK: - CTM-003-switch_active_content_tab

    /// CTM-003-switch_active_content_tab: setCurrent로 Directory tab 전환 시 activeTabID와 activePageAnchor가 일치함
    /// active tab switching이 ContentTabState와 projection을 함께 갱신하는지 검증한다.
    /// - 검증 내용: activeTabID가 Directory tab으로 변경되고 activePageAnchor가 directory anchor와 일치함
    /// - 사전 조건: Home과 Directory 두 탭이 있고 Home이 active 상태
    /// - 기대 결과: .setCurrent(directoryID) 후 activeTabID == directoryID, activePageAnchor == .directory(path:)
    func testSetCurrentDirectoryTab_activePageAnchorHandoff() async {
        let homeID = ContentTabID()
        let directoryID = ContentTabID()
        let directoryAnchor = ContentTabPageAnchor.directory(path: "/test1")
        let tabs: IdentifiedArrayOf<ContentTabItem> = [
            ContentTabItem(id: homeID, page: .home, anchor: .homeDefault, isPinned: false, title: nil, iconName: nil),
            ContentTabItem(
                id: directoryID,
                page: .directory,
                anchor: directoryAnchor,
                isPinned: false,
                title: nil,
                iconName: nil,
            ),
        ]
        let store = TestStore(
            initialState: ContentTabState(tabs: tabs, activeTabID: homeID, recentlyClosed: nil),
        ) {
            ContentTabFeature()
        }

        await store.send(.setCurrent(directoryID)) {
            $0.previousActiveTabID = homeID
            $0.recentlyUsedTabIDs = [directoryID, homeID]
            $0.activeTabID = directoryID
        }
        XCTAssertEqual(ContentTabProjection.activePageAnchor(from: store.state), directoryAnchor)
        await store.finish()
    }

    /// CTM-003-switch_active_content_tab: setCurrent로 Home tab 전환 시 activePageAnchor가 homeDefault로 복원됨
    /// Directory tab에서 Home tab으로 전환 시 anchor가 올바르게 homeDefault로 전환되는지 검증한다.
    /// - 검증 내용: activeTabID가 Home tab으로 변경되고 activePageAnchor가 .homeDefault와 일치함
    /// - 사전 조건: Home과 Directory 두 탭이 있고 Directory가 active 상태
    /// - 기대 결과: .setCurrent(homeID) 후 activeTabID == homeID, activePageAnchor == .homeDefault
    func testSetCurrentHomeTab_activePageAnchorHomeDefault() async {
        let homeID = ContentTabID()
        let directoryID = ContentTabID()
        let directoryAnchor = ContentTabPageAnchor.directory(path: "/test1")
        let tabs: IdentifiedArrayOf<ContentTabItem> = [
            ContentTabItem(id: homeID, page: .home, anchor: .homeDefault, isPinned: false, title: nil, iconName: nil),
            ContentTabItem(
                id: directoryID,
                page: .directory,
                anchor: directoryAnchor,
                isPinned: false,
                title: nil,
                iconName: nil,
            ),
        ]
        let store = TestStore(
            initialState: ContentTabState(tabs: tabs, activeTabID: directoryID, recentlyClosed: nil),
        ) {
            ContentTabFeature()
        }

        await store.send(.setCurrent(homeID)) {
            $0.previousActiveTabID = directoryID
            $0.recentlyUsedTabIDs = [homeID, directoryID]
            $0.activeTabID = homeID
        }
        XCTAssertEqual(ContentTabProjection.activePageAnchor(from: store.state), .homeDefault)
        await store.finish()
    }

    /// CTM-003-switch_active_content_tab: 존재하지 않는 tab ID로 setCurrent를 호출하면 아무 변화도 없음
    /// invalid target tab ID가 주어질 때 activeTabID와 anchor가 보존되는지 검증한다.
    /// - 검증 내용: activeTabID와 activePageAnchor가 setCurrent 호출 전후로 동일함
    /// - 사전 조건: Home tab 하나가 active 상태, invalidID는 tabs에 존재하지 않음
    /// - 기대 결과: activeTabID와 activePageAnchor가 변경되지 않음
    func testInvalidTabID_doesNotChangeActiveTabOrAnchor() async {
        let homeID = ContentTabID()
        let invalidID = ContentTabID()
        let store = TestStore(
            initialState: ContentTabState(
                tabs: [ContentTabItem(
                    id: homeID,
                    page: .home,
                    anchor: .homeDefault,
                    isPinned: false,
                    title: nil,
                    iconName: nil,
                )],
                activeTabID: homeID,
                recentlyClosed: nil,
            ),
        ) {
            ContentTabFeature()
        }

        let beforeActiveID = store.state.activeTabID
        let beforeAnchor = ContentTabProjection.activePageAnchor(from: store.state)

        await store.send(.setCurrent(invalidID))

        XCTAssertEqual(store.state.activeTabID, beforeActiveID)
        XCTAssertEqual(ContentTabProjection.activePageAnchor(from: store.state), beforeAnchor)
        await store.finish()
    }

    /// CTM-003-home_anchor_conversion_metadata: Home tab이 Directory anchor로 전환되면 sidebar row 메타데이터도 갱신됨
    /// Home 화면 카드 선택 후 Tabs 섹션 row가 계속 Home으로 남는 회귀를 방지한다.
    /// - 검증 내용: .updateActivePageAnchor 후 tab title == 마지막 경로명, iconName == folder 계열 기본값
    /// - 사전 조건: title/iconName이 Home인 단일 Home tab
    /// - 기대 결과: 같은 tab id를 유지하면서 Directory tab 메타데이터로 전환됨
    func testUpdateActivePageAnchorFromHome_updatesSidebarMetadata() async {
        let homeID = ContentTabID()
        let desktopAnchor = ContentTabPageAnchor.directory(path: "/Users/test/Desktop")
        let store = TestStore(
            initialState: ContentTabState(tabs: [ContentTabItem(
                id: homeID,
                page: .home,
                anchor: .homeDefault,
                isPinned: false,
                title: "Home",
                iconName: "house",
            )], activeTabID: homeID, recentlyClosed: nil),
        ) {
            ContentTabFeature()
        } withDependencies: {
            $0.entryLoadingClient.displayName = { URL(fileURLWithPath: $0).lastPathComponent }
        }

        await store.send(.updateActivePageAnchor(homeID, desktopAnchor)) {
            $0.tabs[id: homeID]?.page = .directory
            $0.tabs[id: homeID]?.anchor = desktopAnchor
            $0.tabs[id: homeID]?.title = "Desktop"
            $0.tabs[id: homeID]?.iconName = "folder"
        }
        XCTAssertEqual(ContentTabProjection.sidebarItems(from: store.state).first?.title, "Desktop")
        XCTAssertEqual(ContentTabProjection.sidebarItems(from: store.state).first?.iconName, "folder")
        await store.finish()
    }

    /// CTM-003-home_anchor_conversion_metadata: Collection anchor는 컬렉션 타이틀 계열 아이콘을 사용함
    /// Collection tab이 일반 folder 아이콘으로 보이는 회귀를 방지한다.
    func testUpdateActivePageAnchorFromHome_usesCollectionIcon() async {
        let homeID = ContentTabID()
        let collectionURL = URL(fileURLWithPath: "/Users/test/Saved.voycoll")
        let collectionAnchor = ContentTabPageAnchor.collectionFile(url: collectionURL)
        let store = TestStore(
            initialState: ContentTabState(tabs: [ContentTabItem(
                id: homeID,
                page: .home,
                anchor: .homeDefault,
                isPinned: false,
                title: "Home",
                iconName: "house",
            )], activeTabID: homeID, recentlyClosed: nil),
        ) {
            ContentTabFeature()
        }

        await store.send(.updateActivePageAnchor(homeID, collectionAnchor)) {
            $0.tabs[id: homeID]?.page = .collection
            $0.tabs[id: homeID]?.anchor = collectionAnchor
            $0.tabs[id: homeID]?.title = "Saved"
            $0.tabs[id: homeID]?.iconName = "rectangle.stack"
        }
        XCTAssertEqual(ContentTabProjection.sidebarItems(from: store.state).first?.iconName, "rectangle.stack")
        await store.finish()
    }

    /// CTM-003-home_anchor_conversion_metadata: Recents virtual collection은 Sidebar Recents와 같은 clock 아이콘을 사용함
    /// Recents tab이 일반 folder 아이콘으로 보이는 회귀를 방지한다.
    func testUpdateActivePageAnchorFromHome_usesRecentsIcon() async {
        let homeID = ContentTabID()
        let recentsAnchor = ContentTabPageAnchor.virtualCollection(id: "Recents")
        let store = TestStore(
            initialState: ContentTabState(tabs: [ContentTabItem(
                id: homeID,
                page: .home,
                anchor: .homeDefault,
                isPinned: false,
                title: "Home",
                iconName: "house",
            )], activeTabID: homeID, recentlyClosed: nil),
        ) {
            ContentTabFeature()
        }

        await store.send(.updateActivePageAnchor(homeID, recentsAnchor)) {
            $0.tabs[id: homeID]?.page = .collection
            $0.tabs[id: homeID]?.anchor = recentsAnchor
            $0.tabs[id: homeID]?.title = "Recents"
            $0.tabs[id: homeID]?.iconName = "clock"
        }
        XCTAssertEqual(ContentTabProjection.sidebarItems(from: store.state).first?.iconName, "clock")
        await store.finish()
    }

    /// CTM-003-home_anchor_conversion_metadata: 특수 폴더 anchor는 Sidebar와 같은 폴더별 아이콘을 사용함
    /// Desktop/Downloads/Documents 등 특수 폴더가 일반 folder 아이콘으로 퇴행하는 회귀를 방지한다.
    /// - 검증 내용: .updateActivePageAnchor(.directory(path:)) 후 fileManagerIconClient가 반환한 iconName이 tab metadata에 반영됨
    /// - 사전 조건: Home tab 하나가 active 상태이고 icon client가 Desktop 경로에 특수 아이콘을 반환함
    /// - 기대 결과: 같은 tab id를 유지하면서 title == Desktop, iconName == menubar.dock.rectangle
    func testUpdateActivePageAnchorFromHome_usesDirectorySpecificIcon() async {
        let homeID = ContentTabID()
        let desktopPath = "/Users/test/Desktop"
        let desktopAnchor = ContentTabPageAnchor.directory(path: desktopPath)
        let store = TestStore(
            initialState: ContentTabState(tabs: [ContentTabItem(
                id: homeID,
                page: .home,
                anchor: .homeDefault,
                isPinned: false,
                title: "Home",
                iconName: "house",
            )], activeTabID: homeID, recentlyClosed: nil),
        ) {
            ContentTabFeature()
        } withDependencies: {
            $0.entryLoadingClient.displayName = { URL(fileURLWithPath: $0).lastPathComponent }
            $0.fileManagerIconClient.iconNameForURL = { url, isDirectory, _ in
                isDirectory && url.path == desktopPath ? "menubar.dock.rectangle" : "folder"
            }
        }

        await store.send(.updateActivePageAnchor(homeID, desktopAnchor)) {
            $0.tabs[id: homeID]?.page = .directory
            $0.tabs[id: homeID]?.anchor = desktopAnchor
            $0.tabs[id: homeID]?.title = "Desktop"
            $0.tabs[id: homeID]?.iconName = "menubar.dock.rectangle"
        }
        XCTAssertEqual(ContentTabProjection.sidebarItems(from: store.state).first?.iconName, "menubar.dock.rectangle")
        await store.finish()
    }

    /// CTM-003-navigation_tab_sync: Directory tab에서 후속 폴더 이동 시 active tab metadata도 새 경로로 갱신됨
    /// ContentPageNavigation route 확정 이후 Sidebar Tabs row가 이전 폴더명에 머무는 회귀를 방지한다.
    /// - 검증 내용: .navigation.delegate(.navigateToState(.folder(nextPath))) 후 active tab anchor/title/icon 및 sidebar
    /// projection 갱신
    /// - 사전 조건: active Directory tab anchor == /Users/test/Desktop, navigationState == /Users/test/Desktop/Project
    /// - 기대 결과: active tab anchor == nextPath, title == Project, Sidebar projection row title == Project
    func testNavigationDelegateToFolder_updatesActiveTabSidebarMetadata() async throws {
        let tabID = ContentTabID()
        let nextPath = "/Users/test/Desktop/Project"
        var state = FileManagerFeature.State()
        state.contentTabs.tabs = [ContentTabItem(
            id: tabID,
            page: .directory,
            anchor: .directory(path: "/Users/test/Desktop"),
            isPinned: false,
            title: "Desktop",
            iconName: "folder",
        )]
        state.contentTabs.activeTabID = tabID
        state.content.navigation.navigationState = .folder(nextPath)
        state.sidebar.contentTabSidebarItems = ContentTabProjection.sidebarItems(from: state.contentTabs)
        let store = TestStore(initialState: state) {
            FileManagerFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
            $0.entryLoadingClient.displayName = { URL(fileURLWithPath: $0).lastPathComponent }
        }
        store.exhaustivity = .off

        await store.send(.navigation(.delegate(.navigateToState(.folder(nextPath)))))
        await store.receive(\.contentTabs)
        await store.receive { action in
            guard case let .tabContent(
                receivedTabID,
                .internal(.applyNavigationState(.folder(receivedPath))),
            ) = action else { return false }
            return receivedTabID == tabID && receivedPath == nextPath
        }

        let tab = try XCTUnwrap(store.state.contentTabs.tabs[id: tabID])
        XCTAssertEqual(tab.anchor, .directory(path: nextPath))
        XCTAssertEqual(tab.title, "Project")
        XCTAssertEqual(tab.iconName, "folder")
        let sidebarItem = try XCTUnwrap(store.state.sidebar.contentTabSidebarItems.first)
        XCTAssertEqual(sidebarItem.title, "Project")
        XCTAssertEqual(sidebarItem.iconName, "folder")
    }

    /// CTM-003-switch_active_content_tab: 마지막 Directory tab close 시 Home tab으로 복원됨
    /// Task 3의 last-tab Home restore 정책이 tab 상태와 projection anchor를 올바르게 재설정하는지 검증한다.
    /// - 검증 내용: close 후 tabs.count == 1, page == .home, anchor == .homeDefault, title == "Home", activeTabID != nil
    /// - 사전 조건: Directory tab 단일 active 상태
    /// - 기대 결과: 마지막 tab이 제거되지 않고 Home tab으로 reset되어 새 Home tab을 보여줌
    func testLastTabClose_restoresHomeTab() {
        let directoryID = ContentTabID()
        let directoryAnchor = ContentTabPageAnchor.directory(path: "/test1")
        var state = ContentTabState(
            tabs: [ContentTabItem(
                id: directoryID,
                page: .directory,
                anchor: directoryAnchor,
                isPinned: false,
                title: nil,
                iconName: nil,
            )],
            activeTabID: directoryID,
            recentlyClosed: nil,
        )
        let reducer = ContentTabFeature()

        _ = reducer.reduce(into: &state, action: .close(directoryID))

        XCTAssertEqual(state.tabs.count, 1)
        XCTAssertEqual(state.tabs[0].page, .home)
        XCTAssertEqual(state.tabs[0].anchor, .homeDefault)
        XCTAssertEqual(state.tabs[0].title, "Home")
        XCTAssertNotNil(state.activeTabID)
    }

    /// CTM-003-switch_active_content_tab: non-last tab close는 영향을 받은 tab만 제거하고 snapshot을 생성함
    /// 마지막 tab이 아닌 tab을 닫을 때 기존 tab 목록과 active 상태가 유지되는지 검증한다.
    /// - 검증 내용: Directory tab close 후 tabs.count == 1, 나머지 Home tab의 anchor가 .homeDefault로 유지됨
    /// - 사전 조건: Home과 Directory 두 탭이 있고 Home이 active 상태
    /// - 기대 결과: Directory tab만 제거되고 recentlyClosed snapshot이 생성됨
    func testNonLastTabClose_preservesExistingBehavior() throws {
        let homeID = ContentTabID()
        let directoryID = ContentTabID()
        let directoryAnchor = ContentTabPageAnchor.directory(path: "/test1")
        var state = ContentTabState(
            tabs: [
                ContentTabItem(
                    id: homeID,
                    page: .home,
                    anchor: .homeDefault,
                    isPinned: false,
                    title: nil,
                    iconName: nil,
                ),
                ContentTabItem(
                    id: directoryID,
                    page: .directory,
                    anchor: directoryAnchor,
                    isPinned: false,
                    title: nil,
                    iconName: nil,
                ),
            ],
            activeTabID: homeID,
            recentlyClosed: nil,
        )
        let reducer = ContentTabFeature()

        _ = reducer.reduce(into: &state, action: .close(directoryID))

        XCTAssertEqual(state.tabs.count, 1)
        XCTAssertEqual(state.tabs[0].id, homeID)
        XCTAssertEqual(state.activeTabID, homeID)
        XCTAssertEqual(state.recentlyClosed?.page, .directory)
        XCTAssertEqual(state.recentlyClosed?.anchor, directoryAnchor)
        XCTAssertFalse(try XCTUnwrap(state.recentlyClosed?.wasPinned))
        XCTAssertNotNil(state.recentlyClosed?.closedAt)
    }

    /// CTM-003-switch_active_content_tab: active tab close 시 previousActiveTabID로 fallback되고 anchor가 보존됨
    /// active tab을 닫을 때 previousActiveTabID로 지정된 tab으로 focus가 이동하며
    /// 해당 tab의 anchor가 유지되는지 검증한다.
    /// - 검증 내용: close 후 activeTabID == previousActiveTabID(A), A anchor == .homeDefault,
    ///   recentlyClosed anchor == closed tab(B) anchor
    /// - 사전 조건: 세 tab [A(home), B(directory, active), C(collection)]이 있고 previousActiveTabID == A
    /// - 기대 결과: activeTabID가 A로 fallback되고, A의 anchor는 변하지 않으며,
    ///   recentlyClosed에 B의 snapshot이 저장됨
    func testActiveCloseFallbackAnchorPreserved() {
        let tabA = ContentTabID()
        let tabB = ContentTabID()
        let tabC = ContentTabID()
        let directoryAnchor = ContentTabPageAnchor.directory(path: "/test1")
        var state = ContentTabState(
            tabs: [
                ContentTabItem(
                    id: tabA,
                    page: .home,
                    anchor: .homeDefault,
                    isPinned: false,
                    title: nil,
                    iconName: nil,
                ),
                ContentTabItem(
                    id: tabB,
                    page: .directory,
                    anchor: directoryAnchor,
                    isPinned: false,
                    title: nil,
                    iconName: nil,
                ),
                ContentTabItem(
                    id: tabC,
                    page: .collection,
                    anchor: .collectionFile(url: URL(fileURLWithPath: "/test.voycoll")),
                    isPinned: false,
                    title: nil,
                    iconName: nil,
                ),
            ],
            activeTabID: tabB,
            previousActiveTabID: tabA,
            recentlyClosed: nil,
        )
        let reducer = ContentTabFeature()

        _ = reducer.reduce(into: &state, action: .close(tabB))

        XCTAssertEqual(state.activeTabID, tabA)
        XCTAssertEqual(state.tabs[id: tabA]?.anchor, .homeDefault)
        XCTAssertEqual(state.recentlyClosed?.page, .directory)
        XCTAssertEqual(state.recentlyClosed?.anchor, directoryAnchor)
        XCTAssertNotNil(state.recentlyClosed?.closedAt)
    }
}
