import ComposableArchitecture
import Foundation
@testable import Voyager
import VoyagerEntitiesAppPreferences
import VoyagerEntitiesCollection
import VoyagerEntitiesEntry
import VoyagerEntitiesTag
import VoyagerFeaturesComposer
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

    /// pinned 저장 성공 이벤트는 external marker 여부와 무관하게 열린 모든 window로 fan-out한다.
    /// pinned sidebar가 window마다 어긋나지 않고 external unpinned tab이 보존되는지 검증한다.
    /// - 검증 내용: child pinnedRecordSaveSucceeded → pinnedContentTabsStoreChanged → 모든 window applyPinnedContentTabs
    /// - 사전 조건: 일반 window와 active external marker window, global pinned store 1개
    /// - 기대 결과: 두 window 모두 동일한 pinned tab을 받고 external window의 unpinned tab은 유지
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
        initialState.externalWindowBatchIDs[secondID] = UUID()

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
        XCTAssertEqual(
            store.state.windows[id: secondID]?.window.contentTabs.tabs.contains {
                !$0.isPinned && $0.anchor == .directory(path: "/Users/test/B")
            },
            true,
        )
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
            $0.builtInCollectionClient = .liveValue
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

    // MARK: - External Open Placement

    /// key/resign/close/new-window lifecycle에서 focused state와 runtime MRU가 서로 다른 계약을 유지한다.
    func testWindowLifecycleMaintainsRuntimeMRUIndependentlyFromFocus() async {
        let firstID = UUID()
        let secondID = UUID()
        var initialState = WindowManagerFeature.State()
        initialState.windows = [
            Self.makeWindow(id: firstID, tabCount: 1),
            Self.makeWindow(id: secondID, tabCount: 1),
        ]
        let newWindowID = UUID(100)
        let store = TestStore(initialState: initialState) {
            WindowManagerFeature()
        } withDependencies: {
            $0.uuid = .constant(newWindowID)
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
            $0.onboardingWindowClient.showIfNeeded = { false }
            $0.fileManagerWindowClient.open = { _ in }
        }
        // store.exhaustivity = .off: 새 창 bootstrap effect는 MRU lifecycle assertion 범위가 아니다.
        store.exhaustivity = .off

        await store.send(.event(.windowBecameKey(firstID))) {
            $0.focusedWindowID = firstID
            $0.lastUsedWindowIDs = [firstID]
        }
        await store.send(.event(.windowBecameKey(secondID))) {
            $0.focusedWindowID = secondID
            $0.lastUsedWindowIDs = [secondID, firstID]
        }
        await store.send(.event(.windowResignedKey(secondID))) {
            $0.focusedWindowID = nil
        }
        await store.send(.event(.windowClosed(secondID))) {
            $0.windows.remove(id: secondID)
            $0.lastUsedWindowIDs = [firstID]
        }
        await store.send(.file(.newWindow(path: "/new"))) {
            $0.windows.append(.init(id: newWindowID, window: .makeInitial(path: "/new")))
            $0.focusedWindowID = newWindowID
            $0.lastUsedWindowIDs = [newWindowID, firstID]
        }
    }

    /// preferred window가 commit 전에 닫히면 frozen MRU의 다음 생존 window만 선택한다.
    func testPlacementRevalidatesPreferredMRUAfterClose() async {
        let closedID = UUID()
        let survivingID = UUID()
        let unrelatedID = UUID()
        let itemID = UUID()
        let batchID = UUID()
        var initialState = WindowManagerFeature.State()
        initialState.windows = [
            Self.makeWindow(id: survivingID, tabCount: 19),
            Self.makeWindow(id: unrelatedID, tabCount: 1),
        ]
        initialState.lastUsedWindowIDs = [unrelatedID, survivingID]
        let request = ExternalOpenPlacementRequest(
            batchID: batchID,
            itemIDs: [itemID],
            preferredWindowIDs: [closedID, survivingID],
        )
        let store = TestStore(initialState: initialState) {
            WindowManagerFeature()
        } withDependencies: {
            $0.uuid = .incrementing
        }

        await store.send(.placement(.plan(request)))
        await store.receive { action in
            guard case let .delegate(.externalOpenPlacementCompleted(completion)) = action,
                  case let .success(plan) = completion.result
            else {
                return false
            }
            return plan.batchID == batchID
                && plan.windows.count == 1
                && plan.windows[0].windowID == survivingID
                && !plan.windows[0].isNewWindow
                && plan.windows[0].items.map(\.itemID) == [itemID]
        }
    }

    /// preferred snapshot이 비어도 focused live window가 있으면 새 window 대신 해당 window를 재사용한다.
    func testPlacementUsesFocusedLiveWindowWhenPreferredSnapshotIsEmpty() async {
        let firstID = UUID()
        let focusedID = UUID()
        let itemID = UUID()
        var initialState = WindowManagerFeature.State()
        initialState.windows = [
            Self.makeWindow(id: firstID, tabCount: 1),
            Self.makeWindow(id: focusedID, tabCount: 19),
        ]
        initialState.focusedWindowID = focusedID
        let store = TestStore(initialState: initialState) {
            WindowManagerFeature()
        } withDependencies: {
            $0.uuid = .incrementing
        }

        await store.send(.placement(.plan(.init(
            batchID: UUID(),
            itemIDs: [itemID],
            preferredWindowIDs: [],
        ))))
        await store.receive { action in
            guard case let .delegate(.externalOpenPlacementCompleted(completion)) = action,
                  case let .success(plan) = completion.result
            else {
                return false
            }
            return plan.windows.count == 1
                && plan.windows[0].windowID == focusedID
                && !plan.windows[0].isNewWindow
                && plan.windows[0].items.map(\.itemID) == [itemID]
        }
    }

    /// preferred snapshot과 focus가 비어도 live MRU의 첫 window를 재사용한다.
    func testPlacementUsesLiveMRUWhenPreferredSnapshotAndFocusAreEmpty() async {
        let firstID = UUID()
        let mostRecentID = UUID()
        let itemID = UUID()
        var initialState = WindowManagerFeature.State()
        initialState.windows = [
            Self.makeWindow(id: firstID, tabCount: 1),
            Self.makeWindow(id: mostRecentID, tabCount: 19),
        ]
        initialState.lastUsedWindowIDs = [mostRecentID, firstID]
        let store = TestStore(initialState: initialState) {
            WindowManagerFeature()
        } withDependencies: {
            $0.uuid = .incrementing
        }

        await store.send(.placement(.plan(.init(
            batchID: UUID(),
            itemIDs: [itemID],
            preferredWindowIDs: [],
        ))))
        await store.receive { action in
            guard case let .delegate(.externalOpenPlacementCompleted(completion)) = action,
                  case let .success(plan) = completion.result
            else {
                return false
            }
            return plan.windows.count == 1
                && plan.windows[0].windowID == mostRecentID
                && !plan.windows[0].isNewWindow
                && plan.windows[0].items.map(\.itemID) == [itemID]
        }
    }

    /// preferred snapshot, focus, live MRU가 모두 비어도 첫 live state window를 재사용한다.
    func testPlacementUsesFirstLiveWindowWhenRuntimeHistoryIsEmpty() async {
        let firstID = UUID()
        let secondID = UUID()
        let itemID = UUID()
        var initialState = WindowManagerFeature.State()
        initialState.windows = [
            Self.makeWindow(id: firstID, tabCount: 19),
            Self.makeWindow(id: secondID, tabCount: 1),
        ]
        let store = TestStore(initialState: initialState) {
            WindowManagerFeature()
        } withDependencies: {
            $0.uuid = .incrementing
        }

        await store.send(.placement(.plan(.init(
            batchID: UUID(),
            itemIDs: [itemID],
            preferredWindowIDs: [],
        ))))
        await store.receive { action in
            guard case let .delegate(.externalOpenPlacementCompleted(completion)) = action,
                  case let .success(plan) = completion.result
            else {
                return false
            }
            return plan.windows.count == 1
                && plan.windows[0].windowID == firstID
                && !plan.windows[0].isNewWindow
                && plan.windows[0].items.map(\.itemID) == [itemID]
        }
    }

    /// preferred snapshot과 live MRU의 교집합이 없으면 기존 unrelated window 대신 새 window를 사용한다.
    func testPlacementCreatesNewWindowWhenPreferredMRUHasNoSurvivor() async {
        let closedID = UUID()
        let unrelatedID = UUID()
        let itemIDs = [UUID(), UUID()]
        var initialState = WindowManagerFeature.State()
        initialState.windows = [Self.makeWindow(id: unrelatedID, tabCount: 1)]
        initialState.lastUsedWindowIDs = [unrelatedID]
        let store = TestStore(initialState: initialState) {
            WindowManagerFeature()
        } withDependencies: {
            $0.uuid = .incrementing
        }

        await store.send(.placement(.plan(.init(
            batchID: UUID(),
            itemIDs: itemIDs,
            preferredWindowIDs: [closedID],
        ))))
        await store.receive { action in
            guard case let .delegate(.externalOpenPlacementCompleted(completion)) = action,
                  case let .success(plan) = completion.result
            else {
                return false
            }
            return plan.windows.count == 1
                && plan.windows[0].windowID != unrelatedID
                && plan.windows[0].isNewWindow
                && plan.windows[0].items.map(\.itemID) == itemIDs
        }
    }

    /// preferred existing window 하나만 free slot을 소비하고 older MRU에는 spill하지 않는다.
    func testPlacementUsesOnlyOnePreferredExistingWindowBeforeOverflow() async {
        let preferredID = UUID()
        let olderID = UUID()
        let itemIDs = (0 ..< 22).map { _ in UUID() }
        var initialState = WindowManagerFeature.State()
        initialState.windows = [
            Self.makeWindow(id: preferredID, tabCount: 19),
            Self.makeWindow(id: olderID, tabCount: 1),
        ]
        initialState.lastUsedWindowIDs = [preferredID, olderID]
        let store = TestStore(initialState: initialState) {
            WindowManagerFeature()
        } withDependencies: {
            $0.uuid = .incrementing
        }

        await store.send(.placement(.plan(.init(
            batchID: UUID(),
            itemIDs: itemIDs,
            preferredWindowIDs: [preferredID, olderID],
        ))))
        await store.receive { action in
            guard case let .delegate(.externalOpenPlacementCompleted(completion)) = action,
                  case let .success(plan) = completion.result
            else {
                return false
            }
            return plan.windows.map(\.windowID).first == preferredID
                && !plan.windows.map(\.windowID).contains(olderID)
                && plan.windows.map(\.items.count) == [1, 20, 1]
                && plan.windows.flatMap(\.items).map(\.itemID) == itemIDs
                && Set(plan.windows.flatMap(\.items).map(\.tabID)).count == itemIDs.count
        }
    }

    /// free 0/1/20과 valid 20/21/40/41 경계에서 overflow chunk 수와 크기가 항상 최소다.
    func testPlacementBoundaryMatrixUsesMinimalChunks() async {
        let scenarios = [
            PlacementBoundaryScenario(free: 0, valid: 20, expected: [20]),
            PlacementBoundaryScenario(free: 0, valid: 21, expected: [20, 1]),
            PlacementBoundaryScenario(free: 0, valid: 40, expected: [20, 20]),
            PlacementBoundaryScenario(free: 0, valid: 41, expected: [20, 20, 1]),
            PlacementBoundaryScenario(free: 1, valid: 20, expected: [1, 19]),
            PlacementBoundaryScenario(free: 1, valid: 21, expected: [1, 20]),
            PlacementBoundaryScenario(free: 1, valid: 40, expected: [1, 20, 19]),
            PlacementBoundaryScenario(free: 1, valid: 41, expected: [1, 20, 20]),
            PlacementBoundaryScenario(free: 20, valid: 20, expected: [20]),
            PlacementBoundaryScenario(free: 20, valid: 21, expected: [20, 1]),
            PlacementBoundaryScenario(free: 20, valid: 40, expected: [20, 20]),
            PlacementBoundaryScenario(free: 20, valid: 41, expected: [20, 20, 1]),
        ]

        for scenario in scenarios {
            let preferredID = UUID()
            let itemIDs = (0 ..< scenario.valid).map { _ in UUID() }
            var initialState = WindowManagerFeature.State()
            initialState.windows = [
                Self.makeWindow(id: preferredID, tabCount: ContentTabConstants.maxTabs - scenario.free),
            ]
            initialState.lastUsedWindowIDs = [preferredID]
            let store = TestStore(initialState: initialState) {
                WindowManagerFeature()
            } withDependencies: {
                $0.uuid = .incrementing
            }

            await store.send(.placement(.plan(.init(
                batchID: UUID(),
                itemIDs: itemIDs,
                preferredWindowIDs: [preferredID],
            ))))
            await store.receive { action in
                guard case let .delegate(.externalOpenPlacementCompleted(completion)) = action,
                      case let .success(plan) = completion.result
                else {
                    return false
                }
                return plan.windows.map(\.items.count) == scenario.expected
                    && plan.windows.allSatisfy { !$0.items.isEmpty && $0.items.count <= 20 }
                    && plan.windows.flatMap(\.items).map(\.itemID) == itemIDs
            }
        }
    }

    /// probe가 진행되는 동안 preferred window에 tab이 추가되면 placement는 live free capacity를 다시 계산한다.
    func testPlacementRecalculatesCapacityAfterTabsAddedDuringProbe() async {
        let preferredID = UUID()
        let itemIDs = [UUID(), UUID()]
        let request = ExternalOpenPlacementRequest(
            batchID: UUID(),
            itemIDs: itemIDs,
            preferredWindowIDs: [preferredID],
        )
        var initialState = WindowManagerFeature.State()
        initialState.windows = [Self.makeWindow(id: preferredID, tabCount: 18)]
        initialState.lastUsedWindowIDs = [preferredID]
        initialState.windows[id: preferredID]?.window.contentTabs.tabs.append(ContentTabItem(
            id: ContentTabID(rawValue: "added-during-probe"),
            page: .directory,
            anchor: .directory(path: "/added-during-probe"),
            isPinned: false,
        ))
        let store = TestStore(initialState: initialState) {
            WindowManagerFeature()
        } withDependencies: {
            $0.uuid = .incrementing
        }

        await store.send(.placement(.plan(request)))
        await store.receive { action in
            guard case let .delegate(.externalOpenPlacementCompleted(completion)) = action,
                  case let .success(plan) = completion.result
            else {
                return false
            }
            return plan.windows.map(\.items.count) == [1, 1]
                && plan.windows.first?.windowID == preferredID
                && plan.windows.flatMap(\.items).map(\.itemID) == itemIDs
        }
    }

    /// uuid dependency가 만든 window/tab ID는 commit 전에 모두 유일해야 한다.
    func testPlacementRejectsDuplicateAllocatedIDsBeforeMutation() async {
        let duplicateID = UUID()
        let initialState = WindowManagerFeature.State()
        let store = TestStore(initialState: initialState) {
            WindowManagerFeature()
        } withDependencies: {
            $0.uuid = .constant(duplicateID)
        }

        await store.send(.placement(.plan(.init(
            batchID: UUID(),
            itemIDs: [UUID(), UUID()],
            preferredWindowIDs: [],
        ))))
        await store.receive { action in
            guard case let .delegate(.externalOpenPlacementCompleted(completion)) = action,
                  case let .failure(failure) = completion.result
            else {
                return false
            }
            return failure == .duplicateAllocatedID(duplicateID)
        }
        XCTAssertEqual(store.state, initialState)
    }

    /// duplicate item ID와 maxTabs 초과 live state는 mutation 없이 fail-closed한다.
    func testPlacementRejectsDuplicateItemsAndImpossibleCapacityBeforeMutation() async {
        let duplicateItemID = UUID()
        let duplicateState = WindowManagerFeature.State()
        let duplicateStore = TestStore(initialState: duplicateState) {
            WindowManagerFeature()
        }
        await duplicateStore.send(.placement(.plan(.init(
            batchID: UUID(),
            itemIDs: [duplicateItemID, duplicateItemID],
            preferredWindowIDs: [],
        ))))
        await duplicateStore.receive { action in
            guard case let .delegate(.externalOpenPlacementCompleted(completion)) = action,
                  case let .failure(failure) = completion.result
            else {
                return false
            }
            return failure == .duplicateItemID(duplicateItemID)
        }
        XCTAssertEqual(duplicateStore.state, duplicateState)

        let impossibleID = UUID()
        var impossibleState = WindowManagerFeature.State()
        impossibleState.windows = [Self.makeWindow(id: impossibleID, tabCount: 21)]
        impossibleState.lastUsedWindowIDs = [impossibleID]
        let impossibleStore = TestStore(initialState: impossibleState) {
            WindowManagerFeature()
        }
        await impossibleStore.send(.placement(.plan(.init(
            batchID: UUID(),
            itemIDs: [UUID()],
            preferredWindowIDs: [impossibleID],
        ))))
        await impossibleStore.receive { action in
            guard case let .delegate(.externalOpenPlacementCompleted(completion)) = action,
                  case let .failure(failure) = completion.result
            else {
                return false
            }
            return failure == .invalidExistingTabCount(windowID: impossibleID, count: 21)
        }
        XCTAssertEqual(impossibleStore.state, impossibleState)
    }

    /// valid item이 없으면 ID를 소비하거나 window placement를 만들지 않는다.
    func testPlacementWithZeroValidItemsCreatesNothing() async {
        let existingID = UUID()
        var initialState = WindowManagerFeature.State()
        initialState.windows = [Self.makeWindow(id: existingID, tabCount: 1)]
        initialState.lastUsedWindowIDs = [existingID]
        let store = TestStore(initialState: initialState) {
            WindowManagerFeature()
        } withDependencies: {
            $0.uuid = .constant(existingID)
        }
        let batchID = UUID()

        await store.send(.placement(.plan(.init(
            batchID: batchID,
            itemIDs: [],
            preferredWindowIDs: [existingID],
        ))))
        await store.receive { action in
            guard case let .delegate(.externalOpenPlacementCompleted(completion)) = action,
                  case let .success(plan) = completion.result
            else {
                return false
            }
            return plan == .init(batchID: batchID, windows: [])
        }
        XCTAssertEqual(store.state, initialState)
    }

    /// placement failure delegate는 요청을 만든 batch identity를 보존한다.
    func testPlacementFailureDelegateCarriesOriginatingBatchID() async {
        let batchID = UUID()
        let duplicateItemID = UUID()
        let store = TestStore(initialState: WindowManagerFeature.State()) {
            WindowManagerFeature()
        }

        await store.send(.placement(.plan(.init(
            batchID: batchID,
            itemIDs: [duplicateItemID, duplicateItemID],
            preferredWindowIDs: [],
        ))))
        await store.receive { action in
            guard case let .delegate(.externalOpenPlacementCompleted(completion)) = action else {
                return false
            }
            return completion.batchID == batchID
                && completion.result == .failure(.duplicateItemID(duplicateItemID))
        }
    }

    /// authorization이 없는 stale apply는 window state와 native open을 변경하지 않는다.
    func testUnauthorizedPlacementApplicationDoesNotMutateOrOpenWindow() async {
        let batchID = UUID()
        let itemID = UUID()
        let windowID = UUID()
        let tabID = ContentTabID(rawValue: "unauthorized-apply")
        let plan = ExternalOpenPlacementPlan(
            batchID: batchID,
            windows: [
                .init(
                    windowID: windowID,
                    isNewWindow: true,
                    items: [.init(itemID: itemID, tabID: tabID)],
                ),
            ],
        )
        let openedWindowIDs = LockIsolated<[UUID]>([])
        let store = TestStore(initialState: WindowManagerFeature.State()) {
            WindowManagerFeature()
        } withDependencies: {
            $0.fileManagerWindowClient.open = { id in
                openedWindowIDs.withValue { $0.append(id) }
            }
        }
        // store.exhaustivity = .off: unauthorized command가 child effect를 전혀 만들지 않는 경계만 검증함.
        store.exhaustivity = .off

        await store.send(.placement(.apply(
            plan: plan,
            reservationsByItemID: [
                itemID: .init(id: tabID, anchor: .directory(path: "/tmp/unauthorized-apply")),
            ],
        )))
        await store.finish()

        XCTAssertTrue(store.state.windows.isEmpty)
        XCTAssertTrue(store.state.externalWindowBatchIDs.isEmpty)
        XCTAssertTrue(openedWindowIDs.value.isEmpty)
    }

    /// reservation tab identity가 commit 전에 달라지면 mutation 없이 batch-scoped failure를 보낸다.
    func testPlacementApplicationValidationFailureEmitsBatchScopedTerminal() async {
        let batchID = UUID()
        let itemID = UUID()
        let windowID = UUID()
        let plan = ExternalOpenPlacementPlan(
            batchID: batchID,
            windows: [
                .init(
                    windowID: windowID,
                    isNewWindow: true,
                    items: [.init(itemID: itemID, tabID: ContentTabID(rawValue: "planned-tab"))],
                ),
            ],
        )
        var initialState = WindowManagerFeature.State()
        initialState.authorizedExternalOpenBatchID = batchID
        let store = TestStore(initialState: initialState) {
            WindowManagerFeature()
        }

        await store.send(.placement(.apply(
            plan: plan,
            reservationsByItemID: [
                itemID: .init(
                    id: ContentTabID(rawValue: "raced-tab"),
                    anchor: .directory(path: "/tmp/race"),
                ),
            ],
        ))) {
            $0.authorizedExternalOpenBatchID = nil
        }
        await store.receive(
            \.delegate.externalOpenApplyCompleted,
            .init(batchID: batchID, result: .failure(.validationFailed)),
        )

        initialState.authorizedExternalOpenBatchID = nil
        XCTAssertEqual(store.state, initialState)
    }

    /// 기존 mounted window의 external reservation은 state commit 후 canonical tab handoff로 활성화된다.
    /// Directory load가 장기 실행 중이어도 apply terminal은 load 완료를 기다리지 않는 경계를 검증한다.
    /// - 검증 내용: ordered append, old→new active 전환, suspended load 전 terminal 1회다.
    /// - 사전 조건: seed tab이 active인 기존 window와 Directory reservation 하나다.
    /// - 기대 결과: 마지막 preallocated tab이 active가 되고 apply completion은 load gate가 닫힌 동안 도착한다.
    func testPlacementApplicationActivatesExistingWindowWithoutAwaitingDirectoryLoad() async throws {
        let batchID = UUID()
        let windowID = UUID()
        let itemID = UUID()
        let tabID = ContentTabID(rawValue: "existing-window-external")
        var existingWindow = FileManagerWindowFeature.State.makeInitial(path: "/seed")
        existingWindow.content.entryViewLayout.entryOperations.windowID = windowID
        existingWindow.content.composer.cancellationOwnerID = windowID
        existingWindow.syncActiveTabContentState()
        let previousActiveID = try XCTUnwrap(existingWindow.contentTabs.activeTabID)
        var initialState = WindowManagerFeature.State()
        initialState.windows = [.init(id: windowID, window: existingWindow)]
        initialState.authorizedExternalOpenBatchID = batchID
        let plan = ExternalOpenPlacementPlan(
            batchID: batchID,
            windows: [
                .init(
                    windowID: windowID,
                    isNewWindow: false,
                    items: [.init(itemID: itemID, tabID: tabID)],
                ),
            ],
        )
        let loadGate = WindowBootstrapSuspensionGate()
        let loadStarted = expectation(description: "destination load started")
        let terminalReceived = expectation(description: "apply terminal received")
        let terminalCount = LockIsolated(0)
        let store = TestStore(initialState: initialState) {
            CombineReducers {
                WindowManagerFeature()
                Reduce { _, action in
                    if case .delegate(.externalOpenApplyCompleted(.init(
                        batchID: batchID,
                        result: .success(plan),
                    ))) = action {
                        terminalCount.withValue { $0 += 1 }
                        terminalReceived.fulfill()
                    }
                    return .none
                }
            }
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
            $0.entryLoadingClient.loadItems = { url, _ in
                XCTAssertEqual(url.path, "/external")
                loadStarted.fulfill()
                await loadGate.wait()
                return []
            }
            $0.fileChangeGatewayClient.observeEvents = {
                AsyncStream { $0.finish() }
            }
        }
        // store.exhaustivity = .off: child navigation action보다 WindowManager commit/terminal 경계를 검증한다.
        store.exhaustivity = .off

        await store.send(.placement(.apply(
            plan: plan,
            reservationsByItemID: [
                itemID: .init(id: tabID, anchor: .directory(path: "/external")),
            ],
        )))
        await fulfillment(of: [loadStarted, terminalReceived], timeout: 1)
        await store.skipReceivedActions()

        let committedWindow = try XCTUnwrap(store.state.windows[id: windowID]?.window)
        XCTAssertEqual(committedWindow.contentTabs.tabs.map(\.id), [previousActiveID, tabID])
        XCTAssertEqual(committedWindow.contentTabs.activeTabID, tabID)
        XCTAssertEqual(committedWindow.contentTabs.previousActiveTabID, previousActiveID)
        XCTAssertEqual(terminalCount.value, 1)

        await loadGate.open()
        await store.skipReceivedActions()
        await store.finish()
    }

    /// 새 external no-Home window의 active Collection은 canonical open을 정확히 한 번 시작한다.
    /// Collection load가 장기 실행 중이어도 apply terminal은 load 완료를 기다리지 않는 경계를 검증한다.
    /// - 검증 내용: active Collection load 1회, suspended load 전 terminal 1회, 모든 tab의 window context 보존이다.
    /// - 사전 조건: Directory와 active Collection reservation으로 구성된 새 window 하나다.
    /// - 기대 결과: Collection open이 시작되고 terminal은 load gate가 닫힌 동안 도착한다.
    func testPlacementApplicationStartsNewWindowCollectionOpenWithoutAwaitingLoad() async throws {
        enum TestError: Error {
            case loadFailed
        }

        let batchID = UUID()
        let windowID = UUID()
        let directoryItemID = UUID()
        let collectionItemID = UUID()
        let directoryTabID = ContentTabID(rawValue: "new-window-directory")
        let collectionTabID = ContentTabID(rawValue: "new-window-collection")
        let collectionURL = URL(fileURLWithPath: "/tmp/new-window-active.voycoll")
        let plan = ExternalOpenPlacementPlan(
            batchID: batchID,
            windows: [
                .init(
                    windowID: windowID,
                    isNewWindow: true,
                    items: [
                        .init(itemID: directoryItemID, tabID: directoryTabID),
                        .init(itemID: collectionItemID, tabID: collectionTabID),
                    ],
                ),
            ],
        )
        let loadGate = WindowBootstrapSuspensionGate()
        let loadStarted = expectation(description: "collection load started")
        let terminalReceived = expectation(description: "apply terminal received")
        let openedURLs = LockIsolated<[URL]>([])
        let terminalCount = LockIsolated(0)
        var initialState = WindowManagerFeature.State()
        initialState.authorizedExternalOpenBatchID = batchID
        let store = TestStore(initialState: initialState) {
            CombineReducers {
                WindowManagerFeature()
                Reduce { _, action in
                    if case .delegate(.externalOpenApplyCompleted(.init(
                        batchID: batchID,
                        result: .success(plan),
                    ))) = action {
                        terminalCount.withValue { $0 += 1 }
                        terminalReceived.fulfill()
                    }
                    return .none
                }
            }
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
            $0.collectionFileClient.load = { url in
                openedURLs.withValue { $0.append(url) }
                loadStarted.fulfill()
                await loadGate.wait()
                throw TestError.loadFailed
            }
            $0.collectionAlertClient.showCollectionOpenErrorAlert = { _, _ in }
            $0.fileManagerWindowClient.open = { _ in }
        }
        // store.exhaustivity = .off: child Collection action보다 새 window commit/open/terminal 경계를 검증한다.
        store.exhaustivity = .off

        await store.send(.placement(.apply(
            plan: plan,
            reservationsByItemID: [
                directoryItemID: .init(id: directoryTabID, anchor: .directory(path: "/tmp")),
                collectionItemID: .init(id: collectionTabID, anchor: .collectionFile(url: collectionURL)),
            ],
        )))
        await fulfillment(of: [loadStarted, terminalReceived], timeout: 1)
        await store.skipReceivedActions()

        let committedWindow = try XCTUnwrap(store.state.windows[id: windowID]?.window)
        XCTAssertEqual(committedWindow.contentTabs.tabs.map(\.id), [directoryTabID, collectionTabID])
        XCTAssertEqual(committedWindow.contentTabs.activeTabID, collectionTabID)
        XCTAssertEqual(committedWindow.contentTabs.previousActiveTabID, directoryTabID)
        XCTAssertTrue(committedWindow.tabContentStates.values.allSatisfy { content in
            content.entryViewLayout.entryOperations.windowID == windowID
                && content.composer.cancellationOwnerID == windowID
        })
        XCTAssertEqual(openedURLs.value, [collectionURL])
        XCTAssertEqual(terminalCount.value, 1)

        await loadGate.open()
        await store.skipReceivedActions()
        await store.finish()
    }

    /// external placement 적용은 reservation 첫 항목부터 overflow window를 만들고 bootstrap 대상으로 등록하지 않는다.
    func testPlacementApplicationCreatesNoHomeOverflowWindowsOutsideBootstrap() async {
        let batchID = UUID()
        let firstWindowID = UUID()
        let secondWindowID = UUID()
        let itemIDs = (0 ..< 21).map { _ in UUID() }
        let tabIDs = (0 ..< 21).map { ContentTabID(rawValue: "external-tab-\($0)") }
        let plan = ExternalOpenPlacementPlan(
            batchID: batchID,
            windows: [
                .init(
                    windowID: firstWindowID,
                    isNewWindow: true,
                    items: zip(itemIDs.prefix(20), tabIDs.prefix(20)).map {
                        .init(itemID: $0.0, tabID: $0.1)
                    },
                ),
                .init(
                    windowID: secondWindowID,
                    isNewWindow: true,
                    items: [.init(itemID: itemIDs[20], tabID: tabIDs[20])],
                ),
            ],
        )
        let reservationsByItemID = Dictionary(
            uniqueKeysWithValues: zip(itemIDs, tabIDs).enumerated().map { index, pair in
                (
                    pair.0,
                    ExternalContentTabReservation(
                        id: pair.1,
                        anchor: .directory(path: "/external/\(index)"),
                    ),
                )
            },
        )
        let openedIDs = LockIsolated<[UUID]>([])
        var initialState = WindowManagerFeature.State()
        initialState.authorizedExternalOpenBatchID = batchID
        let store = TestStore(initialState: initialState) {
            WindowManagerFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
            $0.fileManagerWindowClient.open = { id in openedIDs.withValue { $0.append(id) } }
            $0.fileManagerWindowClient.activate = { _ in .becameKey }
        }
        // store.exhaustivity = .off: window별 초기화 child action보다 외부 window 생성 경계와 bootstrap 제외를 검증한다.
        store.exhaustivity = .off

        await store.send(.placement(.apply(
            plan: plan,
            reservationsByItemID: reservationsByItemID,
        )))
        await store.finish()

        XCTAssertEqual(store.state.windows.map(\.id), [firstWindowID, secondWindowID])
        XCTAssertEqual(store.state.windows.map(\.window.contentTabs.tabs.count), [20, 1])
        XCTAssertTrue(store.state.windows.allSatisfy { window in
            window.window.content.entryViewLayout.entryOperations.windowID == window.id
                && window.window.content.composer.cancellationOwnerID == window.id
                && window.window.tabContentStates.values.allSatisfy { content in
                    content.entryViewLayout.entryOperations.windowID == window.id
                        && content.composer.cancellationOwnerID == window.id
                }
        })
        XCTAssertTrue(store.state.windows.allSatisfy { window in
            !window.window.contentTabs.tabs.contains(where: { $0.page == .home || $0.isPinned })
        })
        XCTAssertTrue(store.state.defaultWindowBootstrapWindowIDs.isEmpty)
        XCTAssertNil(store.state.defaultWindowBootstrapRequestID)
        XCTAssertEqual(
            store.state.externalWindowBatchIDs,
            [firstWindowID: batchID, secondWindowID: batchID],
        )
        XCTAssertEqual(Set(openedIDs.value), Set([firstWindowID, secondWindowID]))
    }

    /// 다른 batch identity의 external no-Home window는 늦은 default bootstrap completion이 변경하지 않는다.
    func testLateBootstrapCompletionSkipsExternalWindowWithBatchIdentity() async throws {
        let externalBatchID = UUID()
        let bootstrapRequestID = UUID()
        let windowID = UUID()
        let externalTabID = ContentTabID(rawValue: "external-stale-bootstrap-guard")
        let externalWindow = try XCTUnwrap(FileManagerWindowFeature.State.makeExternalInitial(reservations: [
            .init(id: externalTabID, anchor: .directory(path: "/external/stable")),
        ]))
        let stalePinnedState = ContentTabState.restoringPinnedRecords(from: ContentTabPinnedRecordStore(records: [
            ContentTabPinnedRecord(
                id: "stale-pin",
                page: .directory,
                anchor: .directory(path: "/stale/pinned"),
                title: "Stale",
                iconName: "folder",
                pinnedAt: Date(timeIntervalSince1970: 1),
            ),
        ])).state
        var initialState = WindowManagerFeature.State()
        initialState.windows = [.init(id: windowID, window: externalWindow)]
        initialState.externalWindowBatchIDs = [windowID: externalBatchID]
        initialState.defaultWindowBootstrapRequestID = bootstrapRequestID
        initialState.defaultWindowBootstrapWindowIDs = [windowID]
        let store = TestStore(initialState: initialState) {
            WindowManagerFeature()
        }

        await store.send(.defaultWindowBootstrapCompleted(
            requestID: bootstrapRequestID,
            contentTabs: stalePinnedState,
        )) {
            $0.defaultWindowBootstrapRequestID = nil
            $0.defaultWindowBootstrapWindowIDs = []
        }
        await store.finish()

        XCTAssertEqual(store.state.windows[id: windowID]?.window, externalWindow)
        XCTAssertEqual(store.state.externalWindowBatchIDs[windowID], externalBatchID)
        XCTAssertEqual(store.state.windows[id: windowID]?.window.contentTabs.tabs.map(\.id), [externalTabID])
        XCTAssertFalse(store.state.windows[id: windowID]?.window.contentTabs.tabs.contains(where: {
            $0.page == .home || $0.isPinned
        }) ?? true)
    }

    /// authorization이 없는 stale activate는 native activation을 시작하지 않는다.
    func testUnauthorizedPlacementActivationDoesNotCallNativeClient() async throws {
        let batchID = UUID()
        let windowID = UUID()
        let tabID = ContentTabID(rawValue: "unauthorized-activation")
        let plan = ExternalOpenPlacementPlan(
            batchID: batchID,
            windows: [
                .init(
                    windowID: windowID,
                    isNewWindow: false,
                    items: [.init(itemID: UUID(), tabID: tabID)],
                ),
            ],
        )
        let window = try XCTUnwrap(FileManagerWindowFeature.State.makeExternalInitial(reservations: [
            .init(id: tabID, anchor: .directory(path: "/tmp/unauthorized-activation")),
        ]))
        var initialState = WindowManagerFeature.State()
        initialState.windows = [.init(id: windowID, window: window)]
        let activatedWindowIDs = LockIsolated<[UUID]>([])
        let store = TestStore(initialState: initialState) {
            WindowManagerFeature()
        } withDependencies: {
            $0.fileManagerWindowClient.activate = { id in
                activatedWindowIDs.withValue { $0.append(id) }
                return .becameKey
            }
        }
        // store.exhaustivity = .off: unauthorized command의 native boundary no-op만 검증함.
        store.exhaustivity = .off

        await store.send(.placement(.activate(plan)))
        await store.finish()

        XCTAssertNil(store.state.externalOpenActivationAttempt)
        XCTAssertTrue(activatedWindowIDs.value.isEmpty)
    }

    /// native activation이 becameKey를 반환하기 전에는 batch terminal delegate를 보내지 않는다.
    func testPlacementActivationCompletesOnlyAfterBecameKeyResult() async throws {
        let batchID = UUID()
        let windowID = UUID()
        let tabID = ContentTabID(rawValue: "awaited-native-activation")
        let plan = ExternalOpenPlacementPlan(
            batchID: batchID,
            windows: [
                .init(
                    windowID: windowID,
                    isNewWindow: true,
                    items: [.init(itemID: UUID(), tabID: tabID)],
                ),
            ],
        )
        let window = try XCTUnwrap(FileManagerWindowFeature.State.makeExternalInitial(reservations: [
            .init(id: tabID, anchor: .directory(path: "/awaited-native")),
        ]))
        let attempt = ExternalOpenActivationAttempt(
            batchID: batchID,
            plan: plan,
            windowID: windowID,
            excludedWindowIDs: [],
        )
        var initialState = WindowManagerFeature.State()
        initialState.windows = [.init(id: windowID, window: window)]
        initialState.externalWindowBatchIDs = [windowID: batchID]
        initialState.authorizedExternalOpenBatchID = batchID
        let activationStarted = expectation(description: "native activation started")
        let activationGate = AsyncStream<FileManagerWindowActivationResult>.makeStream()
        let completionCount = LockIsolated(0)
        let store = TestStore(initialState: initialState) {
            CombineReducers {
                WindowManagerFeature()
                Reduce { _, action in
                    if case .delegate(.externalOpenActivationCompleted(batchID: batchID)) = action {
                        completionCount.withValue { $0 += 1 }
                    }
                    return .none
                }
            }
        } withDependencies: {
            $0.fileManagerWindowClient.activate = { id in
                XCTAssertEqual(id, windowID)
                activationStarted.fulfill()
                for await result in activationGate.stream {
                    return result
                }
                return .discarded
            }
        }

        await store.send(.placement(.activate(plan))) {
            $0.externalOpenActivationAttempt = attempt
        }
        await fulfillment(of: [activationStarted], timeout: 1)
        XCTAssertEqual(completionCount.value, 0)

        activationGate.continuation.yield(.becameKey)
        activationGate.continuation.finish()
        await store.receive { action in
            action.isActivationResult(attempt, .becameKey)
        } assert: {
            $0.authorizedExternalOpenBatchID = nil
            $0.externalOpenActivationAttempt = nil
        }
        await store.receive(\.delegate.externalOpenActivationCompleted, batchID)

        XCTAssertEqual(completionCount.value, 1)
    }

    /// 실제 focus가 A로 이동한 뒤 도착한 B activation result는 focus와 MRU를 되돌리지 않는다.
    func testLateActivationResultDoesNotOverwriteActualFocusAndMRU() async throws {
        let batchID = UUID()
        let firstWindowID = UUID()
        let finalWindowID = UUID()
        let firstTabID = ContentTabID(rawValue: "actual-focus-first")
        let finalTabID = ContentTabID(rawValue: "late-result-final")
        let plan = ExternalOpenPlacementPlan(
            batchID: batchID,
            windows: [
                .init(
                    windowID: firstWindowID,
                    isNewWindow: false,
                    items: [.init(itemID: UUID(), tabID: firstTabID)],
                ),
                .init(
                    windowID: finalWindowID,
                    isNewWindow: false,
                    items: [.init(itemID: UUID(), tabID: finalTabID)],
                ),
            ],
        )
        let firstWindow = try XCTUnwrap(FileManagerWindowFeature.State.makeExternalInitial(reservations: [
            .init(id: firstTabID, anchor: .directory(path: "/actual-focus")),
        ]))
        let finalWindow = try XCTUnwrap(FileManagerWindowFeature.State.makeExternalInitial(reservations: [
            .init(id: finalTabID, anchor: .directory(path: "/late-result")),
        ]))
        let attempt = ExternalOpenActivationAttempt(
            batchID: batchID,
            plan: plan,
            windowID: finalWindowID,
            excludedWindowIDs: [],
        )
        var initialState = WindowManagerFeature.State()
        initialState.windows = [
            .init(id: firstWindowID, window: firstWindow),
            .init(id: finalWindowID, window: finalWindow),
        ]
        initialState.authorizedExternalOpenBatchID = batchID
        initialState.externalOpenActivationAttempt = attempt
        let keyEventCount = LockIsolated(0)
        let store = TestStore(initialState: initialState) {
            CombineReducers {
                WindowManagerFeature()
                Reduce { _, action in
                    if case .event(.windowBecameKey) = action {
                        keyEventCount.withValue { $0 += 1 }
                    }
                    return .none
                }
            }
        }

        await store.send(.event(.windowBecameKey(finalWindowID))) {
            $0.focusedWindowID = finalWindowID
            $0.lastUsedWindowIDs = [finalWindowID]
        }
        await store.send(.event(.windowResignedKey(finalWindowID))) {
            $0.focusedWindowID = nil
        }
        await store.send(.event(.windowBecameKey(firstWindowID))) {
            $0.focusedWindowID = firstWindowID
            $0.lastUsedWindowIDs = [firstWindowID, finalWindowID]
        }

        await store.send(.externalOpenActivationResult(attempt: attempt, result: .becameKey)) {
            $0.authorizedExternalOpenBatchID = nil
            $0.externalOpenActivationAttempt = nil
        }
        await store.receive(\.delegate.externalOpenActivationCompleted, batchID)
        await store.finish()

        XCTAssertEqual(store.state.focusedWindowID, firstWindowID)
        XCTAssertEqual(store.state.lastUsedWindowIDs, [firstWindowID, finalWindowID])
        XCTAssertEqual(keyEventCount.value, 2)
    }

    /// B activation request 전에 B가 닫히면 tombstone을 소비하고 최신 state의 A를 재시도한 뒤 terminal을 한 번 보낸다.
    func testPlacementActivationRetriesPreviousSurvivorAfterDiscard() async throws {
        let batchID = UUID()
        let firstWindowID = UUID()
        let finalWindowID = UUID()
        let firstTabID = ContentTabID(rawValue: "first-survivor")
        let finalTabID = ContentTabID(rawValue: "discarded-final")
        let plan = ExternalOpenPlacementPlan(
            batchID: batchID,
            windows: [
                .init(
                    windowID: firstWindowID,
                    isNewWindow: true,
                    items: [.init(itemID: UUID(), tabID: firstTabID)],
                ),
                .init(
                    windowID: finalWindowID,
                    isNewWindow: true,
                    items: [.init(itemID: UUID(), tabID: finalTabID)],
                ),
            ],
        )
        let firstWindow = try XCTUnwrap(FileManagerWindowFeature.State.makeExternalInitial(reservations: [
            .init(id: firstTabID, anchor: .directory(path: "/first")),
        ]))
        let finalWindow = try XCTUnwrap(FileManagerWindowFeature.State.makeExternalInitial(reservations: [
            .init(id: finalTabID, anchor: .directory(path: "/final")),
        ]))
        let finalAttempt = ExternalOpenActivationAttempt(
            batchID: batchID,
            plan: plan,
            windowID: finalWindowID,
            excludedWindowIDs: [],
        )
        let firstAttempt = ExternalOpenActivationAttempt(
            batchID: batchID,
            plan: plan,
            windowID: firstWindowID,
            excludedWindowIDs: [finalWindowID],
        )
        var initialState = WindowManagerFeature.State()
        initialState.windows = [
            .init(id: firstWindowID, window: firstWindow),
            .init(id: finalWindowID, window: finalWindow),
        ]
        initialState.externalWindowBatchIDs = [firstWindowID: batchID, finalWindowID: batchID]
        initialState.authorizedExternalOpenBatchID = batchID
        let tracker = FileManagerWindowActivationTracker()
        let finalRequestGate = WindowBootstrapSuspensionGate()
        let activatedIDs = LockIsolated<[UUID]>([])
        let firstStarted = expectation(description: "fallback activation started")
        let completionCount = LockIsolated(0)
        let store = TestStore(initialState: initialState) {
            CombineReducers {
                WindowManagerFeature()
                Reduce { _, action in
                    if case .delegate(.externalOpenActivationCompleted(batchID: batchID)) = action {
                        completionCount.withValue { $0 += 1 }
                    }
                    return .none
                }
            }
        } withDependencies: {
            $0.fileManagerWindowClient.activate = { id in
                activatedIDs.withValue { $0.append(id) }
                if id == finalWindowID {
                    await finalRequestGate.wait()
                    return await tracker.request(id)
                }
                XCTAssertEqual(id, firstWindowID)
                return await tracker.request(id) {
                    firstStarted.fulfill()
                }
            }
        }

        await store.send(.placement(.activate(plan))) {
            $0.externalOpenActivationAttempt = finalAttempt
        }
        await finalRequestGate.waitUntilWaiting()
        await store.send(.event(.windowClosed(finalWindowID))) {
            $0.windows.remove(id: finalWindowID)
            $0.externalWindowBatchIDs[finalWindowID] = nil
        }
        tracker.discard(finalWindowID)
        await finalRequestGate.open()

        await store.receive { action in
            action.isActivationResult(finalAttempt, .discarded)
        } assert: {
            $0.externalOpenActivationAttempt = firstAttempt
        }
        await fulfillment(of: [firstStarted], timeout: 1)
        XCTAssertEqual(completionCount.value, 0)

        tracker.complete(firstWindowID, result: .becameKey)
        await store.receive { action in
            action.isActivationResult(firstAttempt, .becameKey)
        } assert: {
            $0.authorizedExternalOpenBatchID = nil
            $0.externalOpenActivationAttempt = nil
        }
        await store.receive(\.delegate.externalOpenActivationCompleted, batchID)
        await store.finish()

        XCTAssertEqual(activatedIDs.value, [finalWindowID, firstWindowID])
        XCTAssertEqual(completionCount.value, 1)
    }

    /// becameKey 결과 도착 전에 target이 사라지면 missing window를 focus하지 않고 이전 survivor를 재시도한다.
    func testPlacementActivationRetriesWhenBecameKeyTargetVanishes() async throws {
        let batchID = UUID()
        let firstWindowID = UUID()
        let finalWindowID = UUID()
        let firstTabID = ContentTabID(rawValue: "became-key-first")
        let finalTabID = ContentTabID(rawValue: "became-key-vanished")
        let plan = ExternalOpenPlacementPlan(
            batchID: batchID,
            windows: [
                .init(
                    windowID: firstWindowID,
                    isNewWindow: true,
                    items: [.init(itemID: UUID(), tabID: firstTabID)],
                ),
                .init(
                    windowID: finalWindowID,
                    isNewWindow: true,
                    items: [.init(itemID: UUID(), tabID: finalTabID)],
                ),
            ],
        )
        let firstWindow = try XCTUnwrap(FileManagerWindowFeature.State.makeExternalInitial(reservations: [
            .init(id: firstTabID, anchor: .directory(path: "/first")),
        ]))
        let finalWindow = try XCTUnwrap(FileManagerWindowFeature.State.makeExternalInitial(reservations: [
            .init(id: finalTabID, anchor: .directory(path: "/final")),
        ]))
        let finalAttempt = ExternalOpenActivationAttempt(
            batchID: batchID,
            plan: plan,
            windowID: finalWindowID,
            excludedWindowIDs: [],
        )
        let firstAttempt = ExternalOpenActivationAttempt(
            batchID: batchID,
            plan: plan,
            windowID: firstWindowID,
            excludedWindowIDs: [finalWindowID],
        )
        var initialState = WindowManagerFeature.State()
        initialState.windows = [
            .init(id: firstWindowID, window: firstWindow),
            .init(id: finalWindowID, window: finalWindow),
        ]
        initialState.externalWindowBatchIDs = [firstWindowID: batchID, finalWindowID: batchID]
        initialState.authorizedExternalOpenBatchID = batchID
        let finalStarted = expectation(description: "vanishing target activation started")
        let finalGate = AsyncStream<FileManagerWindowActivationResult>.makeStream()
        let store = TestStore(initialState: initialState) {
            WindowManagerFeature()
        } withDependencies: {
            $0.fileManagerWindowClient.activate = { id in
                guard id == finalWindowID else { return .becameKey }
                finalStarted.fulfill()
                for await result in finalGate.stream {
                    return result
                }
                return .discarded
            }
        }

        await store.send(.placement(.activate(plan))) {
            $0.externalOpenActivationAttempt = finalAttempt
        }
        await fulfillment(of: [finalStarted], timeout: 1)
        await store.send(.event(.windowClosed(finalWindowID))) {
            $0.windows.remove(id: finalWindowID)
            $0.externalWindowBatchIDs[finalWindowID] = nil
        }
        finalGate.continuation.yield(.becameKey)
        finalGate.continuation.finish()
        await store.receive { action in
            action.isActivationResult(finalAttempt, .becameKey)
        } assert: {
            $0.externalOpenActivationAttempt = firstAttempt
        }
        await store.receive { action in
            action.isActivationResult(firstAttempt, .becameKey)
        } assert: {
            $0.authorizedExternalOpenBatchID = nil
            $0.externalOpenActivationAttempt = nil
        }
        await store.receive(\.delegate.externalOpenActivationCompleted, batchID)
    }

    /// 마지막 reserved tab만 닫히면 이전 successful candidate를 정확히 한 번 활성화한다.
    func testPlacementActivationFallsBackWhenFinalTabClosesButWindowSurvives() async throws {
        let batchID = UUID()
        let firstWindowID = UUID()
        let finalWindowID = UUID()
        let firstTabID = ContentTabID(rawValue: "first-tab-survivor")
        let closedFinalTabID = ContentTabID(rawValue: "closed-final-tab")
        let replacementTabID = ContentTabID(rawValue: "replacement-tab")
        let plan = ExternalOpenPlacementPlan(
            batchID: batchID,
            windows: [
                .init(
                    windowID: firstWindowID,
                    isNewWindow: true,
                    items: [.init(itemID: UUID(), tabID: firstTabID)],
                ),
                .init(
                    windowID: finalWindowID,
                    isNewWindow: true,
                    items: [.init(itemID: UUID(), tabID: closedFinalTabID)],
                ),
            ],
        )
        let firstWindow = try XCTUnwrap(FileManagerWindowFeature.State.makeExternalInitial(reservations: [
            .init(id: firstTabID, anchor: .directory(path: "/first")),
        ]))
        let survivingFinalWindow = try XCTUnwrap(FileManagerWindowFeature.State.makeExternalInitial(reservations: [
            .init(id: replacementTabID, anchor: .directory(path: "/replacement")),
        ]))
        let attempt = ExternalOpenActivationAttempt(
            batchID: batchID,
            plan: plan,
            windowID: firstWindowID,
            excludedWindowIDs: [],
        )
        var initialState = WindowManagerFeature.State()
        initialState.windows = [
            .init(id: firstWindowID, window: firstWindow),
            .init(id: finalWindowID, window: survivingFinalWindow),
        ]
        initialState.externalWindowBatchIDs = [firstWindowID: batchID, finalWindowID: batchID]
        initialState.authorizedExternalOpenBatchID = batchID
        let activatedIDs = LockIsolated<[UUID]>([])
        let store = TestStore(initialState: initialState) {
            WindowManagerFeature()
        } withDependencies: {
            $0.fileManagerWindowClient.activate = { id in
                activatedIDs.withValue { $0.append(id) }
                return .becameKey
            }
        }

        await store.send(.placement(.activate(plan))) {
            $0.externalOpenActivationAttempt = attempt
        }
        await store.receive { action in
            action.isActivationResult(attempt, .becameKey)
        } assert: {
            $0.authorizedExternalOpenBatchID = nil
            $0.externalOpenActivationAttempt = nil
        }
        await store.receive(\.delegate.externalOpenActivationCompleted, batchID)

        XCTAssertEqual(activatedIDs.value, [firstWindowID])
        XCTAssertNotNil(store.state.windows[id: finalWindowID])
    }

    /// 모든 successful candidate가 닫히면 key event 없이 terminal을 정확히 한 번 보낸다.
    func testPlacementActivationWithoutSurvivorSendsOneTerminalAndNoKeyEvent() async {
        let windowID = UUID()
        let plan = ExternalOpenPlacementPlan(
            batchID: UUID(),
            windows: [
                .init(
                    windowID: windowID,
                    isNewWindow: true,
                    items: [.init(itemID: UUID(), tabID: ContentTabID(rawValue: "closed"))],
                ),
            ],
        )
        let activatedIDs = LockIsolated<[UUID]>([])
        let terminalCount = LockIsolated(0)
        let keyEventCount = LockIsolated(0)
        var initialState = WindowManagerFeature.State()
        initialState.authorizedExternalOpenBatchID = plan.batchID
        let store = TestStore(initialState: initialState) {
            CombineReducers {
                WindowManagerFeature()
                Reduce { _, action in
                    switch action {
                    case .delegate(.externalOpenActivationCompleted(batchID: plan.batchID)):
                        terminalCount.withValue { $0 += 1 }
                    case .event(.windowBecameKey):
                        keyEventCount.withValue { $0 += 1 }
                    default:
                        break
                    }
                    return .none
                }
            }
        } withDependencies: {
            $0.fileManagerWindowClient.activate = { id in
                activatedIDs.withValue { $0.append(id) }
                return .becameKey
            }
            $0.fileManagerWindowClient.open = { _ in
                XCTFail("생존 candidate가 없으면 window를 만들지 않아야 한다")
            }
        }

        await store.send(.placement(.activate(plan))) {
            $0.authorizedExternalOpenBatchID = nil
        }
        await store.receive(\.delegate.externalOpenActivationCompleted, plan.batchID)
        await store.finish()

        XCTAssertTrue(activatedIDs.value.isEmpty)
        XCTAssertEqual(terminalCount.value, 1)
        XCTAssertEqual(keyEventCount.value, 0)
        XCTAssertTrue(store.state.windows.isEmpty)
    }

    /// 현재 activation attempt와 다른 늦은 결과는 state와 terminal을 변경하지 않는다.
    func testStalePlacementActivationResultIsIgnored() async {
        let batchID = UUID()
        let currentWindowID = UUID()
        let staleWindowID = UUID()
        let plan = ExternalOpenPlacementPlan(batchID: batchID, windows: [])
        let currentAttempt = ExternalOpenActivationAttempt(
            batchID: batchID,
            plan: plan,
            windowID: currentWindowID,
            excludedWindowIDs: [],
        )
        let staleAttempt = ExternalOpenActivationAttempt(
            batchID: batchID,
            plan: plan,
            windowID: staleWindowID,
            excludedWindowIDs: [],
        )
        var initialState = WindowManagerFeature.State()
        initialState.authorizedExternalOpenBatchID = batchID
        initialState.externalOpenActivationAttempt = currentAttempt
        let terminalCount = LockIsolated(0)
        let store = TestStore(initialState: initialState) {
            CombineReducers {
                WindowManagerFeature()
                Reduce { _, action in
                    if case .delegate(.externalOpenActivationCompleted) = action {
                        terminalCount.withValue { $0 += 1 }
                    }
                    return .none
                }
            }
        }

        await store.send(.externalOpenActivationResult(attempt: staleAttempt, result: .becameKey))
        await store.finish()

        XCTAssertEqual(store.state.externalOpenActivationAttempt, currentAttempt)
        XCTAssertEqual(terminalCount.value, 0)
    }

    private struct PlacementBoundaryScenario {
        let free: Int
        let valid: Int
        let expected: [Int]
    }

    private static func makeWindow(id: UUID, tabCount: Int) -> WindowSessionState {
        var window = FileManagerWindowFeature.State.makeInitial(path: "/window-\(id.uuidString)")
        let tabs = (0 ..< tabCount).map { index in
            ContentTabItem(
                id: ContentTabID(rawValue: "\(id.uuidString)-tab-\(index)"),
                page: .directory,
                anchor: .directory(path: "/window-\(id.uuidString)/\(index)"),
                isPinned: false,
                title: nil,
                iconName: nil,
            )
        }
        window.contentTabs = ContentTabState(
            tabs: .init(uniqueElements: tabs),
            activeTabID: tabs.first?.id,
        )
        return WindowSessionState(id: id, window: window)
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

@MainActor
private extension WindowManagerAction {
    func isActivationResult(
        _ expectedAttempt: ExternalOpenActivationAttempt,
        _ expectedResult: FileManagerWindowActivationResult,
    ) -> Bool {
        guard case let .externalOpenActivationResult(attempt, result) = self else { return false }
        return attempt == expectedAttempt && result == expectedResult
    }
}
