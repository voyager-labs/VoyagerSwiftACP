import ComposableArchitecture
import Foundation
import VoyagerEntitiesTag
@testable import VoyagerPagesFileManager
import XCTest

@MainActor
final class CTM004ContentTabSidebarTests: XCTestCase {
    // MARK: - CTM-004-sidebar_projection_content_tabs

    /// CTM-004-sidebar_projection_content_tabs: Sidebar projection은 열린 모든 탭을 tab 순서대로 flat list로 반영함
    /// ContentTabProjection.sidebarItems(from:)의 기본 출력 정확성을 검증한다.
    /// - 검증 내용: 3개 탭(Home, Directory, Collection) projection count == 3, 순서 일치
    /// - 사전 조건: HomeID → home, DirectoryID → .directory(path: "/test1"), CollectionID → .collectionFile(url:) 순서의
    /// ContentTabState
    /// - 기대 결과: sidebarItems가 tabs와 동일한 순서로 3개 항목을 반환
    func testSidebarProjection_listsAllOpenTabsInOrder() {
        let homeID = ContentTabID()
        let directoryID = ContentTabID()
        let collectionID = ContentTabID()
        let collectionURL = URL(fileURLWithPath: "/test/file.collection")
        let state = ContentTabState(
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
                    anchor: .directory(path: "/test1"),
                    isPinned: true,
                    title: "Test Folder",
                    iconName: "folder",
                ),
                ContentTabItem(
                    id: collectionID,
                    page: .collection,
                    anchor: .collectionFile(url: collectionURL),
                    isPinned: false,
                    title: "My Collection",
                    iconName: "list.bullet",
                ),
            ],
            activeTabID: homeID,
            recentlyClosed: nil,
        )

        let sidebarItems = ContentTabProjection.sidebarItems(from: state)

        XCTAssertEqual(sidebarItems.count, 3)
        XCTAssertEqual(sidebarItems[0].id, homeID)
        XCTAssertEqual(sidebarItems[0].title, "Home")
        XCTAssertEqual(sidebarItems[0].iconName, "house")
        XCTAssertEqual(sidebarItems[0].pageType, .home)
        XCTAssertEqual(sidebarItems[0].isPinned, false)
        XCTAssertEqual(sidebarItems[1].id, directoryID)
        XCTAssertEqual(sidebarItems[1].title, "Test Folder")
        XCTAssertEqual(sidebarItems[1].iconName, "folder")
        XCTAssertEqual(sidebarItems[1].pageType, .directory)
        XCTAssertEqual(sidebarItems[1].isPinned, true)
        XCTAssertEqual(sidebarItems[2].id, collectionID)
        XCTAssertEqual(sidebarItems[2].title, "My Collection")
        XCTAssertEqual(sidebarItems[2].iconName, "list.bullet")
        XCTAssertEqual(sidebarItems[2].pageType, .collection)
        XCTAssertEqual(sidebarItems[2].isPinned, false)
    }

    /// CTM-004-sidebar_projection_content_tabs: Sidebar projection은 정확히 하나의 tab만 active로 표시함
    /// activeTabID와 일치하는 항목만 isActive == true가 되는 정책을 검증한다.
    /// - 검증 내용: Directory tab이 active일 때 정확히 한 항목 isActive == true, 해당 id == directoryID
    /// - 사전 조건: Home + Directory(active) + Collection 세 탭, activeTabID == directoryID
    /// - 기대 결과: directoryID 항목만 isActive == true, 나머지는 isActive == false
    func testSidebarProjection_marksExactlyOneActiveTab() {
        let homeID = ContentTabID()
        let directoryID = ContentTabID()
        let collectionID = ContentTabID()
        let state = ContentTabState(
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
                    anchor: .directory(path: "/active"),
                    isPinned: false,
                    title: nil,
                    iconName: nil,
                ),
                ContentTabItem(
                    id: collectionID,
                    page: .collection,
                    anchor: .collectionFile(url: URL(fileURLWithPath: "/test.voycoll")),
                    isPinned: false,
                    title: nil,
                    iconName: nil,
                ),
            ],
            activeTabID: directoryID,
            recentlyClosed: nil,
        )

        let sidebarItems = ContentTabProjection.sidebarItems(from: state)

        XCTAssertEqual(sidebarItems.count, 3)
        let activeItems = sidebarItems.filter(\.isActive)
        XCTAssertEqual(activeItems.count, 1, "exactly one tab must be marked active")
        XCTAssertEqual(activeItems.first?.id, directoryID, "the active tab must match activeTabID")
        XCTAssertFalse(sidebarItems[0].isActive)
        XCTAssertTrue(sidebarItems[1].isActive)
        XCTAssertFalse(sidebarItems[2].isActive)
    }

    /// CTM-004-sidebar_projection_content_tabs: withHomeTab() 기본 상태의 sidebar projection은 Home tab 하나만 반영함
    /// ContentTabState.withHomeTab()에서 생성된 기본 상태의 projection 출력을 검증한다.
    /// - 검증 내용: count == 1, title == "Home", iconName == "house", isActive == true, pageType == .home
    /// - 사전 조건: ContentTabState.withHomeTab()
    /// - 기대 결과: 단일 Home tab 항목이 active 상태로 반환됨
    func testSidebarProjection_activeHomeTab() {
        let state = ContentTabState.withHomeTab()

        let sidebarItems = ContentTabProjection.sidebarItems(from: state)

        XCTAssertEqual(sidebarItems.count, 1)
        let homeItem = sidebarItems[0]
        XCTAssertEqual(homeItem.title, "Home")
        XCTAssertEqual(homeItem.iconName, "house")
        XCTAssertEqual(homeItem.pageType, .home)
        XCTAssertTrue(homeItem.isActive)
        XCTAssertFalse(homeItem.isPinned)
    }

    /// CTM-004-sidebar_projection_content_tabs: 빈 tab 목록의 sidebar projection은 빈 배열을 반환함
    /// tab이 없는 edge case에서 projection이 빈 배열을 반환하는 정책을 검증한다.
    /// - 검증 내용: tabs == [], activeTabID == nil → sidebarItems가 빈 배열
    /// - 사전 조건: 빈 ContentTabState
    /// - 기대 결과: sidebarItems.isEmpty == true
    func testSidebarProjection_withNoTabs() {
        let state = ContentTabState(tabs: [], activeTabID: nil, recentlyClosed: nil)

        let sidebarItems = ContentTabProjection.sidebarItems(from: state)

        XCTAssertTrue(sidebarItems.isEmpty)
    }

    /// CTM-004-sidebar_projection_content_tabs: Home에서 Directory로 전환된 단일 tab은 새 title/icon으로 표시됨
    /// 실제 Home Quick Access 선택 후 Sidebar Tabs row가 Home으로 남는 회귀를 검증한다.
    /// - 검증 내용: updateActivePageAnchor 적용 후 projection title == Desktop, pageType == directory
    /// - 사전 조건: ContentTabState.withHomeTab()의 Home tab
    /// - 기대 결과: tab id는 유지되고 row 표시만 Directory 메타데이터로 바뀜
    func testSidebarProjection_homeConvertedToDirectoryShowsDirectoryMetadata() {
        var state = ContentTabState.withHomeTab()
        let id = state.tabs[0].id
        let reducer = ContentTabFeature()

        _ = reducer.reduce(into: &state, action: .updateActivePageAnchor(id, .directory(path: "/Users/test/Desktop")))

        let sidebarItems = ContentTabProjection.sidebarItems(from: state)

        XCTAssertEqual(sidebarItems.count, 1)
        XCTAssertEqual(sidebarItems[0].id, id)
        XCTAssertEqual(sidebarItems[0].title, "Desktop")
        XCTAssertEqual(sidebarItems[0].iconName, "folder")
        XCTAssertEqual(sidebarItems[0].pageType, .directory)
        XCTAssertTrue(sidebarItems[0].isActive)
    }

    /// CTM-004-sidebar_initial_sync: 초기 Sidebar Tabs 섹션은 기본 Home tab을 표시함
    /// 첫 화면에서 Tabs 섹션이 비어 있다가 첫 tab action 후 나타나는 회귀를 방지한다.
    /// - 검증 내용: fresh FileManagerFeature.State의 sidebar.contentTabSidebarItems에 Home row 1개가 있음
    /// - 사전 조건: FileManagerWindowState.contentTabs 기본값은 withHomeTab()
    /// - 기대 결과: 초기 Sidebar Tabs row title == Home, pageType == home, isActive == true
    func testInitialStateSyncsHomeTabIntoSidebarItems() throws {
        let state = FileManagerFeature.State()

        XCTAssertEqual(state.sidebar.contentTabSidebarItems.count, 1)
        let item = try XCTUnwrap(state.sidebar.contentTabSidebarItems.first)
        XCTAssertEqual(item.title, "Home")
        XCTAssertEqual(item.iconName, "house")
        XCTAssertEqual(item.pageType, .home)
        XCTAssertTrue(item.isActive)
    }

    /// CTM-004-sidebar_projection_content_tabs: Directory tab은 기존 Locations 항목의 name/iconName을 재사용함
    /// Tabs row가 `/`, `.Trash` 같은 raw path 이름으로 표시되는 회귀를 방지한다.
    func testContentTabSidebarItems_reuseLocationDisplayNameAndIconForMatchingDirectory() {
        let rootID = ContentTabID()
        let trashID = ContentTabID()
        let rootURL = URL(fileURLWithPath: "/")
        let trashURL = URL(fileURLWithPath: "/Users/test/.Trash")
        var state = FileManagerFeature.State()
        state.contentTabs = ContentTabState(
            tabs: [
                ContentTabItem(
                    id: rootID,
                    page: .directory,
                    anchor: .directory(path: rootURL.path),
                    isPinned: false,
                    title: "/",
                    iconName: "folder",
                ),
                ContentTabItem(
                    id: trashID,
                    page: .directory,
                    anchor: .directory(path: trashURL.path),
                    isPinned: false,
                    title: ".Trash",
                    iconName: "folder",
                ),
            ],
            activeTabID: rootID,
            recentlyClosed: nil,
        )
        state.sidebar.locations = [
            SidebarItems.LocationItem(name: "Macintosh HD", url: rootURL, iconName: "internaldrive"),
            SidebarItems.LocationItem(name: "Trash", url: trashURL, iconName: "trash"),
        ]

        state.syncContentTabSidebarItems()

        XCTAssertEqual(state.sidebar.contentTabSidebarItems.map(\.title), ["Macintosh HD", "Trash"])
        XCTAssertEqual(state.sidebar.contentTabSidebarItems.map(\.iconName), ["internaldrive", "trash"])
        XCTAssertEqual(state.sidebar.contentTabSidebarItems.map(\.targetURL), [rootURL, trashURL])
        XCTAssertTrue(state.sidebar.contentTabSidebarItems.allSatisfy { $0.tagColorCode == nil })
    }

    /// CTM-004-sidebar_projection_content_tabs: Tag tab은 기존 Tags 섹션과 같은 tagColor를 재사용함
    /// Tags row가 SF Symbol tag 아이콘으로 표시되는 회귀를 방지한다.
    func testContentTabSidebarItems_reuseTagColorForMatchingTagVirtualCollection() throws {
        let tagID = ContentTabID()
        var state = FileManagerFeature.State()
        state.contentTabs = ContentTabState(
            tabs: [ContentTabItem(
                id: tagID,
                page: .collection,
                anchor: .virtualCollection(id: "Work"),
                isPinned: false,
                title: "Work",
                iconName: "folder",
            )],
            activeTabID: tagID,
            recentlyClosed: nil,
        )
        state.sidebar.tags = [Tag(name: "Work", colorCode: TagColor.red.colorCode)]

        state.syncContentTabSidebarItems()

        let item = try XCTUnwrap(state.sidebar.contentTabSidebarItems.first)
        XCTAssertEqual(item.title, "Work")
        XCTAssertEqual(item.tagColorCode, TagColor.red.colorCode)
    }

    // MARK: - CTM-004-sidebar_row_click_routing

    /// CTM-004-sidebar_row_click_routing: Sidebar ContentTab row click이 active tab과 저장된 ContentPane session을 함께 전환함
    /// SidebarView delegate → FileManagerWindowRoutingReducer → ContentTabFeature → tabContentStates swap을 검증한다.
    /// - 검증 내용: Directory tab row click 후 activeTabID가 바뀌고 content.navigation.currentPath가 저장된 tab session으로 복원됨
    /// - 사전 조건: Home + Directory 두 탭, 각 탭마다 별도 FileManagerContentFeature.State 저장
    /// - 기대 결과: Directory tab이 active로 전환되고 ContentPane state가 재네비게이션 없이 Directory tab session으로 swap됨
    func testRenderedRowClick_dispatchesSetCurrentAndRestoresContentSession() async {
        let homeID = ContentTabID()
        let directoryID = ContentTabID()
        let homeSessionPath = "/home/session"
        let directoryPath = "/test"
        var homeContent = FileManagerContentFeature.State()
        homeContent.navigation.seedInitialFolderPath(homeSessionPath)
        var directoryContent = FileManagerContentFeature.State()
        directoryContent.navigation.seedInitialFolderPath(directoryPath)
        var state = FileManagerFeature.State()
        state.contentTabs.tabs = [
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
                title: "Test",
                iconName: "folder",
            ),
        ]
        state.contentTabs.activeTabID = homeID
        state.content = homeContent
        state.tabContentStates = [
            homeID: homeContent,
            directoryID: directoryContent,
        ]
        state.syncContentTabSidebarItems()
        let store = TestStore(initialState: state) {
            FileManagerFeature()
        }

        await store.send(.sidebar(.delegate(.selectContentTab(directoryID))))
        await store.receive(\.contentTabs) {
            $0.contentTabs.previousActiveTabID = homeID
            $0.contentTabs.activeTabID = directoryID
            $0.tabContentStates[homeID] = homeContent
            $0.content = directoryContent
            $0.sidebar.contentTabSidebarItems = ContentTabProjection.sidebarItems(from: $0.contentTabs)
        }

        XCTAssertEqual(store.state.contentTabs.activeTabID, directoryID, "active tab must switch to Directory")
        XCTAssertEqual(store.state.content.navigation.currentPath, directoryPath)
        XCTAssertEqual(store.state.tabContentStates[homeID]?.navigation.currentPath, homeSessionPath)

        await store.send(.sidebar(.delegate(.selectContentTab(homeID))))
        await store.receive(\.contentTabs) {
            $0.contentTabs.previousActiveTabID = directoryID
            $0.contentTabs.activeTabID = homeID
            $0.tabContentStates[directoryID] = directoryContent
            $0.content = homeContent
            $0.sidebar.contentTabSidebarItems = ContentTabProjection.sidebarItems(from: $0.contentTabs)
        }

        XCTAssertEqual(store.state.contentTabs.activeTabID, homeID, "active tab must switch back to Home")
        XCTAssertEqual(ContentTabProjection.activePageAnchor(from: store.state.contentTabs), .homeDefault)
        XCTAssertEqual(store.state.content.navigation.currentPath, homeSessionPath)
        XCTAssertEqual(store.state.tabContentStates[directoryID]?.navigation.currentPath, directoryPath)
    }
}
