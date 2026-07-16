import AppKit
import ComposableArchitecture
import Foundation
import UniformTypeIdentifiers
import VoyagerEntitiesAi
import VoyagerEntitiesAppPreferences
import VoyagerEntitiesEntry
import VoyagerFeaturesEntryOperations
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

    /// CTM-004-sidebar_fixed_locations: window appearance마다 Locations를 effect에서 한 번만 조회함
    /// 같은 appearance의 중복 onAppear는 무시하고, onDisappear 이후 다시 나타날 때만 새 조회를 허용한다.
    func testWindowAppearanceLoadsFixedLocationsOnceUntilDisappear() async {
        let requestID = UUID()
        let loadCount = LockIsolated(0)
        let sourceLocations = Self.fixedLocationClient().loadLocations(.testValue)
        let projectedLocations = FileManagerHomeDashboardProjection.makeFixedLocations(from: sourceLocations)
        let store = TestStore(initialState: FileManagerFeature.State()) {
            FileManagerFeature()
        } withDependencies: {
            $0.uuid = .constant(requestID)
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
            $0.fileChangeGatewayClient.observeEvents = {
                AsyncStream { continuation in continuation.finish() }
            }
            $0.fileManagerLocationsClient.loadLocations = { _ in
                loadCount.withValue { $0 += 1 }
                return sourceLocations
            }
        }
        store.exhaustivity = .off

        await store.send(.onAppear) {
            $0.fixedLocationsLoadPhase = .loading(requestID)
        }
        await store.receive(\.internal.fixedLocationsLoaded) {
            $0.fixedLocationsLoadPhase = .loaded
            $0.applyFixedLocationItems(projectedLocations)
        }

        await store.send(.onAppear)
        XCTAssertEqual(loadCount.value, 1)

        await store.send(.onDisappear) {
            $0.fixedLocationsLoadPhase = .idle
        }
        await store.send(.onAppear) {
            $0.fixedLocationsLoadPhase = .loading(requestID)
        }
        await store.receive(\.internal.fixedLocationsLoaded) {
            $0.fixedLocationsLoadPhase = .loaded
        }

        XCTAssertEqual(loadCount.value, 2)
    }

    /// CTM-004-sidebar_fixed_locations_visibility: 새 window appearance는 저장된 숨김 설정을 복원함
    /// Locations 조회 완료 전 preference를 state에 적용하고 완료 시에도 동일한 설정을 유지한다.
    func testWindowAppearanceRestoresPersistedHiddenLocationIDs() async throws {
        let requestID = UUID()
        let sourceLocations = Self.fixedLocationClient().loadLocations(.testValue)
        let projectedLocations = FileManagerHomeDashboardProjection.makeFixedLocations(from: sourceLocations)
        let oneDriveID = try XCTUnwrap(projectedLocations.first { $0.title == "OneDrive" }?.id)
        let store = TestStore(initialState: FileManagerFeature.State()) {
            FileManagerFeature()
        } withDependencies: {
            $0.uuid = .constant(requestID)
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
            $0.fileChangeGatewayClient.observeEvents = {
                AsyncStream { continuation in continuation.finish() }
            }
            $0.fileManagerLocationsClient.loadLocations = { _ in sourceLocations }
            $0.userDefaultsClient.object = { key in
                key == SettingsKeys.hiddenFixedLocationIDs ? [oneDriveID] : nil
            }
        }
        store.exhaustivity = .off

        await store.send(.onAppear) {
            $0.sidebar.hiddenFixedLocationItemIDs = [oneDriveID]
            $0.fixedLocationsLoadPhase = .loading(requestID)
        }
        await store.receive(\.internal.fixedLocationsLoaded) {
            $0.fixedLocationsLoadPhase = .loaded
            $0.applyFixedLocationItems(projectedLocations, hiddenLocationIDs: [oneDriveID])
        }

        XCTAssertFalse(store.state.sidebar.fixedLocationItems.contains { $0.id == oneDriveID })
        XCTAssertTrue(store.state.content.homeLocationItems.contains { $0.id == oneDriveID })
    }

    /// CTM-004-sidebar_fixed_locations_visibility: 진행 중인 Locations 조회는 최신 visibility를 유지함
    /// 조회 시작 후 숨김 설정이 바뀌어도 완료 payload가 해당 설정을 되돌리지 않아야 한다.
    func testFixedLocationsCompletionPreservesVisibilityChangedWhileLoading() async throws {
        let requestID = UUID()
        let sourceLocations = Self.fixedLocationClient().loadLocations(.testValue)
        let projectedLocations = FileManagerHomeDashboardProjection.makeFixedLocations(from: sourceLocations)
        let oneDriveID = try XCTUnwrap(projectedLocations.first { $0.title == "OneDrive" }?.id)
        var state = FileManagerFeature.State()
        state.fixedLocationsLoadPhase = .loading(requestID)
        state.sidebar.hiddenFixedLocationItemIDs = [oneDriveID]

        let store = TestStore(initialState: state) {
            FileManagerFeature()
        }
        store.exhaustivity = .off

        await store.send(.internal(.fixedLocationsLoaded(
            requestID: requestID,
            items: projectedLocations,
        ))) {
            $0.fixedLocationsLoadPhase = .loaded
            $0.applyFixedLocationItems(projectedLocations, hiddenLocationIDs: [oneDriveID])
        }

        XCTAssertFalse(store.state.sidebar.fixedLocationItems.contains { $0.id == oneDriveID })
        XCTAssertTrue(store.state.content.homeLocationItems.contains { $0.id == oneDriveID })
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
        XCTAssertEqual(state.sidebar.fixedLocationItems.map(\.kind), [
            .directory,
            .directory,
            .directory,
            .directory,
            .trash,
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

    /// VOY-566: Window appearance는 Finder Favorites를 Home shortcut source로 독립 로드함
    func testWindowAppearanceLoadsHomeFavoritesIndependentlyFromPinnedTabs() async {
        let requestID = UUID()
        let favoriteURL = URL(fileURLWithPath: "/Users/test/Projects")
        let favorite = SidebarItems.FavoriteItem(
            name: "Projects",
            url: favoriteURL,
            iconName: "folder",
        )
        let expectedFavorites = FileManagerHomeDashboardProjection.homeFavorites(
            from: [favorite],
            fileExistsWithIsDirectory: { _, isDirectory in
                isDirectory?.pointee = true
                return true
            },
        )
        let store = TestStore(initialState: FileManagerFeature.State()) {
            FileManagerFeature()
        } withDependencies: {
            $0.uuid = .constant(requestID)
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
            $0.fileManagerFavoritesClient.loadFavorites = { _, _ in [favorite] }
            $0.entryLoadingClient.fileExistsAtPath = { path, isDirectory in
                guard path == favoriteURL.path else { return false }
                isDirectory?.pointee = true
                return true
            }
            $0.fileManagerLocationsClient.loadLocations = { _ in [] }
            $0.fileChangeGatewayClient.observeEvents = { AsyncStream { $0.finish() } }
        }
        store.exhaustivity = .off

        await store.send(.onAppear) {
            $0.fixedLocationsLoadPhase = .loading(requestID)
        }
        await store.receive(\.internal.homeFavoritesLoaded) {
            $0.applyHomeFavoriteItems(expectedFavorites)
        }

        XCTAssertEqual(store.state.content.homeFavoriteItems.map(\.title), ["Projects"])
        XCTAssertTrue(store.state.contentTabs.tabs.filter(\.isPinned).isEmpty)
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
        state.applyHomeFavoriteItems([
            FileManagerHomeFavoriteItem(
                id: ContentTabID(rawValue: "finder-projects"),
                title: "Projects",
                iconName: "folder",
                filePath: "/Users/test/Projects",
                anchor: .directory(path: "/Users/test/Projects"),
                page: .directory,
            ),
        ])

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

    // MARK: - CTM-004-sidebar_entry_drop_routing

    /// CTM-004-sidebar_entry_drop_routing: visible Fixed Location은 현재 visible item의 path로 한 번만 전달됨
    func testEntryDrop_visibleFixedLocationForwardsExactlyOnce() async {
        let location = FileManagerFixedLocationItem(
            id: "desktop",
            title: "Desktop",
            path: "/Users/test/Desktop/latest",
            iconName: "folder",
            accessibilityLabel: "Desktop",
        )
        var state = FileManagerFeature.State()
        state.sidebar.setFixedLocationItems([location])
        state.content.entryViewLayout.selectedIds = ["selected-entry"]
        let providers = [NSItemProvider(), NSItemProvider()]

        await assertEntryDropForwarded(
            target: .fixedLocation(location.id),
            providers: providers,
            isOptionDrag: false,
            destinationPath: location.path,
            initialState: state,
        )
    }

    /// CTM-004-sidebar_entry_drop_routing: visible Fixed Location의 Option-drop은 copy intent를 그대로 전달함
    /// 사용자가 보이는 Fixed Location에 Option 키를 누른 채 드롭하는 경로를 검증한다.
    /// - 검증 내용: `handleDrop` exactly-once, destination snapshot과 perform-time Option intent, Window 직접 routing 부재
    /// - 사전 조건: visible Fixed Location과 선택 상태가 있는 Window, 동일 identity의 provider 두 개
    /// - 기대 결과: `isOptionDrag == true`인 `handleDrop` 한 개만 방출되고 전체 tab/session state가 보존됨
    func testEntryDrop_visibleFixedLocationOptionCopyPreservesIntent() async {
        let location = FileManagerFixedLocationItem(
            id: "desktop-copy",
            title: "Desktop",
            path: "/Users/test/Desktop/copy-target",
            iconName: "folder",
            accessibilityLabel: "Desktop",
        )
        var state = FileManagerFeature.State()
        state.sidebar.setFixedLocationItems([location])
        state.content.entryViewLayout.selectedIds = ["selected-entry"]
        let providers = [NSItemProvider(), NSItemProvider()]

        await assertEntryDropForwarded(
            target: .fixedLocation(location.id),
            providers: providers,
            isOptionDrag: true,
            destinationPath: location.path,
            initialState: state,
        )
    }

    /// CTM-004-sidebar_entry_drop_routing: Trash Fixed Location은 Option 여부와 무관하게 전용 Trash route를 사용함
    /// Window가 typed location kind만 판별하고 provider decode나 generic move를 수행하지 않는 경계를 검증한다.
    /// - 검증 내용: `handleDropToTrash` exactly-once, generic `handleDrop` action 부재
    /// - 사전 조건: `.trash` kind의 visible Fixed Location과 동일 identity의 provider 두 개, Option drag
    /// - 기대 결과: provider identity/order를 보존한 Trash route 하나만 방출되고 Window state는 불변
    func testEntryDrop_trashFixedLocationRoutesOnlyToTrashOperations() async {
        let location = FileManagerFixedLocationItem(
            id: "canonical-trash",
            title: "Renamed Location",
            path: "/typed/location",
            iconName: "folder",
            accessibilityLabel: "Typed Location",
            kind: .trash,
        )
        var state = FileManagerFeature.State()
        state.sidebar.setFixedLocationItems([location])
        let providers = [NSItemProvider(), NSItemProvider()]
        let request = FileManagerSidebarEntryDropRequest(
            target: .fixedLocation(location.id),
            providers: providers,
            isOptionDrag: true,
        )
        let store = TestStore(initialState: state) {
            FileManagerWindowCommandRoutingReducer()
        }
        let expectedRoute = AnyCasePath<FileManagerFeature.Action, Void>(
            embed: { _ in
                .internal(.sidebarEntryDrop(.routing(.handleDropToTrash(providers: providers))))
            },
            extract: { action in
                guard case let .internal(.sidebarEntryDrop(.routing(.handleDropToTrash(receivedProviders)))) = action
                else { return nil }
                XCTAssertEqual(receivedProviders.count, providers.count)
                XCTAssertTrue(zip(receivedProviders, providers).allSatisfy { $0 === $1 })
                return ()
            },
        )

        await store.send(.sidebar(.delegate(.entryDropRequested(request))))
        await store.receive(expectedRoute)
        XCTAssertEqual(store.state, state)
        await store.finish()
    }

    /// CTM-004-sidebar_entry_drop_routing: NSURL-backed fileURL provider가 실제 move chain을 완료함
    /// production drag writer와 같은 NSURL payload가 Sidebar view에서 Window-owned EOP 경로로 전달되는지 검증한다.
    /// - 검증 내용: provider decode, direct Window shortcut 없는 단일 move, tab identity와 selection 보존
    /// - 사전 조건: `fixtures/fixtures/texts/plain/11.txt` temp copy와 isolated destination, public.file-url NSURL provider
    /// - 기대 결과: source는 사라지고 destination에 존재하며 mutation은 정확히 1회, active tab은 바뀌지 않음
    func testEntryDrop_productionNSURLProviderMovesThroughFullChain() async throws {
        let fixture = try makeTabSwitchDropFixture()
        defer { fixture.sandbox.cleanup() }
        let sourceURL = fixture.sandbox.fileURL
        let destinationURL = URL(fileURLWithPath: fixture.location.path)
            .appendingPathComponent(sourceURL.lastPathComponent)
        let provider = NSItemProvider(
            item: sourceURL as NSURL,
            typeIdentifier: UTType.fileURL.identifier,
        )
        let mutations = LockIsolated<[(source: URL, destination: URL)]>([])
        let reloads = LockIsolated<[[String]]>([])
        let initialTabs = fixture.state.contentTabs
        let initialSelection = fixture.state.content.entryViewLayout.selectedIds
        let store = makeTabSwitchDropStore(
            state: fixture.state,
            mutations: mutations,
            reloads: reloads,
        )
        // store.exhaustivity = .off: Sidebar→Window-owned EOP 비동기 chain은 최종 filesystem과 tab 불변식으로 검증한다.
        store.exhaustivity = .off

        await store.send(.sidebar(.view(.entryDropRequested(.init(
            target: .fixedLocation(fixture.location.id),
            providers: [provider],
            isOptionDrag: false,
        )))))
        await store.finish()
        await store.skipReceivedActions()

        XCTAssertEqual(mutations.value.count, 1)
        XCTAssertEqual(mutations.value.first?.source, sourceURL)
        XCTAssertEqual(mutations.value.first?.destination, destinationURL)
        XCTAssertFalse(FileManager.default.fileExists(atPath: sourceURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: destinationURL.path))
        XCTAssertEqual(store.state.contentTabs, initialTabs)
        XCTAssertEqual(store.state.contentTabs.activeTabID, fixture.sourceID)
        XCTAssertEqual(store.state.content.entryViewLayout.selectedIds, initialSelection)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.sandbox.originalFixture.path))
    }

    /// CTM-004-sidebar_entry_drop_routing: active Directory tab은 stale anchor/cache보다 live content path를 우선함
    func testEntryDrop_activeDirectoryUsesLiveContentPath() async {
        let activeID = ContentTabID(rawValue: "active")
        var state = makeEntryDropState(activeID: activeID)
        state.contentTabs.tabs[id: activeID]?.anchor = .directory(path: "/anchor")
        state.content.navigation.seedInitialFolderPath("/active/latest")
        var staleCachedContent = FileManagerContentFeature.State()
        staleCachedContent.navigation.seedInitialFolderPath("/cached/stale")
        state.tabContentStates[activeID] = staleCachedContent
        let providers = [NSItemProvider()]

        await assertEntryDropForwarded(
            target: .contentTab(activeID),
            providers: providers,
            isOptionDrag: true,
            destinationPath: "/active/latest",
            initialState: state,
        )
    }

    /// CTM-004-sidebar_entry_drop_routing: inactive pinned Directory tab은 anchor보다 session의 최신 folder path를 우선함
    func testEntryDrop_inactiveDirectoryUsesSessionPathWithoutActivating() async {
        let activeID = ContentTabID(rawValue: "active")
        let inactiveID = ContentTabID(rawValue: "inactive")
        var state = makeEntryDropState(activeID: activeID, inactiveID: inactiveID)
        state.contentTabs.previousActiveTabID = inactiveID
        state.contentTabs.recentlyClosed = ClosedContentTabSnapshot(
            page: .directory,
            anchor: .directory(path: "/recently-closed"),
            wasPinned: false,
            closedAt: Date(timeIntervalSince1970: 1_234_567_890),
            title: "Recently Closed",
            iconName: "folder",
        )
        state.content.entryViewLayout.selectedIds = ["selected-entry"]
        var inactiveContent = FileManagerContentFeature.State()
        inactiveContent.navigation.seedInitialFolderPath("/inactive/latest")
        state.tabContentStates[inactiveID] = inactiveContent
        let providers = [NSItemProvider()]

        await assertEntryDropForwarded(
            target: .contentTab(inactiveID),
            providers: providers,
            isOptionDrag: true,
            destinationPath: "/inactive/latest",
            initialState: state,
        )
    }

    /// CTM-004-sidebar_entry_drop_routing: inactive unpinned Directory도 활성화 없이 최신 session path를 사용함
    /// 사용자가 unpinned inactive Directory 행에 Entry를 드롭하는 경로를 검증한다.
    /// - 검증 내용: unpinned identity의 최신 currentPath와 `handleDrop` exactly-once, select/dropItems action 부재
    /// - 사전 조건: active Directory와 최신 session path를 가진 inactive unpinned Directory
    /// - 기대 결과: inactive tab은 활성화되지 않고 최신 destination으로 한 번만 전달되며 전체 tab/session state가 보존됨
    func testEntryDrop_inactiveUnpinnedDirectoryUsesSessionPathWithoutActivating() async {
        let activeID = ContentTabID(rawValue: "active")
        let inactiveID = ContentTabID(rawValue: "inactive-unpinned")
        var state = makeEntryDropState(
            activeID: activeID,
            inactiveID: inactiveID,
            inactiveIsPinned: false,
        )
        var inactiveContent = FileManagerContentFeature.State()
        inactiveContent.navigation.seedInitialFolderPath("/inactive/unpinned/latest")
        state.tabContentStates[inactiveID] = inactiveContent

        await assertEntryDropForwarded(
            target: .contentTab(inactiveID),
            providers: [NSItemProvider()],
            isOptionDrag: false,
            destinationPath: "/inactive/unpinned/latest",
            initialState: state,
        )
    }

    /// CTM-004-sidebar_entry_drop_routing: inactive session이 없을 때만 Directory anchor를 fallback으로 사용함
    func testEntryDrop_inactiveDirectoryWithoutSessionUsesAnchorFallback() async {
        let activeID = ContentTabID(rawValue: "active")
        let inactiveID = ContentTabID(rawValue: "inactive")
        var state = makeEntryDropState(activeID: activeID, inactiveID: inactiveID)
        state.tabContentStates[inactiveID] = nil
        let providers = [NSItemProvider()]

        await assertEntryDropForwarded(
            target: .contentTab(inactiveID),
            providers: providers,
            isOptionDrag: false,
            destinationPath: "/inactive/anchor",
            initialState: state,
        )
    }

    /// CTM-004-sidebar_entry_drop_routing: hidden 또는 missing Fixed Location은 EOP action을 만들지 않음
    func testEntryDrop_hiddenAndMissingFixedLocationsAreRejected() async {
        let hiddenLocation = FileManagerFixedLocationItem(
            id: "hidden",
            title: "Hidden",
            path: "/hidden",
            iconName: "folder",
            accessibilityLabel: "Hidden",
        )
        var hiddenState = FileManagerFeature.State()
        hiddenState.sidebar.setFixedLocationItems([hiddenLocation], hiddenIDs: [hiddenLocation.id])

        await assertEntryDropRejected(
            target: .fixedLocation(hiddenLocation.id),
            initialState: hiddenState,
        )
        await assertEntryDropRejected(
            target: .fixedLocation("missing"),
            initialState: FileManagerFeature.State(),
        )
    }

    /// CTM-004-sidebar_entry_drop_routing: missing/non-directory tab과 non-folder session은 EOP action을 만들지 않음
    func testEntryDrop_invalidContentTabTargetsAreRejected() async {
        let activeID = ContentTabID(rawValue: "active")
        let inactiveID = ContentTabID(rawValue: "inactive")
        let missingID = ContentTabID(rawValue: "missing")

        await assertEntryDropRejected(
            target: .contentTab(missingID),
            initialState: makeEntryDropState(activeID: activeID),
        )

        let invalidTabs: [(ContentTabPage, ContentTabPageAnchor)] = [
            (.home, .homeDefault),
            (.collection, .collectionFile(url: URL(fileURLWithPath: "/collection.voycoll"))),
            (.collection, .virtualCollection(id: "virtual")),
            (.aiChat, .aiChat(sessionID: UUID().uuidString)),
        ]
        for (index, invalidTab) in invalidTabs.enumerated() {
            let invalidID = ContentTabID(rawValue: "invalid-\(index)")
            var state = makeEntryDropState(activeID: activeID)
            state.contentTabs.tabs.append(ContentTabItem(
                id: invalidID,
                page: invalidTab.0,
                anchor: invalidTab.1,
                isPinned: false,
                title: nil,
                iconName: nil,
            ))
            await assertEntryDropRejected(target: .contentTab(invalidID), initialState: state)
        }

        var activeNonFolderState = makeEntryDropState(activeID: activeID)
        activeNonFolderState.content.navigation.navigationState = .home
        await assertEntryDropRejected(
            target: .contentTab(activeID),
            initialState: activeNonFolderState,
        )

        var inactiveNonFolderState = makeEntryDropState(activeID: activeID, inactiveID: inactiveID)
        var inactiveContent = FileManagerContentFeature.State()
        inactiveContent.navigation.navigationState = .home
        inactiveNonFolderState.tabContentStates[inactiveID] = inactiveContent
        await assertEntryDropRejected(
            target: .contentTab(inactiveID),
            initialState: inactiveNonFolderState,
        )

        var malformedAnchorState = makeEntryDropState(activeID: activeID, inactiveID: inactiveID)
        malformedAnchorState.tabContentStates[inactiveID] = nil
        malformedAnchorState.contentTabs.tabs[id: inactiveID]?.anchor = .homeDefault
        await assertEntryDropRejected(
            target: .contentTab(inactiveID),
            initialState: malformedAnchorState,
        )
    }

    /// CTM-004-sidebar_entry_drop_routing: Window lifecycle은 dedicated EOP에 동일하게 전달됨
    /// - 검증 내용: windowIDChanged와 resetForDuplicate가 dedicated state만 갱신·초기화함
    /// - 사전 조건: dedicated/content EOP가 서로 다른 history와 Window identity를 가진 상태
    /// - 기대 결과: duplicate reset 후 dedicated history만 비워지고 active content EOP는 보존됨
    func testSidebarEntryDropOperations_mirrorsWindowLifecycle() async {
        let contentWindowID = UUID()
        let firstWindowID = UUID()
        let duplicateWindowID = UUID()
        let expectedUndoOwnerID = UUID()
        let record = EntryActionRecord(
            operationKind: .pasteFileMove,
            targets: [.init(beforePath: "/source/item", afterPath: "/destination/item")],
        )
        var state = FileManagerFeature.State()
        state.content.entryViewLayout.entryOperations.windowID = contentWindowID
        state.content.entryViewLayout.entryOperations.undoRecords = [record]
        state.sidebarEntryDropOperations.undoRecords = [record]
        let contentEntryOperations = state.content.entryViewLayout.entryOperations
        let store = TestStore(initialState: state) {
            FileManagerFeature()
        } withDependencies: {
            $0.uuid = .constant(expectedUndoOwnerID)
        }

        await store.send(.internal(.sidebarEntryDrop(.lifecycle(.windowIDChanged(firstWindowID))))) {
            $0.sidebarEntryDropOperations.windowID = firstWindowID
        }
        await store.send(.internal(.sidebarEntryDrop(.lifecycle(.resetForDuplicate(windowID: duplicateWindowID))))) {
            $0.sidebarEntryDropOperations.resetForDuplicate(
                windowID: duplicateWindowID,
                undoOwnerID: expectedUndoOwnerID,
            )
        }

        XCTAssertEqual(store.state.sidebarEntryDropOperations.undoOwnerID, expectedUndoOwnerID)
        XCTAssertEqual(store.state.content.entryViewLayout.entryOperations, contentEntryOperations)
        await store.finish()
    }

    /// CTM-004-sidebar_entry_drop_routing: Window undo/redo가 root availability와 shared client만 사용함
    /// - 검증 내용: child local stack 선택 없이 Window ID로 shared undo/redo를 직접 호출함
    /// - 사전 조건: root canUndo/canRedo true, content/dedicated child history 모두 존재함
    /// - 기대 결과: root availability 갱신, shared client 각 1회 호출, child history 불변
    func testWindowUndoRedo_usesRootAvailabilityAndSharedClientOnly() async throws {
        let windowID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000569"))
        let record = EntryActionRecord(
            operationKind: .pasteFileMove,
            targets: [.init(beforePath: "/source/item", afterPath: "/destination/item")],
        )
        var state = FileManagerFeature.State()
        state.windowID = windowID
        state.sidebarEntryDropOperations.undoRecords = [record]
        state.sidebarEntryDropOperations.redoRecords = [record]
        state.content.entryViewLayout.entryOperations.undoRecords = [record]
        state.content.entryViewLayout.entryOperations.redoRecords = [record]
        let undoTarget = UndoManagerRecordIdentity(
            ownerID: state.sidebarEntryDropOperations.undoOwnerID,
            recordID: record.id,
        )
        let redoTarget = UndoManagerRecordIdentity(
            ownerID: state.content.entryViewLayout.entryOperations.undoOwnerID,
            recordID: record.id,
        )
        state.undoManagerAvailability = .init(
            canUndo: true,
            canRedo: true,
            undoTarget: undoTarget,
            redoTarget: redoTarget,
        )
        let initialContentOperations = state.content.entryViewLayout.entryOperations
        let initialSidebarOperations = state.sidebarEntryDropOperations
        XCTAssertTrue(state.menuCommandProjection.canUndo)
        XCTAssertTrue(state.menuCommandProjection.canRedo)

        let calls = LockIsolated<[String]>([])
        let initialAvailability = state.undoManagerAvailability
        let availability = LockIsolated(initialAvailability)
        let client = UndoManagerClient(
            registerUndo: { _, _, _ in },
            undo: { receivedWindowID, receivedTarget in
                XCTAssertEqual(receivedWindowID, windowID)
                XCTAssertEqual(receivedTarget, undoTarget)
                calls.withValue { $0.append("undo") }
                availability.setValue(.init(
                    canUndo: false,
                    canRedo: true,
                    redoTarget: redoTarget,
                ))
                return .init(didInvoke: false, availability: availability.value)
            },
            redo: { receivedWindowID, receivedTarget in
                XCTAssertEqual(receivedWindowID, windowID)
                XCTAssertEqual(receivedTarget, redoTarget)
                calls.withValue { $0.append("redo") }
                availability.setValue(.init(
                    canUndo: true,
                    canRedo: false,
                    undoTarget: undoTarget,
                ))
                return .init(didInvoke: false, availability: availability.value)
            },
            availability: { _ in availability.value },
        )
        let requestID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000571"))
        let store = TestStore(initialState: state) {
            FileManagerWindowCommandRoutingReducer()
        } withDependencies: {
            $0.undoManagerClient = client
            $0.uuid = .constant(requestID)
        }

        await store.send(.request(.requestUndo)) {
            $0.undoRedoPhase = .invoking(requestID: requestID, direction: .undo)
        }
        await store.receive(\.internal.undoManagerInvocationFinished) {
            $0.undoManagerAvailability = .init(
                canUndo: false,
                canRedo: true,
                redoTarget: redoTarget,
            )
            $0.undoRedoPhase = .idle
        }
        await store.send(.request(.requestRedo)) {
            $0.undoRedoPhase = .invoking(requestID: requestID, direction: .redo)
        }
        await store.receive(\.internal.undoManagerInvocationFinished) {
            $0.undoManagerAvailability = .init(
                canUndo: true,
                canRedo: false,
                undoTarget: undoTarget,
            )
            $0.undoRedoPhase = .idle
        }

        XCTAssertEqual(calls.value, ["undo", "redo"])
        XCTAssertEqual(store.state.content.entryViewLayout.entryOperations, initialContentOperations)
        XCTAssertEqual(store.state.sidebarEntryDropOperations, initialSidebarOperations)
        XCTAssertTrue(store.state.menuCommandProjection.canUndo)
        XCTAssertFalse(store.state.menuCommandProjection.canRedo)
        await store.finish()
    }

    /// CTM-004-sidebar_entry_drop_routing: 두 EntryOperations owner availability outcome이 같은 root를 갱신함
    /// - 검증 내용: content와 dedicated outcome 모두 root availability의 단일 projection으로 수렴함
    /// - 사전 조건: 초기 root availability false/false
    /// - 기대 결과: 마지막 shared-manager snapshot이 메뉴 canUndo/canRedo를 결정함
    func testUndoManagerAvailabilityOutcomes_syncSingleWindowRoot() async {
        let record = EntryActionRecord(
            operationKind: .rename,
            targets: [.init(beforePath: "/availability/old", afterPath: "/availability/new")],
        )
        var state = FileManagerFeature.State()
        state.content.entryViewLayout.entryOperations.undoRecords = [record]
        state.sidebarEntryDropOperations.redoRecords = [record]
        state.syncActiveTabContentState()
        let contentTarget = UndoManagerRecordIdentity(
            ownerID: state.content.entryViewLayout.entryOperations.undoOwnerID,
            recordID: record.id,
        )
        let sidebarTarget = UndoManagerRecordIdentity(
            ownerID: state.sidebarEntryDropOperations.undoOwnerID,
            recordID: record.id,
        )
        let store = TestStore(initialState: state) {
            FileManagerWindowRoutingReducer()
        }

        await store.send(.content(.entryViewLayout(.entryOperations(.outcome(
            .undoManagerAvailabilityChanged(.init(
                canUndo: true,
                canRedo: false,
                undoTarget: contentTarget,
            )),
        ))))) {
            $0.undoManagerAvailability = .init(
                canUndo: true,
                canRedo: false,
                undoTarget: contentTarget,
            )
        }
        XCTAssertTrue(store.state.menuCommandProjection.canUndo)

        await store.send(.internal(.sidebarEntryDrop(.outcome(
            .undoManagerAvailabilityChanged(.init(
                canUndo: false,
                canRedo: true,
                redoTarget: sidebarTarget,
            )),
        )))) {
            $0.undoManagerAvailability = .init(
                canUndo: false,
                canRedo: true,
                redoTarget: sidebarTarget,
            )
        }

        XCTAssertFalse(store.state.menuCommandProjection.canUndo)
        XCTAssertTrue(store.state.menuCommandProjection.canRedo)
        await store.finish()
    }

    // MARK: - CTM-004-directory_reload_lifecycle

    /// CTM-004-directory_reload_lifecycle: mutation success가 active는 한 번 reload하고 inactive는 pending 처리함
    /// aggregate outcome 전 per-item completion이 reload하지 않고 success 시점의 현재 session만 평가하는지 검증한다.
    /// - 검증 내용: source/destination active exactly-once reload, inactive pending, unrelated tab 불변
    /// - 사전 조건: active source와 destination/source/unrelated inactive Directory session
    /// - 기대 결과: reload action 1회, affected inactive ID 2개 pending, tab/session/selection 불변
    func testEntriesMutated_refreshesActiveOnceAndMarksAffectedInactiveTabs() async {
        let activeID = ContentTabID(rawValue: "active")
        let destinationID = ContentTabID(rawValue: "destination")
        let sourceID = ContentTabID(rawValue: "source")
        let unrelatedID = ContentTabID(rawValue: "unrelated")
        var state = makeDirectoryReloadState(
            activeID: activeID,
            activePath: "/source",
            inactiveTabs: [
                .init(id: destinationID, path: "/destination", isPinned: true),
                .init(id: sourceID, path: "/source", isPinned: false),
                .init(id: unrelatedID, path: "/unrelated", isPinned: false),
            ],
        )
        state.content.entryViewLayout.selectedIds = ["selected-entry"]
        let initialTabs = state.contentTabs
        let initialInactiveStates = state.tabContentStates
        let impact = EntryOperationsMutationImpact(
            sourceParentPaths: ["/source", "/source"],
            destinationPath: "/destination",
        )
        var contentState = FileManagerContentFeature.State()
        contentState.navigation.seedInitialFolderPath("/source")
        let completionStore = TestStore(initialState: contentState) {
            FileManagerContentEntryOperationsBridgeReducer()
        }
        await completionStore.send(dropCompletion(path: "/source/item-a"))
        await completionStore.send(dropCompletion(path: "/source/item-b"))
        await completionStore.finish()

        let store = TestStore(initialState: state) {
            Reduce<FileManagerFeature.State, FileManagerFeature.Action> { state, action in
                guard case let .content(.entryViewLayout(.entryOperations(.outcome(.entriesMutated(impact))))) = action
                else { return .none }
                return handleEntriesMutated(impact, state: &state)
            }
        }

        await store.send(entryMutationOutcome(impact)) {
            $0.pendingDirectoryReloadTabIDs = [destinationID, sourceID]
        }
        let reloadAction = routedDirectoryReloadAction(tabID: activeID)
        await store.receive(reloadAction)

        XCTAssertEqual(store.state.contentTabs, initialTabs)
        XCTAssertEqual(store.state.tabContentStates, initialInactiveStates)
        XCTAssertEqual(store.state.content.entryViewLayout.selectedIds, ["selected-entry"])
        await store.finish()
    }

    /// CTM-004-directory_reload_lifecycle: 성공한 Sidebar Trash record의 실제 target 부모만 refresh함
    /// moveToTrash client가 확정한 source/Trash 경로를 기준으로 active와 inactive Directory를 갱신한다.
    /// - 검증 내용: active source reload 1회, inactive Trash parent pending, unrelated tab 불변
    /// - 사전 조건: source active tab, Trash parent와 unrelated inactive tab, 성공한 moveToTrash record
    /// - 기대 결과: 요청 경로가 아니라 record target 부모만 기존 directory refresh helper에 전달됨
    func testSidebarTrashCompletion_refreshesSuccessfulTargetParents() async {
        let activeID = ContentTabID(rawValue: "trash-source")
        let trashID = ContentTabID(rawValue: "trash-destination")
        let unrelatedID = ContentTabID(rawValue: "trash-unrelated")
        let state = makeDirectoryReloadState(
            activeID: activeID,
            activePath: "/source",
            inactiveTabs: [
                .init(id: trashID, path: "/actual-trash", isPinned: false),
                .init(id: unrelatedID, path: "/unrelated", isPinned: false),
            ],
        )
        let record = EntryActionRecord(
            operationKind: .moveToTrash,
            targets: [.init(
                beforePath: "/source/item.txt",
                afterPath: "/actual-trash/item.txt",
            )],
        )
        let store = TestStore(initialState: state) {
            FileManagerWindowRoutingReducer()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
        }
        // store.exhaustivity = .off: routed listing reload의 하위 정렬 action보다 target parent refresh를 검증한다.
        store.exhaustivity = .off

        await store.send(.internal(.sidebarEntryDrop(.lifecycle(.entryActionCompleted(record))))) {
            $0.pendingDirectoryReloadTabIDs = [trashID]
        }
        await store.receive(routedDirectoryReloadAction(tabID: activeID))
        await store.skipReceivedActions()
        XCTAssertFalse(store.state.pendingDirectoryReloadTabIDs.contains(unrelatedID))
        await store.finish()
    }

    /// CTM-004-sidebar_entry_drop_routing: inactive tab recovery는 matching cache owner만 회전한다.
    /// - 검증 내용: inactive cache의 owner/history 회전과 active content 불변
    /// - 사전 조건: inactive tab owner를 대상으로 성공한 invalidation completion
    /// - 기대 결과: inactive cache에 새 owner와 빈 history, active content는 동일
    func testUndoReplay_recoveryRotatesMatchingInactiveContentOwner() async {
        let activeID = ContentTabID(rawValue: "recovery-active")
        let inactiveID = ContentTabID(rawValue: "recovery-inactive")
        let requestID = UUID()
        let ownerID = UUID()
        let newOwnerID = UUID()
        let record = EntryActionRecord(
            operationKind: .rename,
            targets: [.init(beforePath: "/inactive/old", afterPath: "/inactive/new")],
        )
        var state = makeDirectoryReloadState(
            activeID: activeID,
            activePath: "/active",
            inactiveTabs: [.init(id: inactiveID, path: "/inactive", isPinned: false)],
        )
        state.undoRedoPhase = .recovering(requestID: requestID, direction: .redo, ownerID: ownerID)
        state.tabContentStates[inactiveID]?.entryViewLayout.entryOperations.undoOwnerID = ownerID
        state.tabContentStates[inactiveID]?.entryViewLayout.entryOperations.undoRecords = [record]
        state.tabContentStates[inactiveID]?.entryViewLayout.entryOperations.redoRecords = [record]
        let activeOperations = state.content.entryViewLayout.entryOperations
        let availability = UndoManagerAvailability(canUndo: true, canRedo: false)
        let store = TestStore(initialState: state) {
            FileManagerWindowRoutingReducer()
        } withDependencies: {
            $0.uuid = .constant(newOwnerID)
        }

        await store.send(.internal(.undoManagerOwnerInvalidationFinished(
            requestID: requestID,
            ownerID: ownerID,
            result: .init(succeeded: true, availability: availability),
        ))) {
            $0.tabContentStates[inactiveID]?.entryViewLayout.entryOperations.rotateUndoOwner(to: newOwnerID)
            $0.undoRedoPhase = .idle
            $0.undoManagerAvailability = availability
        }

        XCTAssertEqual(store.state.content.entryViewLayout.entryOperations, activeOperations)
        await store.finish()
    }

    /// CTM-004-sidebar_entry_drop_routing: inactive content owner event는 해당 tab state로만 전달됨
    func testUndoManagerEvent_routesToMatchingInactiveContentOwner() async {
        let activeID = ContentTabID(rawValue: "event-active")
        let inactiveID = ContentTabID(rawValue: "event-inactive")
        let windowID = UUID()
        let requestID = UUID()
        let ownerID = UUID()
        let record = EntryActionRecord(
            operationKind: .rename,
            targets: [.init(beforePath: "/inactive/old", afterPath: "/inactive/new")],
        )
        var state = makeDirectoryReloadState(
            activeID: activeID,
            activePath: "/active",
            inactiveTabs: [.init(id: inactiveID, path: "/inactive", isPinned: false)],
        )
        state.windowID = windowID
        state.undoRedoPhase = .invoking(requestID: requestID, direction: .undo)
        state.tabContentStates[inactiveID]?.entryViewLayout.entryOperations.windowID = windowID
        state.tabContentStates[inactiveID]?.entryViewLayout.entryOperations.undoOwnerID = ownerID
        state.tabContentStates[inactiveID]?.entryViewLayout.entryOperations.undoRecords = [record]
        let activeOperations = state.content.entryViewLayout.entryOperations
        let store = TestStore(initialState: state) {
            FileManagerFeature()
        } withDependencies: {
            $0.entryFileOpsClient = .previewValue
            $0.entryLoadingClient = .previewValue
            $0.undoManagerClient = .previewValue
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
        }
        store.exhaustivity = .off

        await store.send(.internal(.undoManagerEventReceived(.init(
            ownerID: ownerID,
            record: record,
            direction: .undo,
        ))))
        await store.receive { action in
            guard case let .internal(.routeContent(
                tabID: receivedTabID,
                action: .entryViewLayout(.entryOperations(.undoRedo(.undoEntryAction(receivedRecord)))),
            )) = action else { return false }
            return receivedTabID == inactiveID && receivedRecord == record
        }
        await store.skipReceivedActions()
        await store.finish()

        XCTAssertEqual(store.state.undoRedoPhase, .idle)
        XCTAssertEqual(store.state.content.entryViewLayout.entryOperations, activeOperations)
        XCTAssertTrue(store.state.tabContentStates[inactiveID]?.entryViewLayout.entryOperations.undoRecords
            .isEmpty == true)
        XCTAssertEqual(
            store.state.tabContentStates[inactiveID]?.entryViewLayout.entryOperations.redoRecords,
            [record],
        )
    }

    /// CTM-004-sidebar_entry_drop_routing: tab close는 해당 content owner만 invalidate함
    func testContentTabClose_invalidatesOnlyClosedOwnerAndPreservesSidebarOwner() async throws {
        let activeID = ContentTabID(rawValue: "close-owner-active")
        let inactiveID = ContentTabID(rawValue: "close-owner-inactive")
        let windowID = UUID()
        var state = makeDirectoryReloadState(
            activeID: activeID,
            activePath: "/active",
            inactiveTabs: [.init(id: inactiveID, path: "/inactive", isPinned: false)],
        )
        state.windowID = windowID
        let closedOwnerID = try XCTUnwrap(state.tabContentStates[inactiveID]?.entryViewLayout.entryOperations
            .undoOwnerID)
        let sidebarOwnerID = state.sidebarEntryDropOperations.undoOwnerID
        let invalidatedOwners = LockIsolated<[UUID]>([])
        let client = UndoManagerClient(
            registerUndo: { _, _, _ in },
            undo: { _, _ in .init(didInvoke: false, availability: .init()) },
            redo: { _, _ in .init(didInvoke: false, availability: .init()) },
            invalidateOwner: { receivedWindowID, ownerID in
                XCTAssertEqual(receivedWindowID, windowID)
                invalidatedOwners.withValue { $0.append(ownerID) }
                return .init(succeeded: true, availability: .init())
            },
        )
        let store = TestStore(initialState: state) {
            FileManagerFeature()
        } withDependencies: {
            $0.undoManagerClient = client
            $0.uuid = .incrementing
        }
        // 비포괄적: full feature의 projection 파생 액션보다 owner invalidation과 close commit 순서를 검증한다.
        store.exhaustivity = .off

        await store.send(.contentTabs(.requestClose(inactiveID)))
        await store.receive(\.internal.undoManagerOwnerInvalidationFinished)
        await store.receive(\.contentTabs.commitClose)
        await store.finish()

        XCTAssertEqual(invalidatedOwners.value, [closedOwnerID])
        XCTAssertFalse(invalidatedOwners.value.contains(sidebarOwnerID))
        XCTAssertEqual(store.state.sidebarEntryDropOperations.undoOwnerID, sidebarOwnerID)
        XCTAssertNil(store.state.tabContentStates[inactiveID])
    }

    /// CTM-004-sidebar_entry_drop_routing: active/inactive/last tab은 owner invalidation 완료 전 identity와 cache를 유지한다.
    /// - 검증 내용: 세 close 종류 모두 teardown phase에서 row/cache/owner를 보존하고 성공 completion 뒤 기존 fallback/reset을 한 번만 commit한다.
    /// - 사전 조건: windowID가 있는 Directory tab 상태와 지연되는 invalidateOwner client
    /// - 기대 결과: completion 전 identity 보존, completion 후 inactive 제거·active fallback·last Home reset
    func testContentTabClose_preservesActiveInactiveAndLastIdentityUntilInvalidationCompletes() async throws {
        let scenarios: [(name: String, state: FileManagerFeature.State, closingID: ContentTabID)] = try {
            let activeID = ContentTabID(rawValue: "teardown-active")
            let inactiveID = ContentTabID(rawValue: "teardown-inactive")
            let inactiveClose = makeDirectoryReloadState(
                activeID: activeID,
                activePath: "/active",
                inactiveTabs: [.init(id: inactiveID, path: "/inactive", isPinned: false)],
            )
            var activeClose = inactiveClose
            activeClose.contentTabs.activeTabID = inactiveID
            activeClose.contentTabs.previousActiveTabID = activeID
            activeClose.content = try XCTUnwrap(activeClose.tabContentStates[inactiveID])
            let lastClose = makeDirectoryReloadState(
                activeID: ContentTabID(rawValue: "teardown-last"),
                activePath: "/last",
            )
            let lastID = try XCTUnwrap(lastClose.contentTabs.activeTabID)
            return [
                ("inactive", inactiveClose, inactiveID),
                ("active", activeClose, inactiveID),
                ("last", lastClose, lastID),
            ]
        }()

        for scenario in scenarios {
            let windowID = UUID()
            let gate = CTM004ReplayFileOperationGate()
            var state = scenario.state
            state.windowID = windowID
            let ownerID = if scenario.closingID == state.contentTabs.activeTabID {
                state.content.entryViewLayout.entryOperations.undoOwnerID
            } else {
                try XCTUnwrap(state.tabContentStates[scenario.closingID]).entryViewLayout.entryOperations.undoOwnerID
            }
            let scenarioName = scenario.name
            let client = UndoManagerClient(
                registerUndo: { _, _, _ in },
                undo: { _, _ in .init(didInvoke: false, availability: .init()) },
                redo: { _, _ in .init(didInvoke: false, availability: .init()) },
                invalidateOwner: { _, receivedOwnerID in
                    XCTAssertEqual(receivedOwnerID, ownerID, scenarioName)
                    await gate.suspend()
                    return .init(succeeded: true, availability: .init())
                },
            )
            let store = TestStore(initialState: state) {
                FileManagerFeature()
            } withDependencies: {
                $0.undoManagerClient = client
                $0.uuid = .incrementing
                $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
            }
            // store.exhaustivity = .off: close 후 handoff cleanup 중 핵심 teardown ordering만 검증한다.
            store.exhaustivity = .off

            await store.send(.contentTabs(.requestClose(scenario.closingID)))
            await gate.waitUntilSuspended()
            XCTAssertNotNil(store.state.contentTabs.tabs[id: scenario.closingID], scenario.name)
            XCTAssertNotNil(store.state.tabContentStates[scenario.closingID], scenario.name)
            XCTAssertEqual(store.state.pendingContentTabTeardown?.ownerID, ownerID, scenario.name)
            XCTAssertFalse(store.state.menuCommandProjection.canUndo, scenario.name)
            XCTAssertFalse(store.state.menuCommandProjection.canRedo, scenario.name)

            await store.send(.sidebar(.delegate(.pinContentTab(scenario.closingID))))
            XCTAssertEqual(store.state.contentTabs.tabs[id: scenario.closingID]?.isPinned, false, scenario.name)

            await gate.resume()
            await store.receive(\.internal.undoManagerOwnerInvalidationFinished)
            await store.receive(\.contentTabs.commitClose)
            await store.finish()

            if scenario.name == "last" {
                XCTAssertEqual(store.state.contentTabs.tabs[id: scenario.closingID]?.anchor, .homeDefault)
                XCTAssertNotNil(store.state.tabContentStates[scenario.closingID])
            } else {
                XCTAssertNil(store.state.contentTabs.tabs[id: scenario.closingID])
                XCTAssertNil(store.state.tabContentStates[scenario.closingID])
            }
        }
    }

    /// CTM-004-sidebar_entry_drop_routing: tab owner invalidation 실패는 identity를 보존하고 desynchronized로 잠근다.
    /// - 검증 내용: 실패 completion 이후 tab row/cache/owner가 유지되고 menu availability가 비활성화된다.
    /// - 사전 조건: inactive tab과 실패 invalidateOwner client
    /// - 기대 결과: tab/cache 보존, pending teardown 정리, desynchronized
    func testContentTabClose_invalidationFailurePreservesIdentityAndDesynchronizes() async throws {
        let activeID = ContentTabID(rawValue: "teardown-failure-active")
        let inactiveID = ContentTabID(rawValue: "teardown-failure-inactive")
        var state = makeDirectoryReloadState(
            activeID: activeID,
            activePath: "/active",
            inactiveTabs: [.init(id: inactiveID, path: "/inactive", isPinned: false)],
        )
        state.windowID = UUID()
        state.undoManagerAvailability = .init(canUndo: true, canRedo: true)
        let ownerID = try XCTUnwrap(state.tabContentStates[inactiveID]).entryViewLayout.entryOperations.undoOwnerID
        let client = UndoManagerClient(
            registerUndo: { _, _, _ in },
            undo: { _, _ in .init(didInvoke: false, availability: .init()) },
            redo: { _, _ in .init(didInvoke: false, availability: .init()) },
            invalidateOwner: { _, _ in .init(succeeded: false, availability: .init(canUndo: true, canRedo: true)) },
        )
        let store = TestStore(initialState: state) {
            FileManagerFeature()
        } withDependencies: {
            $0.undoManagerClient = client
            $0.uuid = .incrementing
        }
        // store.exhaustivity = .off: child projection action보다 invalidation 실패 terminal 상태를 검증한다.
        store.exhaustivity = .off

        await store.send(.contentTabs(.requestClose(inactiveID)))
        await store.receive(\.internal.undoManagerOwnerInvalidationFinished)
        XCTAssertNotNil(store.state.contentTabs.tabs[id: inactiveID])
        XCTAssertEqual(
            store.state.tabContentStates[inactiveID]?.entryViewLayout.entryOperations.undoOwnerID,
            ownerID,
        )
        XCTAssertNil(store.state.pendingContentTabTeardown)
        XCTAssertEqual(store.state.undoRedoPhase, .desynchronized)
        XCTAssertFalse(store.state.menuCommandProjection.canUndo)
        XCTAssertFalse(store.state.menuCommandProjection.canRedo)
        await store.finish()
    }

    /// CTM-004-sidebar_entry_drop_routing: desynchronized 상태에서도 inactive unpinned tab을 즉시 닫는다.
    /// owner invalidation을 재시도하지 않고 inactive tab identity와 cache만 정리하는 회귀를 검증한다.
    /// - 검증 내용: phase/pending/availability 유지, invalidation 0회, inactive row/cache/pending reload 제거
    /// - 사전 조건: desynchronized Window에 active tab과 inactive unpinned tab이 존재함
    /// - 기대 결과: active content/cache는 유지되고 inactive tab 관련 상태만 제거됨
    func testContentTabClose_desynchronizedClosesInactiveWithoutInvalidation() async {
        let activeID = ContentTabID(rawValue: "desynchronized-inactive-close-active")
        let inactiveID = ContentTabID(rawValue: "desynchronized-inactive-close-target")
        var state = makeDirectoryReloadState(
            activeID: activeID,
            activePath: "/active",
            inactiveTabs: [.init(id: inactiveID, path: "/inactive", isPinned: false)],
        )
        state.windowID = UUID()
        state.undoRedoPhase = .desynchronized
        state.undoManagerAvailability = .init(canUndo: true, canRedo: true)
        state.pendingDirectoryReloadTabIDs = [inactiveID]
        let activeContent = state.content
        let activeCache = state.tabContentStates[activeID]
        let invalidationCount = LockIsolated(0)
        let client = UndoManagerClient(
            registerUndo: { _, _, _ in },
            undo: { _, _ in .init(didInvoke: false, availability: .init()) },
            redo: { _, _ in .init(didInvoke: false, availability: .init()) },
            invalidateOwner: { _, _ in
                invalidationCount.withValue { $0 += 1 }
                return .init(succeeded: true, availability: .init())
            },
        )
        let store = TestStore(initialState: state) {
            FileManagerFeature()
        } withDependencies: {
            $0.undoManagerClient = client
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
        }
        // store.exhaustivity = .off: full feature projection보다 desynchronized close의 terminal 상태를 검증한다.
        store.exhaustivity = .off

        await store.send(.contentTabs(.requestClose(inactiveID)))
        await store.finish()

        XCTAssertEqual(store.state.undoRedoPhase, .desynchronized)
        XCTAssertNil(store.state.pendingContentTabTeardown)
        XCTAssertEqual(store.state.undoManagerAvailability, .init(canUndo: true, canRedo: true))
        XCTAssertEqual(invalidationCount.value, 0)
        XCTAssertNil(store.state.contentTabs.tabs[id: inactiveID])
        XCTAssertNil(store.state.tabContentStates[inactiveID])
        XCTAssertEqual(store.state.contentTabs.activeTabID, activeID)
        XCTAssertEqual(store.state.content, activeContent)
        XCTAssertEqual(store.state.tabContentStates[activeID], activeCache)
        XCTAssertFalse(store.state.pendingDirectoryReloadTabIDs.contains(inactiveID))
    }

    /// CTM-004-sidebar_entry_drop_routing: desynchronized 상태에서도 active unpinned tab을 즉시 닫고 handoff한다.
    /// owner invalidation 없이 기존 active-close fallback과 cache 정리를 그대로 수행하는지 검증한다.
    /// - 검증 내용: phase/pending 유지, invalidation 0회, closing cache 제거와 fallback content 복원
    /// - 사전 조건: desynchronized Window의 active unpinned tab 뒤에 inactive fallback tab이 존재함
    /// - 기대 결과: fallback tab이 active가 되고 해당 cache가 active content로 복원됨
    func testContentTabClose_desynchronizedClosesActiveAndRestoresFallbackWithoutInvalidation() async throws {
        let activeID = ContentTabID(rawValue: "desynchronized-active-close-target")
        let fallbackID = ContentTabID(rawValue: "desynchronized-active-close-fallback")
        var state = makeDirectoryReloadState(
            activeID: activeID,
            activePath: "/active",
            inactiveTabs: [.init(id: fallbackID, path: "/fallback", isPinned: false)],
        )
        state.windowID = UUID()
        state.undoRedoPhase = .desynchronized
        state.pendingDirectoryReloadTabIDs = [activeID]
        let fallbackContent = try XCTUnwrap(state.tabContentStates[fallbackID])
        let invalidationCount = LockIsolated(0)
        let client = UndoManagerClient(
            registerUndo: { _, _, _ in },
            undo: { _, _ in .init(didInvoke: false, availability: .init()) },
            redo: { _, _ in .init(didInvoke: false, availability: .init()) },
            invalidateOwner: { _, _ in
                invalidationCount.withValue { $0 += 1 }
                return .init(succeeded: true, availability: .init())
            },
        )
        let store = TestStore(initialState: state) {
            FileManagerFeature()
        } withDependencies: {
            $0.undoManagerClient = client
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
        }
        // store.exhaustivity = .off: active handoff의 파생 action보다 desynchronized close 결과를 검증한다.
        store.exhaustivity = .off

        await store.send(.contentTabs(.requestClose(activeID)))
        await store.skipReceivedActions()
        await store.finish()

        XCTAssertEqual(store.state.undoRedoPhase, .desynchronized)
        XCTAssertNil(store.state.pendingContentTabTeardown)
        XCTAssertEqual(invalidationCount.value, 0)
        XCTAssertNil(store.state.contentTabs.tabs[id: activeID])
        XCTAssertNil(store.state.tabContentStates[activeID])
        XCTAssertEqual(store.state.contentTabs.activeTabID, fallbackID)
        XCTAssertEqual(store.state.tabContentStates[fallbackID], fallbackContent)
        XCTAssertEqual(store.state.content.navigation.navigationState, fallbackContent.navigation.navigationState)
        XCTAssertEqual(
            store.state.content.entryViewLayout.entryOperations.undoOwnerID,
            fallbackContent.entryViewLayout.entryOperations.undoOwnerID,
        )
        XCTAssertFalse(store.state.pendingDirectoryReloadTabIDs.contains(activeID))
    }

    /// CTM-004-sidebar_entry_drop_routing: in-flight undo/redo phase는 unpinned tab close를 계속 차단한다.
    /// desynchronized 예외가 invoking/replaying/refreshing/recovering/tearingDownTab으로 확장되지 않음을 검증한다.
    /// - 검증 내용: 각 phase에서 tab/cache/phase/pending 불변, invalidation 0회
    /// - 사전 조건: active tab과 inactive unpinned target, 5개 in-flight phase별 Window state
    /// - 기대 결과: 모든 close request가 no-op으로 종료됨
    func testContentTabClose_inFlightPhasesRemainBlocked() async {
        let requestID = UUID()
        let ownerID = UUID()
        let phases: [FileManagerUndoRedoPhase] = [
            .invoking(requestID: requestID, direction: .undo),
            .replaying(requestID: requestID, direction: .redo),
            .refreshing(requestID: requestID),
            .recovering(requestID: requestID, direction: .undo, ownerID: ownerID),
            .tearingDownTab(requestID: requestID, ownerID: ownerID),
        ]

        for phase in phases {
            let activeID = ContentTabID(rawValue: "in-flight-close-active")
            let inactiveID = ContentTabID(rawValue: "in-flight-close-target")
            var state = makeDirectoryReloadState(
                activeID: activeID,
                activePath: "/active",
                inactiveTabs: [.init(id: inactiveID, path: "/inactive", isPinned: false)],
            )
            state.windowID = UUID()
            state.undoRedoPhase = phase
            let initialState = state
            let invalidationCount = LockIsolated(0)
            let client = UndoManagerClient(
                registerUndo: { _, _, _ in },
                undo: { _, _ in .init(didInvoke: false, availability: .init()) },
                redo: { _, _ in .init(didInvoke: false, availability: .init()) },
                invalidateOwner: { _, _ in
                    invalidationCount.withValue { $0 += 1 }
                    return .init(succeeded: true, availability: .init())
                },
            )
            let store = TestStore(initialState: state) {
                FileManagerWindowRoutingReducer()
            } withDependencies: {
                $0.undoManagerClient = client
            }

            await store.send(.contentTabs(.requestClose(inactiveID)))
            await store.finish()

            XCTAssertEqual(store.state, initialState)
            XCTAssertEqual(invalidationCount.value, 0)
        }
    }

    /// CTM-004-directory_reload_lifecycle: 실제 shared UndoManager의 Sidebar replay 동안 두 menu command를 잠금
    /// - 검증 내용: NSUndoManager stack 이동 후 delayed move replay terminal 전까지 undo/redo와 추가 filesystem 호출 차단
    /// - 사전 조건: Window-owned Sidebar record가 실제 shared UndoManager에 등록되고 moveFile이 gate에서 대기함
    /// - 기대 결과: in-flight menu 잠금, 반대 command no-op, terminal 후 idle/실제 availability/active reload 1회
    func testSidebarUndoReplay_realSharedManagerLocksCommandsUntilDelayedTerminal() async throws {
        let sandbox = try FileManagerFixtureSandbox.copyingFileWithDirectorySymlink(
            from: "fixtures/fixtures/texts/plain/11.txt",
        )
        defer { sandbox.cleanup() }
        let sourceDirectory = sandbox.fileURL.deletingLastPathComponent()
        let destinationDirectory = sandbox.root.appendingPathComponent("DelayedSidebar", isDirectory: true)
        try FileManager.default.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)
        let movedURL = destinationDirectory.appendingPathComponent(sandbox.fileURL.lastPathComponent)
        try FileManager.default.moveItem(at: sandbox.fileURL, to: movedURL)

        let windowID = UUID()
        let undoManager = UndoManager()
        let undoClient = UndoManagerClient.live(undoManager: undoManager)
        let gate = CTM004ReplayFileOperationGate()
        let listingLoads = LockIsolated<[String]>([])
        var fileOps = EntryFileOpsClient.previewValue
        fileOps.moveFile = { source, destination in
            await gate.suspend()
            try FileManager.default.moveItem(at: source, to: destination)
        }
        var loadingClient = EntryLoadingClient.previewValue
        loadingClient.loadItems = { url, _ in
            listingLoads.withValue { $0.append(url.path) }
            return []
        }

        let activeID = ContentTabID(rawValue: "delayed-sidebar-active")
        var state = makeDirectoryReloadState(activeID: activeID, activePath: sourceDirectory.path)
        state.windowID = windowID
        state.sidebarEntryDropOperations.windowID = windowID
        let record = EntryActionRecord(
            operationKind: .pasteFileMove,
            targets: [.init(beforePath: sandbox.fileURL.path, afterPath: movedURL.path)],
        )
        let store = Store(initialState: state) {
            FileManagerFeature()
        } withDependencies: {
            $0.undoManagerClient = undoClient
            $0.entryFileOpsClient = fileOps
            $0.entryLoadingClient = loadingClient
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
            $0.uuid = .incrementing
        }

        store.send(.internal(.undoManagerWindowIDChanged(windowID)))
        try await waitUntilUndoReplayCondition {
            store.withState { $0.sidebarEntryDropOperations.windowID == windowID }
        }
        store.send(.internal(.sidebarEntryDrop(.lifecycle(.entryActionCompleted(record)))))
        try await waitUntilUndoReplayCondition {
            store.withState { $0.undoManagerAvailability.canUndo }
        }
        store.send(.request(.requestUndo))
        await gate.waitUntilSuspended()

        let inFlightPhase = store.withState { $0.undoRedoPhase }
        XCTAssertNotEqual(inFlightPhase, .idle)
        XCTAssertFalse(store.withState { $0.menuCommandProjection.canUndo })
        XCTAssertFalse(store.withState { $0.menuCommandProjection.canRedo })
        let sidebarReplayInvocationCount = await gate.invocationCount()
        XCTAssertEqual(sidebarReplayInvocationCount, 1)
        store.send(.request(.requestRedo))
        let sidebarReplayInvocationCountAfterRedo = await gate.invocationCount()
        XCTAssertEqual(sidebarReplayInvocationCountAfterRedo, 1)

        await gate.resume()
        try await waitUntilUndoReplayCondition {
            store.withState { $0.undoRedoPhase == .idle }
                && store.withState { !$0.sidebarEntryDropOperations.itemStates.values.contains(where: \.isBusy) }
                && listingLoads.value.count == 1
        }
        let actualAvailability = await undoClient.availability(windowID)

        XCTAssertEqual(store.withState { $0.undoManagerAvailability }, actualAvailability)
        XCTAssertEqual(listingLoads.value, [sourceDirectory.path])
        XCTAssertTrue(FileManager.default.fileExists(atPath: sandbox.fileURL.path))
        let finalSidebarReplayInvocationCount = await gate.invocationCount()
        XCTAssertEqual(finalSidebarReplayInvocationCount, 1)
    }

    /// CTM-004-directory_reload_lifecycle: 실제 shared UndoManager의 content replay도 같은 gate와 local reload만 사용함
    /// - 검증 내용: delayed rename undo 동안 menu 잠금, 반대 command no-op, terminal 후 content local reload exactly-once
    /// - 사전 조건: active content record가 shared manager에 등록되고 renameFile이 gate에서 대기함
    /// - 기대 결과: idle/실제 availability 복구, busy 해제, Window aggregate 중복 없이 listing load 1회
    func testContentUndoReplay_realSharedManagerLocksCommandsAndKeepsLocalReloadOwnership() async throws {
        let sandbox = try FileManagerFixtureSandbox.copyingFileWithDirectorySymlink(
            from: "fixtures/fixtures/texts/plain/11.txt",
        )
        defer { sandbox.cleanup() }
        let sourceURL = sandbox.fileURL
        let renamedURL = sourceURL.deletingLastPathComponent().appendingPathComponent("renamed.txt")
        try FileManager.default.moveItem(at: sourceURL, to: renamedURL)

        let windowID = UUID()
        let undoManager = UndoManager()
        let undoClient = UndoManagerClient.live(undoManager: undoManager)
        let gate = CTM004ReplayFileOperationGate()
        let listingLoads = LockIsolated<[String]>([])
        var fileOps = EntryFileOpsClient.previewValue
        fileOps.renameFile = { source, destination in
            await gate.suspend()
            try FileManager.default.moveItem(at: source, to: destination)
        }
        var loadingClient = EntryLoadingClient.previewValue
        loadingClient.loadItems = { url, _ in
            listingLoads.withValue { $0.append(url.path) }
            return []
        }

        let activeID = ContentTabID(rawValue: "delayed-content-active")
        var state = makeDirectoryReloadState(
            activeID: activeID,
            activePath: sourceURL.deletingLastPathComponent().path,
        )
        state.windowID = windowID
        state.content.entryViewLayout.entryOperations.windowID = windowID
        state.syncActiveTabContentState()
        let record = EntryActionRecord(
            operationKind: .rename,
            targets: [.init(beforePath: sourceURL.path, afterPath: renamedURL.path)],
        )
        let store = Store(initialState: state) {
            FileManagerFeature()
        } withDependencies: {
            $0.undoManagerClient = undoClient
            $0.entryFileOpsClient = fileOps
            $0.entryLoadingClient = loadingClient
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
            $0.uuid = .incrementing
        }

        store.send(.internal(.undoManagerWindowIDChanged(windowID)))
        try await waitUntilUndoReplayCondition {
            store.withState { $0.sidebarEntryDropOperations.windowID == windowID }
        }
        store.send(.content(.entryViewLayout(.entryOperations(.lifecycle(.entryActionCompleted(record))))))
        try await waitUntilUndoReplayCondition {
            store.withState { $0.undoManagerAvailability.canUndo }
        }
        store.send(.request(.requestUndo))
        await gate.waitUntilSuspended()

        XCTAssertNotEqual(store.withState { $0.undoRedoPhase }, .idle)
        XCTAssertFalse(store.withState { $0.menuCommandProjection.canUndo })
        XCTAssertFalse(store.withState { $0.menuCommandProjection.canRedo })
        let contentReplayInvocationCount = await gate.invocationCount()
        XCTAssertEqual(contentReplayInvocationCount, 1)
        store.send(.request(.requestRedo))
        let contentReplayInvocationCountAfterRedo = await gate.invocationCount()
        XCTAssertEqual(contentReplayInvocationCountAfterRedo, 1)

        await gate.resume()
        try await waitUntilUndoReplayCondition {
            store.withState { $0.undoRedoPhase == .idle }
                && store.withState {
                    !$0.content.entryViewLayout.entryOperations.itemStates.values.contains(where: \.isBusy)
                }
                && listingLoads.value.count == 1
        }
        let actualAvailability = await undoClient.availability(windowID)

        XCTAssertEqual(store.withState { $0.undoManagerAvailability }, actualAvailability)
        XCTAssertEqual(listingLoads.value, [sourceURL.deletingLastPathComponent().path])
        XCTAssertTrue(FileManager.default.fileExists(atPath: sourceURL.path))
        let finalContentReplayInvocationCount = await gate.invocationCount()
        XCTAssertEqual(finalContentReplayInvocationCount, 1)
    }

    /// CTM-004-directory_reload_lifecycle: Sidebar undo와 redo replay가 affected listing을 각각 갱신함
    /// - 검증 내용: replay record의 before/after 부모 dedup, active exactly-once, inactive pending
    /// - 사전 조건: fixture source가 active, destination이 inactive, unrelated Directory가 존재함
    /// - 기대 결과: undo/redo마다 active reload 1회, destination만 pending, unrelated 불변
    func testSidebarReplay_undoAndRedoRefreshAffectedListings() async throws {
        let sandbox = try FileManagerFixtureSandbox.copyingFileWithDirectorySymlink(
            from: "fixtures/fixtures/texts/plain/11.txt",
        )
        defer { sandbox.cleanup() }
        let sourceDirectory = sandbox.fileURL.deletingLastPathComponent()
        let destinationDirectory = sandbox.root.appendingPathComponent("ReplayDestination", isDirectory: true)
        try FileManager.default.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)
        let activeID = ContentTabID(rawValue: "replay-source")
        let destinationID = ContentTabID(rawValue: "replay-destination")
        let unrelatedID = ContentTabID(rawValue: "replay-unrelated")
        let state = makeDirectoryReloadState(
            activeID: activeID,
            activePath: sourceDirectory.path,
            inactiveTabs: [
                .init(id: destinationID, path: destinationDirectory.path, isPinned: true),
                .init(id: unrelatedID, path: sandbox.root.appendingPathComponent("Unrelated").path, isPinned: false),
            ],
        )
        let record = EntryActionRecord(
            operationKind: .pasteFileMove,
            targets: [.init(
                beforePath: sandbox.fileURL.path,
                afterPath: destinationDirectory.appendingPathComponent(sandbox.fileURL.lastPathComponent).path,
            )],
        )
        let store = TestStore(initialState: state) {
            Reduce<FileManagerFeature.State, FileManagerFeature.Action> { state, action in
                guard case let .internal(.sidebarEntryDrop(.outcome(.entryActionReplayFinished(
                    _,
                    .success(replayedRecord),
                )))) = action
                else { return .none }
                return handleSidebarEntryActionReplayTerminal(.success(replayedRecord), state: &state)
            }
        }

        await store.send(.internal(.sidebarEntryDrop(.outcome(
            .entryActionReplayFinished(direction: .undo, terminal: .success(record)),
        )))) {
            $0.pendingDirectoryReloadTabIDs = [destinationID]
        }
        await store.receive(routedDirectoryReloadAction(tabID: activeID))
        await store.send(.internal(.sidebarEntryDrop(.outcome(
            .entryActionReplayFinished(direction: .redo, terminal: .success(record)),
        ))))
        await store.receive(routedDirectoryReloadAction(tabID: activeID))

        XCTAssertEqual(store.state.pendingDirectoryReloadTabIDs, [destinationID])
        XCTAssertFalse(store.state.pendingDirectoryReloadTabIDs.contains(unrelatedID))
        XCTAssertTrue(FileManager.default.fileExists(atPath: sandbox.originalFixture.path))
        await store.finish()
    }

    /// CTM-004-directory_reload_lifecycle: partial replay failure는 applied prefix 부모만 refresh한다.
    /// - 검증 내용: 실패 target 경로는 제외하고 appliedTargets 첫 항목의 source/destination parent만 반영한다.
    /// - 사전 조건: active source, inactive applied destination, unrelated failed destination tab
    /// - 기대 결과: active reload 1회, applied destination만 pending, failed destination 불변
    func testSidebarReplay_partialFailureRefreshesOnlyAppliedPrefixPaths() async {
        let activeID = ContentTabID(rawValue: "partial-source")
        let appliedID = ContentTabID(rawValue: "partial-applied")
        let failedID = ContentTabID(rawValue: "partial-failed")
        let appliedTarget = EntryActionRecord.Target(
            beforePath: "/source/first.txt",
            afterPath: "/applied/first.txt",
        )
        let state = makeDirectoryReloadState(
            activeID: activeID,
            activePath: "/source",
            inactiveTabs: [
                .init(id: appliedID, path: "/applied", isPinned: false),
                .init(id: failedID, path: "/failed", isPinned: false),
            ],
        )
        let store = TestStore(initialState: state) {
            Reduce<FileManagerFeature.State, FileManagerFeature.Action> { state, action in
                guard case let .internal(.sidebarEntryDrop(.outcome(.entryActionReplayFinished(
                    _,
                    terminal,
                )))) = action else { return .none }
                return handleSidebarEntryActionReplayTerminal(terminal, state: &state)
            }
        }

        await store.send(.internal(.sidebarEntryDrop(.outcome(.entryActionReplayFinished(
            direction: .undo,
            terminal: .failure(reason: .operationFailed, appliedTargets: [appliedTarget]),
        ))))) {
            $0.pendingDirectoryReloadTabIDs = [appliedID]
        }
        await store.receive(routedDirectoryReloadAction(tabID: activeID))
        XCTAssertFalse(store.state.pendingDirectoryReloadTabIDs.contains(failedID))
        await store.finish()
    }

    /// CTM-004-directory_reload_lifecycle: source tab 종료 뒤 Sidebar replay는 surviving affected tab만 갱신함
    /// - 검증 내용: closed source owner를 재생성하지 않고 destination active reload와 source mirror pending 처리
    /// - 사전 조건: fixture source owner tab은 없고 destination active/source mirror inactive만 생존함
    /// - 기대 결과: destination reload 1회, source mirror pending, closed tab state 없음
    func testSidebarReplay_sourceTabClosedRefreshesOnlySurvivingTabs() async throws {
        let sandbox = try FileManagerFixtureSandbox.copyingFileWithDirectorySymlink(
            from: "fixtures/fixtures/texts/plain/11.txt",
        )
        defer { sandbox.cleanup() }
        let sourceDirectory = sandbox.fileURL.deletingLastPathComponent()
        let destinationDirectory = sandbox.root.appendingPathComponent("ReplayDestination", isDirectory: true)
        try FileManager.default.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)
        let destinationID = ContentTabID(rawValue: "surviving-destination")
        let sourceMirrorID = ContentTabID(rawValue: "surviving-source-mirror")
        let closedSourceID = ContentTabID(rawValue: "closed-source-owner")
        let state = makeDirectoryReloadState(
            activeID: destinationID,
            activePath: destinationDirectory.path,
            inactiveTabs: [.init(id: sourceMirrorID, path: sourceDirectory.path, isPinned: false)],
        )
        let record = EntryActionRecord(
            operationKind: .pasteFileMove,
            targets: [.init(
                beforePath: sandbox.fileURL.path,
                afterPath: destinationDirectory.appendingPathComponent(sandbox.fileURL.lastPathComponent).path,
            )],
        )
        let store = TestStore(initialState: state) {
            Reduce<FileManagerFeature.State, FileManagerFeature.Action> { state, action in
                guard case let .internal(.sidebarEntryDrop(.outcome(.entryActionReplayFinished(
                    _,
                    .success(replayedRecord),
                )))) = action
                else { return .none }
                return handleSidebarEntryActionReplayTerminal(.success(replayedRecord), state: &state)
            }
        }

        await store.send(.internal(.sidebarEntryDrop(.outcome(
            .entryActionReplayFinished(direction: .undo, terminal: .success(record)),
        )))) {
            $0.pendingDirectoryReloadTabIDs = [sourceMirrorID]
        }
        await store.receive(routedDirectoryReloadAction(tabID: destinationID))

        XCTAssertNil(store.state.contentTabs.tabs[id: closedSourceID])
        XCTAssertNil(store.state.tabContentStates[closedSourceID])
        XCTAssertEqual(store.state.pendingDirectoryReloadTabIDs, [sourceMirrorID])
        await store.finish()
    }

    /// CTM-004-directory_reload_lifecycle: content replay outcome은 Window aggregate refresh를 추가하지 않음
    /// - 검증 내용: content owner의 typed replay success가 Sidebar 전용 affected refresh를 우회함
    /// - 사전 조건: active Directory와 실제 fixture record가 있으며 기존 content operationFinished local reload는 별도 유지됨
    /// - 기대 결과: root undo availability만 재동기화되고 content local reload만 canonical owner로 남음
    func testContentReplay_doesNotAddWindowAggregateRefresh() async throws {
        let sandbox = try FileManagerFixtureSandbox.copyingFileWithDirectorySymlink(
            from: "fixtures/fixtures/texts/plain/11.txt",
        )
        defer { sandbox.cleanup() }
        let activeID = ContentTabID(rawValue: "content-replay")
        let state = makeDirectoryReloadState(
            activeID: activeID,
            activePath: sandbox.fileURL.deletingLastPathComponent().path,
        )
        let record = EntryActionRecord(
            operationKind: .rename,
            targets: [.init(beforePath: sandbox.fileURL.path, afterPath: sandbox.fileURL.path + ".renamed")],
        )
        let refreshRequestID = UUID()
        let refreshedAvailability = UndoManagerAvailability(canUndo: true, canRedo: false)
        let client = UndoManagerClient(
            registerUndo: { _, _, _ in },
            undo: { _, _ in .init(didInvoke: false, availability: .init()) },
            redo: { _, _ in .init(didInvoke: false, availability: .init()) },
            availability: { _ in refreshedAvailability },
        )
        let store = TestStore(initialState: state) {
            CombineReducers {
                FileManagerWindowCommandRoutingReducer()
                FileManagerWindowRoutingReducer()
            }
        } withDependencies: {
            $0.undoManagerClient = client
            $0.uuid = .constant(refreshRequestID)
        }

        await store.send(.content(.entryViewLayout(.entryOperations(.outcome(
            .entryActionReplayFinished(direction: .undo, terminal: .success(record)),
        ))))) {
            $0.undoRedoPhase = .refreshing(requestID: refreshRequestID)
        }
        await store.receive { action in
            guard case let .internal(.undoManagerReplayAvailabilityChanged(requestID, availability)) = action else {
                return false
            }
            return requestID == refreshRequestID && availability == refreshedAvailability
        } assert: {
            $0.undoRedoPhase = .idle
            $0.undoManagerAvailability = refreshedAvailability
        }

        var expectedState = state
        expectedState.undoManagerAvailability = refreshedAvailability
        XCTAssertEqual(store.state, expectedState)
        XCTAssertTrue(FileManager.default.fileExists(atPath: sandbox.originalFixture.path))
        await store.finish()
    }

    /// CTM-004-directory_reload_lifecycle: 일반 clipboard paste만 즉시 listing reload를 유지함
    /// drop-origin completion은 per-item reload를 만들지 않고 aggregate outcome에 refresh를 맡기는지 검증한다.
    /// - 검증 내용: clipboard `operationFinished` load 1회, drop completion load 0회
    /// - 사전 조건: `fixtures/fixtures/texts/plain/11.txt`의 temp copy를 표시하는 Directory content
    /// - 기대 결과: 동일 paste operation kind라도 origin에 따라 reload ownership이 분리됨
    func testClipboardPasteCompletionReloadsWhileDropCompletionWaitsForAggregateOutcome() async throws {
        let sandbox = try FileManagerFixtureSandbox.copyingFileWithDirectorySymlink(
            from: "fixtures/fixtures/texts/plain/11.txt",
        )
        defer { sandbox.cleanup() }
        let directoryPath = sandbox.fileURL.deletingLastPathComponent().path
        var contentState = FileManagerContentFeature.State()
        contentState.navigation.seedInitialFolderPath(directoryPath)

        let clipboardStore = TestStore(initialState: contentState) {
            FileManagerContentEntryOperationsBridgeReducer()
        }
        await clipboardStore.send(.entryViewLayout(.entryOperations(.lifecycle(.operationFinished(
            sandbox.fileURL.path,
            .pasteFileMove,
            .success(()),
        )))))
        let reload = AnyCasePath<FileManagerContentAction, Void>(
            embed: { _ in
                .entryViewLayout(.entryOperations(.loading(.loadItems(
                    path: directoryPath,
                    showHidden: false,
                ))))
            },
            extract: { action in
                guard case let .entryViewLayout(.entryOperations(.loading(.loadItems(path, false)))) = action,
                      path == directoryPath
                else { return nil }
                return ()
            },
        )
        await clipboardStore.receive(reload)
        await clipboardStore.finish()

        let dropStore = TestStore(initialState: contentState) {
            FileManagerContentEntryOperationsBridgeReducer()
        }
        await dropStore.send(dropCompletion(path: sandbox.fileURL.path))
        await dropStore.finish()
        XCTAssertTrue(FileManager.default.fileExists(atPath: sandbox.originalFixture.path))
    }

    /// CTM-004-directory_reload_lifecycle: operation 중 unrelated tab 전환 후 새 active는 reload하지 않음
    /// mutation 완료 시점의 현재 active/inactive session을 다시 평가하는지 검증한다.
    /// - 검증 내용: unrelated active refresh 0회와 source/destination inactive pending
    /// - 사전 조건: unrelated Directory가 active이고 source/destination Directory는 inactive
    /// - 기대 결과: emitted reload 없음, source/destination ID만 pending
    func testEntriesMutated_afterMidOperationSwitchDoesNotRefreshUnrelatedActiveTab() async {
        let activeID = ContentTabID(rawValue: "active-unrelated")
        let sourceID = ContentTabID(rawValue: "source")
        let destinationID = ContentTabID(rawValue: "destination")
        let state = makeDirectoryReloadState(
            activeID: activeID,
            activePath: "/unrelated",
            inactiveTabs: [
                .init(id: sourceID, path: "/source", isPinned: false),
                .init(id: destinationID, path: "/destination", isPinned: true),
            ],
        )
        let store = TestStore(initialState: state) {
            FileManagerWindowRoutingReducer()
        }

        await store.send(entryMutationOutcome(.init(
            sourceParentPaths: ["/source"],
            destinationPath: "/destination",
        ))) {
            $0.pendingDirectoryReloadTabIDs = [sourceID, destinationID]
        }
        await store.finish()
    }

    /// CTM-004-directory_reload_lifecycle: source tab 종료 후에도 Window-owned EOP 후속 effect가 완료됨
    /// provider decode를 보류한 동안 source tab을 닫아 Window lifetime의 전체 downstream chain을 검증한다.
    /// - 검증 내용: dedicated busy 완료/undo 1건, active/inactive content EOP 불변,
    ///   live destination refresh와 source mirror pending
    /// - 사전 조건: `fixtures/fixtures/texts/plain/11.txt` temp copy, controlled provider,
    ///   source/destination/source mirror Directory tab
    /// - 기대 결과: source tab tombstone 없이 move 1회, dedicated EOP만 undo를 소유하고 live affected tab refresh가 유지됨
    func testEntryDrop_sourceTabCloseKeepsWindowOwnedFollowUpEffectsAlive() async throws {
        let fixture = try makeTabSwitchDropFixture()
        defer { fixture.sandbox.cleanup() }
        let providerLoadStarted = expectation(description: "provider load started")
        let provider = ControlledFileURLItemProvider(
            fileURL: fixture.sandbox.fileURL,
            loadStarted: providerLoadStarted,
        )
        let mutations = LockIsolated<[(source: URL, destination: URL)]>([])
        let reloads = LockIsolated<[[String]]>([])
        let listingLoads = LockIsolated<[String]>([])
        let store = makeTabSwitchDropStore(
            state: fixture.state,
            mutations: mutations,
            reloads: reloads,
            listingLoads: listingLoads,
        )
        // store.exhaustivity = .off: Window-owned EOP의 비동기 완료와 tab별 최종 불변식을 함께 검증한다.
        store.exhaustivity = .off

        await store.send(.sidebar(.delegate(.entryDropRequested(.init(
            target: .fixedLocation(fixture.location.id),
            providers: [provider.provider],
            isOptionDrag: false,
        )))))
        await store.skipReceivedActions()
        await fulfillment(of: [providerLoadStarted], timeout: 1)

        await store.send(.contentTabs(.close(fixture.sourceID)))
        await store.skipReceivedActions()
        listingLoads.withValue { $0.removeAll() }
        provider.complete()
        await store.finish()
        await store.skipReceivedActions()
        await store.finish()

        try assertClosedSourceDropResult(
            store: store,
            fixture: fixture,
            mutations: mutations.value,
            reloads: reloads.value,
            listingLoads: listingLoads.value,
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.sandbox.originalFixture.path))
    }

    /// CTM-004-directory_reload_lifecycle: 같은 path의 여러 inactive Directory를 모두 pending 처리함
    /// 동일 destination을 공유하는 pinned/unpinned inactive tab의 identity를 각각 유지하는지 검증한다.
    /// - 검증 내용: path-equivalent inactive ID 두 개의 pending 포함과 tab order/pinned/session snapshot 불변
    /// - 사전 조건: unrelated active Directory와 같은 path를 표시하는 pinned/unpinned inactive Directory 두 개
    /// - 기대 결과: 두 inactive ID가 모두 pending이고 active/previous/order/pinned/recentlyClosed/selection/snapshot이 보존됨
    func testEntriesMutated_samePathInactiveTabsPreserveIdentityAndAllBecomePending() async {
        let activeID = ContentTabID(rawValue: "active-unrelated")
        let pinnedID = ContentTabID(rawValue: "same-path-pinned")
        let unpinnedID = ContentTabID(rawValue: "same-path-unpinned")
        var state = makeDirectoryReloadState(
            activeID: activeID,
            activePath: "/unrelated",
            inactiveTabs: [
                .init(id: pinnedID, path: "/shared/destination", isPinned: true),
                .init(id: unpinnedID, path: "/shared/destination", isPinned: false),
            ],
        )
        state.contentTabs.previousActiveTabID = unpinnedID
        state.content.entryViewLayout.selectedIds = ["selected-entry"]
        let initialTabs = state.contentTabs
        let initialInactiveStates = state.tabContentStates
        let store = TestStore(initialState: state) {
            FileManagerWindowRoutingReducer()
        }

        await store.send(entryMutationOutcome(.init(
            sourceParentPaths: ["/source"],
            destinationPath: "/shared/destination",
        ))) {
            $0.pendingDirectoryReloadTabIDs = [pinnedID, unpinnedID]
        }

        XCTAssertEqual(store.state.contentTabs.tabs.map(\.id), initialTabs.tabs.map(\.id))
        XCTAssertEqual(store.state.contentTabs.tabs.count, initialTabs.tabs.count)
        XCTAssertEqual(store.state.contentTabs.activeTabID, initialTabs.activeTabID)
        XCTAssertEqual(store.state.contentTabs.previousActiveTabID, initialTabs.previousActiveTabID)
        XCTAssertEqual(store.state.contentTabs.tabs.map(\.isPinned), initialTabs.tabs.map(\.isPinned))
        XCTAssertEqual(store.state.contentTabs.recentlyClosed, initialTabs.recentlyClosed)
        XCTAssertEqual(store.state.content.entryViewLayout.selectedIds, ["selected-entry"])
        XCTAssertEqual(store.state.tabContentStates, initialInactiveStates)
        await store.finish()
    }

    /// CTM-004-directory_reload_lifecycle: aggregate success outcome이 없으면 lifecycle 상태를 변경하지 않음
    /// failure/rejection/no-op 경로가 pending 또는 listing reload를 만들지 않는지 검증한다.
    /// - 검증 내용: non-outcome mutation lifecycle action의 Window state 불변
    /// - 사전 조건: affected path를 표시하는 active Directory
    /// - 기대 결과: pending Set과 전체 Window state 불변, emitted action 없음
    func testMutationFailureOrNoOutcome_doesNotChangeReloadLifecycle() async {
        let activeID = ContentTabID(rawValue: "active")
        let state = makeDirectoryReloadState(activeID: activeID, activePath: "/affected")
        let store = TestStore(initialState: state) {
            FileManagerWindowRoutingReducer()
        }

        await store.send(.content(.entryViewLayout(.entryOperations(.lifecycle(.pathsMutated(["/affected"]))))))
        XCTAssertEqual(store.state, state)
        await store.finish()
    }

    /// CTM-004-directory_reload_lifecycle: 시작 tab 종료 후에도 완료된 mutation의 global refresh는 유지됨
    /// filesystem mutation 완료 전에 source tab이 닫혀도 살아 있는 affected tab의 listing 계약을 검증한다.
    /// - 검증 내용: missing source owner state는 버리되 destination active tab reload는 stable route 1회
    /// - 사전 조건: affected active Directory와 이미 제거된 source tab ID를 가진 routed outcome
    /// - 기대 결과: closed tab snapshot 재생성 없이 active destination에 routed reload가 전달됨
    func testEntriesMutated_closedStartingTabStillRefreshesAffectedLiveTab() async {
        let activeID = ContentTabID(rawValue: "active-destination")
        let closedID = ContentTabID(rawValue: "closed-source")
        let state = makeDirectoryReloadState(activeID: activeID, activePath: "/destination")
        let store = TestStore(initialState: state) {
            FileManagerWindowRoutingReducer()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
        }
        // store.exhaustivity = .off: stable reload 이후 child loading chain은 이 Window ownership 테스트 범위 밖이다.
        store.exhaustivity = .off

        await store.send(.internal(.routeContent(
            tabID: closedID,
            action: .entryViewLayout(.entryOperations(.outcome(.entriesMutated(.init(
                sourceParentPaths: ["/source"],
                destinationPath: "/destination",
            ))))),
        )))
        await store.receive(routedDirectoryReloadAction(tabID: activeID))
        await store.skipReceivedActions()
        await store.finish()

        XCTAssertNil(store.state.contentTabs.tabs[id: closedID])
        XCTAssertNil(store.state.tabContentStates[closedID])
    }

    /// CTM-004-directory_reload_lifecycle: repeated success는 같은 inactive ID를 Set으로 deduplicate함
    /// source와 destination이 같은 path이고 outcome이 반복되어도 pending 수명이 결정적인지 검증한다.
    /// - 검증 내용: 동일 affected inactive ID의 repeated insertion
    /// - 사전 조건: unrelated active와 affected inactive Directory 하나
    /// - 기대 결과: pending Set에 affected ID 한 개만 유지
    func testEntriesMutated_repeatedOutcomeDeduplicatesPendingTabID() async {
        let activeID = ContentTabID(rawValue: "active")
        let pendingID = ContentTabID(rawValue: "pending")
        let state = makeDirectoryReloadState(
            activeID: activeID,
            activePath: "/unrelated",
            inactiveTabs: [.init(id: pendingID, path: "/affected", isPinned: false)],
        )
        let impact = EntryOperationsMutationImpact(
            sourceParentPaths: ["/affected"],
            destinationPath: "/affected",
        )
        let store = TestStore(initialState: state) {
            FileManagerWindowRoutingReducer()
        }

        await store.send(entryMutationOutcome(impact)) {
            $0.pendingDirectoryReloadTabIDs = [pendingID]
        }
        await store.send(entryMutationOutcome(impact))

        XCTAssertEqual(store.state.pendingDirectoryReloadTabIDs, [pendingID])
        await store.finish()
    }

    /// CTM-004-directory_reload_lifecycle: pending tab 선택은 content swap 뒤 한 번 refresh하고 선택 ID만 제거함
    /// 기존 folder handoff가 저장 session을 먼저 복원한 후 listing load를 한 번 수행하는지 검증한다.
    /// - 검증 내용: selected content path, tab metadata, recentlyClosed, remaining pending ID
    /// - 사전 조건: pending inactive Directory 두 개와 별도 active Directory session
    /// - 기대 결과: selected path restore 후 applyNavigationState 1회, selected ID만 pending에서 제거
    func testSelectPendingDirectory_swapsBeforeSingleRefreshAndRemovesOnlySelectedID() async {
        let previousID = ContentTabID(rawValue: "previous")
        let selectedID = ContentTabID(rawValue: "selected")
        let remainingID = ContentTabID(rawValue: "remaining")
        let selectedPath = "/selected"
        var state = makeDirectoryReloadState(
            activeID: previousID,
            activePath: "/previous",
            inactiveTabs: [
                .init(id: selectedID, path: selectedPath, isPinned: false),
                .init(id: remainingID, path: "/remaining", isPinned: true),
            ],
        )
        state.contentTabs.previousActiveTabID = previousID
        state.contentTabs.activeTabID = selectedID
        state.pendingDirectoryReloadTabIDs = [selectedID, remainingID]
        let initialTabs = state.contentTabs.tabs
        let initialRecentlyClosed = state.contentTabs.recentlyClosed
        let store = TestStore(initialState: state) {
            FileManagerWindowRoutingReducer()
        }
        // 기존 tab handoff의 inspector/sidebar 파생 상태 변화는 최종 불변식으로 검증한다.
        store.exhaustivity = .off

        await store.send(.contentTabs(.setCurrent(selectedID)))
        let selectedDirectoryRefresh = AnyCasePath<FileManagerFeature.Action, Void>(
            embed: { _ in .content(.internal(.applyNavigationState(.folder(selectedPath)))) },
            extract: { action in
                guard case let .content(.internal(.applyNavigationState(.folder(path)))) = action,
                      path == selectedPath
                else { return nil }
                return ()
            },
        )
        await store.receive(selectedDirectoryRefresh)

        XCTAssertEqual(store.state.content.navigation.navigationState, .folder(selectedPath))
        XCTAssertEqual(store.state.contentTabs.tabs, initialTabs)
        XCTAssertEqual(store.state.contentTabs.recentlyClosed, initialRecentlyClosed)
        XCTAssertEqual(store.state.pendingDirectoryReloadTabIDs, [remainingID])
        await store.finish()
    }

    /// CTM-004-directory_reload_lifecycle: close, missing replacement, non-directory 전환은 pending ID를 정리함
    /// tab lifecycle의 세 cleanup 경계가 inactive snapshot 재생성 없이 deterministic하게 동작하는지 검증한다.
    /// - 검증 내용: close ID 제거, replacement 교집합, Home page transition cleanup
    /// - 사전 조건: 각 lifecycle 대상 ID가 pending Set에 포함됨
    /// - 기대 결과: 각 경계에서 존재하는 Directory ID만 pending에 유지
    func testPendingDirectoryReload_cleanupForCloseReplacementAndPageTransition() async {
        let activeID = ContentTabID(rawValue: "active")
        let closedID = ContentTabID(rawValue: "closed")
        var closeState = makeDirectoryReloadState(
            activeID: activeID,
            activePath: "/active",
            inactiveTabs: [.init(id: closedID, path: "/closed", isPinned: false)],
        )
        let closeWindowID = UUID()
        let closeRequestID = UUID()
        closeState.windowID = closeWindowID
        closeState.pendingDirectoryReloadTabIDs = [closedID]
        let closeClient = UndoManagerClient(
            registerUndo: { _, _, _ in },
            undo: { _, _ in .init(didInvoke: false, availability: .init()) },
            redo: { _, _ in .init(didInvoke: false, availability: .init()) },
            invalidateOwner: { receivedWindowID, _ in
                XCTAssertEqual(receivedWindowID, closeWindowID)
                return .init(succeeded: true, availability: .init())
            },
        )
        let closeStore = TestStore(initialState: closeState) {
            FileManagerFeature()
        } withDependencies: {
            $0.undoManagerClient = closeClient
            $0.uuid = .constant(closeRequestID)
        }
        // 비포괄적: full feature의 파생 projection보다 two-phase close 완료와 pending cleanup을 검증한다.
        closeStore.exhaustivity = .off
        await closeStore.send(.contentTabs(.requestClose(closedID)))
        await closeStore.receive(\.internal.undoManagerOwnerInvalidationFinished)
        await closeStore.receive(\.contentTabs.commitClose)
        await closeStore.finish()
        XCTAssertNil(closeStore.state.contentTabs.tabs[id: closedID])
        XCTAssertNil(closeStore.state.tabContentStates[closedID])
        XCTAssertEqual(closeStore.state.pendingDirectoryReloadTabIDs, [])

        let retainedID = ContentTabID(rawValue: "retained")
        let missingID = ContentTabID(rawValue: "missing")
        var replacementState = makeDirectoryReloadState(
            activeID: retainedID,
            activePath: "/retained",
            inactiveTabs: [.init(id: missingID, path: "/missing", isPinned: true)],
            activeIsPinned: true,
        )
        replacementState.pendingDirectoryReloadTabIDs = [retainedID, missingID]
        guard let retainedTab = replacementState.contentTabs.tabs[id: retainedID] else {
            return XCTFail("retained tab fixture must exist")
        }
        let restored = ContentTabState(
            tabs: [retainedTab],
            activeTabID: retainedID,
        )
        let replacementStore = TestStore(initialState: replacementState) {
            FileManagerWindowRoutingReducer()
        }
        // pinned replacement의 projection 파생 변화는 pending 교집합과 tab 존재성으로 검증한다.
        replacementStore.exhaustivity = .off
        await replacementStore.send(.applyPinnedContentTabs(restored))
        XCTAssertEqual(replacementStore.state.pendingDirectoryReloadTabIDs, [retainedID])
        XCTAssertNil(replacementStore.state.contentTabs.tabs[id: missingID])

        var transitionState = replacementStore.state
        transitionState.contentTabs.tabs[id: retainedID]?.page = .home
        transitionState.contentTabs.tabs[id: retainedID]?.anchor = .homeDefault
        let transitionStore = TestStore(initialState: transitionState) {
            FileManagerWindowRoutingReducer()
        }
        // page transition의 projection 파생 변화는 non-directory pending cleanup 결과로 검증한다.
        transitionStore.exhaustivity = .off
        await transitionStore.send(.contentTabs(.updateActivePageAnchor(retainedID, .homeDefault)))
        XCTAssertEqual(transitionStore.state.pendingDirectoryReloadTabIDs, [])
        await transitionStore.finish()
    }

    private struct TabSwitchDropFixture {
        let sandbox: FileManagerFixtureSandbox
        let sourceID: ContentTabID
        let destinationID: ContentTabID
        let sourceMirrorID: ContentTabID
        let location: FileManagerFixedLocationItem
        let state: FileManagerFeature.State
    }

    private func makeTabSwitchDropFixture() throws -> TabSwitchDropFixture {
        let sandbox = try FileManagerFixtureSandbox.copyingFileWithDirectorySymlink(
            from: "fixtures/fixtures/texts/plain/11.txt",
        )
        let destination = sandbox.root.appendingPathComponent("Destination", isDirectory: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let sourceID = ContentTabID(rawValue: "drop-source")
        let destinationID = ContentTabID(rawValue: "drop-destination")
        let sourceMirrorID = ContentTabID(rawValue: "drop-source-mirror")
        let sourcePath = sandbox.fileURL.deletingLastPathComponent().path
        var state = makeDirectoryReloadState(
            activeID: sourceID,
            activePath: sourcePath,
            inactiveTabs: [
                .init(id: destinationID, path: destination.path, isPinned: false),
                .init(id: sourceMirrorID, path: sourcePath, isPinned: false),
            ],
        )
        let location = FileManagerFixedLocationItem(
            id: "drop-destination",
            title: "Destination",
            path: destination.path,
            iconName: "folder",
            accessibilityLabel: "Destination",
        )
        state.sidebar.setFixedLocationItems([location])
        return .init(
            sandbox: sandbox,
            sourceID: sourceID,
            destinationID: destinationID,
            sourceMirrorID: sourceMirrorID,
            location: location,
            state: state,
        )
    }

    private func makeTabSwitchDropStore(
        state: FileManagerFeature.State,
        mutations: LockIsolated<[(source: URL, destination: URL)]>,
        reloads: LockIsolated<[[String]]>,
        listingLoads: LockIsolated<[String]> = .init([]),
    ) -> TestStore<FileManagerFeature.State, FileManagerFeature.Action> {
        TestStore(initialState: state) {
            FileManagerFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
            var client = EntryFileOpsClient.previewValue
            client.fileExists = { _ in false }
            client.moveFile = { source, destination in
                try FileManager.default.moveItem(at: source, to: destination)
                mutations.withValue { $0.append((source, destination)) }
            }
            client.postFileSystemChanged = { paths in reloads.withValue { $0.append(paths) } }
            $0.entryFileOpsClient = client
            var loadingClient = EntryLoadingClient.testValue
            loadingClient.loadItems = { url, _ in
                listingLoads.withValue { $0.append(url.path) }
                return []
            }
            $0.entryLoadingClient = loadingClient
            $0.undoManagerClient = UndoManagerClient(
                registerUndo: { _, _, _ in },
                undo: { _, _ in .init(didInvoke: false, availability: .init()) },
                redo: { _, _ in .init(didInvoke: false, availability: .init()) },
            )
        }
    }

    private func assertClosedSourceDropResult(
        store: TestStore<FileManagerFeature.State, FileManagerFeature.Action>,
        fixture: TabSwitchDropFixture,
        mutations: [(source: URL, destination: URL)],
        reloads: [[String]],
        listingLoads: [String],
    ) throws {
        let sourcePath = fixture.sandbox.fileURL.path
        let destinationURL = URL(fileURLWithPath: fixture.location.path)
            .appendingPathComponent(fixture.sandbox.fileURL.lastPathComponent)
        let dedicatedOperations = store.state.sidebarEntryDropOperations

        XCTAssertEqual(mutations.count, 1)
        XCTAssertEqual(mutations.first?.source.path, sourcePath)
        XCTAssertEqual(mutations.first?.destination, destinationURL)
        XCTAssertFalse(FileManager.default.fileExists(atPath: sourcePath))
        XCTAssertTrue(FileManager.default.fileExists(atPath: destinationURL.path))
        XCTAssertEqual(dedicatedOperations.itemStates[sourcePath]?.isBusy, false)
        XCTAssertNil(dedicatedOperations.itemStates[sourcePath]?.lastError)
        XCTAssertEqual(dedicatedOperations.undoRecords.count, 1)
        XCTAssertFalse(dedicatedOperations.isLoading)
        XCTAssertTrue(store.state.content.entryViewLayout.entryOperations.itemStates.isEmpty)
        XCTAssertTrue(store.state.content.entryViewLayout.entryOperations.undoRecords.isEmpty)
        XCTAssertFalse(store.state.content.entryViewLayout.entryOperations.isLoading)
        let sourceMirrorOperations = try XCTUnwrap(
            store.state.tabContentStates[fixture.sourceMirrorID]?.entryViewLayout.entryOperations,
        )
        XCTAssertTrue(sourceMirrorOperations.itemStates.isEmpty)
        XCTAssertTrue(sourceMirrorOperations.undoRecords.isEmpty)
        XCTAssertFalse(sourceMirrorOperations.isLoading)
        XCTAssertNil(store.state.contentTabs.tabs[id: fixture.sourceID])
        XCTAssertNil(store.state.tabContentStates[fixture.sourceID])
        XCTAssertEqual(store.state.contentTabs.activeTabID, fixture.destinationID)
        XCTAssertEqual(store.state.pendingDirectoryReloadTabIDs, [fixture.sourceMirrorID])
        XCTAssertEqual(listingLoads, [fixture.location.path])
        XCTAssertTrue(reloads.isEmpty)
    }

    private func waitUntilUndoReplayCondition(
        timeout: Duration = .seconds(2),
        condition: @MainActor () -> Bool,
    ) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while !condition() {
            guard clock.now < deadline else {
                XCTFail("Timed out waiting for undo replay condition")
                return
            }
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    private func dropCompletion(path: String) -> FileManagerContentAction {
        .entryViewLayout(.entryOperations(.lifecycle(.dropOperationFinished(
            path,
            .pasteFileMove,
            .success(()),
        ))))
    }

    private struct DirectoryTabFixture {
        let id: ContentTabID
        let path: String
        let isPinned: Bool
    }

    private func routedDirectoryReloadAction(
        tabID: ContentTabID,
    ) -> AnyCasePath<FileManagerFeature.Action, Void> {
        AnyCasePath(
            embed: { _ in
                .internal(.routeContent(
                    tabID: tabID,
                    action: .internal(.reloadDirectoryListing),
                ))
            },
            extract: { action in
                guard case let .internal(.routeContent(receivedTabID, .internal(.reloadDirectoryListing))) = action,
                      receivedTabID == tabID
                else { return nil }
                return ()
            },
        )
    }

    private func entryMutationOutcome(
        _ impact: EntryOperationsMutationImpact,
    ) -> FileManagerFeature.Action {
        .content(.entryViewLayout(.entryOperations(.outcome(.entriesMutated(impact)))))
    }

    private func makeDirectoryReloadState(
        activeID: ContentTabID,
        activePath: String,
        inactiveTabs: [DirectoryTabFixture] = [],
        activeIsPinned: Bool = false,
    ) -> FileManagerFeature.State {
        var tabs = [
            ContentTabItem(
                id: activeID,
                page: .directory,
                anchor: .directory(path: activePath),
                isPinned: activeIsPinned,
                title: "Active",
                iconName: "folder",
            ),
        ]
        tabs.append(contentsOf: inactiveTabs.map { fixture in
            ContentTabItem(
                id: fixture.id,
                page: .directory,
                anchor: .directory(path: fixture.path),
                isPinned: fixture.isPinned,
                title: fixture.path,
                iconName: "folder",
            )
        })

        var state = FileManagerFeature.State()
        state.contentTabs = ContentTabState(
            tabs: .init(uniqueElements: tabs),
            activeTabID: activeID,
        )
        state.content.navigation.seedInitialFolderPath(activePath)
        state.tabContentStates = [activeID: state.content]
        for fixture in inactiveTabs {
            var content = FileManagerContentFeature.State()
            content.navigation.seedInitialFolderPath(fixture.path)
            state.tabContentStates[fixture.id] = content
        }
        state.syncContentTabSidebarItems()
        return state
    }

    private func makeEntryDropState(
        activeID: ContentTabID,
        inactiveID: ContentTabID? = nil,
        inactiveIsPinned: Bool = true,
    ) -> FileManagerFeature.State {
        var tabs = [ContentTabItem(
            id: activeID,
            page: .directory,
            anchor: .directory(path: "/active/anchor"),
            isPinned: false,
            title: "Active",
            iconName: "folder",
        )]
        if let inactiveID {
            tabs.append(ContentTabItem(
                id: inactiveID,
                page: .directory,
                anchor: .directory(path: "/inactive/anchor"),
                isPinned: inactiveIsPinned,
                title: "Inactive",
                iconName: "folder",
            ))
        }

        var state = FileManagerFeature.State()
        state.contentTabs = ContentTabState(
            tabs: .init(uniqueElements: tabs),
            activeTabID: activeID,
        )
        state.content.navigation.seedInitialFolderPath("/active/latest")
        state.tabContentStates = [activeID: state.content]
        state.syncContentTabSidebarItems()
        return state
    }

    private func assertEntryDropForwarded(
        target: FileManagerSidebarEntryDropTarget,
        providers: [NSItemProvider],
        isOptionDrag: Bool,
        destinationPath: String,
        initialState: FileManagerFeature.State,
        file: StaticString = #filePath,
        line: UInt = #line,
    ) async {
        let request = FileManagerSidebarEntryDropRequest(
            target: target,
            providers: providers,
            isOptionDrag: isOptionDrag,
        )
        let store = TestStore(initialState: initialState) {
            FileManagerWindowCommandRoutingReducer()
        }
        let expectedHandleDrop = AnyCasePath<FileManagerFeature.Action, Void>(
            embed: { _ in
                FileManagerFeature.Action.internal(.sidebarEntryDrop(.routing(.handleDrop(
                    providers: providers,
                    destinationPath: destinationPath,
                    isOptionDrag: isOptionDrag,
                ))))
            },
            extract: { action in
                guard case let .internal(.sidebarEntryDrop(.routing(.handleDrop(
                    receivedProviders,
                    receivedDestinationPath,
                    receivedIsOptionDrag,
                )))) = action
                else { return nil }
                XCTAssertEqual(receivedProviders.count, providers.count, file: file, line: line)
                XCTAssertTrue(
                    zip(receivedProviders, providers).allSatisfy { $0 === $1 },
                    "provider identity and order must be preserved",
                    file: file,
                    line: line,
                )
                XCTAssertEqual(receivedDestinationPath, destinationPath, file: file, line: line)
                XCTAssertEqual(receivedIsOptionDrag, isOptionDrag, file: file, line: line)
                return ()
            },
        )

        await store.send(.sidebar(.delegate(.entryDropRequested(request))))
        await store.receive(expectedHandleDrop)
        XCTAssertEqual(store.state, initialState, "drop routing must preserve Window state", file: file, line: line)
        await store.finish()
    }

    private func assertEntryDropRejected(
        target: FileManagerSidebarEntryDropTarget,
        initialState: FileManagerFeature.State,
        file: StaticString = #filePath,
        line: UInt = #line,
    ) async {
        let request = FileManagerSidebarEntryDropRequest(
            target: target,
            providers: [NSItemProvider()],
            isOptionDrag: false,
        )
        let store = TestStore(initialState: initialState) {
            FileManagerWindowCommandRoutingReducer()
        }

        await store.send(.sidebar(.delegate(.entryDropRequested(request))))
        XCTAssertEqual(store.state, initialState, "rejected drop must preserve Window state", file: file, line: line)
        await store.finish()
    }

    // MARK: - CTM-004-sidebar_duplicate_routing

    /// CTM-004-sidebar_duplicate_routing: Sidebar clicked ID duplicateContentTab delegate가 request로 전달됨
    /// FileManagerWindowRoutingReducer가 sidebar delegate를 .request(.duplicateContentTab(sourceID))로 변환하고,
    /// FileManagerWindowCommandRoutingReducer.handleDuplicateContentTabRequested를 통해
    /// .contentTabs(.duplicate) child action으로 이어져 새 tab row가 생성된다.
    /// - 검증 내용: sidebar delegate 전송 후 content tab row에 duplicateID가 추가됨
    /// - 사전 조건: Directory tab이 sidebar에 있는 상태
    /// - 기대 결과: 새 tab row가 추가되고 active가 duplicate로 전환됨
    func testSidebarDelegate_duplicateContentTab_routesToRequest() async {
        let directoryID = ContentTabID()
        let directoryPath = "/Users/test/Desktop"
        var state = FileManagerFeature.State()
        state.contentTabs = ContentTabState(
            tabs: [ContentTabItem(
                id: directoryID,
                page: .directory,
                anchor: .directory(path: directoryPath),
                isPinned: false,
                title: "Desktop",
                iconName: "folder",
            )],
            activeTabID: directoryID,
            recentlyClosed: nil,
        )
        state.content.navigation.seedInitialFolderPath(directoryPath)
        state.syncActiveTabContentState()
        state.syncContentTabSidebarItems()

        let store = TestStore(initialState: state) {
            FileManagerFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
            var client = FileManagerClient.testValue
            client.fileExistsWithIsDirectory = { path, isDir in
                if path == directoryPath {
                    isDir?.pointee = true
                    return true
                }
                return false
            }
            $0.fileManagerClient = client
            $0.fileChangeGatewayClient.observeEvents = {
                AsyncStream { continuation in continuation.finish() }
            }
        }
        store.exhaustivity = .off

        await store.send(.sidebar(.delegate(.duplicateContentTab(directoryID))))
        await store.skipReceivedActions()

        // Tab row가 생성되어 2개가 됨
        XCTAssertEqual(store.state.contentTabs.tabs.count, 2)
        // Duplicate가 active로 전환
        XCTAssertNotEqual(store.state.contentTabs.activeTabID, directoryID)
        await store.finish()
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
                    kind: .trash,
                ),
            ]
        }
    }
}

private final class ControlledFileURLItemProvider: @unchecked Sendable {
    let provider = NSItemProvider()

    private let fileURL: URL
    private let lock = NSLock()
    private var completionHandler: ((Data?, Error?) -> Void)?

    init(fileURL: URL, loadStarted: XCTestExpectation) {
        self.fileURL = fileURL
        provider.registerDataRepresentation(
            forTypeIdentifier: UTType.fileURL.identifier,
            visibility: .all,
        ) { [weak self] completionHandler in
            self?.store(completionHandler)
            loadStarted.fulfill()
            return Progress(totalUnitCount: 1)
        }
    }

    func complete() {
        lock.lock()
        let completionHandler = completionHandler
        self.completionHandler = nil
        lock.unlock()
        completionHandler?(Data(fileURL.absoluteString.utf8), nil)
    }

    private func store(_ completionHandler: @escaping (Data?, Error?) -> Void) {
        lock.lock()
        self.completionHandler = completionHandler
        lock.unlock()
    }
}

private actor CTM004ReplayFileOperationGate {
    private var suspension: CheckedContinuation<Void, Never>?
    private var suspensionWaiters: [CheckedContinuation<Void, Never>] = []
    private var count = 0

    func suspend() async {
        count += 1
        await withCheckedContinuation { continuation in
            suspension = continuation
            suspensionWaiters.forEach { $0.resume() }
            suspensionWaiters.removeAll()
        }
    }

    func waitUntilSuspended() async {
        guard suspension == nil else { return }
        await withCheckedContinuation { continuation in
            suspensionWaiters.append(continuation)
        }
    }

    func invocationCount() -> Int {
        count
    }

    func resume() {
        suspension?.resume()
        suspension = nil
    }
}
