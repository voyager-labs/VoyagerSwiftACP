import ComposableArchitecture
@testable import Voyager
import VoyagerFeaturesContentPageNavigation
import VoyagerFeaturesEntryArrangements
import VoyagerFeaturesEntryOperations
@testable import VoyagerPagesFileManager
import VoyagerPagesOnboarding
import VoyagerShared
import VoyagerWidgetsEntryViewLayout
import XCTest

/// 윈도우 관리자 계약 — 포커스 윈도우로의 명령 팬아웃과 미사용 시 no-op를 검증.
@MainActor
final class WindowManagerFeatureContractTests: XCTestCase {
    /// testApplyAppPreferencesFansOutToAllWindows 테스트 동작을 검증한다.
    func testApplyAppPreferencesFansOutToAllWindows() async {
        let firstID = UUID()
        let secondID = UUID()

        var initialState = WindowManagerFeature.State()
        initialState.windows = [
            WindowSessionState(id: firstID, window: .makeInitial(path: "/a")),
            WindowSessionState(id: secondID, window: .makeInitial(path: "/b")),
        ]

        var preferences = Voyager.AppPreferencesState()
        preferences.viewLayout = EntryViewLayoutState.Mode.grid
        preferences.groupKey = GroupKey.kind

        let store = TestStore(initialState: initialState) {
            WindowManagerFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
            $0.contentTabPinnedRecordClient.loadStore = { _ in ContentTabPinnedRecordStore() }
            $0.contentTabPinnedRecordClient.saveStore = { _, _ in }
            $0.onboardingWindowClient.showIfNeeded = { false }
            $0.fileManagerWindowClient.open = { _ in }
        }
        store.exhaustivity = .off

        await store.send(.lifecycle(.applyAppPreferences(preferences))) {
            $0.appPreferences = preferences
        }
    }

    /// Sidebar Locations 표시 설정은 같은 앱의 다른 열린 창에 즉시 반영된다.
    func testFixedLocationVisibilityChangeFansOutToOtherWindows() async {
        let firstID = UUID()
        let secondID = UUID()
        let location = FileManagerFixedLocationItem(
            id: "fixed-location-projects",
            title: "Projects",
            path: "/Users/test/Projects",
            iconName: "folder",
            accessibilityLabel: "Projects",
        )
        let hiddenIDs: Set<FileManagerFixedLocationItem.ID> = [location.id]
        var firstWindow = WindowSessionState(id: firstID, window: .makeInitial(path: "/a"))
        firstWindow.window.sidebar.setFixedLocationItems([location], hiddenIDs: hiddenIDs)
        var secondWindow = WindowSessionState(id: secondID, window: .makeInitial(path: "/b"))
        secondWindow.window.sidebar.setFixedLocationItems([location])
        var initialState = WindowManagerFeature.State()
        initialState.windows = [firstWindow, secondWindow]
        let store = TestStore(initialState: initialState) {
            WindowManagerFeature()
        }
        store.exhaustivity = .off

        await store.send(.windows(.element(
            id: firstID,
            action: .window(.delegate(.fixedLocationVisibilityChanged(hiddenIDs))),
        )))
        await store.receive(.windows(.element(
            id: secondID,
            action: .window(.applyHiddenFixedLocationIDs(hiddenIDs)),
        ))) { state in
            state.windows[id: secondID]?.window.sidebar.setFixedLocationItems(
                [location],
                hiddenIDs: hiddenIDs,
            )
        }

        XCTAssertEqual(store.state.windows[id: firstID]?.window.sidebar.fixedLocationItems.isEmpty, true)
        XCTAssertEqual(store.state.windows[id: secondID]?.window.sidebar.fixedLocationItems.isEmpty, true)
    }

    /// app preference 갱신은 기존 열린 창의 Sidebar 크기/표시 상태를 덮어쓰지 않는다.
    /// 새 창은 생성 시 app preference를 적용하지만, 이미 열린 창은 window-local Sidebar 상태를 유지해야 한다.
    func testApplyAppPreferencesPreservesExistingWindowSidebarState() async {
        let firstID = UUID()
        let secondID = UUID()

        var firstWindow = WindowSessionState(id: firstID, window: .makeInitial(path: "/a"))
        firstWindow.window.sidebar.sidebarVisible = true

        var secondWindow = WindowSessionState(id: secondID, window: .makeInitial(path: "/b"))
        secondWindow.window.sidebar.sidebarVisible = false

        var initialState = WindowManagerFeature.State()
        initialState.windows = [firstWindow, secondWindow]

        var preferences = Voyager.AppPreferencesState()
        preferences.sidebarVisible = true
        preferences.sidebarWidth = 300
        preferences.viewLayout = EntryViewLayoutState.Mode.grid

        let store = TestStore(initialState: initialState) {
            WindowManagerFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
            $0.contentTabPinnedRecordClient.loadStore = { _ in ContentTabPinnedRecordStore() }
            $0.contentTabPinnedRecordClient.saveStore = { _, _ in }
            $0.onboardingWindowClient.showIfNeeded = { false }
            $0.fileManagerWindowClient.open = { _ in }
        }
        store.exhaustivity = .off

        await store.send(.lifecycle(.applyAppPreferences(preferences))) {
            $0.appPreferences = preferences
        }

        var firstPackagePreferences = preferences.toPackageState()
        firstPackagePreferences.sidebarVisible = true
        firstPackagePreferences.sidebarWidth = 220
        await store.receive { action in
            guard case let .windows(.element(
                id: id,
                action: .window(.applyAppPreferences(preferences)),
            )) = action else {
                return false
            }
            return id == firstID && preferences == firstPackagePreferences
        }

        var secondPackagePreferences = preferences.toPackageState()
        secondPackagePreferences.sidebarVisible = false
        secondPackagePreferences.sidebarWidth = 220
        await store.receive { action in
            guard case let .windows(.element(
                id: id,
                action: .window(.applyAppPreferences(preferences)),
            )) = action else {
                return false
            }
            return id == secondID && preferences == secondPackagePreferences
        }
    }

    /// 온보딩 완료 후 completion handoff 경로에서 newWindow가 정상적으로 FMW를 생성하는지 검증.
    /// showIfNeeded가 false(온보딩 불필요/완료)를 반환하면 openWindowSession이 윈도우를 생성하고
    /// fileManagerWindowClient.open을 호출해야 한다.
    /// 이 테스트는 Task 1의 save→open→close 시퀀싱 이후, 라이브 앱/윈도우 경로를 통해
    /// FMW가 성공적으로 열리는지 증명한다.
    /// - 검증 내용: onboardingRequired=false일 때 newWindow 액션으로 윈도우 생성 및 client.open 호출
    /// - 사전 조건: 빈 윈도우 상태, onboardingWindowClient.showIfNeeded = false
    /// - 기대 결과: windows.count == 1, focusedWindowID == newID, openCallCount == 1
    func testNewWindowSucceedsAfterOnboardingComplete() async {
        let newID = UUID()
        let openedIDs = LockIsolated<[UUID]>([])

        let store = TestStore(initialState: WindowManagerFeature.State()) {
            WindowManagerFeature()
        } withDependencies: {
            $0.uuid = .constant(newID)
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
            $0.contentTabPinnedRecordClient.loadStore = { _ in ContentTabPinnedRecordStore() }
            $0.contentTabPinnedRecordClient.saveStore = { _, _ in }
            $0.onboardingWindowClient.showIfNeeded = { false }
            $0.fileManagerWindowClient.open = { id in
                openedIDs.withValue { $0.append(id) }
            }
        }
        store.exhaustivity = .off

        // makeWindowSession에서 pinnedRecords가 없으므로 기본 Home tab으로 fallback
        await store.send(.file(.newWindow(path: nil))) {
            $0.windows.append(.init(id: newID, window: .makeInitial(path: nil)))
            $0.focusedWindowID = newID
        }

        await store.finish()

        XCTAssertEqual(openedIDs.value.count, 1, "fileManagerWindowClient.open은 온보딩 완료 후 정확히 한 번 호출되어야 한다")
        XCTAssertEqual(openedIDs.value.first, newID, "open에 전달된 ID는 생성된 윈도우 ID와 일치해야 한다")
    }

    /// Default window(path == nil)가 Home shell을 즉시 생성하고,
    /// async bootstrap effect가 pinned record store를 로드하여 pinned tab을 적용함을 검증한다.
    /// - 검증 내용: pinned record 1개 load → window에 pinned tab 1개 포함
    /// - 사전 조건: contentTabPinnedRecordClient.loadStore가 1개 pinned record 반환
    /// - 기대 결과: window state에 isPinned=true인 tab 1개 존재
    func testDefaultWindowBootstrapRestoresPinnedRecords() async {
        let newID = UUID()
        let pinnedStore = ContentTabPinnedRecordStore(records: [
            ContentTabPinnedRecord(
                id: "dir-1",
                page: .directory,
                anchor: .directory(path: "/Users/test/Documents"),
                title: "Documents",
                iconName: "folder",
                pinnedAt: Date(timeIntervalSince1970: 443),
            ),
        ])

        let store = TestStore(initialState: WindowManagerFeature.State()) {
            WindowManagerFeature()
        } withDependencies: {
            $0.uuid = .constant(newID)
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
            $0.contentTabPinnedRecordClient.loadStore = { _ in pinnedStore }
            $0.contentTabPinnedRecordClient.saveStore = { _, _ in }
            $0.fileManagerClient.fileExistsWithIsDirectory = { path, isDirectory in
                guard path == "/Users/test/Documents" else { return false }
                isDirectory?.pointee = ObjCBool(true)
                return true
            }
            $0.onboardingWindowClient.showIfNeeded = { false }
            $0.fileManagerWindowClient.open = { _ in }
        }
        store.exhaustivity = .off

        await store.send(.file(.newWindow(path: nil)))
        await store.receive(\.defaultWindowBootstrapCompleted)
        await store.receive { action in
            guard case let .windows(.element(id: id, action: .window(.applyPinnedContentTabs))) = action
            else {
                return false
            }
            return id == newID
        }
        await store.finish()

        let window = store.state.windows.first?.window
        XCTAssertNotNil(window, "window가 생성되어야 함")
        XCTAssertEqual(window?.contentTabs.tabs.count, 2, "pinned tab 1개와 focused Home tab 1개가 있어야 함")
        XCTAssertEqual(window?.contentTabs.tabs.filter(\.isPinned).map(\.id.rawValue), ["dir-1"])
        XCTAssertEqual(window?.contentTabs.tabs[id: ContentTabID(rawValue: "dir-1")]?.page, .directory)
        XCTAssertEqual(window?.contentTabs.tabs[id: ContentTabID(rawValue: "dir-1")]?.title, "Documents")
        XCTAssertEqual(
            window?.contentTabs.tabs[id: window?.contentTabs.activeTabID ?? ContentTabID(rawValue: "")]?.page,
            .home,
        )
    }

    /// Collection window도 Home shell과 collection navigation을 먼저 구성한 뒤 pinned bootstrap을 비동기로 적용한다.
    func testCollectionWindowStartsDefaultPinnedBootstrap() async {
        let newID = UUID()
        let collectionURL = URL(fileURLWithPath: "/Users/test/Saved.voyagercollection")
        let loadCount = LockIsolated(0)
        let pinnedStore = ContentTabPinnedRecordStore(records: [
            ContentTabPinnedRecord(
                id: "dir-1",
                page: .directory,
                anchor: .directory(path: "/Users/test/Documents"),
                title: "Documents",
                iconName: "folder",
                pinnedAt: Date(timeIntervalSince1970: 443),
            ),
        ])
        let store = TestStore(initialState: WindowManagerFeature.State()) {
            WindowManagerFeature()
        } withDependencies: {
            $0.uuid = .constant(newID)
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
            $0.contentTabPinnedRecordClient.loadStore = { _ in
                loadCount.withValue { $0 += 1 }
                return pinnedStore
            }
            $0.contentTabPinnedRecordClient.saveStore = { _, _ in }
            $0.fileManagerClient.fileExistsWithIsDirectory = { path, isDirectory in
                guard path == "/Users/test/Documents" else { return false }
                isDirectory?.pointee = ObjCBool(true)
                return true
            }
            $0.onboardingWindowClient.showIfNeeded = { false }
            $0.fileManagerWindowClient.open = { _ in }
        }
        store.exhaustivity = .off

        await store.send(.file(.openCollectionFile(collectionURL)))
        XCTAssertEqual(store.state.windows.count, 1)
        XCTAssertTrue(store.state.windows.first?.window.contentTabs.tabs.filter(\.isPinned).isEmpty == true)

        await store.receive(\.defaultWindowBootstrapCompleted)
        await store.receive { action in
            guard case let .windows(.element(id: id, action: .window(.applyPinnedContentTabs))) = action
            else {
                return false
            }
            return id == newID
        }
        await store.finish()

        XCTAssertEqual(loadCount.value, 1)
        XCTAssertEqual(
            store.state.windows.first?.window.contentTabs.tabs.filter(\.isPinned).map(\.id.rawValue),
            ["dir-1"],
        )
    }

    /// Default window의 async bootstrap은 삭제된 pinned Directory record를 제외하고 compact save한다.
    /// 삭제된 대상이 placeholder tab으로 반복 복원되지 않도록 WindowManager의 파일 존재 검증과 compaction을 검증한다.
    /// - 검증 내용: valid record만 window에 복원, compacted store 저장
    /// - 사전 조건: valid directory 1개 + deleted directory 1개
    /// - 기대 결과: deleted record 제외 및 saveStore 1회 호출
    func testDefaultWindowBootstrapDropsDeletedPinnedDirectoryRecordsAndCompactsStore() async {
        let newID = UUID()
        let savedStores = LockIsolated<[ContentTabPinnedRecordStore]>([])
        let pinnedStore = ContentTabPinnedRecordStore(records: [
            ContentTabPinnedRecord(
                id: "valid-dir",
                page: .directory,
                anchor: .directory(path: "/Users/test/Documents"),
                title: "Documents",
                iconName: "folder",
                pinnedAt: Date(timeIntervalSince1970: 443),
            ),
            ContentTabPinnedRecord(
                id: "deleted-dir",
                page: .directory,
                anchor: .directory(path: "/Users/test/Deleted"),
                title: "Deleted",
                iconName: "folder",
                pinnedAt: Date(timeIntervalSince1970: 444),
            ),
        ])

        let store = TestStore(initialState: WindowManagerFeature.State()) {
            WindowManagerFeature()
        } withDependencies: {
            $0.uuid = .constant(newID)
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
            $0.contentTabPinnedRecordClient.loadStore = { _ in pinnedStore }
            $0.contentTabPinnedRecordClient.saveStore = { store, _ in
                savedStores.withValue { $0.append(store) }
            }
            $0.fileManagerClient.fileExistsWithIsDirectory = { path, isDirectory in
                guard path == "/Users/test/Documents" else { return false }
                isDirectory?.pointee = ObjCBool(true)
                return true
            }
            $0.onboardingWindowClient.showIfNeeded = { false }
            $0.fileManagerWindowClient.open = { _ in }
        }
        store.exhaustivity = .off

        await store.send(.file(.newWindow(path: nil)))
        await store.receive(\.defaultWindowBootstrapCompleted)
        await store.receive { action in
            guard case let .windows(.element(id: id, action: .window(.applyPinnedContentTabs))) = action
            else {
                return false
            }
            return id == newID
        }
        await store.finish()

        let window = store.state.windows.first?.window
        XCTAssertEqual(window?.contentTabs.tabs.filter(\.isPinned).map(\.id.rawValue), ["valid-dir"])
        XCTAssertEqual(
            window?.contentTabs.tabs[id: window?.contentTabs.activeTabID ?? ContentTabID(rawValue: "")]?.page,
            .home,
        )
        XCTAssertEqual(savedStores.value.last?.records.map(\.id), ["valid-dir"])
    }

    /// Collection file이 macOS package(directory)로 보이더라도 async bootstrap에서 정상 pinned record로 복원해야 한다.
    /// Finder 문서 패키지를 broken record로 오판하면 sync 시 active pinned tab이 제거되어 탭이 닫힌 것처럼 보인다.
    func testDefaultWindowBootstrapRestoresCollectionPackagePinnedRecord() async {
        let newID = UUID()
        let collectionURL = URL(fileURLWithPath: "/Users/test/Saved.voyagercollection")
        let pinnedStore = ContentTabPinnedRecordStore(records: [
            ContentTabPinnedRecord(
                id: "collection-pin",
                page: .collection,
                anchor: .collectionFile(url: collectionURL),
                title: "Saved",
                iconName: "rectangle.stack",
                pinnedAt: Date(timeIntervalSince1970: 443),
            ),
        ])

        let store = TestStore(initialState: WindowManagerFeature.State()) {
            WindowManagerFeature()
        } withDependencies: {
            $0.uuid = .constant(newID)
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
            $0.contentTabPinnedRecordClient.loadStore = { _ in pinnedStore }
            $0.contentTabPinnedRecordClient.saveStore = { _, _ in }
            $0.fileManagerClient.fileExistsWithIsDirectory = { path, isDirectory in
                guard path == collectionURL.path else { return false }
                isDirectory?.pointee = ObjCBool(true)
                return true
            }
            $0.onboardingWindowClient.showIfNeeded = { false }
            $0.fileManagerWindowClient.open = { _ in }
        }
        store.exhaustivity = .off

        await store.send(.file(.newWindow(path: nil)))
        await store.receive(\.defaultWindowBootstrapCompleted)
        await store.receive { action in
            guard case let .windows(.element(id: id, action: .window(.applyPinnedContentTabs))) = action
            else {
                return false
            }
            return id == newID
        }
        await store.finish()

        let window = store.state.windows.first?.window
        XCTAssertEqual(window?.contentTabs.tabs.filter(\.isPinned).map(\.id.rawValue), ["collection-pin"])
        XCTAssertEqual(window?.contentTabs.tabs[id: ContentTabID(rawValue: "collection-pin")]?.page, .collection)
        XCTAssertEqual(
            window?.contentTabs.tabs[id: ContentTabID(rawValue: "collection-pin")]?.anchor,
            .collectionFile(url: collectionURL),
        )
        XCTAssertEqual(
            window?.contentTabs.tabs[id: window?.contentTabs.activeTabID ?? ContentTabID(rawValue: "")]?.page,
            .home,
        )
    }

    /// pinned 저장 성공 이벤트는 전역 pinned store를 다시 읽어 열린 모든 window로 fan-out한다.
    /// pinned sidebar가 window마다 어긋나지 않도록 WindowManager 레벨 동기화 액션을 검증한다.
    /// - 검증 내용: child pinnedRecordSaveSucceeded → pinnedContentTabsStoreChanged → 모든 window applyPinnedContentTabs
    /// - 사전 조건: 열린 window 2개, global pinned store 1개
    /// - 기대 결과: 두 window 모두 동일한 pinned tab 상태 수신
    func testPinnedRecordSaveSucceededSyncsPinnedTabsAcrossOpenWindows() async {
        let firstID = UUID()
        let secondID = UUID()
        let pinnedStore = ContentTabPinnedRecordStore(records: [
            ContentTabPinnedRecord(
                id: "global-pin",
                page: .directory,
                anchor: .directory(path: "/Users/test/Documents"),
                title: "Documents",
                iconName: "folder",
                pinnedAt: Date(timeIntervalSince1970: 443),
            ),
        ])
        var initialState = WindowManagerFeature.State()
        initialState.windows = [
            WindowSessionState(id: firstID, window: .makeInitial(path: "/Users/test/A")),
            WindowSessionState(id: secondID, window: .makeInitial(path: "/Users/test/B")),
        ]

        let store = TestStore(initialState: initialState) {
            WindowManagerFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
            $0.contentTabPinnedRecordClient.loadStore = { _ in pinnedStore }
            $0.contentTabPinnedRecordClient.saveStore = { _, _ in }
            $0.fileManagerClient.fileExistsWithIsDirectory = { path, isDirectory in
                guard path == "/Users/test/Documents" else { return false }
                isDirectory?.pointee = ObjCBool(true)
                return true
            }
            $0.onboardingWindowClient.showIfNeeded = { false }
            $0.fileManagerWindowClient.open = { _ in }
        }
        // pinnedRecordSaveSucceeded fan-out은 각 window reducer의 handoff child action을 동반하므로,
        // 이 테스트는 parent sync action과 applyPinnedContentTabs payload만 검증한다.
        store.exhaustivity = .off

        await store.send(.windows(.element(
            id: firstID,
            action: .window(.contentTabs(.pinnedRecordSaveSucceeded)),
        )))
        await store.receive(\.pinnedContentTabsStoreChanged)
        await store.receive { action in
            guard case let .windows(.element(id: id, action: .window(.applyPinnedContentTabs(contentTabs)))) = action
            else {
                return false
            }
            return id == firstID
                && contentTabs.tabs.filter(\.isPinned).map(\.id.rawValue) == ["global-pin"]
                && contentTabs.tabs[id: contentTabs.activeTabID ?? ContentTabID(rawValue: "")]?.page == .home
        }
        await store.receive { action in
            guard case let .windows(.element(id: id, action: .window(.applyPinnedContentTabs(contentTabs)))) = action
            else {
                return false
            }
            return id == secondID
                && contentTabs.tabs.filter(\.isPinned).map(\.id.rawValue) == ["global-pin"]
                && contentTabs.tabs[id: contentTabs.activeTabID ?? ContentTabID(rawValue: "")]?.page == .home
        }

        XCTAssertEqual(store.state.windows[id: firstID]?.window.contentTabs.tabs.first?.id.rawValue, "global-pin")
        XCTAssertEqual(store.state.windows[id: secondID]?.window.contentTabs.tabs.first?.id.rawValue, "global-pin")
    }

    /// live sync는 bootstrap cleanup과 달리 파일 존재 검증으로 열린 pinned tab을 갑자기 제거하지 않는다.
    /// - 검증 내용: deleted directory record가 store에 있어도 sync fan-out state에는 유지되고 saveStore compaction이 호출되지 않음
    /// - 사전 조건: 열린 window 1개, global pinned store에 현재 존재하지 않는 directory record 1개
    /// - 기대 결과: applyPinnedContentTabs가 deleted-pin을 포함하고, live sync 중 saveStore 미호출
    func testPinnedRecordSaveSucceededSyncPreservesDeletedDirectoryRecord() async {
        let windowID = UUID()
        let saveStoreCalled = LockIsolated(false)
        let pinnedStore = ContentTabPinnedRecordStore(records: [
            ContentTabPinnedRecord(
                id: "deleted-pin",
                page: .directory,
                anchor: .directory(path: "/Users/test/Deleted"),
                title: "Deleted",
                iconName: "folder",
                pinnedAt: Date(timeIntervalSince1970: 443),
            ),
        ])
        var initialState = WindowManagerFeature.State()
        initialState.windows = [
            WindowSessionState(id: windowID, window: .makeInitial(path: "/Users/test/A")),
        ]

        let store = TestStore(initialState: initialState) {
            WindowManagerFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
            $0.contentTabPinnedRecordClient.loadStore = { _ in pinnedStore }
            $0.contentTabPinnedRecordClient.saveStore = { _, _ in
                saveStoreCalled.withValue { $0 = true }
            }
            $0.fileManagerClient.fileExistsWithIsDirectory = { _, _ in false }
            $0.onboardingWindowClient.showIfNeeded = { false }
            $0.fileManagerWindowClient.open = { _ in }
        }
        // live sync fan-out은 window-local handoff child action을 동반하므로,
        // 이 테스트는 broken record 보존 payload와 saveStore 미호출만 검증한다.
        store.exhaustivity = .off

        await store.send(.windows(.element(
            id: windowID,
            action: .window(.contentTabs(.pinnedRecordSaveSucceeded)),
        )))
        await store.receive(\.pinnedContentTabsStoreChanged)
        await store.receive { action in
            guard case let .windows(.element(id: id, action: .window(.applyPinnedContentTabs(contentTabs)))) = action
            else {
                return false
            }
            return id == windowID
                && contentTabs.tabs.filter(\.isPinned).map(\.id.rawValue) == ["deleted-pin"]
        }

        XCTAssertFalse(saveStoreCalled.value)
    }

    /// 명시적 path가 있는 window(path != nil)에서는 pinned record restore가
    /// 발생하지 않고 기존 makeInitial(path:) 동작을 유지함을 검증한다.
    /// - 검증 내용: loadStore가 호출되지 않고 window가 정상 생성됨
    /// - 사전 조건: path = "/Users/test/Documents"
    /// - 기대 결과: loadStore 미호출, 생성된 window는 일반 directory tab 포함
    func testExplicitPathWindowSkipsPinnedRestore() async {
        let newID = UUID()
        let storeLoadCalled = LockIsolated(false)

        let store = TestStore(initialState: WindowManagerFeature.State()) {
            WindowManagerFeature()
        } withDependencies: {
            $0.uuid = .constant(newID)
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
            $0.contentTabPinnedRecordClient.loadStore = { _ in
                storeLoadCalled.withValue { $0 = true }
                return ContentTabPinnedRecordStore()
            }
            $0.onboardingWindowClient.showIfNeeded = { false }
            $0.fileManagerWindowClient.open = { _ in }
        }
        // 명시적 path window의 부수 window/open action은 완전히 검증하지 않으므로
        // path bypass 조건만 검증한다.
        store.exhaustivity = .off

        let testPath = "/Users/test/Documents"
        await store.send(.file(.newWindow(path: testPath)))
        await store.finish()

        XCTAssertFalse(storeLoadCalled.value, "명시적 path window에서는 loadStore가 호출되지 않아야 함")
        let window = store.state.windows.first?.window
        XCTAssertNotNil(window, "window가 생성되어야 함")
        XCTAssertEqual(window?.contentTabs.tabs.count, 1, "기본 Home tab 1개")
        XCTAssertEqual(window?.contentTabs.tabs[0].anchor, .directory(path: testPath))
        XCTAssertFalse(window?.contentTabs.tabs[0].isPinned ?? true, "명시적 path window의 tab은 unpinned")
    }

    /// in-flight default bootstrap 완료는 bootstrap을 요청한 window에만 pinned state를 적용한다.
    /// 명시적 path window가 bootstrap 도중 열려도 해당 window의 directory tab을 유지해야 한다.
    func testDefaultBootstrapCompletionSkipsExplicitPathWindows() async {
        let defaultWindowID = UUID()
        let explicitPathWindowID = UUID()
        let explicitPath = "/Users/test/Documents"
        let pinnedStore = ContentTabPinnedRecordStore(records: [
            ContentTabPinnedRecord(
                id: "global-pin",
                page: .directory,
                anchor: .directory(path: "/Users/test/Pinned"),
                title: "Pinned",
                iconName: "folder",
                pinnedAt: Date(timeIntervalSince1970: 443),
            ),
        ])
        let restoredState = ContentTabState.restoringPinnedRecords(from: pinnedStore).state

        let requestID = UUID()
        var initialState = WindowManagerFeature.State()
        initialState.windows = [
            WindowSessionState(id: defaultWindowID, window: .makeInitial(path: nil)),
            WindowSessionState(id: explicitPathWindowID, window: .makeInitial(path: explicitPath)),
        ]
        initialState.defaultWindowBootstrapRequestID = requestID
        initialState.defaultWindowBootstrapWindowIDs = [defaultWindowID]

        let store = TestStore(initialState: initialState) {
            WindowManagerFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
        }
        store.exhaustivity = .off

        await store.send(.defaultWindowBootstrapCompleted(
            requestID: requestID,
            contentTabs: restoredState,
        ))
        await store.receive { action in
            guard case let .windows(.element(id: id, action: .window(.applyPinnedContentTabs(contentTabs)))) = action
            else {
                return false
            }
            return id == defaultWindowID
                && contentTabs.tabs.filter(\.isPinned).map(\.id.rawValue) == ["global-pin"]
        }

        XCTAssertEqual(
            store.state.windows[id: defaultWindowID]?.window.contentTabs.tabs.filter(\.isPinned).map(\.id.rawValue),
            ["global-pin"],
        )
        XCTAssertEqual(store.state.windows[id: explicitPathWindowID]?.window.contentTabs.tabs.count, 1)
        XCTAssertEqual(
            store.state.windows[id: explicitPathWindowID]?.window.contentTabs.tabs.first?.anchor,
            .directory(path: explicitPath),
        )
        XCTAssertFalse(store.state.windows[id: explicitPathWindowID]?.window.contentTabs.tabs.first?.isPinned ?? true)
    }

    /// live pinned store 변경은 진행 중인 bootstrap을 무효화해 오래된 snapshot 적용을 막는다.
    func testPinnedStoreChangeInvalidatesStaleDefaultBootstrapCompletion() async {
        let windowID = UUID()
        let requestID = UUID()
        let latestStore = ContentTabPinnedRecordStore(records: [
            ContentTabPinnedRecord(
                id: "latest-pin",
                page: .directory,
                anchor: .directory(path: "/Users/test/Latest"),
                title: "Latest",
                iconName: "folder",
                pinnedAt: Date(timeIntervalSince1970: 444),
            ),
        ])
        let staleStore = ContentTabPinnedRecordStore(records: [
            ContentTabPinnedRecord(
                id: "stale-pin",
                page: .directory,
                anchor: .directory(path: "/Users/test/Stale"),
                title: "Stale",
                iconName: "folder",
                pinnedAt: Date(timeIntervalSince1970: 443),
            ),
        ])
        let staleState = ContentTabState.restoringPinnedRecords(from: staleStore).state
        var initialState = WindowManagerFeature.State()
        initialState.windows = [WindowSessionState(id: windowID, window: .makeInitial(path: nil))]
        initialState.defaultWindowBootstrapRequestID = requestID
        initialState.defaultWindowBootstrapWindowIDs = [windowID]

        let store = TestStore(initialState: initialState) {
            WindowManagerFeature()
        } withDependencies: {
            $0.contentTabPinnedRecordClient.loadStore = { _ in latestStore }
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
        }
        store.exhaustivity = .off

        await store.send(.pinnedContentTabsStoreChanged) {
            $0.defaultWindowBootstrapRequestID = nil
            $0.defaultWindowBootstrapWindowIDs = []
        }
        await store.receive { action in
            guard case let .windows(.element(id: id, action: .window(.applyPinnedContentTabs(contentTabs)))) = action
            else { return false }
            return id == windowID
                && contentTabs.tabs.filter(\.isPinned).map(\.id.rawValue) == ["latest-pin"]
        }
        await store.send(.defaultWindowBootstrapCompleted(
            requestID: requestID,
            contentTabs: staleState,
        ))

        XCTAssertEqual(
            store.state.windows[id: windowID]?.window.contentTabs.tabs.filter(\.isPinned).map(\.id.rawValue),
            ["latest-pin"],
        )
    }

    /// restoreLastClosedTab 코맨드가 포커스된 윈도우의 contentTabs.recentlyClosed로 라우팅되어
    /// recentlyClosed snapshot을 소비하고 새 탭을 추가하는지 검증한다.
    /// - 검증 내용: restore 후 recentlyClosed == nil, tabs.count 1 증가
    /// - 사전 조건: 포커스된 FMW 1개, Directory recentlyClosed snapshot 1개, fileExistsWithIsDirectory true 응답
    /// - 기대 결과: recentlyClosed 소비, tab count +1
    func testRestoreLastClosedTabCommandRoutesToFocusedWindowContentTab() async {
        let windowID = UUID()
        let directoryPath = "/Users/test/Restored"
        let directoryAnchor = ContentTabPageAnchor.directory(path: directoryPath)
        let closedSnapshot = ClosedContentTabSnapshot(
            page: .directory,
            anchor: directoryAnchor,
            wasPinned: false,
            closedAt: Date(timeIntervalSince1970: 1_234_567_890),
        )

        var initialState = WindowManagerFeature.State()
        initialState.windows = [
            WindowSessionState(id: windowID, window: .makeInitial(path: nil)),
        ]
        initialState.focusedWindowID = windowID
        initialState.windows[id: windowID]?.window.contentTabs.recentlyClosed = closedSnapshot

        let initialTabCount = initialState.windows[id: windowID]?.window.contentTabs.tabs.count ?? 0

        let store = TestStore(initialState: initialState) {
            WindowManagerFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
            $0.contentTabPinnedRecordClient.loadStore = { _ in ContentTabPinnedRecordStore() }
            $0.contentTabPinnedRecordClient.saveStore = { _, _ in }
            $0.onboardingWindowClient.showIfNeeded = { false }
            $0.fileManagerClient.fileExistsWithIsDirectory = { path, isDirectory in
                guard path == directoryPath else { return false }
                isDirectory?.pointee = ObjCBool(true)
                return true
            }
            $0.fileManagerWindowClient.open = { _ in }
        }
        // 비포괄적: file(.restoreLastClosedTab) → sendCommandToFocusedWindow → window(.request(.restoreLastClosedContentTab))
        // → handleRestoreLastClosedContentTab → .contentTabs(.restore)로 이어지는 sync .send 체인을
        // 명시적 receive로 처리한다. 각 receive는 forEach wrapper를 통과한 중첩 action을 소비한다.
        store.exhaustivity = .off

        await store.send(.file(.restoreLastClosedTab))
        await store.receive(\.windows)
        await store.receive(\.windows)

        let window = store.state.windows[id: windowID]?.window
        XCTAssertNotNil(window, "window가 존재해야 함")
        XCTAssertNil(window?.contentTabs.recentlyClosed, "restore 후 recentlyClosed는 소비되어 nil이어야 함")
        XCTAssertEqual(window?.contentTabs.tabs.count, initialTabCount + 1, "restore 후 tab count가 1 증가해야 함")
        XCTAssertEqual(window?.contentTabs.tabs.last?.anchor, directoryAnchor, "복원된 tab의 anchor가 일치해야 함")
    }

    /// FileCommand .duplicateTab이 focused window로
    /// .request(.duplicateActiveContentTab) 명령을 전송하는지 검증한다.
    func testFileDuplicateTabCommand_routesToFocusedWindowDuplicateRequest() async {
        let windowID = UUID()

        var initialState = WindowManagerFeature.State()
        initialState.windows = [
            WindowSessionState(id: windowID, window: .makeInitial(path: nil)),
        ]
        initialState.focusedWindowID = windowID

        let store = TestStore(initialState: initialState) {
            WindowManagerFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
            $0.contentTabPinnedRecordClient.loadStore = { _ in ContentTabPinnedRecordStore() }
            $0.contentTabPinnedRecordClient.saveStore = { _, _ in }
            $0.onboardingWindowClient.showIfNeeded = { false }
            $0.fileManagerWindowClient.open = { _ in }
        }
        store.exhaustivity = .off

        await store.send(.file(.duplicateTab))
        // request(.duplicateActiveContentTab)가 focused window로 전달되어야 함
        await store.receive(\.windows)

        let window = store.state.windows[id: windowID]?.window
        XCTAssertNotNil(window, "window가 존재해야 함")
    }

    /// EditCommand .duplicate(⌘D)가 Entry duplicate 경로(.edit(.duplicate))로
    /// 라우팅되는 기존 동작이 변경되지 않았음을 검증한다.
    func testEntryDuplicate_unchanged() async {
        let windowID = UUID()

        var initialState = WindowManagerFeature.State()
        initialState.windows = [
            WindowSessionState(id: windowID, window: .makeInitial(path: nil)),
        ]
        initialState.focusedWindowID = windowID

        let store = TestStore(initialState: initialState) {
            WindowManagerFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
            $0.contentTabPinnedRecordClient.loadStore = { _ in ContentTabPinnedRecordStore() }
            $0.contentTabPinnedRecordClient.saveStore = { _, _ in }
            $0.onboardingWindowClient.showIfNeeded = { false }
            $0.fileManagerWindowClient.open = { _ in }
        }
        store.exhaustivity = .off

        await store.send(.edit(.duplicate))
        await store.receive(\.windows)
    }

    // MARK: - Default Pinned Favorites Seed

    /// 최초 실행(finder flag=false, pinnedStore empty)에서 Finder Favorites를 compatible pinned tab으로 변환하고
    /// store를 저장하며 finder seed flag를 true로 설정하는지 검증한다.
    /// - 검증 내용: favorites 기반 pinned tab + Home tab, saveStore 호출, finder flag 저장
    /// - 사전 조건: finder seed flag=false(default), pinnedStore empty, favorites client가 2개 directory favorite 반환
    /// - 기대 결과: favorite 2개가 directory pinned tab으로 복원, saveStore 1회 호출
    func testDefaultBootstrapSeedsPinnedTabsFromFinderFavoritesOnFirstLaunch() async {
        let newID = UUID()
        let savedStores = LockIsolated<[ContentTabPinnedRecordStore]>([])
        let legacySeedFlag = LockIsolated(false)
        let finderSeedFlag = LockIsolated(false)
        let applicationsURL = URL(fileURLWithPath: "/Applications")
        let projectsURL = URL(fileURLWithPath: "/Users/test/Projects")
        let favorites = Self.favoriteItems(applicationsURL: applicationsURL, projectsURL: projectsURL)

        let store = TestStore(initialState: WindowManagerFeature.State()) {
            WindowManagerFeature()
        } withDependencies: {
            $0.uuid = .constant(newID)
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
            $0.contentTabPinnedRecordClient.loadStore = { _ in ContentTabPinnedRecordStore() }
            $0.contentTabPinnedRecordClient.saveStore = { store, _ in
                savedStores.withValue { $0.append(store) }
            }
            $0.fileManagerFavoritesClient.loadFavorites = { _, _ in favorites }
            $0.fileManagerClient.fileExistsWithIsDirectory = Self.fileExistsForFavoriteURLs([
                applicationsURL,
                projectsURL,
            ])
            $0.onboardingWindowClient.showIfNeeded = { false }
            $0.fileManagerWindowClient.open = { _ in }
            $0.userDefaultsClient.bool = { key in
                switch key {
                case "fileManager.defaultPinnedTabsSeedCompleted":
                    legacySeedFlag.value
                case "fileManager.finderFavoritesPinnedSeedCompleted":
                    finderSeedFlag.value
                default:
                    false
                }
            }
            $0.userDefaultsClient.setBool = { value, key in
                switch key {
                case "fileManager.defaultPinnedTabsSeedCompleted":
                    legacySeedFlag.withValue { $0 = value }
                case "fileManager.finderFavoritesPinnedSeedCompleted":
                    finderSeedFlag.withValue { $0 = value }
                default:
                    break
                }
            }
        }
        store.exhaustivity = .off

        await store.send(.file(.newWindow(path: nil)))
        await store.receive(\.defaultWindowBootstrapCompleted)
        await store.receive { action in
            guard case let .windows(.element(id: id, action: .window(.applyPinnedContentTabs))) = action
            else {
                return false
            }
            return id == newID
        }
        await store.finish()

        Self.assertFinderFavoritesSeeded(
            in: store.state,
            savedRecords: savedStores.value.last?.records ?? [],
        )
        XCTAssertTrue(legacySeedFlag.value, "legacy seed flag도 완료 상태로 전환되어야 함")
        XCTAssertTrue(finderSeedFlag.value, "finder favorites seed 완료 flag가 true로 설정되어야 함")
    }

    /// 이전 잘못된 기본 seed flag가 이미 true인 사용자에게도 finder seed flag가 false이면
    /// Finder Favorites migration이 1회 실행되어 pinned tab으로 들어가는지 검증한다.
    func testFinderFavoritesSeedRunsWhenLegacyDefaultSeedFlagAlreadyTrue() async {
        let newID = UUID()
        let savedStores = LockIsolated<[ContentTabPinnedRecordStore]>([])
        let legacySeedFlag = LockIsolated(true)
        let finderSeedFlag = LockIsolated(false)
        let applicationsURL = URL(fileURLWithPath: "/Applications")
        let projectsURL = URL(fileURLWithPath: "/Users/test/Projects")
        let favorites = Self.favoriteItems(applicationsURL: applicationsURL, projectsURL: projectsURL)

        let store = TestStore(initialState: WindowManagerFeature.State()) {
            WindowManagerFeature()
        } withDependencies: {
            $0.uuid = .constant(newID)
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
            $0.contentTabPinnedRecordClient.loadStore = { _ in ContentTabPinnedRecordStore() }
            $0.contentTabPinnedRecordClient.saveStore = { store, _ in
                savedStores.withValue { $0.append(store) }
            }
            $0.fileManagerFavoritesClient.loadFavorites = { _, _ in favorites }
            $0.fileManagerClient.fileExistsWithIsDirectory = Self.fileExistsForFavoriteURLs([
                applicationsURL,
                projectsURL,
            ])
            $0.onboardingWindowClient.showIfNeeded = { false }
            $0.fileManagerWindowClient.open = { _ in }
            $0.userDefaultsClient.bool = { key in
                switch key {
                case "fileManager.defaultPinnedTabsSeedCompleted":
                    legacySeedFlag.value
                case "fileManager.finderFavoritesPinnedSeedCompleted":
                    finderSeedFlag.value
                default:
                    false
                }
            }
            $0.userDefaultsClient.setBool = { value, key in
                switch key {
                case "fileManager.defaultPinnedTabsSeedCompleted":
                    legacySeedFlag.withValue { $0 = value }
                case "fileManager.finderFavoritesPinnedSeedCompleted":
                    finderSeedFlag.withValue { $0 = value }
                default:
                    break
                }
            }
        }
        store.exhaustivity = .off

        await store.send(.file(.newWindow(path: nil)))
        await store.receive(\.defaultWindowBootstrapCompleted)
        await store.receive { action in
            guard case let .windows(.element(id: id, action: .window(.applyPinnedContentTabs))) = action
            else {
                return false
            }
            return id == newID
        }
        await store.finish()

        Self.assertFinderFavoritesSeeded(
            in: store.state,
            savedRecords: savedStores.value.last?.records ?? [],
        )
        XCTAssertTrue(legacySeedFlag.value, "기존 legacy flag는 유지되어야 함")
        XCTAssertTrue(finderSeedFlag.value, "finder favorites seed 완료 flag가 true로 설정되어야 함")
    }

    /// 기존 pinned store가 있으면 missing favorite을 재삽입하지 않고 migration 완료 flag만 기록한다.
    /// - 검증 내용: 사용자가 일부 favorite을 unpin한 상태를 seed migration이 덮어쓰지 않음
    /// - 사전 조건: finder seed flag=false, pinnedStore non-empty
    /// - 기대 결과: 기존 pinned tab만 유지, favorites load/save 없음, finder flag true
    func testFinderFavoritesSeedPreservesNonEmptyPinnedStoreWithoutAppendingMissingFavorites() async {
        let newID = UUID()
        let saveStoreCalled = LockIsolated(false)
        let loadFavoritesCalled = LockIsolated(false)
        let legacySeedFlag = LockIsolated(true)
        let finderSeedFlag = LockIsolated(false)
        let existingRecord = ContentTabPinnedRecord(
            id: "existing-projects",
            page: .directory,
            anchor: .directory(path: "/Users/test/Projects"),
            title: "Projects",
            iconName: "folder",
            pinnedAt: Date(timeIntervalSince1970: 443),
        )

        let store = TestStore(initialState: WindowManagerFeature.State()) {
            WindowManagerFeature()
        } withDependencies: {
            $0.uuid = .constant(newID)
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
            $0.contentTabPinnedRecordClient.loadStore = { _ in
                ContentTabPinnedRecordStore(records: [existingRecord])
            }
            $0.contentTabPinnedRecordClient.saveStore = { _, _ in
                saveStoreCalled.withValue { $0 = true }
            }
            $0.fileManagerFavoritesClient.loadFavorites = { _, _ in
                loadFavoritesCalled.withValue { $0 = true }
                return Self.favoriteItems(
                    applicationsURL: URL(fileURLWithPath: "/Applications"),
                    projectsURL: URL(fileURLWithPath: "/Users/test/Projects"),
                )
            }
            $0.onboardingWindowClient.showIfNeeded = { false }
            $0.fileManagerWindowClient.open = { _ in }
            $0.fileManagerClient.fileExistsWithIsDirectory = Self.fileExistsForFavoriteURLs([
                URL(fileURLWithPath: "/Users/test/Projects"),
            ])
            $0.userDefaultsClient.bool = { key in
                switch key {
                case "fileManager.defaultPinnedTabsSeedCompleted":
                    legacySeedFlag.value
                case "fileManager.finderFavoritesPinnedSeedCompleted":
                    finderSeedFlag.value
                default:
                    false
                }
            }
            $0.userDefaultsClient.setBool = { value, key in
                switch key {
                case "fileManager.defaultPinnedTabsSeedCompleted":
                    legacySeedFlag.withValue { $0 = value }
                case "fileManager.finderFavoritesPinnedSeedCompleted":
                    finderSeedFlag.withValue { $0 = value }
                default:
                    break
                }
            }
        }
        store.exhaustivity = .off

        await store.send(.file(.newWindow(path: nil)))
        await store.receive(\.defaultWindowBootstrapCompleted)
        await store.receive { action in
            guard case let .windows(.element(id: id, action: .window(.applyPinnedContentTabs))) = action
            else {
                return false
            }
            return id == newID
        }
        await store.finish()

        let pinnedTabs = store.state.windows.first?.window.contentTabs.tabs.filter(\.isPinned) ?? []
        XCTAssertEqual(
            pinnedTabs.map(\.anchor),
            [.directory(path: "/Users/test/Projects")],
            "non-empty pinned store는 사용자 의도일 수 있으므로 missing favorite을 재삽입하지 않아야 함",
        )
        XCTAssertFalse(loadFavoritesCalled.value, "non-empty store에서는 favorites를 다시 읽지 않아야 함")
        XCTAssertFalse(saveStoreCalled.value, "non-empty store에서는 seed 저장이 없어야 함")
        XCTAssertTrue(finderSeedFlag.value, "finder favorites seed 완료 flag가 true로 설정되어야 함")
    }

    /// seed store 저장에 실패하면 완료 flag를 세우지 않고 다음 실행에서 재시도할 수 있어야 한다.
    func testFinderFavoritesSeedDoesNotSetFlagWhenSaveFails() async {
        let newID = UUID()
        let legacySeedFlag = LockIsolated(true)
        let finderSeedFlag = LockIsolated(false)
        let applicationsURL = URL(fileURLWithPath: "/Applications")
        let projectsURL = URL(fileURLWithPath: "/Users/test/Projects")
        let favorites = Self.favoriteItems(applicationsURL: applicationsURL, projectsURL: projectsURL)

        struct SeedSaveFailure: Error {}

        let store = TestStore(initialState: WindowManagerFeature.State()) {
            WindowManagerFeature()
        } withDependencies: {
            $0.uuid = .constant(newID)
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
            $0.contentTabPinnedRecordClient.loadStore = { _ in ContentTabPinnedRecordStore() }
            $0.contentTabPinnedRecordClient.saveStore = { _, _ in
                throw SeedSaveFailure()
            }
            $0.fileManagerFavoritesClient.loadFavorites = { _, _ in favorites }
            $0.fileManagerClient.fileExistsWithIsDirectory = Self.fileExistsForFavoriteURLs([
                applicationsURL,
                projectsURL,
            ])
            $0.onboardingWindowClient.showIfNeeded = { false }
            $0.fileManagerWindowClient.open = { _ in }
            $0.userDefaultsClient.bool = { key in
                switch key {
                case "fileManager.defaultPinnedTabsSeedCompleted":
                    legacySeedFlag.value
                case "fileManager.finderFavoritesPinnedSeedCompleted":
                    finderSeedFlag.value
                default:
                    false
                }
            }
            $0.userDefaultsClient.setBool = { value, key in
                switch key {
                case "fileManager.defaultPinnedTabsSeedCompleted":
                    legacySeedFlag.withValue { $0 = value }
                case "fileManager.finderFavoritesPinnedSeedCompleted":
                    finderSeedFlag.withValue { $0 = value }
                default:
                    break
                }
            }
        }
        store.exhaustivity = .off

        await store.send(.file(.newWindow(path: nil)))
        await store.receive(\.defaultWindowBootstrapCompleted)
        await store.receive { action in
            guard case let .windows(.element(id: id, action: .window(.applyPinnedContentTabs))) = action
            else {
                return false
            }
            return id == newID
        }
        await store.finish()

        let pinnedTabs = store.state.windows.first?.window.contentTabs.tabs.filter(\.isPinned) ?? []
        XCTAssertTrue(pinnedTabs.isEmpty, "save 실패 시 in-memory pinned seed도 적용하지 않아야 함")
        XCTAssertFalse(finderSeedFlag.value, "save 실패 시 finder seed 완료 flag를 세우면 안 됨")
    }

    /// finder seed 완료 flag가 true이면 pinnedStore가 비어있어도 seed를 건너뛰고 Home tab만 있는 window를 생성한다.
    /// - 검증 내용: pinned tab 없음, saveStore 미호출
    /// - 사전 조건: finder seed flag=true, pinnedStore empty
    /// - 기대 결과: pinned tab 0개, Home tab 1개, saveStore 미호출
    func testDefaultBootstrapDoesNotReseedWhenFinderFlagTrueAndStoreEmpty() async {
        let newID = UUID()
        let saveStoreCalled = LockIsolated(false)
        let legacySeedFlag = LockIsolated(true)
        let finderSeedFlag = LockIsolated(true)

        let store = TestStore(initialState: WindowManagerFeature.State()) {
            WindowManagerFeature()
        } withDependencies: {
            $0.uuid = .constant(newID)
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
            $0.contentTabPinnedRecordClient.loadStore = { _ in ContentTabPinnedRecordStore() }
            $0.contentTabPinnedRecordClient.saveStore = { _, _ in
                saveStoreCalled.withValue { $0 = true }
            }
            $0.fileManagerFavoritesClient.loadFavorites = { _, _ in
                XCTFail("finder seed flag가 true이면 favorites를 다시 읽지 않아야 함")
                return []
            }
            $0.onboardingWindowClient.showIfNeeded = { false }
            $0.fileManagerWindowClient.open = { _ in }
            $0.userDefaultsClient.bool = { key in
                switch key {
                case "fileManager.defaultPinnedTabsSeedCompleted":
                    legacySeedFlag.value
                case "fileManager.finderFavoritesPinnedSeedCompleted":
                    finderSeedFlag.value
                default:
                    false
                }
            }
            $0.userDefaultsClient.setBool = { value, key in
                switch key {
                case "fileManager.defaultPinnedTabsSeedCompleted":
                    legacySeedFlag.withValue { $0 = value }
                case "fileManager.finderFavoritesPinnedSeedCompleted":
                    finderSeedFlag.withValue { $0 = value }
                default:
                    break
                }
            }
        }
        store.exhaustivity = .off

        await store.send(.file(.newWindow(path: nil)))
        await store.receive(\.defaultWindowBootstrapCompleted)
        await store.receive { action in
            guard case let .windows(.element(id: id, action: .window(.applyPinnedContentTabs))) = action
            else {
                return false
            }
            return id == newID
        }
        await store.finish()

        let pinnedTabs = store.state.windows.first?.window.contentTabs.tabs.filter(\.isPinned) ?? []
        XCTAssertTrue(pinnedTabs.isEmpty, "pinned tab이 없어야 함")
        XCTAssertFalse(saveStoreCalled.value, "seed 완료 상태에서는 saveStore가 호출되지 않아야 함")
    }

    private static func assertFinderFavoritesSeeded(
        in state: WindowManagerFeature.State,
        savedRecords: [ContentTabPinnedRecord],
    ) {
        let pinnedTabs = state.windows.first?.window.contentTabs.tabs.filter(\.isPinned) ?? []
        XCTAssertEqual(
            pinnedTabs.map(\.title),
            ["Applications", "Projects"],
            "Finder Favorites가 pinned tab title로 복원되어야 함",
        )
        XCTAssertEqual(
            pinnedTabs.map(\.anchor),
            [
                .directory(path: "/Applications"),
                .directory(path: "/Users/test/Projects"),
            ],
            "초기 pinned seed는 하드코딩 위치가 아니라 Finder Favorites directory anchor를 사용해야 함",
        )
        XCTAssertEqual(
            savedRecords.map(\.title),
            ["Applications", "Projects"],
            "saveStore에 Finder Favorites record가 저장되어야 함",
        )
        XCTAssertTrue(
            savedRecords.allSatisfy { $0.page == .directory },
            "기본 seed는 compatible directory page만 저장해야 함",
        )
        XCTAssertEqual(
            savedRecords.map(\.anchor),
            [
                .directory(path: "/Applications"),
                .directory(path: "/Users/test/Projects"),
            ],
            "기본 seed는 Recents/Tags/AI Chat이 아니라 Finder Favorites compatible anchor만 저장해야 함",
        )
    }

    nonisolated private static func favoriteItems(
        applicationsURL: URL,
        projectsURL: URL,
    ) -> [SidebarItems.FavoriteItem] {
        [
            SidebarItems.FavoriteItem(name: "Applications", url: applicationsURL, iconName: "appstore"),
            SidebarItems.FavoriteItem(name: "Projects", url: projectsURL, iconName: "folder"),
        ]
    }

    nonisolated private static func fileExistsForFavoriteURLs(
        _ urls: [URL],
    ) -> @Sendable (String, UnsafeMutablePointer<ObjCBool>?) -> Bool {
        { path, isDirectory in
            guard urls.contains(where: { $0.path == path }) else { return false }
            isDirectory?.pointee = ObjCBool(true)
            return true
        }
    }
}
