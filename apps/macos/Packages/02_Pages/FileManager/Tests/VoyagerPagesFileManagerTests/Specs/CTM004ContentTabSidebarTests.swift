import ComposableArchitecture
import Foundation
import VoyagerEntitiesAi
import VoyagerEntitiesAppPreferences
import VoyagerEntitiesEntry
@testable import VoyagerPagesFileManager
import VoyagerShared
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
        let reducer = withDependencies {
            $0.entryLoadingClient.displayName = { _ in "Desktop" }
        } operation: {
            ContentTabFeature()
        }

        _ = reducer.reduce(into: &state, action: .updateActivePageAnchor(id, .directory(path: "/Users/test/Desktop")))

        let sidebarItems = ContentTabProjection.sidebarItems(from: state)

        XCTAssertEqual(sidebarItems.count, 1)
        XCTAssertEqual(sidebarItems[0].id, id)
        XCTAssertEqual(sidebarItems[0].title, "Desktop")
        XCTAssertEqual(sidebarItems[0].iconName, "folder")
        XCTAssertEqual(sidebarItems[0].pageType, .directory)
        XCTAssertTrue(sidebarItems[0].isActive)
    }

    /// CTM-004-sidebar_projection_content_tabs: Collection tab은 collection 파일 표시 이름을 사용함
    /// 삭제된 FavoriteItem.displayName의 .voycoll 확장자 제거 표시 로직을 ContentTab metadata 생성 단계에서 유지한다.
    func testSidebarProjection_collectionFileUsesCollectionDisplayName() {
        var state = ContentTabState.withHomeTab()
        let id = state.tabs[0].id
        let reducer = ContentTabFeature()

        _ = reducer.reduce(
            into: &state,
            action: .updateActivePageAnchor(
                id,
                .collectionFile(url: URL(fileURLWithPath: "/Users/test/Research.voycoll")),
            ),
        )

        let sidebarItems = ContentTabProjection.sidebarItems(from: state)

        XCTAssertEqual(sidebarItems.first?.title, "Research")
        XCTAssertEqual(sidebarItems.first?.iconName, "rectangle.stack")
        XCTAssertEqual(sidebarItems.first?.pageType, .collection)
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

    /// CTM-004-sidebar_projection_content_tabs: Directory tab은 ContentTab 자체 metadata를 그대로 표시함
    /// Fixed Locations grid와 Tabs row가 서로 다른 projection 원천을 사용하는 정책을 검증한다.
    func testContentTabSidebarItems_useContentTabMetadataForDirectory() {
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

        XCTAssertEqual(state.sidebar.contentTabSidebarItems.map(\.title), ["Desktop"])
        XCTAssertEqual(state.sidebar.contentTabSidebarItems.map(\.iconName), ["folder"])
        XCTAssertEqual(
            state.sidebar.contentTabSidebarItems.first?.targetURL,
            URL(fileURLWithPath: "/Users/test/Desktop"),
        )
        XCTAssertTrue(state.sidebar.contentTabSidebarItems.allSatisfy { $0.tagColorCode == nil })
    }

    /// CTM-004-sidebar_projection_content_tabs: virtual collection tab은 Sidebar Tags 섹션 상태 없이 ContentTab metadata만 사용함
    /// Tags 섹션 제거 후 tagColor enrich가 사라지고 tab row metadata가 직접 투영되는 정책을 검증한다.
    func testContentTabSidebarItems_useContentTabMetadataForVirtualCollection() throws {
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

        state.syncContentTabSidebarItems()

        let item = try XCTUnwrap(state.sidebar.contentTabSidebarItems.first)
        XCTAssertEqual(item.title, "Work")
        XCTAssertEqual(item.iconName, "folder")
        XCTAssertNil(item.tagColorCode)
    }

    // MARK: - CTM-004-sidebar_fixed_locations

    /// CTM-004-sidebar_fixed_locations: fixed Locations는 window onAppear sync 전에는 비어 있음
    /// Locations grid가 ContentTabProjection에 섞이지 않고 window bootstrap에서 별도 주입되는 정책을 검증한다.
    func testInitialStateHasNoFixedLocationsUntilWindowAppearSync() {
        let state = FileManagerFeature.State()

        XCTAssertTrue(state.sidebar.fixedLocationItems.isEmpty)
        XCTAssertEqual(state.sidebar.contentTabSidebarItems.map(\.title), ["Home"])
    }

    /// CTM-004-sidebar_fixed_locations: fixed Locations는 Finder/Voyager Locations source를 별도 grid item으로 구성함
    /// Sidebar 상단 icon grid가 iCloud/CloudStorage/home/root/Trash source를 안정적인 id/path로 노출함을 검증한다.
    func testSyncFixedLocationItems_populatesSystemLocations() {
        var state = FileManagerFeature.State()

        state.syncFixedLocationItems(with: Self.fixedLocationClient(), entryLoadingClient: .testValue)

        XCTAssertEqual(state.sidebar.fixedLocationItems.map(\.title), [
            "iCloud Drive",
            "OneDrive",
            "wonsik",
            "Macintosh HD",
            "Trash",
        ])
        XCTAssertEqual(state.sidebar.fixedLocationItems.map(\.path), [
            "/Users/test/Library/Mobile Documents/com~apple~CloudDocs",
            "/Users/test/Library/CloudStorage/OneDrive",
            "/Users/test",
            "/",
            "/Users/test/.Trash",
        ])
    }

    /// CTM-004-sidebar_fixed_locations: fixed Locations grid는 pinned/unpinned ContentTab row와 섞이지 않음
    /// Favorites로 seed된 pinned tab은 일반 ContentTab row list에 남고, Locations는 별도 grid에만 남는 구조를 검증한다.
    func testFixedLocationsRemainSeparateFromContentTabSidebarItems() {
        let pinnedID = ContentTabID()
        var state = FileManagerFeature.State()
        state.contentTabs = ContentTabState(
            tabs: [ContentTabItem(
                id: pinnedID,
                page: .directory,
                anchor: .directory(path: "/Users/test/Projects"),
                isPinned: true,
                title: "Projects",
                iconName: "folder",
            )],
            activeTabID: pinnedID,
            recentlyClosed: nil,
        )

        state.syncFixedLocationItems(with: Self.fixedLocationClient(), entryLoadingClient: .testValue)
        state.syncContentTabSidebarItems()

        XCTAssertEqual(state.sidebar.fixedLocationItems.map(\.title), [
            "iCloud Drive",
            "OneDrive",
            "wonsik",
            "Macintosh HD",
            "Trash",
        ])
        XCTAssertEqual(state.content.homeLocationItems.map(\.title), state.sidebar.fixedLocationItems.map(\.title))
        XCTAssertEqual(state.sidebar.contentTabSidebarItems.map(\.title), ["Projects"])
        XCTAssertTrue(state.sidebar.contentTabSidebarItems.allSatisfy(\.isPinned))
    }

    /// CTM-004-sidebar_fixed_locations_visibility: 숨긴 Locations는 Sidebar와 Home dashboard projection에서 제외함
    /// 전체 Locations 원본은 보존해 all-hidden 상태에서도 컨텍스트 메뉴 복구가 가능해야 함.
    func testSyncFixedLocationItems_appliesHiddenLocationPreferenceToSidebarAndHome() throws {
        var seedState = FileManagerFeature.State()
        seedState.syncFixedLocationItems(with: Self.fixedLocationClient(), entryLoadingClient: .testValue)
        let oneDriveID = try XCTUnwrap(seedState.sidebar.fixedLocationItems.first { $0.title == "OneDrive" }?.id)
        let trashID = try XCTUnwrap(seedState.sidebar.fixedLocationItems.first { $0.title == "Trash" }?.id)
        var state = FileManagerFeature.State()

        state.syncFixedLocationItems(
            with: Self.fixedLocationClient(),
            entryLoadingClient: .testValue,
            hiddenLocationIDs: [oneDriveID, trashID],
        )

        XCTAssertEqual(state.sidebar.allFixedLocationItems.map(\.title), [
            "iCloud Drive",
            "OneDrive",
            "wonsik",
            "Macintosh HD",
            "Trash",
        ])
        XCTAssertEqual(state.sidebar.fixedLocationItems.map(\.title), [
            "iCloud Drive",
            "wonsik",
            "Macintosh HD",
        ])
        XCTAssertEqual(state.content.homeLocationItems.map(\.title), [
            "iCloud Drive",
            "OneDrive",
            "wonsik",
            "Macintosh HD",
            "Trash",
        ])
        XCTAssertFalse(state.sidebar.isFixedLocationVisible(oneDriveID))
        XCTAssertFalse(state.sidebar.isFixedLocationVisible(trashID))
    }

    /// CTM-004-sidebar_fixed_locations_visibility: 사용자 토글은 hidden ID를 저장하고 Home projection을 즉시 갱신함
    /// - 검증 내용: Sidebar context menu Toggle action → hidden IDs persist → Home Locations에서 제거
    func testFixedLocationVisibilityActionPersistsHiddenIDsAndUpdatesHomeProjection() async throws {
        var state = FileManagerFeature.State()
        state.syncFixedLocationItems(with: Self.fixedLocationClient(), entryLoadingClient: .testValue)
        let oneDriveID = try XCTUnwrap(state.sidebar.fixedLocationItems.first { $0.title == "OneDrive" }?.id)
        let persistedIDs = LockIsolated<[String]?>(nil)
        let persistedKey = LockIsolated<String?>(nil)
        let store = TestStore(initialState: state) {
            FileManagerFeature()
        } withDependencies: {
            $0.userDefaultsClient.setObject = { value, key in
                let ids = value as? [String]
                persistedIDs.setValue(ids)
                persistedKey.setValue(key)
            }
        }
        store.exhaustivity = .off

        await store.send(.sidebar(.view(.setFixedLocationVisibility(oneDriveID, false)))) {
            $0.sidebar.setFixedLocationVisibility(id: oneDriveID, isVisible: false)
            $0.syncHomeLocationItems()
        }

        XCTAssertEqual(persistedKey.value, SettingsKeys.hiddenFixedLocationIDs)
        XCTAssertEqual(persistedIDs.value, [oneDriveID])
        XCTAssertFalse(store.state.sidebar.fixedLocationItems.contains { $0.id == oneDriveID })
        XCTAssertTrue(store.state.content.homeLocationItems.contains { $0.id == oneDriveID })
    }

    /// CTM-004-sidebar_fixed_locations_visibility: 모든 Locations를 숨기거나 다시 보이게 할 수 있음
    /// allFixedLocationItems는 유지되어 전부 숨긴 상태에서도 메뉴 source로 사용된다.
    func testSetAllFixedLocationVisibilityCanHideAndRestoreAllLocations() async {
        var state = FileManagerFeature.State()
        state.syncFixedLocationItems(with: Self.fixedLocationClient(), entryLoadingClient: .testValue)
        let allIDs = Set(state.sidebar.allFixedLocationItems.map(\.id))
        let persistedValues = LockIsolated<[[String]]>([])
        let store = TestStore(initialState: state) {
            FileManagerFeature()
        } withDependencies: {
            $0.userDefaultsClient.setObject = { value, _ in
                let ids = value as? [String] ?? []
                persistedValues.withValue { $0.append(ids) }
            }
        }
        store.exhaustivity = .off

        await store.send(.sidebar(.view(.setAllFixedLocationVisibility(false)))) {
            $0.sidebar.setAllFixedLocationVisibility(false)
            $0.syncHomeLocationItems()
        }
        XCTAssertEqual(Set(persistedValues.value.last ?? []), allIDs)
        XCTAssertEqual(store.state.sidebar.allFixedLocationItems.count, 5)
        XCTAssertTrue(store.state.sidebar.fixedLocationItems.isEmpty)
        XCTAssertEqual(store.state.content.homeLocationItems.count, 5)

        await store.send(.sidebar(.view(.setAllFixedLocationVisibility(true)))) {
            $0.sidebar.setAllFixedLocationVisibility(true)
            $0.syncHomeLocationItems()
        }
        XCTAssertEqual(persistedValues.value.last, [])
        XCTAssertEqual(store.state.sidebar.fixedLocationItems.map(\.title), [
            "iCloud Drive",
            "OneDrive",
            "wonsik",
            "Macintosh HD",
            "Trash",
        ])
        XCTAssertEqual(
            store.state.content.homeLocationItems.map(\.title),
            store.state.sidebar.fixedLocationItems.map(\.title),
        )
    }

    /// CTM-004-sidebar_fixed_locations: fixed Location tap은 현재 active tab을 해당 Location으로 전환함
    /// Locations grid는 새 탭 생성기가 아니라 현재 탭을 빠르게 이동시키는 shortcut임을 검증한다.
    func testFixedLocationTap_navigatesActiveTab() async throws {
        let homeID = ContentTabID()
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
        state.syncFixedLocationItems(with: Self.fixedLocationClient(), entryLoadingClient: .testValue)
        state.syncContentTabSidebarItems()
        let iCloudLocationID = try XCTUnwrap(state.sidebar.fixedLocationItems.first?.id)
        let locationAnchor = ContentTabPageAnchor
            .directory(path: "/Users/test/Library/Mobile Documents/com~apple~CloudDocs")
        let store = TestStore(initialState: state) {
            FileManagerFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
            $0.fileChangeGatewayClient.observeEvents = {
                AsyncStream { continuation in
                    continuation.finish()
                }
            }
        }
        store.exhaustivity = .off

        await store.send(.sidebar(.delegate(.selectFixedLocation(iCloudLocationID))))
        await store.receive(\.contentTabs)

        XCTAssertEqual(store.state.contentTabs.tabs.count, 1)
        XCTAssertEqual(store.state.contentTabs.activeTabID, homeID)
        XCTAssertEqual(store.state.contentTabs.tabs[id: homeID]?.anchor, locationAnchor)
        XCTAssertEqual(ContentTabProjection.activePageAnchor(from: store.state.contentTabs), locationAnchor)
    }

    /// CTM-004-home_dashboard_projection: 새 Home tab을 열어도 Home dashboard Favorites/Locations projection이 유지됨
    /// ContentTab handoff가 새 content state를 만들 때 Home dashboard data를 누락하지 않는지 검증한다.
    func testOpenNewHomeTab_keepsHomeDashboardFavoritesAndLocations() async {
        let pinnedID = ContentTabID()
        var state = FileManagerFeature.State()
        state.contentTabs = ContentTabState(
            tabs: [ContentTabItem(
                id: pinnedID,
                page: .directory,
                anchor: .directory(path: "/Users/test/Projects"),
                isPinned: true,
                title: "Projects",
                iconName: "folder",
            )],
            activeTabID: pinnedID,
            recentlyClosed: nil,
        )
        state.syncContentTabSidebarItems()
        state.syncFixedLocationItems(with: Self.fixedLocationClient(), entryLoadingClient: .testValue)
        state.syncHomeFavoriteItems()

        let store = TestStore(initialState: state) {
            FileManagerFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
            $0.fileManagerLocationsClient = Self.fixedLocationClient()
            $0.fileChangeGatewayClient.observeEvents = {
                AsyncStream { continuation in
                    continuation.finish()
                }
            }
        }
        store.exhaustivity = .off

        await store.send(.sidebar(.delegate(.openContentTab)))
        await store.receive(\.contentTabs)

        XCTAssertEqual(store.state.contentTabs.tabs.count, 2)
        XCTAssertEqual(store.state.contentTabs.tabs.last?.anchor, .homeDefault)
        XCTAssertEqual(store.state.content.homeFavoriteItems.map(\.title), ["Projects"])
        XCTAssertEqual(store.state.content.homeLocationItems.map(\.title), [
            "iCloud Drive",
            "OneDrive",
            "wonsik",
            "Macintosh HD",
            "Trash",
        ])
    }

    /// CTM-004-home_dashboard_projection: tab lifecycle은 fixed Locations를 재조회하지 않고 기존 projection만 전달함
    /// - 검증 내용: Home tab open 시 syncDashboardProjections가 fileManagerLocationsClient를 호출하지 않음
    /// - 사전 조건: onAppear에서 fixed Locations가 이미 동기화된 window state
    /// - 기대 결과: 새 Home tab에서도 기존 Locations 유지, locations client 호출 0회
    func testOpenNewHomeTab_doesNotReloadFixedLocations() async {
        let pinnedID = ContentTabID()
        let locationsLoadCount = LockIsolated(0)
        var state = FileManagerFeature.State()
        state.contentTabs = ContentTabState(
            tabs: [ContentTabItem(
                id: pinnedID,
                page: .directory,
                anchor: .directory(path: "/Users/test/Projects"),
                isPinned: true,
                title: "Projects",
                iconName: "folder",
            )],
            activeTabID: pinnedID,
            recentlyClosed: nil,
        )
        state.syncContentTabSidebarItems()
        state.syncFixedLocationItems(with: Self.fixedLocationClient(), entryLoadingClient: .testValue)
        state.syncHomeFavoriteItems()

        let store = TestStore(initialState: state) {
            FileManagerFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
            $0.fileManagerLocationsClient.loadLocations = { _ in
                locationsLoadCount.withValue { $0 += 1 }
                return []
            }
            $0.fileChangeGatewayClient.observeEvents = {
                AsyncStream { continuation in
                    continuation.finish()
                }
            }
        }
        store.exhaustivity = .off

        await store.send(.sidebar(.delegate(.openContentTab)))
        await store.receive(\.contentTabs)

        XCTAssertEqual(locationsLoadCount.value, 0, "tab lifecycle에서는 fixed Locations를 재조회하지 않아야 함")
        XCTAssertEqual(store.state.content.homeLocationItems.map(\.title), [
            "iCloud Drive",
            "OneDrive",
            "wonsik",
            "Macintosh HD",
            "Trash",
        ])
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
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
            $0.fileChangeGatewayClient.observeEvents = {
                AsyncStream { continuation in
                    continuation.finish()
                }
            }
        }
        store.exhaustivity = .off

        await store.send(.sidebar(.delegate(.selectContentTab(directoryID))))
        await store.receive(\.contentTabs)

        XCTAssertEqual(store.state.contentTabs.activeTabID, directoryID, "active tab must switch to Directory")
        XCTAssertEqual(store.state.content.navigation.currentPath, directoryPath)
        XCTAssertEqual(store.state.tabContentStates[homeID]?.navigation.currentPath, homeSessionPath)

        await store.send(.sidebar(.delegate(.selectContentTab(homeID))))
        await store.receive(\.contentTabs)

        XCTAssertEqual(store.state.contentTabs.activeTabID, homeID, "active tab must switch back to Home")
        XCTAssertEqual(ContentTabProjection.activePageAnchor(from: store.state.contentTabs), .homeDefault)
        XCTAssertEqual(store.state.content.navigation.currentPath, homeSessionPath)
        XCTAssertEqual(store.state.tabContentStates[directoryID]?.navigation.currentPath, directoryPath)
    }

    /// CTM-004-sidebar_projection_content_tabs: Composer overlay는 Sidebar 섹션 제거 후에도 기본 scope favorites를 유지함
    /// Favorites 섹션 state 삭제가 Composer scope picker의 Desktop/Documents/Downloads shortcut을 제거하지 않음을 검증한다.
    func testContentOverlayProps_restoreDefaultComposerFavorites() {
        let state = FileManagerFeature.State()
        let client = FileManagerClient(
            contentsOfDirectory: { _, _, _ in [] },
            createDirectory: { _, _, _ in },
            mountedVolumeURLs: { _, _ in nil },
            urlsForDirectory: { directory, domain in
                switch (directory, domain) {
                case (.applicationDirectory, .localDomainMask):
                    [URL(fileURLWithPath: "/Applications")]
                case (.desktopDirectory, .userDomainMask):
                    [URL(fileURLWithPath: "/Users/test/Desktop")]
                case (.documentDirectory, .userDomainMask):
                    [URL(fileURLWithPath: "/Users/test/Documents")]
                case (.downloadsDirectory, .userDomainMask):
                    [URL(fileURLWithPath: "/Users/test/Downloads")]
                default:
                    []
                }
            },
            copyItem: { _, _ in },
            moveItem: { _, _ in },
            removeItem: { _ in },
            trashItem: { _ in URL(fileURLWithPath: "/tmp/.Trash/test") },
            fileExists: { _ in false },
            fileExistsWithIsDirectory: { _, _ in false },
            attributesOfItem: { _ in [:] },
            displayName: { URL(fileURLWithPath: $0).lastPathComponent },
            temporaryDirectory: { URL(fileURLWithPath: "/tmp") },
            currentDirectoryPath: { "/" },
        )

        let overlayProps = FileManagerContentChromePropsBuilder.makeContentOverlayProps(
            from: state,
            fileManagerClient: client,
        )

        XCTAssertEqual(overlayProps.favorites.map(\.name), [
            "Applications",
            "Desktop",
            "Documents",
            "Downloads",
        ])
        XCTAssertEqual(overlayProps.favorites.map(\.url.path), [
            "/Applications",
            "/Users/test/Desktop",
            "/Users/test/Documents",
            "/Users/test/Downloads",
        ])
        XCTAssertEqual(overlayProps.favorites.map(\.iconName), [
            "folder.badge.gearshape",
            "menubar.dock.rectangle",
            "doc",
            "arrow.down.circle",
        ])
    }

    func testSidebarProjection_ignoresBackgroundAiChatStates() {
        let homeID = ContentTabID()
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

        let bgSessionID = AiChatSessionID(rawValue: UUID())
        state.backgroundAiChatStates[bgSessionID] = FileManagerContentFeature.State()

        state.syncContentTabSidebarItems()

        XCTAssertEqual(state.sidebar.contentTabSidebarItems.count, 1)
        XCTAssertEqual(state.sidebar.contentTabSidebarItems[0].id, homeID)
        XCTAssertEqual(state.sidebar.contentTabSidebarItems[0].pageType, .home)
    }

    private static func fixedLocationClient() -> FileManagerLocationsClient {
        FileManagerLocationsClient { _ in
            [
                SidebarItems.LocationItem(
                    name: "iCloud Drive",
                    url: URL(fileURLWithPath: "/Users/test/Library/Mobile Documents/com~apple~CloudDocs"),
                    iconName: "icloud",
                ),
                SidebarItems.LocationItem(
                    name: "OneDrive",
                    url: URL(fileURLWithPath: "/Users/test/Library/CloudStorage/OneDrive"),
                    iconName: "folder",
                ),
                SidebarItems.LocationItem(
                    name: "wonsik",
                    url: URL(fileURLWithPath: "/Users/test"),
                    iconName: "house",
                ),
                SidebarItems.LocationItem(
                    name: "Macintosh HD",
                    url: URL(fileURLWithPath: "/"),
                    iconName: "internaldrive",
                ),
                SidebarItems.LocationItem(
                    name: "Trash",
                    url: URL(fileURLWithPath: "/Users/test/.Trash"),
                    iconName: "trash",
                ),
            ]
        }
    }
}
