import ComposableArchitecture
import Foundation
@testable import Voyager
import VoyagerEntitiesCollection
import VoyagerFeaturesContentPageNavigation
import VoyagerFeaturesEntryArrangements
import VoyagerFeaturesEntryOperations
@testable import VoyagerPagesFileManager
import VoyagerPagesOnboarding
import VoyagerShared
import VoyagerWidgetsEntryViewLayout
import XCTest

private actor WindowBootstrapSuspensionGate {
    private var releaseContinuation: CheckedContinuation<Void, Never>?
    private var entryWaiters: [CheckedContinuation<Void, Never>] = []
    private var isWaiting = false

    func wait() async {
        isWaiting = true
        let waiters = entryWaiters
        entryWaiters.removeAll()
        waiters.forEach { $0.resume() }
        await withCheckedContinuation { releaseContinuation = $0 }
    }

    func waitUntilWaiting() async {
        guard !isWaiting else { return }
        await withCheckedContinuation { entryWaiters.append($0) }
    }

    func open() {
        releaseContinuation?.resume()
        releaseContinuation = nil
    }
}

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
        await store.receive(
            \.windows[id: secondID].window.applyHiddenFixedLocationIDs,
            hiddenIDs,
        ) { state in
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
        XCTAssertFalse(
            store.state.windows.first?.window.contentTabs.tabs.contains(where: \.isPinned) ?? true,
        )

        await store.receive(\.defaultWindowBootstrapCompleted)
        await store.receive { action in
            guard case let .windows(.element(id: id, action: .window(.applyPinnedContentTabs))) = action
            else {
                return false
            }
            return id == newID
        }
        await store.finish()

        XCTAssertEqual(loadCount.value, 2)
        XCTAssertEqual(
            store.state.windows.first?.window.contentTabs.tabs.filter(\.isPinned).map(\.id.rawValue),
            ["dir-1"],
        )
    }

    /// Default window의 async bootstrap은 삭제된 pinned Directory record를 제외하고 locked update로 compact한다.
    /// 삭제된 대상이 placeholder tab으로 반복 복원되지 않도록 WindowManager의 파일 존재 검증과 compaction을 검증한다.
    /// - 검증 내용: valid record만 window에 복원, 최신 store 기반 locked compaction
    /// - 사전 조건: valid directory 1개 + deleted directory 1개
    /// - 기대 결과: deleted record 제외 및 updateStoreAndLoad 1회 호출
    func testDefaultWindowBootstrapDropsDeletedPinnedDirectoryRecordsAndCompactsStore() async {
        let newID = UUID()
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
        let persistedStore = LockIsolated(pinnedStore)
        let updateCount = LockIsolated(0)
        let unlockedSaveCalled = LockIsolated(false)

        let store = TestStore(initialState: WindowManagerFeature.State()) {
            WindowManagerFeature()
        } withDependencies: {
            $0.uuid = .constant(newID)
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
            $0.contentTabPinnedRecordClient = ContentTabPinnedRecordClient(
                loadStore: { _ in persistedStore.value },
                saveStore: { _, _ in unlockedSaveCalled.withValue { $0 = true } },
                updateStoreAndLoad: { _, transform in
                    updateCount.withValue { $0 += 1 }
                    return try persistedStore.withValue { value in
                        let updated = try transform(value)
                        value = updated
                        return updated
                    }
                },
            )
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
        XCTAssertEqual(persistedStore.value.records.map(\.id), ["valid-dir"])
        XCTAssertEqual(updateCount.value, 1)
        XCTAssertFalse(unlockedSaveCalled.value)
    }

    /// Default window compaction은 snapshot load 이후 발생한 최신 pin을 덮어쓰지 않는다.
    /// stale snapshot에서 복원 필요성을 감지해도 실제 write는 locked latest store를 다시 변환해야 한다.
    /// - 검증 내용: snapshot load → concurrent pin → locked compaction interleaving
    /// - 사전 조건: stale store에는 valid/deleted record, 최신 store에는 concurrent record 추가
    /// - 기대 결과: deleted record만 제거되고 concurrent record는 저장·복원됨
    func testDefaultWindowBootstrapCompactionPreservesConcurrentPinnedRecord() async {
        let newID = UUID()
        let staleStore = ContentTabPinnedRecordStore(records: [
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
        let concurrentRecord = ContentTabPinnedRecord(
            id: "concurrent-dir",
            page: .directory,
            anchor: .directory(path: "/Users/test/Concurrent"),
            title: "Concurrent",
            iconName: "folder",
            pinnedAt: Date(timeIntervalSince1970: 445),
        )
        let persistedStore = LockIsolated(staleStore)
        let updateCount = LockIsolated(0)
        let unlockedSaveCalled = LockIsolated(false)

        let store = TestStore(initialState: WindowManagerFeature.State()) {
            WindowManagerFeature()
        } withDependencies: {
            $0.uuid = .constant(newID)
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
            $0.contentTabPinnedRecordClient = ContentTabPinnedRecordClient(
                loadStore: { _ in staleStore },
                saveStore: { _, _ in unlockedSaveCalled.withValue { $0 = true } },
                updateStoreAndLoad: { _, transform in
                    updateCount.withValue { $0 += 1 }
                    return try persistedStore.withValue { value in
                        value = ContentTabPinnedRecordStore(
                            schemaVersion: value.schemaVersion,
                            records: value.records + [concurrentRecord],
                        )
                        let updated = try transform(value)
                        value = updated
                        return updated
                    }
                },
            )
            $0.fileManagerClient.fileExistsWithIsDirectory = { path, isDirectory in
                guard path == "/Users/test/Documents" || path == "/Users/test/Concurrent" else {
                    return false
                }
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

        XCTAssertEqual(persistedStore.value.records.map(\.id), ["valid-dir", "concurrent-dir"])
        XCTAssertEqual(
            store.state.windows.first?.window.contentTabs.tabs.filter(\.isPinned).map(\.id.rawValue),
            ["valid-dir", "concurrent-dir"],
        )
        XCTAssertEqual(updateCount.value, 1)
        XCTAssertFalse(unlockedSaveCalled.value)
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

    /// 취소된 default window bootstrap은 ensure 완료 후 built-in seed를 영구 저장하지 않는다.
    /// - 검증 내용: cancellation을 무시하는 ensure 반환 이후 seed store와 completion flag 미기록
    /// - 사전 조건: ensure 대기 중 pinned store 변경으로 bootstrap 취소
    /// - 기대 결과: built-in update 0회, 빈 persisted store, 항목별 completion false
    func testPinnedStoreChangeCancelsBuiltInSeedWritesAfterEnsure() async {
        let windowID = UUID()
        let gate = WindowBootstrapSuspensionGate()
        let applicationSupportURL = URL(fileURLWithPath: "/tmp/Application Support")
        let recentsURL = BuiltInCollectionIdentity.recents.canonicalPackageURL(
            applicationSupportURL: applicationSupportURL,
        )
        let allTagsURL = BuiltInCollectionIdentity.allTags.canonicalPackageURL(
            applicationSupportURL: applicationSupportURL,
        )
        let persistedStore = LockIsolated(ContentTabPinnedRecordStore())
        let updateCount = LockIsolated(0)
        let flags = LockIsolated([
            "fileManager.defaultPinnedTabsSeedCompleted": true,
            "fileManager.finderFavoritesPinnedSeedCompleted": true,
        ])

        let store = TestStore(initialState: WindowManagerFeature.State()) {
            WindowManagerFeature()
        } withDependencies: {
            $0.uuid = .constant(windowID)
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
            $0.contentTabPinnedRecordClient = ContentTabPinnedRecordClient(
                loadStore: { _ in persistedStore.value },
                saveStore: { value, _ in persistedStore.withValue { $0 = value } },
                updateStoreAndLoad: { _, transform in
                    updateCount.withValue { $0 += 1 }
                    let updated = try transform(persistedStore.value)
                    persistedStore.withValue { $0 = updated }
                    return updated
                },
            )
            $0.fileManagerBuiltInCollectionClient.ensureAll = {
                await gate.wait()
                return BuiltInCollectionEnsureReport(
                    recents: .ready(.init(identity: .recents, packageURL: recentsURL)),
                    allTags: .ready(.init(identity: .allTags, packageURL: allTagsURL)),
                )
            }
            $0.userDefaultsClient.bool = { flags.value[$0] ?? false }
            $0.userDefaultsClient.setBool = { value, key in flags.withValue { $0[key] = value } }
            $0.onboardingWindowClient.showIfNeeded = { false }
            $0.fileManagerWindowClient.open = { _ in }
        }
        store.exhaustivity = .off

        await store.send(.file(.newWindow(path: nil)))
        await gate.waitUntilWaiting()
        await store.send(.pinnedContentTabsStoreChanged)
        await gate.open()
        await store.finish()

        XCTAssertEqual(updateCount.value, 0)
        XCTAssertTrue(persistedStore.value.records.isEmpty)
        XCTAssertFalse(flags.value["fileManager.builtInCollection.recentsPinnedSeed.v1"] ?? false)
        XCTAssertFalse(flags.value["fileManager.builtInCollection.allTagsPinnedSeed.v1"] ?? false)
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

    // MARK: - Default Pinned Favorites Seed

    /// 최초 실행(finder flag=false, pinnedStore empty)에서 Finder Favorites를 compatible pinned tab으로 변환하고
    /// store를 저장하며 finder seed flag를 true로 설정하는지 검증한다.
    /// - 검증 내용: favorites 기반 pinned tab + Home tab, saveStore 호출, finder flag 저장
    /// - 사전 조건: finder seed flag=false(default), pinnedStore empty, favorites client가 2개 directory favorite 반환
    /// - 기대 결과: favorite 2개가 directory pinned tab으로 복원, saveStore 1회 호출
    func testDefaultBootstrapSeedsPinnedTabsFromFinderFavoritesOnFirstLaunch() async {
        let newID = UUID()
        let savedStores = LockIsolated<[ContentTabPinnedRecordStore]>([])
        let persistedStore = LockIsolated(ContentTabPinnedRecordStore())
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
            $0.contentTabPinnedRecordClient.loadStore = { _ in persistedStore.value }
            $0.contentTabPinnedRecordClient.saveStore = { store, _ in
                persistedStore.withValue { $0 = store }
                savedStores.withValue { $0.append(store) }
            }
            $0.contentTabPinnedRecordClient.updateStoreAndLoad = { _, transform in
                try persistedStore.withValue { currentStore in
                    let updatedStore = try transform(currentStore)
                    currentStore = updatedStore
                    savedStores.withValue { $0.append(updatedStore) }
                    return updatedStore
                }
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
        let persistedStore = LockIsolated(ContentTabPinnedRecordStore())
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
            $0.contentTabPinnedRecordClient.loadStore = { _ in persistedStore.value }
            $0.contentTabPinnedRecordClient.saveStore = { store, _ in
                persistedStore.withValue { $0 = store }
                savedStores.withValue { $0.append(store) }
            }
            $0.contentTabPinnedRecordClient.updateStoreAndLoad = { _, transform in
                try persistedStore.withValue { currentStore in
                    let updatedStore = try transform(currentStore)
                    currentStore = updatedStore
                    savedStores.withValue { $0.append(updatedStore) }
                    return updatedStore
                }
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
            $0.contentTabPinnedRecordClient.saveStore = { _, _ in }
            $0.contentTabPinnedRecordClient.updateStoreAndLoad = { _, _ in
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

    // VOY-570 Linear AC mapping (FMW cross-owner):
    // AC1 -> testDefaultBootstrapRunsFinderEnsureBuiltInSeedsReloadAndRestoreInOrder
    // AC4 -> testAllTagsDeferredThenLaterReadySeedsAndRestores
    // AC6 -> testBuiltInCompletionSuppressesReseedAfterUnpinWhileEnsureStillRuns
    // AC9 -> testBuiltInSeedFailureIsIsolatedPerItemAndWindowStillCompletes
    // AC10 -> testFinderSeedRetriesAfterWriteFailureWhenOnlyBuiltInResidueExists

    /// 기본 부트스트랩은 Finder → ensure → Recents → All Tags → reload → restore 순서를 보장한다.
    /// - 검증 내용: dependency 호출 순서와 최종 persisted/restored record 순서
    /// - 사전 조건: 빈 store, Finder favorite 1개, 두 built-in descriptor ready
    /// - 기대 결과: Recents → Finder → All Tags 순서로 저장·복원되고 세 완료 플래그가 true
    func testDefaultBootstrapRunsFinderEnsureBuiltInSeedsReloadAndRestoreInOrder() async {
        let windowID = UUID()
        let applicationSupportURL = URL(fileURLWithPath: "/tmp/Application Support")
        let finderURL = URL(fileURLWithPath: "/Users/test/Projects")
        let recentsURL = BuiltInCollectionIdentity.recents.canonicalPackageURL(
            applicationSupportURL: applicationSupportURL,
        )
        let allTagsURL = BuiltInCollectionIdentity.allTags.canonicalPackageURL(
            applicationSupportURL: applicationSupportURL,
        )
        let events = LockIsolated<[String]>([])
        let loadCount = LockIsolated(0)
        let updateCount = LockIsolated(0)
        let persistedStore = LockIsolated(ContentTabPinnedRecordStore())
        let flags = LockIsolated<[String: Bool]>([:])
        let metrics = LockIsolated<[BuiltInSeedLifecycleMetric]>([])

        let store = TestStore(initialState: WindowManagerFeature.State()) {
            WindowManagerFeature()
        } withDependencies: {
            $0.uuid = .constant(windowID)
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
            $0.contentTabPinnedRecordClient = ContentTabPinnedRecordClient(
                loadStore: { _ in
                    let count = loadCount.withValue { value in
                        value += 1
                        return value
                    }
                    events.withValue { $0.append("load-\(count)") }
                    return persistedStore.value
                },
                saveStore: { value, _ in persistedStore.withValue { $0 = value } },
                updateStoreAndLoad: { _, transform in
                    let count = updateCount.withValue { value in
                        value += 1
                        return value
                    }
                    events.withValue { $0.append("update-\(count)") }
                    let updated = try transform(persistedStore.value)
                    persistedStore.withValue { $0 = updated }
                    return updated
                },
            )
            $0.fileManagerFavoritesClient.loadFavorites = { _, _ in
                events.withValue { $0.append("finder") }
                return [SidebarItems.FavoriteItem(name: "Projects", url: finderURL, iconName: "folder")]
            }
            $0.fileManagerBuiltInCollectionClient.ensureAll = {
                events.withValue { $0.append("ensure") }
                return BuiltInCollectionEnsureReport(
                    recents: .ready(.init(identity: .recents, packageURL: recentsURL)),
                    allTags: .ready(.init(identity: .allTags, packageURL: allTagsURL)),
                )
            }
            $0.fileManagerClient.urlsForDirectory = { directory, _ in
                directory == .applicationSupportDirectory ? [applicationSupportURL] : []
            }
            $0.fileManagerClient.fileExistsWithIsDirectory = { path, isDirectory in
                if path == finderURL.path {
                    isDirectory?.pointee = ObjCBool(true)
                    return true
                }
                if path == recentsURL.path || path == allTagsURL.path {
                    events.withValue { $0.append("restore") }
                    return true
                }
                return false
            }
            $0.userDefaultsClient.bool = { flags.value[$0] ?? false }
            $0.userDefaultsClient.setBool = { value, key in
                flags.withValue { $0[key] = value }
                if value {
                    let event: String? = switch key {
                    case "fileManager.defaultPinnedTabsSeedCompleted": "legacy"
                    case "fileManager.finderFavoritesPinnedSeedCompleted": "finder-complete"
                    case "fileManager.builtInCollection.recentsPinnedSeed.v1": "recents-complete"
                    case "fileManager.builtInCollection.allTagsPinnedSeed.v1": "all-tags-complete"
                    default: nil
                    }
                    if let event { events.withValue { $0.append(event) } }
                }
            }
            $0.metricsClient = Self.metricsClient(recording: metrics)
            $0.onboardingWindowClient.showIfNeeded = { false }
            $0.fileManagerWindowClient.open = { _ in }
        }
        // store.exhaustivity = .off: window child handoff보다 bootstrap의 durable 호출 순서와 최종 상태를 검증한다.
        store.exhaustivity = .off

        await store.send(.file(.newWindow(path: nil)))
        await store.receive(\.defaultWindowBootstrapCompleted)
        await store.receive(\.windows)
        await store.finish()

        XCTAssertEqual(
            Array(events.value.prefix(11)),
            [
                "load-1", "legacy", "finder", "update-1", "finder-complete", "ensure",
                "update-2", "recents-complete", "update-3", "all-tags-complete", "load-2",
            ],
        )
        let firstRestoreIndex = try? XCTUnwrap(events.value.firstIndex(of: "restore"))
        let reloadIndex = try? XCTUnwrap(events.value.firstIndex(of: "load-2"))
        XCTAssertNotNil(firstRestoreIndex)
        XCTAssertNotNil(reloadIndex)
        if let firstRestoreIndex, let reloadIndex {
            XCTAssertLessThan(reloadIndex, firstRestoreIndex)
        }
        XCTAssertEqual(
            persistedStore.value.records.map(\.id),
            ["built-in-collection-recents", "favorite-file----Users-test-Projects", "built-in-collection-all-tags"],
        )
        XCTAssertEqual(
            store.state.windows.first?.window.contentTabs.tabs.filter(\.isPinned).map(\.id.rawValue),
            persistedStore.value.records.map(\.id),
        )
        XCTAssertTrue(flags.value["fileManager.finderFavoritesPinnedSeedCompleted"] ?? false)
        XCTAssertTrue(flags.value["fileManager.builtInCollection.recentsPinnedSeed.v1"] ?? false)
        XCTAssertTrue(flags.value["fileManager.builtInCollection.allTagsPinnedSeed.v1"] ?? false)
        XCTAssertEqual(metrics.value, [
            .init(name: "built_in_pinned_seed_started", tags: nil),
            .init(
                name: "built_in_pinned_item_seeded",
                tags: ["identity": "recents", "outcome": "seeded"],
            ),
            .init(
                name: "built_in_pinned_item_seeded",
                tags: ["identity": "all_tags", "outcome": "seeded"],
            ),
        ])
    }

    /// Finder 저장 실패 뒤 built-in residue만 남아도 다음 부트스트랩이 Finder를 재시도한다.
    /// - 검증 내용: 첫 Finder transaction 실패, built-in 성공, 두 번째 Finder retry와 residue ordering
    /// - 사전 조건: 첫 update만 throw, ensure는 두 항목 ready, duplicate Finder favorite 입력
    /// - 기대 결과: Finder flag는 첫 실행 후 false, 두 번째 실행 후 true이며 Finder ID는 하나만 존재
    func testFinderSeedRetriesAfterWriteFailureWhenOnlyBuiltInResidueExists() async {
        struct FinderWriteFailure: Error {}

        let windowID = UUID()
        let applicationSupportURL = URL(fileURLWithPath: "/tmp/Application Support")
        let finderURL = URL(fileURLWithPath: "/Users/test/Projects")
        let recentsURL = BuiltInCollectionIdentity.recents.canonicalPackageURL(
            applicationSupportURL: applicationSupportURL,
        )
        let allTagsURL = BuiltInCollectionIdentity.allTags.canonicalPackageURL(
            applicationSupportURL: applicationSupportURL,
        )
        let persistedStore = LockIsolated(ContentTabPinnedRecordStore())
        let flags = LockIsolated<[String: Bool]>([:])
        let updateCount = LockIsolated(0)
        let finderLoadCount = LockIsolated(0)

        let store = TestStore(initialState: WindowManagerFeature.State()) {
            WindowManagerFeature()
        } withDependencies: {
            $0.uuid = .constant(windowID)
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
            $0.contentTabPinnedRecordClient = ContentTabPinnedRecordClient(
                loadStore: { _ in persistedStore.value },
                saveStore: { value, _ in persistedStore.withValue { $0 = value } },
                updateStoreAndLoad: { _, transform in
                    let count = updateCount.withValue { value in
                        value += 1
                        return value
                    }
                    if count == 1 { throw FinderWriteFailure() }
                    let updated = try transform(persistedStore.value)
                    persistedStore.withValue { $0 = updated }
                    return updated
                },
            )
            $0.fileManagerFavoritesClient.loadFavorites = { _, _ in
                finderLoadCount.withValue { $0 += 1 }
                let favorite = SidebarItems.FavoriteItem(name: "Projects", url: finderURL, iconName: "folder")
                return [favorite, favorite]
            }
            $0.fileManagerBuiltInCollectionClient.ensureAll = {
                BuiltInCollectionEnsureReport(
                    recents: .ready(.init(identity: .recents, packageURL: recentsURL)),
                    allTags: .ready(.init(identity: .allTags, packageURL: allTagsURL)),
                )
            }
            $0.fileManagerClient.urlsForDirectory = { directory, _ in
                directory == .applicationSupportDirectory ? [applicationSupportURL] : []
            }
            $0.fileManagerClient.fileExistsWithIsDirectory = { path, isDirectory in
                if path == finderURL.path { isDirectory?.pointee = ObjCBool(true) }
                return path == finderURL.path || path == recentsURL.path || path == allTagsURL.path
            }
            $0.userDefaultsClient.bool = { flags.value[$0] ?? false }
            $0.userDefaultsClient.setBool = { value, key in flags.withValue { $0[key] = value } }
            $0.onboardingWindowClient.showIfNeeded = { false }
            $0.fileManagerWindowClient.open = { _ in }
        }
        // store.exhaustivity = .off: 연속 두 bootstrap의 persistence 결과와 retry 계약만 추적한다.
        store.exhaustivity = .off

        await store.send(.file(.newWindow(path: nil)))
        await store.receive(\.defaultWindowBootstrapCompleted)
        await store.receive(\.windows)
        XCTAssertFalse(flags.value["fileManager.finderFavoritesPinnedSeedCompleted"] ?? false)
        XCTAssertEqual(
            persistedStore.value.records.map(\.id),
            ["built-in-collection-recents", "built-in-collection-all-tags"],
        )
        flags.withValue {
            $0["fileManager.builtInCollection.recentsPinnedSeed.v1"] = false
            $0["fileManager.builtInCollection.allTagsPinnedSeed.v1"] = false
        }

        await store.send(.event(.windowClosed(windowID)))
        await store.send(.file(.newWindow(path: nil)))
        await store.receive(\.defaultWindowBootstrapCompleted)
        await store.receive(\.windows)
        await store.finish()

        XCTAssertTrue(flags.value["fileManager.finderFavoritesPinnedSeedCompleted"] ?? false)
        XCTAssertTrue(flags.value["fileManager.builtInCollection.recentsPinnedSeed.v1"] ?? false)
        XCTAssertTrue(flags.value["fileManager.builtInCollection.allTagsPinnedSeed.v1"] ?? false)
        XCTAssertEqual(finderLoadCount.value, 2)
        XCTAssertEqual(
            persistedStore.value.records.map(\.id),
            ["built-in-collection-recents", "favorite-file----Users-test-Projects", "built-in-collection-all-tags"],
        )
    }

    /// built-in seed는 항목별 persistence와 completion을 독립적으로 처리한다.
    /// - 검증 내용: Recents 성공 후 All Tags write 실패 시 completion과 restore 결과 분리
    /// - 사전 조건: Finder 완료, 두 descriptor ready, 두 번째 update throw
    /// - 기대 결과: Recents만 완료·복원되고 default window는 정상 완료
    func testBuiltInSeedFailureIsIsolatedPerItemAndWindowStillCompletes() async {
        struct AllTagsWriteFailure: Error {}

        let windowID = UUID()
        let recentsURL = URL(fileURLWithPath: "/tmp/recents.voycoll")
        let allTagsURL = URL(fileURLWithPath: "/tmp/all-tags.voycoll")
        let persistedStore = LockIsolated(ContentTabPinnedRecordStore())
        let flags = LockIsolated(["fileManager.finderFavoritesPinnedSeedCompleted": true])
        let updateCount = LockIsolated(0)
        let metrics = LockIsolated<[BuiltInSeedLifecycleMetric]>([])

        let store = TestStore(initialState: WindowManagerFeature.State()) {
            WindowManagerFeature()
        } withDependencies: {
            $0.uuid = .constant(windowID)
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
            $0.contentTabPinnedRecordClient = ContentTabPinnedRecordClient(
                loadStore: { _ in persistedStore.value },
                saveStore: { value, _ in persistedStore.withValue { $0 = value } },
                updateStoreAndLoad: { _, transform in
                    let count = updateCount.withValue { value in
                        value += 1
                        return value
                    }
                    if count == 2 { throw AllTagsWriteFailure() }
                    let updated = try transform(persistedStore.value)
                    persistedStore.withValue { $0 = updated }
                    return updated
                },
            )
            $0.fileManagerBuiltInCollectionClient.ensureAll = {
                .init(
                    recents: .ready(.init(identity: .recents, packageURL: recentsURL)),
                    allTags: .ready(.init(identity: .allTags, packageURL: allTagsURL)),
                )
            }
            $0.fileManagerClient.fileExistsWithIsDirectory = { path, _ in path == recentsURL.path }
            $0.userDefaultsClient.bool = { flags.value[$0] ?? false }
            $0.userDefaultsClient.setBool = { value, key in flags.withValue { $0[key] = value } }
            $0.metricsClient = Self.metricsClient(recording: metrics)
            $0.onboardingWindowClient.showIfNeeded = { false }
            $0.fileManagerWindowClient.open = { _ in }
        }
        // store.exhaustivity = .off: 항목별 persistence 결과와 downstream window 적용만 검증한다.
        store.exhaustivity = .off

        await store.send(.file(.newWindow(path: nil)))
        await store.receive(\.defaultWindowBootstrapCompleted)
        await store.receive(\.windows)
        await store.finish()

        XCTAssertTrue(flags.value["fileManager.builtInCollection.recentsPinnedSeed.v1"] ?? false)
        XCTAssertFalse(flags.value["fileManager.builtInCollection.allTagsPinnedSeed.v1"] ?? false)
        XCTAssertEqual(persistedStore.value.records.map(\.id), ["built-in-collection-recents"])
        XCTAssertEqual(
            store.state.windows.first?.window.contentTabs.tabs.filter(\.isPinned).map(\.id.rawValue),
            ["built-in-collection-recents"],
        )
        XCTAssertEqual(metrics.value, [
            .init(name: "built_in_pinned_seed_started", tags: nil),
            .init(
                name: "built_in_pinned_item_seeded",
                tags: ["identity": "recents", "outcome": "seeded"],
            ),
            .init(
                name: "built_in_pinned_item_failed",
                tags: ["identity": "all_tags", "outcome": "failed"],
            ),
        ])
    }

    /// completion=true인 built-in은 record가 없어도 reseed하지 않지만 package ensure는 계속 실행한다.
    /// - 검증 내용: ensure 호출과 seed transaction suppression
    /// - 사전 조건: 두 built-in completion=true, 빈 store
    /// - 기대 결과: ensure 1회, update 0회, Home fallback
    func testBuiltInCompletionSuppressesReseedAfterUnpinWhileEnsureStillRuns() async {
        let windowID = UUID()
        let ensureCount = LockIsolated(0)
        let updateCount = LockIsolated(0)
        let metrics = LockIsolated<[BuiltInSeedLifecycleMetric]>([])
        let flags = LockIsolated([
            "fileManager.finderFavoritesPinnedSeedCompleted": true,
            "fileManager.builtInCollection.recentsPinnedSeed.v1": true,
            "fileManager.builtInCollection.allTagsPinnedSeed.v1": true,
        ])

        let store = TestStore(initialState: WindowManagerFeature.State()) {
            WindowManagerFeature()
        } withDependencies: {
            $0.uuid = .constant(windowID)
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
            $0.contentTabPinnedRecordClient = ContentTabPinnedRecordClient(
                loadStore: { _ in ContentTabPinnedRecordStore() },
                saveStore: { _, _ in },
                updateStoreAndLoad: { _, transform in
                    updateCount.withValue { $0 += 1 }
                    return try transform(ContentTabPinnedRecordStore())
                },
            )
            $0.fileManagerBuiltInCollectionClient.ensureAll = {
                ensureCount.withValue { $0 += 1 }
                return .init(recents: .failed, allTags: .failed)
            }
            $0.userDefaultsClient.bool = { flags.value[$0] ?? false }
            $0.userDefaultsClient.setBool = { value, key in flags.withValue { $0[key] = value } }
            $0.metricsClient = Self.metricsClient(recording: metrics)
            $0.onboardingWindowClient.showIfNeeded = { false }
            $0.fileManagerWindowClient.open = { _ in }
        }
        // store.exhaustivity = .off: package ensure 수행과 seed suppression의 경계만 검증한다.
        store.exhaustivity = .off

        await store.send(.file(.newWindow(path: nil)))
        await store.receive(\.defaultWindowBootstrapCompleted)
        await store.receive(\.windows)
        await store.finish()

        XCTAssertEqual(ensureCount.value, 1)
        XCTAssertEqual(updateCount.value, 0)
        XCTAssertFalse(
            store.state.windows.first?.window.contentTabs.tabs.contains(where: \.isPinned) ?? true,
        )
        XCTAssertEqual(metrics.value, [
            .init(name: "built_in_pinned_seed_started", tags: nil),
            .init(
                name: "built_in_pinned_item_suppressed",
                tags: ["identity": "recents", "outcome": "suppressed"],
            ),
            .init(
                name: "built_in_pinned_item_suppressed",
                tags: ["identity": "all_tags", "outcome": "suppressed"],
            ),
        ])
    }

    /// Finder tags가 없어 defer된 All Tags는 다음 bootstrap의 ready 결과에서 seed된다.
    /// - 검증 내용: item completion 독립성, locked store 재시도, final WindowManager downstream restore
    /// - 사전 조건: 첫 ensure는 Recents ready/All Tags deferred, 두 번째 ensure는 두 item ready
    /// - 기대 결과: 첫 window에는 Recents만, 다음 window에는 Recents와 All Tags가 실제 pinned state로 복원됨
    func testAllTagsDeferredThenLaterReadySeedsAndRestores() async {
        let windowID = UUID()
        let recentsURL = URL(fileURLWithPath: "/tmp/recents.voycoll")
        let allTagsURL = URL(fileURLWithPath: "/tmp/all-tags.voycoll")
        let persistedStore = LockIsolated(ContentTabPinnedRecordStore())
        let flags = LockIsolated(["fileManager.finderFavoritesPinnedSeedCompleted": true])
        let ensureCount = LockIsolated(0)
        let metrics = LockIsolated<[BuiltInSeedLifecycleMetric]>([])

        let store = TestStore(initialState: WindowManagerFeature.State()) {
            WindowManagerFeature()
        } withDependencies: {
            $0.uuid = .constant(windowID)
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
            $0.contentTabPinnedRecordClient = ContentTabPinnedRecordClient(
                loadStore: { _ in persistedStore.value },
                saveStore: { value, _ in persistedStore.withValue { $0 = value } },
                updateStoreAndLoad: { _, transform in
                    let updated = try transform(persistedStore.value)
                    persistedStore.withValue { $0 = updated }
                    return updated
                },
            )
            $0.fileManagerBuiltInCollectionClient.ensureAll = {
                let invocation = ensureCount.withValue { value in
                    value += 1
                    return value
                }
                return .init(
                    recents: .ready(.init(identity: .recents, packageURL: recentsURL)),
                    allTags: invocation == 1
                        ? .deferred
                        : .ready(.init(identity: .allTags, packageURL: allTagsURL)),
                )
            }
            $0.fileManagerClient.fileExistsWithIsDirectory = { path, _ in
                path == recentsURL.path || path == allTagsURL.path
            }
            $0.userDefaultsClient.bool = { flags.value[$0] ?? false }
            $0.userDefaultsClient.setBool = { value, key in flags.withValue { $0[key] = value } }
            $0.metricsClient = Self.metricsClient(recording: metrics)
            $0.onboardingWindowClient.showIfNeeded = { false }
            $0.fileManagerWindowClient.open = { _ in }
        }
        // store.exhaustivity = .off: 두 bootstrap의 durable store와 downstream 복원 결과를 검증한다.
        store.exhaustivity = .off

        await store.send(.file(.newWindow(path: nil)))
        await store.receive(\.defaultWindowBootstrapCompleted)
        await store.receive(\.windows)
        XCTAssertEqual(persistedStore.value.records.map(\.id), ["built-in-collection-recents"])
        XCTAssertFalse(flags.value["fileManager.builtInCollection.allTagsPinnedSeed.v1"] ?? false)
        XCTAssertEqual(
            store.state.windows.first?.window.contentTabs.tabs.filter(\.isPinned).map(\.id.rawValue),
            ["built-in-collection-recents"],
        )

        await store.send(.event(.windowClosed(windowID)))
        await store.send(.file(.newWindow(path: nil)))
        await store.receive(\.defaultWindowBootstrapCompleted)
        await store.receive(\.windows)
        await store.finish()

        XCTAssertEqual(persistedStore.value.records.map(\.id), [
            "built-in-collection-recents", "built-in-collection-all-tags",
        ])
        XCTAssertTrue(flags.value["fileManager.builtInCollection.allTagsPinnedSeed.v1"] ?? false)
        XCTAssertEqual(
            store.state.windows.first?.window.contentTabs.tabs.filter(\.isPinned).map(\.id.rawValue),
            persistedStore.value.records.map(\.id),
        )
        XCTAssertEqual(metrics.value, [
            .init(name: "built_in_pinned_seed_started", tags: nil),
            .init(
                name: "built_in_pinned_item_seeded",
                tags: ["identity": "recents", "outcome": "seeded"],
            ),
            .init(
                name: "built_in_pinned_item_deferred",
                tags: ["identity": "all_tags", "outcome": "deferred"],
            ),
            .init(name: "built_in_pinned_seed_started", tags: nil),
            .init(
                name: "built_in_pinned_item_suppressed",
                tags: ["identity": "recents", "outcome": "suppressed"],
            ),
            .init(
                name: "built_in_pinned_item_seeded",
                tags: ["identity": "all_tags", "outcome": "seeded"],
            ),
        ])
        for metric in metrics.value {
            guard let tags = metric.tags else { continue }
            XCTAssertEqual(Set(tags.keys), Set(["identity", "outcome"]))
            XCTAssertFalse(tags.values.contains(where: { value in
                value.contains("/") || value.contains("?") || value.contains("Work")
            }))
        }
    }

    /// persisted record 저장 뒤 completion 기록이 중단되면 다음 bootstrap이 중복 없이 완료를 복구한다.
    /// - 검증 내용: 첫 record write 성공, completion 누락, 두 번째 locked transform과 completion recovery
    /// - 사전 조건: Finder seed 완료, Recents ready, 첫 Recents completion write만 유실
    /// - 기대 결과: persisted/restored Recents record는 한 개이고 두 번째 실행 후 completion=true
    func testBuiltInSeedMissingCompletionAfterPersistRetriesWithoutDuplicateAndRecovers() async {
        let windowID = UUID()
        let recentsURL = URL(fileURLWithPath: "/tmp/recents.voycoll")
        let persistedStore = LockIsolated(ContentTabPinnedRecordStore())
        let flags = LockIsolated([SettingsKeys.finderFavoritesPinnedSeedCompleted: true])
        let recentsCompletionAttempts = LockIsolated(0)
        let updateCount = LockIsolated(0)
        let store = TestStore(initialState: WindowManagerFeature.State()) {
            WindowManagerFeature()
        } withDependencies: {
            $0.uuid = .constant(windowID)
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
            $0.contentTabPinnedRecordClient = ContentTabPinnedRecordClient(
                loadStore: { _ in persistedStore.value },
                saveStore: { value, _ in persistedStore.withValue { $0 = value } },
                updateStoreAndLoad: { _, transform in
                    updateCount.withValue { $0 += 1 }
                    let updated = try transform(persistedStore.value)
                    persistedStore.withValue { $0 = updated }
                    return updated
                },
            )
            $0.fileManagerBuiltInCollectionClient.ensureAll = {
                .init(
                    recents: .ready(.init(identity: .recents, packageURL: recentsURL)),
                    allTags: .deferred,
                )
            }
            $0.fileManagerClient.fileExistsWithIsDirectory = { path, _ in path == recentsURL.path }
            $0.userDefaultsClient.bool = { flags.value[$0] ?? false }
            $0.userDefaultsClient.setBool = { value, key in
                if value, key == SettingsKeys.recentsPinnedSeedCompleted {
                    let attempt = recentsCompletionAttempts.withValue { count in
                        count += 1
                        return count
                    }
                    if attempt == 1 { return }
                }
                flags.withValue { $0[key] = value }
            }
            $0.onboardingWindowClient.showIfNeeded = { false }
            $0.fileManagerWindowClient.open = { _ in }
        }
        // store.exhaustivity = .off: 두 bootstrap 사이 durable interruption과 최종 복원 상태만 검증한다.
        store.exhaustivity = .off

        await store.send(.file(.newWindow(path: nil)))
        await store.receive(\.defaultWindowBootstrapCompleted)
        await store.receive(\.windows)
        XCTAssertEqual(persistedStore.value.records.map(\.id), ["built-in-collection-recents"])
        XCTAssertFalse(flags.value[SettingsKeys.recentsPinnedSeedCompleted] ?? false)

        await store.send(.event(.windowClosed(windowID)))
        await store.send(.file(.newWindow(path: nil)))
        await store.receive(\.defaultWindowBootstrapCompleted)
        await store.receive(\.windows)
        await store.finish()

        XCTAssertEqual(updateCount.value, 2)
        XCTAssertEqual(recentsCompletionAttempts.value, 2)
        XCTAssertTrue(flags.value[SettingsKeys.recentsPinnedSeedCompleted] ?? false)
        XCTAssertEqual(persistedStore.value.records.map(\.id), ["built-in-collection-recents"])
        XCTAssertEqual(
            store.state.windows.first?.window.contentTabs.tabs.filter(\.isPinned).map(\.id.rawValue),
            ["built-in-collection-recents"],
        )
    }

    /// 실제 built-in package ensure 결과가 locked pinned store를 거쳐 WindowManager state로 복원된다.
    /// - 검증 내용: live package file 출력, live updateStoreAndLoad persistence, pinned ContentTab restore
    /// - 사전 조건: 하나의 temp Application Support와 동일한 persistent UserDefaults fixture, Finder tag `Work`
    /// - 기대 결과: canonical package 두 개와 Recents/All Tags pinned Collection tab이 동일 URL로 복원됨
    func testLiveBuiltInEnsureFeedsLockedPinnedStoreAndRestoresWindowState() async throws {
        let windowID = UUID()
        let applicationSupportURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("WindowManagerBuiltInBootstrap-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: applicationSupportURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: applicationSupportURL) }
        let defaultsClient = UserDefaultsClient.testValue
        defaultsClient.setBool(true, SettingsKeys.finderFavoritesPinnedSeedCompleted)
        var fileManagerClient = FileManagerClient.liveValue
        fileManagerClient.urlsForDirectory = { directory, domain in
            guard directory == .applicationSupportDirectory, domain == .userDomainMask else { return [] }
            return [applicationSupportURL]
        }
        let pinnedRecordClient = ContentTabPinnedRecordClient.liveValue
        let store = TestStore(initialState: WindowManagerFeature.State()) {
            WindowManagerFeature()
        } withDependencies: {
            $0.uuid = .constant(windowID)
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
            $0.fileManagerBuiltInCollectionClient = .liveValue
            $0.collectionFileClient = .liveValue
            $0.contentTabPinnedRecordClient = pinnedRecordClient
            $0.fileManagerClient = fileManagerClient
            $0.finderFavoritesTagClient.favoriteTagNames = { ["Work"] }
            $0.registryClient = WindowManagerBuiltInCollectionTestRegistry.client
            $0.userDefaultsClient = defaultsClient
            $0.fileManagerFavoritesClient.loadFavorites = { _, _ in [] }
            $0.metricsClient = MetricsClient(
                logMetric: { _, _, _ in },
                logDAUNavigation: { _ in },
                logDAUEntryAction: { _, _ in },
            )
            $0.onboardingWindowClient.showIfNeeded = { false }
            $0.fileManagerWindowClient.open = { _ in }
        }
        // store.exhaustivity = .off: real file/persistence integration의 최종 pinned state만 검증한다.
        store.exhaustivity = .off

        await store.send(.file(.newWindow(path: nil)))
        await store.receive(\.defaultWindowBootstrapCompleted)
        await store.receive(\.windows)
        await store.finish()

        let recentsURL = BuiltInCollectionIdentity.recents.canonicalPackageURL(
            applicationSupportURL: applicationSupportURL,
        )
        let allTagsURL = BuiltInCollectionIdentity.allTags.canonicalPackageURL(
            applicationSupportURL: applicationSupportURL,
        )
        let recentsFile = try await CollectionFileClient.liveValue.load(recentsURL).file
        let allTagsFile = try await CollectionFileClient.liveValue.load(allTagsURL).file
        let persistedStore = try pinnedRecordClient.loadStore(defaultsClient)
        let pinnedTabs = store.state.windows.first?.window.contentTabs.tabs.filter(\.isPinned) ?? []

        XCTAssertEqual(recentsFile.id, BuiltInCollectionIdentity.recents.rawValue)
        XCTAssertEqual(allTagsFile.id, BuiltInCollectionIdentity.allTags.rawValue)
        XCTAssertEqual(persistedStore.records.map(\.id), [
            "built-in-collection-recents", "built-in-collection-all-tags",
        ])
        XCTAssertEqual(persistedStore.records.map(\.anchor), [
            .collectionFile(url: recentsURL), .collectionFile(url: allTagsURL),
        ])
        XCTAssertEqual(pinnedTabs.map(\.id.rawValue), persistedStore.records.map(\.id))
        XCTAssertEqual(pinnedTabs.map(\.page), [.collection, .collection])
        XCTAssertEqual(pinnedTabs.map(\.anchor), persistedStore.records.map(\.anchor))
    }

    /// load·Finder update·built-in ensure·reload이 모두 실패해도 default window는 Home으로 완료된다.
    /// - 검증 내용: bootstrap failure isolation과 completion action downstream 적용
    /// - 사전 조건: load/update throw, ensure failed
    /// - 기대 결과: failed action 대신 completed Home state가 window에 적용
    func testDefaultBootstrapAllFailuresStillCompletesWithHomeFallback() async {
        struct BootstrapFailure: Error {}

        let windowID = UUID()
        let store = TestStore(initialState: WindowManagerFeature.State()) {
            WindowManagerFeature()
        } withDependencies: {
            $0.uuid = .constant(windowID)
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
            $0.contentTabPinnedRecordClient = ContentTabPinnedRecordClient(
                loadStore: { _ in throw BootstrapFailure() },
                saveStore: { _, _ in throw BootstrapFailure() },
                updateStoreAndLoad: { _, _ in throw BootstrapFailure() },
            )
            $0.fileManagerFavoritesClient.loadFavorites = { _, _ in [] }
            $0.fileManagerBuiltInCollectionClient.ensureAll = { .init(recents: .failed, allTags: .failed) }
            $0.userDefaultsClient.bool = { _ in false }
            $0.userDefaultsClient.setBool = { _, _ in }
            $0.onboardingWindowClient.showIfNeeded = { false }
            $0.fileManagerWindowClient.open = { _ in }
        }
        // store.exhaustivity = .off: 모든 dependency 실패 뒤 completion downstream state만 검증한다.
        store.exhaustivity = .off

        await store.send(.file(.newWindow(path: nil)))
        await store.receive(\.defaultWindowBootstrapCompleted)
        await store.receive(\.windows)
        await store.finish()

        let tabs = store.state.windows.first?.window.contentTabs.tabs
        XCTAssertEqual(tabs?.count, 1)
        XCTAssertEqual(tabs?.first?.page, .home)
        XCTAssertFalse(tabs?.contains(where: \.isPinned) ?? true)
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

    nonisolated private static func metricsClient(
        recording metrics: LockIsolated<[BuiltInSeedLifecycleMetric]>,
    ) -> MetricsClient {
        MetricsClient(
            logMetric: { name, value, tags in
                XCTAssertEqual(value, 1)
                metrics.withValue { $0.append(.init(name: name, tags: tags)) }
            },
            logDAUNavigation: { _ in },
            logDAUEntryAction: { _, _ in },
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

private enum WindowManagerBuiltInCollectionTestRegistry {
    static let client = RegistryClient(
        allProperties: { [] },
        labelForKey: { $0 },
        propertyTypeString: { key in
            switch key {
            case "tag_names": "categorical"
            case "last_used_date": "date"
            case "content_type_tree": "string"
            default: "unknown"
            }
        },
        propertyUnitSpec: { _ in nil },
        operatorCodes: { _ in ["any", "gt", "neq"] },
        operatorDefinition: { OperatorDefinition(uiLabel: $0, uiValueKind: nil) },
        operatorValueUIKind: { code, typeKey in
            switch (code, typeKey) {
            case ("any", "categorical"): "listText"
            case ("gt", "date"): "singleDate"
            case ("neq", "string"): "singleText"
            default: "singleText"
            }
        },
        resolvePropertyKey: { .canonical($0) },
    )
}

private struct BuiltInSeedLifecycleMetric: Equatable {
    let name: String
    let tags: [String: String]?
}
