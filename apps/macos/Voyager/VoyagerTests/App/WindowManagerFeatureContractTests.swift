import ComposableArchitecture
import CoreServices
import Foundation
@testable import Voyager
import VoyagerEntitiesAi
import VoyagerEntitiesAppPreferences
@_spi(Testing)
@testable import VoyagerEntitiesCollection
import VoyagerEntitiesEntry
import VoyagerEntitiesTag
import VoyagerFeaturesAiChat
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

private actor PinnedRecordMutationGate {
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

private actor ContentTabMoveActivationGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private var entryWaiters: [CheckedContinuation<Void, Never>] = []
    private var isWaiting = false

    func wait() async {
        await withTaskCancellationHandler {
            guard !Task.isCancelled else { return }
            isWaiting = true
            let waiters = entryWaiters
            entryWaiters.removeAll()
            waiters.forEach { $0.resume() }
            await withCheckedContinuation { continuation = $0 }
        } onCancel: {
            Task { await self.release() }
        }
    }

    func waitUntilWaiting() async {
        guard !isWaiting else { return }
        await withCheckedContinuation { entryWaiters.append($0) }
    }

    func release() {
        continuation?.resume()
        continuation = nil
    }
}

private struct ContentTabMovePersistenceActionCounts: Equatable {
    var queuedRequests = 0
    var sourceSucceeded = 0
    var sourceRejected = 0
    var lifecycleCompleted = 0
    var nativeRequested = 0
    var snapshotsByWindow: [UUID: Int] = [:]
}

private typealias PinnedGroupMovePersistence = @Sendable (
    UserDefaultsClient,
    [String],
    [ContentTabID],
    FileManagerTopNavigationMoveDestination,
) async throws -> FileManagerTopNavigationCommit

private actor PinnedRecordMutationSignal {
    private var isSignaled = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        guard !isSignaled else { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func signal() {
        isSignaled = true
        let continuations = waiters
        waiters.removeAll()
        continuations.forEach { $0.resume() }
    }
}

private enum PinnedRecordFirstMutationTerminal {
    case applied
    case superseded
}

/// 윈도우 관리자 계약 — 포커스 윈도우로의 명령 팬아웃과 미사용 시 no-op를 검증.
private func pinnedTabIDs(_ contentTabs: ContentTabState?) -> [String] {
    contentTabs?.tabs.filter(\.isPinned).map(\.id.rawValue) ?? []
}

private enum ContentTabObservationRebindEvent: Equatable {
    case stop
    case start
    case apply
}

private func contentTabObservationRebindEvent(
    _ action: FileManagerContentAction,
) -> ContentTabObservationRebindEvent? {
    switch action {
    case .internal(.stopObservingSystemNotifications):
        .stop
    case .internal(.startObservingSystemNotifications):
        .start
    case .internal(.applyNavigationState):
        .apply
    default:
        nil
    }
}

private enum ContentTabMoveFolderLifecycleEvent: String {
    case folderCancel = "folder-cancel"
    case windowRebind = "window-rebind"
    case hierarchyRestart = "hierarchy-restart"
    case collectionRestart = "collection-restart"
    case rebindComplete = "rebind-complete"
}

private func contentTabMoveFolderLifecycleEvent(
    _ action: FileManagerContentAction,
) -> ContentTabMoveFolderLifecycleEvent? {
    switch action {
    case .entryViewLayout(.entryOperations(.loading(.cancelAllFolderItems))):
        .folderCancel
    case .entryViewLayout(.entryOperations(.lifecycle(.windowIDChanged))):
        .windowRebind
    case .entryViewLayout(.hierarchy(.restartUnfinishedExpandedFolderLoads)):
        .hierarchyRestart
    case .entryViewLayout(.internal(.restartCollectionMaterialization)):
        .collectionRestart
    case .internal(.applyNavigationState):
        .rebindComplete
    default:
        nil
    }
}

@MainActor
final class WindowManagerFeatureContractTests: XCTestCase {
    private struct ExpectedPinnedRecordSaveFailure: Error {}

    private func lifecycleWindow(
        tabID: ContentTabID,
        record: ContentTabPinnedRecord,
        path: String,
    ) -> FileManagerWindowFeature.State {
        let homeID = ContentTabID(rawValue: "home-\(tabID.rawValue)")
        var window = FileManagerWindowFeature.State.makeInitial(path: path)
        window.contentTabs = ContentTabState(
            tabs: [
                ContentTabItem(
                    id: tabID,
                    page: record.page,
                    anchor: record.anchor,
                    isPinned: true,
                    title: record.title,
                    iconName: record.iconName,
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
            activeTabID: tabID,
            pinnedRecords: [tabID: record],
        )
        window.lastConfirmedTopNavigationOrder = .init(items: [.contentTab(tabID)])
        window.optimisticTopNavigationOrder = window.lastConfirmedTopNavigationOrder
        window.syncContentTabSidebarItems()
        return window
    }

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
            $0.fileManagerWindowClient.registeredWindowIDs = { [newID] }
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
            $0.fileManagerWindowClient.registeredWindowIDs = { [newID] }
            $0.fileManagerWindowClient.open = { _ in }
        }
        store.exhaustivity = .off

        await store.send(.file(.newWindow(path: nil)))
        await store.receive(\.defaultWindowBootstrapCompleted)
        await store.receive { action in
            guard case let .windows(.element(id: id, action: .window(.applyBootstrap(bootstrap)))) = action
            else {
                return false
            }
            return id == newID
                && bootstrap.authoritativePinnedContentTabs.tabs.filter(\.isPinned).map(\.id.rawValue) == ["dir-1"]
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

    /// VOY-470: icon cache 준비 실패와 무관하게 persisted cross-kind mixed order를 정확히 복원한다.
    /// bootstrap payload가 display-quality icon 결과와 분리되어 pinned tabs와 durable order를 함께 전달하는지 검증한다.
    /// - 검증 내용: icon 준비 false에서도 ContentTab A → Location L1 → ContentTab B 순서의 confirmed/visible 적용
    /// - 사전 조건: 유효한 pinned record A/B, schema-v2 mixed `topNavigationOrder`, icon cache 준비 실패
    /// - 기대 결과: default window의 confirmed/optimistic order가 persisted order와 동일함
    func testDefaultWindowBootstrapRestoresPersistedCrossKindTopNavigationOrder() async throws {
        let windowID = UUID(47061)
        let location = SidebarItems.LocationItem(
            name: "External",
            url: URL(fileURLWithPath: "/Volumes/External"),
            iconName: "externaldrive",
        )
        let fixedLocation = try XCTUnwrap(FileManagerHomeDashboardProjection.makeFixedLocations(from: [location]).first)
        let tabA = ContentTabID(rawValue: "restart-tab-a")
        let tabB = ContentTabID(rawValue: "restart-tab-b")
        let persistedOrder = FileManagerTopNavigationOrder(items: [
            .contentTab(tabA),
            .location(fixedLocation.id),
            .contentTab(tabB),
        ])
        let pinnedStore = ContentTabPinnedRecordStore(
            records: [
                ContentTabPinnedRecord(
                    id: tabA.rawValue,
                    page: .directory,
                    anchor: .directory(path: "/Users/test/A"),
                    title: "A",
                    iconName: "folder",
                    pinnedAt: Date(timeIntervalSince1970: 443),
                ),
                ContentTabPinnedRecord(
                    id: tabB.rawValue,
                    page: .directory,
                    anchor: .directory(path: "/Users/test/B"),
                    title: "B",
                    iconName: "folder",
                    pinnedAt: Date(timeIntervalSince1970: 444),
                ),
            ],
            topNavigationOrder: persistedOrder,
        )
        let store = TestStore(initialState: WindowManagerFeature.State()) {
            WindowManagerFeature()
        } withDependencies: {
            $0.uuid = .constant(windowID)
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
            $0.contentTabPinnedRecordClient.loadStore = { _ in pinnedStore }
            $0.contentTabPinnedRecordClient.saveStore = { _, _ in }
            $0.fileManagerLocationsClient.loadLocations = { _ in [location] }
            $0.fileManagerClient.fileExistsWithIsDirectory = { path, isDirectory in
                guard path == "/Users/test/A" || path == "/Users/test/B" else { return false }
                isDirectory?.pointee = ObjCBool(true)
                return true
            }
            $0.fileManagerBuiltInCollectionClient.ensureAll = { .init(recents: .failed, allTags: .failed) }
            $0.workspaceClient.prepareFileIcons = { _ in false }
            $0.userDefaultsClient.bool = { _ in true }
            $0.onboardingWindowClient.showIfNeeded = { false }
            $0.fileManagerWindowClient.registeredWindowIDs = { [windowID] }
            $0.fileManagerWindowClient.open = { _ in }
        }
        // store.exhaustivity = .off: bootstrap 내부 lifecycle보다 typed completion과 최종 window state를 검증한다.
        store.exhaustivity = .off

        await store.send(.file(.newWindow(path: nil)))
        await store.receive(\.defaultWindowBootstrapCompleted)
        await store.receive { action in
            guard case let .windows(.element(
                id: id,
                action: .window(.applyBootstrap(bootstrap)),
            )) = action else { return false }
            return id == windowID
                && bootstrap.committedTopNavigationOrder == persistedOrder
                && bootstrap.fixedLocationItems == [fixedLocation]
                && bootstrap.authoritativePinnedContentTabs.tabs.filter(\.isPinned).map(\.id) == [tabA, tabB]
        }
        await store.finish()

        XCTAssertEqual(store.state.windows[id: windowID]?.window.lastConfirmedTopNavigationOrder, persistedOrder)
        XCTAssertEqual(store.state.windows[id: windowID]?.window.optimisticTopNavigationOrder, persistedOrder)
        XCTAssertEqual(
            store.state.windows[id: windowID]?.window.sidebar.topNavigationItems.map(\.id),
            persistedOrder.items,
        )
    }

    /// VOY-470: order 필드가 없는 과도기 v2 저장값도 pinned tabs를 첫 window bootstrap에서 복원한다.
    /// 저장된 records가 arrangement corrupt fallback 때문에 사라지지 않는 실제 live-client 경계를 검증한다.
    /// - 검증 내용: migrated legacy-v2 records, synthesized order, available presentation, storage write 0회
    /// - 사전 조건: schemaVersion 2와 pinned records `[A,B]`는 있지만 `topNavigationOrder`가 없는 payload
    /// - 기대 결과: native open 전 pinned A/B가 복원되고 원본 payload는 첫 mutation 전까지 유지됨
    func testDefaultWindowBootstrapRestoresLegacyV2PinnedTabsWithoutOrder() async throws {
        struct LegacyV2Fixture: Encodable {
            let schemaVersion = 2
            let records: [ContentTabPinnedRecord]
        }

        let windowID = UUID(47062)
        let tabA = ContentTabID(rawValue: "legacy-v2-tab-a")
        let tabB = ContentTabID(rawValue: "legacy-v2-tab-b")
        let records = [
            ContentTabPinnedRecord(
                id: tabA.rawValue,
                page: .directory,
                anchor: .directory(path: "/Users/test/A"),
                title: "A",
                iconName: "folder",
                pinnedAt: Date(timeIntervalSince1970: 445),
            ),
            ContentTabPinnedRecord(
                id: tabB.rawValue,
                page: .directory,
                anchor: .directory(path: "/Users/test/B"),
                title: "B",
                iconName: "folder",
                pinnedAt: Date(timeIntervalSince1970: 446),
            ),
        ]
        let sourceData = try JSONEncoder().encode(LegacyV2Fixture(records: records))
        let storedData = LockIsolated(sourceData)
        let storageWriteCount = LockIsolated(0)
        let storageKey = "fileManager.pinnedContentTabs.v1"
        let defaultsClient = UserDefaultsClient(
            bool: { _ in true },
            setBool: { _, _ in },
            string: { _ in nil },
            setString: { _, _ in },
            double: { _ in 0 },
            setDouble: { _, _ in },
            object: { key in key == storageKey ? storedData.value : nil },
            setObject: { value, key in
                guard key == storageKey, let data = value as? Data else { return }
                storedData.setValue(data)
                storageWriteCount.withValue { $0 += 1 }
            },
        )
        let nativeOpenCount = LockIsolated(0)
        let store = TestStore(initialState: WindowManagerFeature.State()) {
            WindowManagerFeature()
        } withDependencies: {
            $0.uuid = .constant(windowID)
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
            $0.contentTabPinnedRecordClient = .liveValue
            $0.userDefaultsClient = defaultsClient
            $0.fileManagerLocationsClient.loadLocations = { _ in [] }
            $0.fileManagerClient.fileExistsWithIsDirectory = { path, isDirectory in
                guard path == "/Users/test/A" || path == "/Users/test/B" else { return false }
                isDirectory?.pointee = ObjCBool(true)
                return true
            }
            $0.fileManagerBuiltInCollectionClient.ensureAll = { .init(recents: .failed, allTags: .failed) }
            $0.onboardingWindowClient.showIfNeeded = { false }
            $0.fileManagerWindowClient.registeredWindowIDs = { [windowID] }
            $0.fileManagerWindowClient.open = { _ in
                nativeOpenCount.withValue { $0 += 1 }
            }
        }
        // store.exhaustivity = .off: live persistence decode와 최종 pre-open bootstrap snapshot을 검증한다.
        store.exhaustivity = .off

        await store.send(.file(.newWindow(path: nil)))
        await store.receive(\.defaultWindowBootstrapCompleted)
        await store.receive { action in
            guard case let .windows(.element(
                id: id,
                action: .window(.applyBootstrap(bootstrap)),
            )) = action else { return false }
            return id == windowID
                && bootstrap.arrangementAvailability == .available
                && bootstrap.authoritativePinnedContentTabs.tabs.filter(\.isPinned).map(\.id) == [tabA, tabB]
                && bootstrap.committedTopNavigationOrder.items == [.contentTab(tabA), .contentTab(tabB)]
        }
        await store.finish()

        XCTAssertEqual(
            store.state.windows[id: windowID]?.window.contentTabs.tabs.filter(\.isPinned).map(\.id),
            [tabA, tabB],
        )
        XCTAssertEqual(store.state.windows[id: windowID]?.window.topNavigationArrangementAvailability, .available)
        XCTAssertNil(store.state.windows[id: windowID]?.window.topNavigationArrangementPresentation)
        XCTAssertEqual(nativeOpenCount.value, 1)
        XCTAssertEqual(storedData.value, sourceData)
        XCTAssertEqual(storageWriteCount.value, 0)
    }

    /// VOY-470: default window는 native registration을 확인한 뒤 persisted top-navigation bootstrap을 적용한다.
    /// - 검증 내용: native open 시점의 초기 상태와 bootstrap 이후 order/pin/location/availability 완성 상태
    /// - 사전 조건: schema-v2 mixed order, pinned tab 1개, fixed location 1개
    /// - 기대 결과: native open은 bootstrap 전에 1회 수행되고 등록된 window가 bootstrap 결과로 완전히 hydrated됨
    func testDefaultWindowBootstrapsAfterNativeRegistration() async throws {
        let windowID = UUID(47081)
        let bootstrapGate = WindowBootstrapSuspensionGate()
        let pinnedTabID = ContentTabID(rawValue: "preopen-pinned-tab")
        let location = SidebarItems.LocationItem(
            name: "External",
            url: URL(fileURLWithPath: "/Volumes/External"),
            iconName: "externaldrive",
        )
        let fixedLocation = try XCTUnwrap(FileManagerHomeDashboardProjection.makeFixedLocations(from: [location]).first)
        let persistedOrder = FileManagerTopNavigationOrder(items: [
            .location(fixedLocation.id),
            .contentTab(pinnedTabID),
        ])
        let pinnedStore = ContentTabPinnedRecordStore(
            records: [
                ContentTabPinnedRecord(
                    id: pinnedTabID.rawValue,
                    page: .directory,
                    anchor: .directory(path: "/Users/test/Pinned"),
                    title: "Pinned",
                    iconName: "folder",
                    pinnedAt: Date(timeIntervalSince1970: 443),
                ),
            ],
            topNavigationOrder: persistedOrder,
        )
        let currentWindowIsHydrated = LockIsolated(false)
        let preparedIconPaths = LockIsolated<[String]>([])
        let hydrationObservedAtOpen = LockIsolated<[Bool]>([])
        let store = TestStore(initialState: WindowManagerFeature.State()) {
            CombineReducers {
                WindowManagerFeature()
                Reduce { state, _ in
                    guard let window = state.windows[id: windowID]?.window else { return .none }
                    let isHydrated = window.topNavigationArrangementAvailability == .available
                        && window.lastConfirmedTopNavigationOrder == persistedOrder
                        && window.contentTabs.tabs[id: pinnedTabID]?.isPinned == true
                        && window.sidebar.allFixedLocationItems == [fixedLocation]
                    currentWindowIsHydrated.withValue { $0 = isHydrated }
                    return .none
                }
            }
        } withDependencies: {
            $0.uuid = .constant(windowID)
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
            $0.contentTabPinnedRecordClient.loadStore = { _ in pinnedStore }
            $0.contentTabPinnedRecordClient.saveStore = { _, _ in }
            $0.fileManagerLocationsClient.loadLocations = { _ in [location] }
            $0.workspaceClient.prepareFileIcons = { paths in
                preparedIconPaths.setValue(paths)
                return true
            }
            $0.fileManagerClient.fileExistsWithIsDirectory = { path, isDirectory in
                guard path == "/Users/test/Pinned" else { return false }
                isDirectory?.pointee = ObjCBool(true)
                return true
            }
            $0.fileManagerBuiltInCollectionClient.ensureAll = {
                await bootstrapGate.wait()
                return .init(recents: .failed, allTags: .failed)
            }
            $0.userDefaultsClient.bool = { _ in true }
            $0.onboardingWindowClient.showIfNeeded = { false }
            $0.fileManagerWindowClient.registeredWindowIDs = { [windowID] }
            $0.fileManagerWindowClient.open = { _ in
                let isReady = currentWindowIsHydrated.value
                    && preparedIconPaths.value == [fixedLocation.path]
                hydrationObservedAtOpen.withValue { $0.append(isReady) }
            }
        }
        // store.exhaustivity = .off: bootstrap 내부 action보다 native registration 이후 aggregate state 경계를 검증한다.
        store.exhaustivity = .off

        await store.send(.file(.newWindow(path: nil)))
        await bootstrapGate.waitUntilWaiting()

        XCTAssertEqual(hydrationObservedAtOpen.value, [false])

        await bootstrapGate.open()
        await store.skipReceivedActions()
        await store.finish()

        XCTAssertEqual(hydrationObservedAtOpen.value, [false])
        XCTAssertTrue(currentWindowIsHydrated.value)
        XCTAssertEqual(preparedIconPaths.value, [fixedLocation.path])
    }

    /// VOY-470: 동시에 등록된 default window들은 하나의 bootstrap 결과를 공유한다.
    /// - 검증 내용: native registration과 bootstrap 실행 횟수 및 두 window의 최종 hydration 상태
    /// - 사전 조건: 첫 window bootstrap이 대기 중일 때 두 번째 default window 생성
    /// - 기대 결과: 두 native open 이후 bootstrap 1회, 두 window 모두 같은 결과로 hydrated됨
    func testConcurrentDefaultWindowsShareBootstrapAfterNativeRegistration() async throws {
        let bootstrapGate = WindowBootstrapSuspensionGate()
        let pinnedTabID = ContentTabID(rawValue: "shared-preopen-pinned-tab")
        let location = SidebarItems.LocationItem(
            name: "Shared",
            url: URL(fileURLWithPath: "/Volumes/Shared"),
            iconName: "externaldrive",
        )
        let fixedLocation = try XCTUnwrap(FileManagerHomeDashboardProjection.makeFixedLocations(from: [location]).first)
        let persistedOrder = FileManagerTopNavigationOrder(items: [
            .contentTab(pinnedTabID),
            .location(fixedLocation.id),
        ])
        let pinnedStore = ContentTabPinnedRecordStore(
            records: [
                ContentTabPinnedRecord(
                    id: pinnedTabID.rawValue,
                    page: .directory,
                    anchor: .directory(path: "/Users/test/Shared"),
                    title: "Shared",
                    iconName: "folder",
                    pinnedAt: Date(timeIntervalSince1970: 444),
                ),
            ],
            topNavigationOrder: persistedOrder,
        )
        let bootstrapCallCount = LockIsolated(0)
        let registeredWindowIDs = LockIsolated<Set<UUID>>([])
        let hydratedWindowIDs = LockIsolated<Set<UUID>>([])
        let hydrationObservedAtOpen = LockIsolated<[UUID: Bool]>([:])
        let store = TestStore(initialState: WindowManagerFeature.State()) {
            CombineReducers {
                WindowManagerFeature()
                Reduce { state, _ in
                    for session in state.windows {
                        let window = session.window
                        let isHydrated = window.topNavigationArrangementAvailability == .available
                            && window.lastConfirmedTopNavigationOrder == persistedOrder
                            && window.contentTabs.tabs[id: pinnedTabID]?.isPinned == true
                            && window.sidebar.allFixedLocationItems == [fixedLocation]
                        if isHydrated {
                            let sessionID = session.id
                            hydratedWindowIDs.withValue { ids in
                                _ = ids.insert(sessionID)
                            }
                        }
                    }
                    return .none
                }
            }
        } withDependencies: {
            $0.uuid = .incrementing
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
            $0.contentTabPinnedRecordClient.loadStore = { _ in pinnedStore }
            $0.contentTabPinnedRecordClient.saveStore = { _, _ in }
            $0.fileManagerLocationsClient.loadLocations = { _ in [location] }
            $0.fileManagerClient.fileExistsWithIsDirectory = { path, isDirectory in
                guard path == "/Users/test/Shared" else { return false }
                isDirectory?.pointee = ObjCBool(true)
                return true
            }
            $0.fileManagerBuiltInCollectionClient.ensureAll = {
                bootstrapCallCount.withValue { $0 += 1 }
                await bootstrapGate.wait()
                return .init(recents: .failed, allTags: .failed)
            }
            $0.userDefaultsClient.bool = { _ in true }
            $0.onboardingWindowClient.showIfNeeded = { false }
            $0.fileManagerWindowClient.registeredWindowIDs = { registeredWindowIDs.value }
            $0.fileManagerWindowClient.open = { id in
                registeredWindowIDs.withValue { _ = $0.insert(id) }
                hydrationObservedAtOpen.withValue { $0[id] = hydratedWindowIDs.value.contains(id) }
            }
        }
        // store.exhaustivity = .off: 공유 request 내부 action보다 native registration과 최종 hydration 경계를 검증한다.
        store.exhaustivity = .off

        await store.send(.file(.newWindow(path: nil)))
        await bootstrapGate.waitUntilWaiting()
        let firstWindowID = try XCTUnwrap(store.state.windows.ids.first)

        await store.send(.file(.newWindow(path: nil)))
        let secondWindowID = try XCTUnwrap(store.state.windows.ids.first(where: { $0 != firstWindowID }))

        XCTAssertEqual(bootstrapCallCount.value, 1)
        XCTAssertEqual(hydrationObservedAtOpen.value, [firstWindowID: false, secondWindowID: false])

        await bootstrapGate.open()
        await store.skipReceivedActions()
        await store.finish()

        XCTAssertEqual(bootstrapCallCount.value, 1)
        XCTAssertEqual(registeredWindowIDs.value, [firstWindowID, secondWindowID])
        XCTAssertEqual(hydratedWindowIDs.value, [firstWindowID, secondWindowID])
        XCTAssertEqual(hydrationObservedAtOpen.value, [firstWindowID: false, secondWindowID: false])
    }

    /// VOY-470: bootstrap 대기 중 닫힌 window는 stale completion으로 다시 열리지 않는다.
    /// - 검증 내용: pending close가 bootstrap target/request를 제거하고 늦은 completion을 무시함
    /// - 사전 조건: pending default window 1개와 in-flight bootstrap request
    /// - 기대 결과: window 제거, native open 0회, stale completion 이후에도 상태 불변
    func testClosingPendingBootstrapWindowPreventsStaleNativeOpen() async {
        let windowID = UUID(47085)
        let requestID = UUID(47086)
        let openedIDs = LockIsolated<[UUID]>([])
        var initialState = WindowManagerFeature.State()
        initialState.windows = [WindowSessionState(id: windowID, window: .makeInitial(path: nil))]
        initialState.focusedWindowID = windowID
        initialState.pendingWindowOpenIDs = [windowID]
        initialState.defaultWindowBootstrapRequestID = requestID
        initialState.defaultWindowBootstrapWindowIDs = [windowID]
        let fallbackWindow = FileManagerWindowFeature.State.makeInitial(path: nil)

        let store = TestStore(initialState: initialState) {
            WindowManagerFeature()
        } withDependencies: {
            $0.fileManagerWindowClient.close = { _ in }
            $0.fileManagerWindowClient.finalizeClose = { _ in }
            $0.fileManagerWindowClient.registeredWindowIDs = { [] }
            $0.fileManagerWindowClient.open = { id in openedIDs.withValue { $0.append(id) } }
        }
        // store.exhaustivity = .off: close effect의 내부 callback보다 terminal ownership을 검증한다.
        store.exhaustivity = .off

        await store.send(.window(.closeFocusedWindow))
        await store.skipReceivedActions()
        await store.finish()

        XCTAssertTrue(store.state.windows.isEmpty)
        XCTAssertNil(store.state.defaultWindowBootstrapRequestID)
        XCTAssertTrue(store.state.defaultWindowBootstrapWindowIDs.isEmpty)

        await store.send(.defaultWindowBootstrapCompleted(
            requestID: requestID,
            result: .init(
                contentTabs: fallbackWindow.contentTabs,
                fixedLocationItems: [],
                topNavigationOrder: .init(),
                arrangementAvailability: .available,
            ),
        ))
        await store.finish()

        XCTAssertTrue(openedIDs.value.isEmpty)
        XCTAssertTrue(store.state.windows.isEmpty)
    }

    /// VOY-470: persistence tombstone window는 reopen 후보에서 제외된다.
    /// - 검증 내용: closing source가 focus/MRU에 남아 있어도 live peer만 native open 대상으로 선택됨
    /// - 사전 조건: deferred source window와 ready peer window가 함께 존재
    /// - 기대 결과: source는 내부 tombstone으로 유지되고 peer만 focus/open됨
    func testDeferredPersistenceWindowIsExcludedFromReopenCandidates() async {
        let sourceID = UUID(47087)
        let peerID = UUID(47088)
        let openedIDs = LockIsolated<[UUID]>([])
        var initialState = WindowManagerFeature.State()
        initialState.windows = [
            .init(id: sourceID, window: .makeInitial(path: "/source")),
            .init(id: peerID, window: .makeInitial(path: "/peer")),
        ]
        initialState.focusedWindowID = sourceID
        initialState.lastUsedWindowIDs = [sourceID, peerID]
        initialState.closingWindowIDs = [sourceID]
        initialState.deferredClosedWindowIDs = [sourceID]

        let store = TestStore(initialState: initialState) { WindowManagerFeature() } withDependencies: {
            $0.fileManagerWindowClient.open = { id in openedIDs.withValue { $0.append(id) } }
        }
        store.exhaustivity = .off

        await store.send(.lifecycle(.reopenWindowIfNeeded(hasVisibleWindows: false)))
        await store.finish()

        XCTAssertEqual(store.state.focusedWindowID, peerID)
        XCTAssertEqual(openedIDs.value, [peerID])
        XCTAssertNotNil(store.state.windows[id: sourceID])
    }

    /// VOY-470: pending/bootstrap window close는 persistence tombstone만 남기고 open ownership을 즉시 해제한다.
    /// - 검증 내용: pending native open, bootstrap target/request, focus/MRU가 close event에서 제거됨
    /// - 사전 조건: source-owned persistence queue와 pending default-window bootstrap이 동시 존재
    /// - 기대 결과: source element는 FIFO 종료까지 유지되지만 어떤 native-open 경로에서도 제외됨
    func testDeferredPersistenceCloseImmediatelyReleasesPendingBootstrapOwnership() async {
        let sourceID = UUID(47089)
        let token = FileManagerTopNavigationOperationToken(value: UUID(47090))
        let requestID = UUID(47091)
        let request = WindowManagerTopNavigationPersistenceRequest(
            sourceWindowID: sourceID,
            token: token,
            operation: .move(
                source: .location("source"),
                destination: .after(.location("destination")),
                discoveredLocationIDs: ["source", "destination"],
            ),
        )
        var initialState = WindowManagerFeature.State()
        initialState.windows = [.init(id: sourceID, window: .makeInitial(path: nil))]
        initialState.focusedWindowID = sourceID
        initialState.lastUsedWindowIDs = [sourceID]
        initialState.pendingWindowOpenIDs = [sourceID]
        initialState.defaultWindowBootstrapRequestID = requestID
        initialState.defaultWindowBootstrapWindowIDs = [sourceID]
        initialState.topNavigationPersistenceQueue = [request]
        initialState.isTopNavigationPersistenceInFlight = true

        let store = TestStore(initialState: initialState) { WindowManagerFeature() }
        store.exhaustivity = .off

        await store.send(.event(.windowClosed(sourceID)))
        await store.finish()

        XCTAssertNotNil(store.state.windows[id: sourceID])
        XCTAssertTrue(store.state.closingWindowIDs.contains(sourceID))
        XCTAssertTrue(store.state.deferredClosedWindowIDs.contains(sourceID))
        XCTAssertFalse(store.state.pendingWindowOpenIDs.contains(sourceID))
        XCTAssertNil(store.state.defaultWindowBootstrapRequestID)
        XCTAssertTrue(store.state.defaultWindowBootstrapWindowIDs.isEmpty)
        XCTAssertNil(store.state.focusedWindowID)
        XCTAssertTrue(store.state.lastUsedWindowIDs.isEmpty)
    }

    /// VOY-470: deferred close의 external activation retry는 다음 persistence FIFO를 막지 않는다.
    /// - 검증 내용: activation이 대기 중이어도 다른 source의 다음 move transaction이 즉시 시작됨
    /// - 사전 조건: closing source finalization, matching activation attempt, queued peer move
    /// - 기대 결과: activation과 다음 persistence가 병렬 시작되고 두 terminal 뒤 queue가 비워짐
    func testDeferredFinalizationDoesNotBlockNextPersistenceBehindExternalActivation() async throws {
        let sourceID = UUID(47092)
        let peerID = UUID(47093)
        let batchID = UUID(47094)
        let sourceRequest = WindowManagerTopNavigationPersistenceRequest(
            sourceWindowID: sourceID,
            token: .init(value: UUID(47095)),
            operation: .move(
                source: .location("source-a"),
                destination: .after(.location("source-b")),
                discoveredLocationIDs: [],
            ),
        )
        let peerRequest = WindowManagerTopNavigationPersistenceRequest(
            sourceWindowID: peerID,
            token: .init(value: UUID(47096)),
            operation: .move(
                source: .location("peer-a"),
                destination: .after(.location("peer-b")),
                discoveredLocationIDs: [],
            ),
        )
        let sourceWindow = FileManagerWindowFeature.State.makeInitial(path: "/source")
        let peerWindow = FileManagerWindowFeature.State.makeInitial(path: "/peer")
        let peerTabID = try XCTUnwrap(peerWindow.contentTabs.activeTabID)
        let plan = ExternalOpenPlacementPlan(
            batchID: batchID,
            windows: [
                .init(windowID: sourceID, isNewWindow: false, items: []),
                .init(
                    windowID: peerID,
                    isNewWindow: false,
                    items: [.init(itemID: UUID(47097), tabID: peerTabID)],
                ),
            ],
        )
        let activationStarted = expectation(description: "external activation retry started")
        let persistenceStarted = expectation(description: "next persistence started")
        let activationGate = AsyncStream<Void>.makeStream()
        let persistenceGate = AsyncStream<Void>.makeStream()
        var initialState = WindowManagerFeature.State()
        initialState.windows = [
            .init(id: sourceID, window: sourceWindow),
            .init(id: peerID, window: peerWindow),
        ]
        initialState.closingWindowIDs = [sourceID]
        initialState.deferredClosedWindowIDs = [sourceID]
        initialState.authorizedExternalOpenBatchID = batchID
        initialState.externalOpenActivationAttempt = .init(
            batchID: batchID,
            plan: plan,
            windowID: sourceID,
            excludedWindowIDs: [],
        )
        initialState.topNavigationPersistenceQueue = [sourceRequest, peerRequest]
        initialState.isTopNavigationPersistenceInFlight = true

        let store = TestStore(initialState: initialState) { WindowManagerFeature() } withDependencies: {
            $0.fileManagerWindowClient.activate = { _ in
                activationStarted.fulfill()
                for await _ in activationGate.stream {
                    break
                }
                return .becameKey
            }
            $0.contentTabPinnedRecordClient.moveTopNavigationItemCommitted = { _, _, source, _ in
                XCTAssertEqual(source, .location("peer-a"))
                persistenceStarted.fulfill()
                for await _ in persistenceGate.stream {
                    break
                }
                return .init(order: .init(), revision: 2)
            }
            $0.undoManagerClient.invalidateWindow = { _ in
                .init(succeeded: true, availability: .init())
            }
            $0.fileManagerWindowClient.finalizeClose = { _ in }
        }
        store.exhaustivity = .off

        await store.send(.topNavigationPersistenceCompleted(.init(
            request: sourceRequest,
            terminal: .failed(.save),
            authoritativePinnedContentTabs: nil,
        )))
        await fulfillment(of: [activationStarted, persistenceStarted], timeout: 5)
        await store.skipReceivedActions()

        XCTAssertFalse(store.state.closingWindowIDs.contains(sourceID))
        XCTAssertEqual(store.state.topNavigationPersistenceQueue, [peerRequest])
        XCTAssertTrue(store.state.isTopNavigationPersistenceInFlight)

        persistenceGate.continuation.yield()
        persistenceGate.continuation.finish()
        activationGate.continuation.yield()
        activationGate.continuation.finish()
        await store.skipReceivedActions()
        await store.finish()

        XCTAssertTrue(store.state.topNavigationPersistenceQueue.isEmpty)
        XCTAssertFalse(store.state.isTopNavigationPersistenceInFlight)
    }

    /// VOY-470: ready-to-open terminal은 close/external ownership을 native open 직전에 다시 검사한다.
    /// - 검증 내용: closing 또는 external-owned pending window에 대한 ready action 무시
    /// - 사전 조건: pending window가 closing set 또는 external batch map에 포함됨
    /// - 기대 결과: 두 경우 모두 native open 0회, pending identity 유지
    func testWindowReadyToOpenRevalidatesPendingOwnership() async {
        let closingWindowID = UUID(47087)
        let externalWindowID = UUID(47088)
        let externalBatchID = UUID(47089)
        let openedIDs = LockIsolated<[UUID]>([])
        var initialState = WindowManagerFeature.State()
        initialState.windows = [
            WindowSessionState(id: closingWindowID, window: .makeInitial(path: nil)),
            WindowSessionState(id: externalWindowID, window: .makeInitial(path: nil)),
        ]
        initialState.pendingWindowOpenIDs = [closingWindowID, externalWindowID]
        initialState.closingWindowIDs = [closingWindowID]
        initialState.externalWindowBatchIDs[externalWindowID] = externalBatchID

        let store = TestStore(initialState: initialState) {
            WindowManagerFeature()
        } withDependencies: {
            $0.fileManagerWindowClient.open = { id in openedIDs.withValue { $0.append(id) } }
        }
        store.exhaustivity = .off

        await store.send(.windowReadyToOpen(id: closingWindowID))
        await store.send(.windowReadyToOpen(id: externalWindowID))
        await store.finish()

        XCTAssertTrue(openedIDs.value.isEmpty)
        XCTAssertEqual(store.state.pendingWindowOpenIDs, [closingWindowID, externalWindowID])
    }

    /// VOY-470: corrupt/future bootstrap은 bytes를 보존하고 typed unavailable state를 노출한다.
    /// 두 unavailable 분류가 missing writable store로 축소되지 않는 실제 default-window 경계를 검증한다.
    /// - 검증 내용: corrupt/unsupportedSchema 구분, redacted presentation, pinned-store/seed write 0회
    /// - 사전 조건: malformed payload 또는 schemaVersion 3 payload
    /// - 기대 결과: 원본 bytes 불변, contract write 0회, 정확한 `.loadUnavailable` typed failure
    func testDefaultWindowBootstrapSurfacesUnavailableStoreWithoutRewritingBytes() async {
        struct Scenario {
            let name: String
            let data: Data
            let failure: FileManagerTopNavigationArrangementLoadFailure
        }

        let storageKey = "fileManager.pinnedContentTabs.v1"
        let scenarios = [
            Scenario(name: "corrupt", data: Data("not-json".utf8), failure: .corrupt),
            Scenario(
                name: "future",
                data: Data(#"{"schemaVersion":3}"#.utf8),
                failure: .unsupportedSchema(3),
            ),
        ]

        for (index, scenario) in scenarios.enumerated() {
            let windowID = UUID(47070 + index)
            let storedData = LockIsolated(scenario.data)
            let contractOwnedKeys: Set<String> = [
                storageKey,
                SettingsKeys.defaultPinnedTabsSeedCompleted,
                SettingsKeys.finderFavoritesPinnedSeedCompleted,
                SettingsKeys.recentsPinnedSeedCompleted,
                SettingsKeys.allTagsPinnedSeedCompleted,
            ]
            let contractWriteCount = LockIsolated(0)
            let observedWriteKeys = LockIsolated<[String]>([])
            let recordWrite: @Sendable (String) -> Void = { key in
                observedWriteKeys.withValue { $0.append(key) }
                if contractOwnedKeys.contains(key) {
                    contractWriteCount.withValue { $0 += 1 }
                }
            }
            let defaultsClient = UserDefaultsClient(
                bool: { _ in false },
                setBool: { _, key in recordWrite(key) },
                string: { _ in nil },
                setString: { _, key in recordWrite(key) },
                double: { _ in 0 },
                setDouble: { _, key in recordWrite(key) },
                object: { key in key == storageKey ? storedData.value : nil },
                setObject: { _, key in recordWrite(key) },
            )
            let store = TestStore(initialState: WindowManagerFeature.State()) {
                WindowManagerFeature()
            } withDependencies: {
                $0.uuid = .constant(windowID)
                $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
                $0.contentTabPinnedRecordClient = .liveValue
                $0.userDefaultsClient = defaultsClient
                $0.onboardingWindowClient.showIfNeeded = { false }
                $0.fileManagerWindowClient.registeredWindowIDs = { [windowID] }
                $0.fileManagerWindowClient.open = { _ in }
            }
            // store.exhaustivity = .off: typed unavailable와 contract-owned write 부재만 검증한다.
            store.exhaustivity = .off

            await store.send(.file(.newWindow(path: nil)))
            await store.receive(\.defaultWindowBootstrapCompleted)
            await store.receive { action in
                guard case let .windows(.element(
                    id: id,
                    action: .window(.applyBootstrap(bootstrap)),
                )) = action else { return false }
                return id == windowID
                    && bootstrap.arrangementAvailability == .unavailable(scenario.failure)
                    && !bootstrap.authoritativePinnedContentTabs.tabs.contains(where: \.isPinned)
            }
            await store.finish()

            let window = store.state.windows[id: windowID]?.window
            XCTAssertEqual(
                window?.topNavigationArrangementAvailability,
                .unavailable(scenario.failure),
                scenario.name,
            )
            XCTAssertEqual(window?.topNavigationArrangementPresentation, .loadUnavailable, scenario.name)
            XCTAssertEqual(
                window?.topNavigationArrangementPresentation?.message,
                "Couldn’t load the saved sidebar arrangement. A default order is shown; the saved data was not changed.",
                scenario.name,
            )
            XCTAssertEqual(storedData.value, scenario.data, scenario.name)
            XCTAssertEqual(contractWriteCount.value, 0, scenario.name)
            XCTAssertEqual(observedWriteKeys.value.count, 3, scenario.name)
            XCTAssertEqual(
                Set(observedWriteKeys.value),
                Set([
                    EntryArrangementsPersistenceKey.sortKey,
                    EntryArrangementsPersistenceKey.sortOrder,
                    EntryArrangementsPersistenceKey.groupKey,
                ]),
                scenario.name,
            )
        }
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
            $0.fileManagerWindowClient.registeredWindowIDs = { [newID] }
            $0.fileManagerWindowClient.open = { _ in }
        }
        store.exhaustivity = .off

        await store.send(.file(.openCollectionFile(collectionURL)))
        XCTAssertEqual(store.state.windows.count, 1)
        XCTAssertFalse(
            store.state.windows.first?.window.contentTabs.tabs.contains(where: \.isPinned) ?? true,
        )

        await store.receive { action in
            guard case let .windows(.element(
                id: id,
                action: .window(.content(.entryViewLayout(.entryOperations(.lifecycle(.windowIDChanged(receivedID)))))),
            )) = action else {
                return false
            }
            return id == newID && receivedID == newID
        }
        await store.receive { action in
            guard case let .windows(.element(
                id: id,
                action: .window(.navigation(.view(.openCollectionFile(url)))),
            )) = action else {
                return false
            }
            return id == newID && url == collectionURL
        }
        let defaultPreferences = AppPreferencesState().toPackageState()
        await store.receive { action in
            guard case let .windows(.element(
                id: id,
                action: .window(.applyAppPreferences(preferences)),
            )) = action else {
                return false
            }
            return id == newID && preferences == defaultPreferences
        }

        await store.receive(\.defaultWindowBootstrapCompleted)
        await store.receive { action in
            guard case let .windows(.element(id: id, action: .window(.applyBootstrap(bootstrap)))) = action
            else {
                return false
            }
            return id == newID
                && bootstrap.authoritativePinnedContentTabs.tabs.filter(\.isPinned).map(\.id.rawValue) == ["dir-1"]
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
            $0.fileManagerWindowClient.registeredWindowIDs = { [newID] }
            $0.fileManagerWindowClient.open = { _ in }
        }
        store.exhaustivity = .off

        await store.send(.file(.newWindow(path: nil)))
        await store.receive(\.defaultWindowBootstrapCompleted)
        await store.receive { action in
            guard case let .windows(.element(id: id, action: .window(.applyBootstrap))) = action
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
            $0.fileManagerWindowClient.registeredWindowIDs = { [newID] }
            $0.fileManagerWindowClient.open = { _ in }
        }
        store.exhaustivity = .off

        await store.send(.file(.newWindow(path: nil)))
        await store.receive(\.defaultWindowBootstrapCompleted)
        await store.receive { action in
            guard case let .windows(.element(id: id, action: .window(.applyBootstrap))) = action
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
            $0.fileManagerWindowClient.registeredWindowIDs = { [newID] }
            $0.fileManagerWindowClient.open = { _ in }
        }
        store.exhaustivity = .off

        await store.send(.file(.newWindow(path: nil)))
        await store.receive(\.defaultWindowBootstrapCompleted)
        await store.receive { action in
            guard case let .windows(.element(id: id, action: .window(.applyBootstrap))) = action
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

    /// app-owned pinned durable commit은 authoritative fan-out을 정확히 한 번만 수행한다.
    /// parent completion 뒤 duplicate child terminal이 추가 store resync나 synthetic snapshot fan-out을 만들지 않는지 검증한다.
    /// - 검증 내용: queue committed fan-out 1회, late child success resync 0회, external window runtime 보존
    /// - 사전 조건: source/peer window 2개, in-flight pinned persistence request 1개, authoritative pinned store 1개
    /// - 기대 결과: 두 window가 동일 committed snapshot을 한 번 받고 late child success 뒤 count/state가 유지된다.
    func testPinnedRecordQueueCommitFansOutExactlyOnceAndIgnoresLateChildSuccess() async throws {
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
        let globalPinID = ContentTabID(rawValue: "global-pin")
        let persistenceIntentID = try XCTUnwrap(
            initialState.windows[id: firstID]?.window.contentTabs
                .markLatestPinnedRecordPersistenceIntent(for: globalPinID),
        )
        let context = ContentTabPinnedRecordTerminalContext(
            intentID: persistenceIntentID,
            generation: ContentTabPinnedRecordMutationGeneration(tabID: globalPinID),
        )
        let request = WindowManagerTopNavigationPersistenceRequest(
            sourceWindowID: firstID,
            token: .init(value: UUID()),
            operation: .pinnedRecord(
                source: .contentTab,
                request: .init(
                    tabID: globalPinID,
                    context: context,
                    rollback: .init(
                        previousIsPinned: false,
                        previousPinnedRecord: nil,
                        previousTabIndex: nil,
                    ),
                    mutation: .upsert(
                        record: pinnedStore.records[0],
                        dormantSlot: nil,
                    ),
                    persistenceScopeID: UUID(),
                ),
                discoveredLocationIDs: [],
            ),
        )
        initialState.topNavigationPersistenceQueue = [request]
        initialState.isTopNavigationPersistenceInFlight = true
        let counts = LockIsolated(WindowManagerPinnedCommitFanOutCounts())

        let store = TestStore(initialState: initialState) {
            CombineReducers {
                WindowManagerFeature()
                Reduce { _, action in
                    counts.withValue { $0.record(action) }
                    return .none
                }
            }
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
            $0.fileManagerClient.fileExistsWithIsDirectory = { path, isDirectory in
                guard path == "/Users/test/Documents" else { return false }
                isDirectory?.pointee = ObjCBool(true)
                return true
            }
            $0.onboardingWindowClient.showIfNeeded = { false }
            $0.fileManagerWindowClient.open = { _ in }
        }
        // store.exhaustivity = .off: queue completion의 committed snapshot count와 late child terminal no-op만 검증한다.
        store.exhaustivity = .off

        await store.send(.topNavigationPersistenceCompleted(.init(
            request: request,
            terminal: .committed(.init(order: pinnedStore.topNavigationOrder, revision: 1)),
            authoritativePinnedContentTabs: ContentTabState.restoringPinnedRecords(from: pinnedStore).state,
        )))
        await store.skipReceivedActions()

        XCTAssertEqual(counts.value.storeChanged, 0)
        XCTAssertEqual(counts.value.committedSnapshotByWindow[firstID], 1)
        XCTAssertEqual(counts.value.committedSnapshotByWindow[secondID], 1)
        XCTAssertTrue(counts.value.authoritativeSyncByWindow.isEmpty)

        XCTAssertEqual(store.state.windows[id: firstID]?.window.contentTabs.tabs.first?.id.rawValue, "global-pin")
        XCTAssertEqual(store.state.windows[id: secondID]?.window.contentTabs.tabs.first?.id.rawValue, "global-pin")
        XCTAssertEqual(
            store.state.windows[id: secondID]?.window.contentTabs.tabs.contains {
                !$0.isPinned && $0.anchor == .directory(path: "/Users/test/B")
            },
            true,
        )

        let countsAfterCommit = counts.value
        await store.send(.windows(.element(
            id: firstID,
            action: .window(.contentTabs(.pinnedRecordSaveSucceeded(
                tabID: globalPinID,
                context: context,
            ))),
        )))
        await store.skipReceivedActions()

        XCTAssertEqual(counts.value, countsAfterCommit)
    }

    /// CTM-003-product_terminal_metrics: 실제 앱 WindowManager 소유 persistence에서 direct pin이
    /// 정확히 한 건의 typed metric으로 귀환하는지 검증하는 전체 왕복 계약.
    /// UI pin → correlation → delegate persistPinnedRecordMutation → 큐 커밋 → source 터미널 복귀.
    /// - 검증 내용: committed 왕복 뒤 `.contentTabAction(.success/.pin)` 1회와 상관 완전 소비
    /// - 사전 조건: 실제 FileManager 창 1개와 applied commit을 반환하는 pinned record client
    /// - 기대 결과: 레코더에 pin success 메트릭 정확히 1건
    func testWindowManagerOwnedDirectPinRoundTripRecordsSingleSuccessMetric() async {
        let windowID = UUID()
        let pinOperationID = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 5, 1))
        let path = "/Users/test/A"
        var initialState = WindowManagerFeature.State()
        initialState.windows = [WindowSessionState(id: windowID, window: .makeInitial(path: path))]
        guard let tabID = initialState.windows[id: windowID]?.window.contentTabs.tabs.first(where: {
            $0.anchor == .directory(path: path) && !$0.isPinned
        })?.id else {
            return XCTFail("initial window must contain the unpinned directory tab")
        }
        let metrics = LockIsolated<[FileManagerProductMetric]>([])
        let operationIDs = LockIsolated([pinOperationID])
        let pinnedStore = ContentTabPinnedRecordStore(
            records: [
                ContentTabPinnedRecord(
                    id: tabID.rawValue,
                    page: .directory,
                    anchor: .directory(path: path),
                    title: nil,
                    iconName: nil,
                    pinnedAt: Date(timeIntervalSince1970: 443),
                ),
            ],
            topNavigationOrder: .init(items: [.contentTab(tabID)]),
        )

        let store = TestStore(initialState: initialState) {
            WindowManagerFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
            $0.fileManagerProductMetricsClient = FileManagerProductMetricsClient(
                record: { metric in metrics.withValue { $0.append(metric) } },
                makeOperationID: {
                    operationIDs.withValue { $0.isEmpty ? UUID() : $0.removeFirst() }
                },
            )
            $0.contentTabPinnedRecordClient.reserveTopNavigationOperationToken = {
                FileManagerTopNavigationOperationToken(value: UUID(uuid: (
                    0,
                    0,
                    0,
                    0,
                    0,
                    0,
                    0,
                    0,
                    0,
                    0,
                    0,
                    0,
                    0,
                    0,
                    5,
                    2,
                )))
            }
            $0.contentTabPinnedRecordClient.applyPersistenceMutationCommitted = { _, _, _ in
                ContentTabPinnedRecordPersistenceCommit(
                    store: pinnedStore,
                    topNavigation: .init(order: pinnedStore.topNavigationOrder, revision: 1),
                )
            }
            $0.fileManagerClient.fileExistsWithIsDirectory = { _, _ in true }
            $0.onboardingWindowClient.showIfNeeded = { false }
            $0.fileManagerWindowClient.open = { _ in }
        }
        // store.exhaustivity = .off: bootstrap/peer fanout 부수 effect보다 metric 왕복 계약에 집중함
        store.exhaustivity = .off

        await store.send(.windows(.element(
            id: windowID,
            action: .window(.contentTabs(.pin(tabID, placement: nil))),
        )))
        await store.skipReceivedActions()

        XCTAssertEqual(
            metrics.value,
            [.contentTabAction(
                result: .success,
                action: .pin,
                source: .contentTabBar,
                operationID: pinOperationID,
            )],
            "WindowManager-owned direct pin must record exactly one success metric",
        )
        XCTAssertTrue(
            store.state.windows[id: windowID]?.window.productContentTabPinMutationMetrics.isEmpty ?? false,
        )
    }

    /// CTM-003-product_terminal_metrics: WindowManager 소유 direct pin의 store-unavailable 왕복도
    /// 정확히 한 건의 `.unavailable` 메트릭으로 귀환하는지 검증.
    /// - 검증 내용: commit 실패 후 `.contentTabAction(.unavailable/.pin)` 1회와 상관 해제
    /// - 사전 조건: corrupt store로 실패하는 pinned record client
    /// - 기대 결과: 레코더에 pin unavailable 메트릭 정확히 1건
    func testWindowManagerOwnedDirectPinFailureRoundTripRecordsSingleUnavailableMetric() async {
        let windowID = UUID()
        let pinOperationID = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 5, 3))
        let path = "/Users/test/A"
        var initialState = WindowManagerFeature.State()
        initialState.windows = [WindowSessionState(id: windowID, window: .makeInitial(path: path))]
        guard let tabID = initialState.windows[id: windowID]?.window.contentTabs.tabs.first(where: {
            $0.anchor == .directory(path: path) && !$0.isPinned
        })?.id else {
            return XCTFail("initial window must contain the unpinned directory tab")
        }
        let metrics = LockIsolated<[FileManagerProductMetric]>([])
        let operationIDs = LockIsolated([pinOperationID])

        let store = TestStore(initialState: initialState) {
            WindowManagerFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
            $0.fileManagerProductMetricsClient = FileManagerProductMetricsClient(
                record: { metric in metrics.withValue { $0.append(metric) } },
                makeOperationID: {
                    operationIDs.withValue { $0.isEmpty ? UUID() : $0.removeFirst() }
                },
            )
            $0.contentTabPinnedRecordClient.reserveTopNavigationOperationToken = {
                FileManagerTopNavigationOperationToken(value: UUID(uuid: (
                    0,
                    0,
                    0,
                    0,
                    0,
                    0,
                    0,
                    0,
                    0,
                    0,
                    0,
                    0,
                    0,
                    0,
                    5,
                    4,
                )))
            }
            $0.contentTabPinnedRecordClient.applyPersistenceMutationCommitted = { _, _, _ in
                throw ContentTabPinnedRecordStoreLoadError.corruptUnavailable
            }
            $0.fileManagerClient.fileExistsWithIsDirectory = { _, _ in true }
            $0.onboardingWindowClient.showIfNeeded = { false }
            $0.fileManagerWindowClient.open = { _ in }
        }
        // store.exhaustivity = .off: rollback/peer fanout 부수 effect보다 metric 왕복 계약에 집중함
        store.exhaustivity = .off

        await store.send(.windows(.element(
            id: windowID,
            action: .window(.contentTabs(.pin(tabID, placement: nil))),
        )))
        await store.skipReceivedActions()

        XCTAssertEqual(
            metrics.value,
            [.contentTabAction(
                result: .unavailable,
                action: .pin,
                source: .contentTabBar,
                operationID: pinOperationID,
            )],
            "WindowManager-owned direct pin failure must record exactly one unavailable metric",
        )
        XCTAssertTrue(
            store.state.windows[id: windowID]?.window.productContentTabPinMutationMetrics.isEmpty ?? false,
        )
    }

    /// busy source window는 최신 pinned snapshot을 batch 완료 뒤 한 번 재생한다.
    /// source가 batch 중 fan-out을 defer해도 추가 store-changed event 없이 최신 snapshot으로 수렴하는지 검증한다.
    /// - 검증 내용: 이전 deferred snapshot을 latest-wins로 교체하고 coordinator clear 뒤 source에 replay
    /// - 사전 조건: source window의 matching batch/current pending, 이전 snapshot, 별도 열린 window, 최신 global store
    /// - 기대 결과: store event는 한 번이고 두 window가 최신 pinned state로 수렴하며 source의 local unpinned tab은 보존됨
    func testBatchPinnedRecordSaveSucceededSyncsOtherWindowsExactlyOnce() async {
        let sourceWindowID = UUID()
        let otherWindowID = UUID()
        let operationID = UUID()
        let batchTabID = ContentTabID(rawValue: "batch-pinned-success")
        let stalePinnedStore = ContentTabPinnedRecordStore(records: [
            ContentTabPinnedRecord(
                id: "stale-batch-pin",
                page: .directory,
                anchor: .directory(path: "/Users/test/StaleBatchPin"),
                title: "Stale Batch Pin",
                iconName: "folder",
                pinnedAt: Date(timeIntervalSince1970: 452),
            ),
        ])
        let globalPinnedStore = ContentTabPinnedRecordStore(records: [
            ContentTabPinnedRecord(
                id: "global-batch-pin",
                page: .directory,
                anchor: .directory(path: "/Users/test/GlobalBatchPin"),
                title: "Global Batch Pin",
                iconName: "folder",
                pinnedAt: Date(timeIntervalSince1970: 453),
            ),
        ])
        let stalePinnedTabs = ContentTabState.restoringPinnedRecords(from: stalePinnedStore).state
        var sourceWindow = FileManagerWindowFeature.State.makeInitial(path: "/Users/test/Source")
        sourceWindow.contentTabs.tabs.append(ContentTabItem(
            id: batchTabID,
            page: .directory,
            anchor: .directory(path: "/Users/test/BatchPinned"),
            isPinned: false,
            title: "Batch Pinned",
            iconName: "folder",
        ))
        sourceWindow.pendingSelectedContentTabClose = PendingSelectedContentTabClose(
            operationID: operationID,
            orderedTargetIDs: [batchTabID],
            currentTabID: batchTabID,
            originalActiveTabID: sourceWindow.contentTabs.activeTabID,
            preferredFallbackIDs: sourceWindow.contentTabs.tabs.map(\.id),
        )
        sourceWindow.pendingContentTabClose = PendingContentTabClose(
            tabID: batchTabID,
            batchOperationID: operationID,
        )
        let otherWindow = FileManagerWindowFeature.State.makeInitial(path: "/Users/test/Other")
        var initialState = WindowManagerFeature.State()
        initialState.windows = [
            WindowSessionState(id: sourceWindowID, window: sourceWindow),
            WindowSessionState(id: otherWindowID, window: otherWindow),
        ]
        let syncCount = LockIsolated(0)
        let store = TestStore(initialState: initialState) {
            CombineReducers {
                WindowManagerFeature()
                Reduce { _, action in
                    if case .pinnedContentTabsStoreChanged = action {
                        syncCount.withValue { $0 += 1 }
                    }
                    return .none
                }
            }
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 453))
            $0.contentTabPinnedRecordClient.loadStore = { _ in globalPinnedStore }
        }
        // store.exhaustivity = .off: parent fan-out과 source replay의 semantic 경계 및 최종 window state를 검증한다.
        store.exhaustivity = .off

        await store.send(.windows(.element(
            id: sourceWindowID,
            action: .window(.applyPinnedContentTabs(stalePinnedTabs)),
        )))
        XCTAssertEqual(
            pinnedTabIDs(store.state.windows[id: sourceWindowID]?.window.deferredPinnedContentTabs),
            ["stale-batch-pin"],
        )

        await store.send(.pinnedContentTabsStoreChanged)
        await store.receive { action in
            guard case let .windows(.element(
                id: id,
                action: .window(.applyAuthoritativePinnedContentTabs(contentTabs)),
            )) = action
            else { return false }
            return id == sourceWindowID
                && contentTabs.tabs.filter(\.isPinned).map(\.id.rawValue) == ["global-batch-pin"]
        }
        await store.receive { action in
            guard case let .windows(.element(
                id: id,
                action: .window(.applyAuthoritativePinnedContentTabs(contentTabs)),
            )) = action
            else { return false }
            return id == otherWindowID
                && contentTabs.tabs.filter(\.isPinned).map(\.id.rawValue) == ["global-batch-pin"]
        }
        XCTAssertEqual(
            pinnedTabIDs(store.state.windows[id: sourceWindowID]?.window.deferredPinnedContentTabs),
            ["global-batch-pin"],
        )

        await store.send(.windows(.element(
            id: sourceWindowID,
            action: .window(.selectedContentTabCloseItemCompleted(
                operationID: operationID,
                tabID: batchTabID,
                outcome: .unpinned,
            )),
        )))
        await store.receive { action in
            guard case let .windows(.element(
                id: id,
                action: .window(.processNextSelectedContentTabClose(receivedID)),
            )) = action else { return false }
            return id == sourceWindowID && receivedID == operationID
        }
        await store.receive { action in
            guard case let .windows(.element(
                id: id,
                action: .window(.applyAuthoritativePinnedContentTabs(contentTabs)),
            )) = action
            else { return false }
            return id == sourceWindowID
                && contentTabs.tabs.filter(\.isPinned).map(\.id.rawValue) == ["global-batch-pin"]
        }
        await store.finish()

        XCTAssertEqual(syncCount.value, 1)
        XCTAssertNil(store.state.windows[id: sourceWindowID]?.window.pendingSelectedContentTabClose)
        XCTAssertNil(store.state.windows[id: sourceWindowID]?.window.deferredPinnedContentTabs)
        XCTAssertEqual(
            store.state.windows[id: sourceWindowID]?.window.contentTabs.tabs.filter(\.isPinned).map(\.id.rawValue),
            ["global-batch-pin"],
        )
        XCTAssertEqual(
            store.state.windows[id: sourceWindowID]?.window.contentTabs.tabs.contains {
                !$0.isPinned && $0.anchor == .directory(path: "/Users/test/Source")
            },
            true,
        )
        XCTAssertEqual(
            store.state.windows[id: otherWindowID]?.window.contentTabs.tabs.filter(\.isPinned).map(\.id.rawValue),
            ["global-batch-pin"],
        )
    }

    /// CTM-003-pin_content_tab_s: 빠른 unpin→repin은 승인 순서대로 저장되고 최신 pin overlay로 수렴한다.
    /// - 검증 내용: 첫 write 대기 중 repin enqueue, 두 committed revision, 빈 overlay queue
    /// - 사전 조건: pinned A와 첫 parent-owned mutation gate
    /// - 기대 결과: durable/runtime 모두 A pinned이며 pending token이 남지 않음
    func testPinnedRecordPersistence_rapidUnpinRepinConvergesPinnedWithoutStaleOverlay() async {
        let windowID = UUID(41101)
        let tabID = ContentTabID(rawValue: "rapid-repin")
        let record = ContentTabPinnedRecord(
            id: tabID.rawValue,
            page: .directory,
            anchor: .directory(path: "/Users/test/Rapid"),
            title: "Rapid",
            iconName: "folder",
            pinnedAt: Date(timeIntervalSince1970: 411),
        )
        let gate = PinnedRecordMutationGate()
        let persistedStore = LockIsolated(ContentTabPinnedRecordStore(
            records: [record],
            topNavigationOrder: .init(items: [.contentTab(tabID)]),
        ))
        let mutationCount = LockIsolated(0)
        var initialState = WindowManagerFeature.State()
        initialState.windows = [.init(
            id: windowID,
            window: lifecycleWindow(tabID: tabID, record: record, path: "/Users/test/Source"),
        )]
        let store = Store(initialState: initialState) { WindowManagerFeature() } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 412))
            $0.contentTabPinnedRecordClient.applyPersistenceMutationCommitted = { _, discoveredLocationIDs, mutation in
                let count = mutationCount.withValue { value in
                    value += 1
                    return value
                }
                if count == 1 { await gate.wait() }
                let updated = try persistedStore.withValue { store in
                    store = try applying(
                        mutation,
                        to: store,
                        discoveredLocationIDs: discoveredLocationIDs,
                    )
                    return store
                }
                return .init(
                    store: updated,
                    topNavigation: .init(order: updated.topNavigationOrder, revision: UInt64(count)),
                )
            }
        }

        let unpinTask = store.send(.windows(.element(
            id: windowID,
            action: .window(.contentTabs(.unpin(tabID))),
        )))
        await gate.waitUntilWaiting()
        let repinTask = store.send(.windows(.element(
            id: windowID,
            action: .window(.contentTabs(.pin(tabID))),
        )))
        await gate.open()
        await unpinTask.finish()
        await repinTask.finish()

        XCTAssertEqual(mutationCount.value, 2)
        XCTAssertEqual(persistedStore.value.records.map(\.id), [tabID.rawValue])
        store.withState { state in
            let window = state.windows[id: windowID]?.window
            XCTAssertEqual(window?.contentTabs.tabs[id: tabID]?.isPinned, true)
            XCTAssertEqual(window?.contentTabs.pendingPinnedRecordIDs.isEmpty, true)
            XCTAssertEqual(window?.pendingTopNavigationIntents.isEmpty, true)
            XCTAssertEqual(window?.optimisticTopNavigationOrder.items, [.contentTab(tabID)])
        }
    }

    /// CTM-003-pin_content_tab_s: committed unpin 뒤 최신 repin 실패는 committed base로 rollback한다.
    /// - 검증 내용: unpin revision 적용 후 repin save failure와 exact overlay cleanup
    /// - 사전 조건: 첫 mutation gate와 두 번째 mutation failure
    /// - 기대 결과: durable/runtime 모두 unpinned이고 save rollback만 표시됨
    func testPinnedRecordPersistence_latestRepinFailureRollsBackToCommittedUnpin() async {
        let windowID = UUID(41102)
        let tabID = ContentTabID(rawValue: "failed-repin")
        let record = ContentTabPinnedRecord(
            id: tabID.rawValue,
            page: .directory,
            anchor: .directory(path: "/Users/test/FailedRepin"),
            title: "Failed Repin",
            iconName: "folder",
            pinnedAt: Date(timeIntervalSince1970: 411),
        )
        let gate = PinnedRecordMutationGate()
        let persistedStore = LockIsolated(ContentTabPinnedRecordStore(
            records: [record],
            topNavigationOrder: .init(items: [.contentTab(tabID)]),
        ))
        let mutationCount = LockIsolated(0)
        var initialState = WindowManagerFeature.State()
        initialState.windows = [.init(
            id: windowID,
            window: lifecycleWindow(tabID: tabID, record: record, path: "/Users/test/Source"),
        )]
        let store = Store(initialState: initialState) { WindowManagerFeature() } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 412))
            $0.contentTabPinnedRecordClient.applyPersistenceMutationCommitted = { _, discoveredLocationIDs, mutation in
                let count = mutationCount.withValue { value in
                    value += 1
                    return value
                }
                if count == 1 { await gate.wait() }
                if count == 2 { throw ExpectedPinnedRecordSaveFailure() }
                let updated = try persistedStore.withValue { store in
                    store = try applying(
                        mutation,
                        to: store,
                        discoveredLocationIDs: discoveredLocationIDs,
                    )
                    return store
                }
                return .init(
                    store: updated,
                    topNavigation: .init(order: updated.topNavigationOrder, revision: UInt64(count)),
                )
            }
        }

        let unpinTask = store.send(.windows(.element(
            id: windowID,
            action: .window(.contentTabs(.unpin(tabID))),
        )))
        await gate.waitUntilWaiting()
        let repinTask = store.send(.windows(.element(
            id: windowID,
            action: .window(.contentTabs(.pin(tabID))),
        )))
        await gate.open()
        await unpinTask.finish()
        await repinTask.finish()

        XCTAssertTrue(persistedStore.value.records.isEmpty)
        store.withState { state in
            let window = state.windows[id: windowID]?.window
            XCTAssertEqual(window?.contentTabs.tabs[id: tabID]?.isPinned, false)
            XCTAssertEqual(window?.contentTabs.pendingPinnedRecordIDs.isEmpty, true)
            XCTAssertEqual(window?.pendingTopNavigationIntents.isEmpty, true)
            XCTAssertEqual(window?.optimisticTopNavigationOrder.items, [])
            XCTAssertEqual(window?.topNavigationArrangementPresentation, .saveRollback)
        }
    }

    /// CTM-003-unpin_content_tab_s: unpin write 중 close는 차단되고 실패 terminal이 runtime을 rollback한다.
    /// - 검증 내용: write gate 중 close request no-op, durable remove 실패, source rollback
    /// - 사전 조건: pinned A와 fallback Home, in-flight parent mutation
    /// - 기대 결과: A tab과 durable record가 pinned로 유지되고 parent queue와 window overlay가 비어 있음
    func testPinnedRecordPersistence_sourceTabCloseDoesNotCancelUnpinWrite() async {
        struct SaveError: Error {}

        let windowID = UUID(41103)
        let tabID = ContentTabID(rawValue: "close-during-unpin")
        let record = ContentTabPinnedRecord(
            id: tabID.rawValue,
            page: .directory,
            anchor: .directory(path: "/Users/test/CloseDuringUnpin"),
            title: "Close During Unpin",
            iconName: "folder",
            pinnedAt: Date(timeIntervalSince1970: 411),
        )
        let gate = PinnedRecordMutationGate()
        let persistedStore = LockIsolated(ContentTabPinnedRecordStore(records: [record]))
        var initialState = WindowManagerFeature.State()
        initialState.windows = [.init(
            id: windowID,
            window: lifecycleWindow(tabID: tabID, record: record, path: "/Users/test/Source"),
        )]
        let store = Store(initialState: initialState) { WindowManagerFeature() } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 411))
            $0.contentTabPinnedRecordClient.applyPersistenceMutationCommitted = { _, _, _ in
                await gate.wait()
                throw SaveError()
            }
        }

        let unpinTask = store.send(.windows(.element(
            id: windowID,
            action: .window(.contentTabs(.unpin(tabID))),
        )))
        await gate.waitUntilWaiting()
        store.withState { state in
            XCTAssertEqual(state.windows[id: windowID]?.window.contentTabs.pendingPinnedRecordIDs, [tabID])
        }
        let closeTask = store.send(.windows(.element(
            id: windowID,
            action: .window(.closeContentTabRequested(tabID)),
        )))
        await closeTask.finish()
        await gate.open()
        await unpinTask.finish()

        XCTAssertEqual(persistedStore.value.records, [record])
        store.withState { state in
            let window = state.windows[id: windowID]?.window
            XCTAssertEqual(window?.contentTabs.tabs[id: tabID]?.isPinned, true)
            XCTAssertEqual(window?.contentTabs.pinnedRecords[tabID], record)
            XCTAssertEqual(window?.contentTabs.pendingPinnedRecordIDs.isEmpty, true)
            XCTAssertEqual(window?.pendingTopNavigationIntents.isEmpty, true)
            XCTAssertEqual(window?.topNavigationArrangementPresentation, .saveRollback)
            XCTAssertTrue(state.topNavigationPersistenceQueue.isEmpty)
            XCTAssertFalse(state.isTopNavigationPersistenceInFlight)
        }
    }

    /// CTM-003-close_pinned_content_tab_s: authoritative fan-out 뒤 source terminal이 실제 close 정리를 완료한다.
    /// - 검증 내용: 실제 close request, parent write gate, peer fan-out, recentlyClosed와 active handoff
    /// - 사전 조건: 같은 pinned A를 가진 source/peer window와 source fallback Home
    /// - 기대 결과: source A 제거·Home 활성화·unpinned 최근 닫힘 기록, peer global pin 제거, queue 정리
    func testPinnedRecordPersistence_realCloseCompletesAfterAuthoritativeFanOut() async {
        let sourceWindowID = UUID(41108)
        let peerWindowID = UUID(41109)
        let tabID = ContentTabID(rawValue: "fanout-before-close-terminal")
        let record = ContentTabPinnedRecord(
            id: tabID.rawValue,
            page: .directory,
            anchor: .directory(path: "/Users/test/FanoutBeforeClose"),
            title: "Fanout Before Close",
            iconName: "folder",
            pinnedAt: Date(timeIntervalSince1970: 411),
        )
        let gate = PinnedRecordMutationGate()
        let persistedStore = LockIsolated(ContentTabPinnedRecordStore(
            records: [record],
            topNavigationOrder: .init(items: [.contentTab(tabID)]),
        ))
        var initialState = WindowManagerFeature.State()
        initialState.windows = [
            .init(
                id: sourceWindowID,
                window: lifecycleWindow(tabID: tabID, record: record, path: "/Users/test/Source"),
            ),
            .init(
                id: peerWindowID,
                window: lifecycleWindow(tabID: tabID, record: record, path: "/Users/test/Peer"),
            ),
        ]
        let store = Store(initialState: initialState) { WindowManagerFeature() } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 412))
            $0.contentTabPinnedRecordClient.applyPersistenceMutationCommitted = { _, discoveredLocationIDs, mutation in
                await gate.wait()
                let updated = try persistedStore.withValue { store in
                    store = try applying(
                        mutation,
                        to: store,
                        discoveredLocationIDs: discoveredLocationIDs,
                    )
                    return store
                }
                return .init(store: updated, topNavigation: .init(order: updated.topNavigationOrder, revision: 1))
            }
        }

        let closeTask = store.send(.windows(.element(
            id: sourceWindowID,
            action: .window(.closeContentTabRequested(tabID)),
        )))
        await gate.waitUntilWaiting()
        store.withState { state in
            let source = state.windows[id: sourceWindowID]?.window
            XCTAssertEqual(source?.contentTabs.tabs[id: tabID]?.isPinned, false)
            XCTAssertEqual(source?.contentTabs.activeTabID, tabID)
            XCTAssertFalse(source?.pendingTopNavigationIntents.isEmpty ?? true)
        }

        await gate.open()
        await closeTask.finish()

        XCTAssertTrue(persistedStore.value.records.isEmpty)
        store.withState { state in
            let source = state.windows[id: sourceWindowID]?.window
            let peer = state.windows[id: peerWindowID]?.window
            XCTAssertNil(source?.contentTabs.tabs[id: tabID])
            XCTAssertEqual(source?.contentTabs.activeTabID?.rawValue, "home-\(tabID.rawValue)")
            XCTAssertEqual(source?.contentTabs.recentlyClosed?.anchor, record.anchor)
            XCTAssertEqual(source?.contentTabs.recentlyClosed?.wasPinned, false)
            XCTAssertTrue(source?.pendingTopNavigationIntents.isEmpty ?? false)
            XCTAssertNil(peer?.contentTabs.tabs[id: tabID])
            XCTAssertEqual(peer?.lastConfirmedTopNavigationOrder.items, [])
            XCTAssertTrue(state.topNavigationPersistenceQueue.isEmpty)
            XCTAssertFalse(state.isTopNavigationPersistenceInFlight)
        }
    }

    /// CTM-003-unpin_content_tab_s: source window close 뒤에도 parent write와 peer fan-out이 완료된다.
    /// - 검증 내용: write gate 중 source 제거, committed authoritative peer snapshot
    /// - 사전 조건: 같은 pinned A를 가진 source/peer window
    /// - 기대 결과: source는 없고 peer에서 global pin이 제거되며 durable store와 parent queue가 비어 있음
    func testPinnedRecordPersistence_sourceWindowCloseStillFansOutCommittedUnpinToPeer() async {
        let sourceWindowID = UUID(41104)
        let peerWindowID = UUID(41105)
        let tabID = ContentTabID(rawValue: "window-close-unpin")
        let record = ContentTabPinnedRecord(
            id: tabID.rawValue,
            page: .directory,
            anchor: .directory(path: "/Users/test/WindowClose"),
            title: "Window Close",
            iconName: "folder",
            pinnedAt: Date(timeIntervalSince1970: 411),
        )
        let gate = PinnedRecordMutationGate()
        let persistedStore = LockIsolated(ContentTabPinnedRecordStore(records: [record]))
        var initialState = WindowManagerFeature.State()
        initialState.windows = [
            .init(
                id: sourceWindowID,
                window: lifecycleWindow(tabID: tabID, record: record, path: "/Users/test/Source"),
            ),
            .init(
                id: peerWindowID,
                window: lifecycleWindow(tabID: tabID, record: record, path: "/Users/test/Peer"),
            ),
        ]
        let store = Store(initialState: initialState) { WindowManagerFeature() } withDependencies: {
            $0.contentTabPinnedRecordClient.applyPersistenceMutationCommitted = { _, discoveredLocationIDs, mutation in
                await gate.wait()
                let updated = try persistedStore.withValue { store in
                    store = try applying(
                        mutation,
                        to: store,
                        discoveredLocationIDs: discoveredLocationIDs,
                    )
                    return store
                }
                return .init(store: updated, topNavigation: .init(order: updated.topNavigationOrder, revision: 1))
            }
        }

        let unpinTask = store.send(.windows(.element(
            id: sourceWindowID,
            action: .window(.contentTabs(.unpin(tabID))),
        )))
        await gate.waitUntilWaiting()
        await store.send(.event(.windowClosed(sourceWindowID))).finish()
        await gate.open()
        await unpinTask.finish()

        XCTAssertTrue(persistedStore.value.records.isEmpty)
        store.withState { state in
            XCTAssertNil(state.windows[id: sourceWindowID])
            XCTAssertNil(state.windows[id: peerWindowID]?.window.contentTabs.tabs[id: tabID])
            XCTAssertEqual(state.windows[id: peerWindowID]?.window.lastConfirmedTopNavigationOrder.items, [])
            XCTAssertTrue(state.topNavigationPersistenceQueue.isEmpty)
            XCTAssertFalse(state.isTopNavigationPersistenceInFlight)
        }
    }

    /// CTM-003-go_to_anchored_path_of_pinned_tab: source window 종료 뒤에도 anchor update가 peer에 수렴한다.
    /// - 검증 내용: parent FIFO write, discovered Location 보존, authoritative peer snapshot
    /// - 사전 조건: 같은 pinned A와 Location을 가진 source/peer window, in-flight update gate
    /// - 기대 결과: source는 재생성되지 않고 peer의 pinned record와 runtime anchor가 최신 값으로 갱신됨
    func testPinnedRecordPersistence_anchorUpdateSurvivesSourceWindowCloseAndFansOutToPeer() async {
        let sourceWindowID = UUID(41106)
        let peerWindowID = UUID(41107)
        let tabID = ContentTabID(rawValue: "window-close-anchor-update")
        let oldAnchor = ContentTabPageAnchor.directory(path: "/Users/test/Old")
        let newAnchor = ContentTabPageAnchor.directory(path: "/Users/test/New")
        let record = ContentTabPinnedRecord(
            id: tabID.rawValue,
            page: .directory,
            anchor: oldAnchor,
            title: "Old",
            iconName: "folder",
            pinnedAt: Date(timeIntervalSince1970: 411),
        )
        let location = FileManagerFixedLocationItem(
            id: "fixed-location-projects",
            title: "Projects",
            path: "/Users/test/Projects",
            iconName: "folder",
            accessibilityLabel: "Projects",
        )
        let initialOrder = FileManagerTopNavigationOrder(items: [
            .location(location.id),
            .contentTab(tabID),
        ])
        let gate = PinnedRecordMutationGate()
        let discoveredLocationIDs = LockIsolated<[String]>([])
        let persistedStore = LockIsolated(ContentTabPinnedRecordStore(
            records: [record],
            topNavigationOrder: initialOrder,
        ))
        var sourceWindow = lifecycleWindow(tabID: tabID, record: record, path: "/Users/test/Source")
        sourceWindow.sidebar.setFixedLocationItems([location])
        sourceWindow.lastConfirmedTopNavigationOrder = initialOrder
        sourceWindow.optimisticTopNavigationOrder = initialOrder
        sourceWindow.syncSidebarTopNavigationItems()
        var peerWindow = lifecycleWindow(tabID: tabID, record: record, path: "/Users/test/Peer")
        peerWindow.sidebar.setFixedLocationItems([location])
        peerWindow.lastConfirmedTopNavigationOrder = initialOrder
        peerWindow.optimisticTopNavigationOrder = initialOrder
        peerWindow.syncSidebarTopNavigationItems()
        var initialState = WindowManagerFeature.State()
        initialState.windows = [
            .init(id: sourceWindowID, window: sourceWindow),
            .init(id: peerWindowID, window: peerWindow),
        ]
        let store = Store(initialState: initialState) { WindowManagerFeature() } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 412))
            $0.contentTabPinnedRecordClient.applyPersistenceMutationCommitted = { _, locationIDs, mutation in
                discoveredLocationIDs.setValue(locationIDs)
                await gate.wait()
                let updated = try persistedStore.withValue { store in
                    store = try applying(
                        mutation,
                        to: store,
                        discoveredLocationIDs: locationIDs,
                    )
                    return store
                }
                return .init(store: updated, topNavigation: .init(order: updated.topNavigationOrder, revision: 1))
            }
        }

        let updateTask = store.send(.windows(.element(
            id: sourceWindowID,
            action: .window(.contentTabs(.updateActivePageAnchor(tabID, newAnchor))),
        )))
        await gate.waitUntilWaiting()
        await store.send(.event(.windowClosed(sourceWindowID))).finish()
        await gate.open()
        await updateTask.finish()

        XCTAssertEqual(discoveredLocationIDs.value, [location.id])
        XCTAssertEqual(persistedStore.value.records.first?.anchor, newAnchor)
        XCTAssertEqual(persistedStore.value.topNavigationOrder, initialOrder)
        store.withState { state in
            XCTAssertNil(state.windows[id: sourceWindowID])
            let peer = state.windows[id: peerWindowID]?.window
            XCTAssertEqual(peer?.contentTabs.tabs[id: tabID]?.anchor, newAnchor)
            XCTAssertEqual(peer?.contentTabs.pinnedRecords[tabID]?.anchor, newAnchor)
            XCTAssertEqual(peer?.lastConfirmedTopNavigationOrder, initialOrder)
            XCTAssertTrue(state.topNavigationPersistenceQueue.isEmpty)
            XCTAssertFalse(state.isTopNavigationPersistenceInFlight)
        }
    }

    /// CTM-003-pin_content_tab_s: corrupt/future store는 parent lifecycle mutation에서도 원본 bytes를 보존한다.
    /// - 검증 내용: typed unavailable terminal, write 0회, optimistic pin rollback
    /// - 사전 조건: malformed payload 또는 future schema payload와 unpinned A
    /// - 기대 결과: bytes 불변, A unpinned, 정확한 load-unavailable failure
    func testPinnedRecordPersistence_unavailableStoresRejectLifecycleMutationWithoutWriting() async throws {
        let scenarios: [(Data, FileManagerTopNavigationArrangementLoadFailure)] = [
            (Data("not-json".utf8), .corrupt),
            (Data(#"{"schemaVersion":3,"records":[],"topNavigationOrder":[]}"#.utf8), .unsupportedSchema(3)),
        ]
        let storageKey = "fileManager.pinnedContentTabs.v1"

        for (index, scenario) in scenarios.enumerated() {
            let windowID = UUID(41110 + index)
            let storedData = LockIsolated(scenario.0)
            let writeCount = LockIsolated(0)
            let defaults = UserDefaultsClient(
                bool: { _ in false },
                setBool: { _, _ in },
                string: { _ in nil },
                setString: { _, _ in },
                double: { _ in 0 },
                setDouble: { _, _ in },
                object: { key in key == storageKey ? storedData.value : nil },
                setObject: { value, key in
                    guard key == storageKey, let data = value as? Data else { return }
                    storedData.setValue(data)
                    writeCount.withValue { $0 += 1 }
                },
            )
            var window = FileManagerWindowFeature.State.makeInitial(path: "/Users/test/Unavailable")
            try window.contentTabs.tabs[id: XCTUnwrap(window.contentTabs.activeTabID)]?.isPinned = false
            let activeID = try XCTUnwrap(window.contentTabs.activeTabID)
            var initialState = WindowManagerFeature.State()
            initialState.windows = [.init(id: windowID, window: window)]
            let store = Store(initialState: initialState) { WindowManagerFeature() } withDependencies: {
                $0.contentTabPinnedRecordClient = .liveValue
                $0.userDefaultsClient = defaults
                $0.date = .constant(Date(timeIntervalSince1970: 411))
            }

            let pinTask = store.send(.windows(.element(
                id: windowID,
                action: .window(.contentTabs(.pin(activeID))),
            )))
            await pinTask.finish()

            XCTAssertEqual(storedData.value, scenario.0)
            XCTAssertEqual(writeCount.value, 0)
            store.withState { state in
                let result = state.windows[id: windowID]?.window
                XCTAssertEqual(result?.contentTabs.tabs[id: activeID]?.isPinned, false)
                XCTAssertEqual(result?.topNavigationArrangementAvailability, .unavailable(scenario.1))
                XCTAssertEqual(result?.topNavigationArrangementPresentation, .loadUnavailable)
            }
        }
    }

    /// 늦은 G1 applied success는 parent FIFO에서 G2보다 먼저 terminal 처리되어도 stale fan-out을 만들지 않는다.
    /// - 검증 내용: G1 unpin write 적용 뒤 G2 repin 예약, committed snapshot은 G2만 window별 1회 fan-out
    /// - 사전 조건: 같은 global pinned tab을 source에서 unpin하는 동안 다른 window에서 repin
    /// - 기대 결과: persisted G2와 양 window G2 anchor 수렴, pending intent 정리, selection 보존
    func testPinnedRecordTerminalOrder_staleAppliedSuccessThenWinnerConverges() async {
        await verifyPinnedRecordTerminalOrder(firstTerminal: .applied)
    }

    /// G1이 적용 전에 superseded되면 parent FIFO는 stale terminal 뒤 G2만 authoritative fan-out한다.
    /// - 검증 내용: G1 superseded terminal fan-out 0회, 직렬화된 G2 success fan-out window별 1회
    /// - 사전 조건: 같은 global pinned tab의 G1 unpin 적용 전 다른 window에서 G2 repin 예약
    /// - 기대 결과: persisted G2와 양 window G2 anchor 수렴, pending intent 정리, selection 보존
    func testPinnedRecordTerminalOrder_winnerThenSupersededRollbackConverges() async {
        await verifyPinnedRecordTerminalOrder(firstTerminal: .superseded)
    }

    private func verifyPinnedRecordTerminalOrder(firstTerminal: PinnedRecordFirstMutationTerminal) async {
        let sourceWindowID = UUID()
        let otherWindowID = UUID()
        let sharedTabID = ContentTabID(rawValue: "shared-pinned-tab")
        let oldAnchor: ContentTabPageAnchor = .directory(path: "/Users/test/OldShared")
        let newAnchor: ContentTabPageAnchor = .directory(path: "/Users/test/NewShared")
        let oldRecord = ContentTabPinnedRecord(
            id: sharedTabID.rawValue,
            page: .directory,
            anchor: oldAnchor,
            title: "Old Shared",
            iconName: "folder",
            pinnedAt: Date(timeIntervalSince1970: 452),
        )
        let newRecord = ContentTabPinnedRecord(
            id: sharedTabID.rawValue,
            page: .directory,
            anchor: newAnchor,
            title: "New Shared",
            iconName: "folder",
            pinnedAt: Date(timeIntervalSince1970: 453),
        )

        var sourceWindow = FileManagerWindowFeature.State.makeInitial(path: "/Users/test/Source")
        sourceWindow.contentTabs.tabs.append(ContentTabItem(
            id: sharedTabID,
            page: .directory,
            anchor: oldAnchor,
            isPinned: true,
            title: "Old Shared",
            iconName: "folder",
        ))
        sourceWindow.contentTabs.pinnedRecords[sharedTabID] = oldRecord
        sourceWindow.contentTabs.selectedTabIDs = [sharedTabID]
        sourceWindow.contentTabs.selectionAnchorID = sharedTabID
        let firstIntentID = sourceWindow.contentTabs.markLatestPinnedRecordPersistenceIntent(for: sharedTabID)
        _ = sourceWindow.contentTabs.markLatestPinnedRecordPersistenceIntent(for: sharedTabID)

        var otherWindow = FileManagerWindowFeature.State.makeInitial(path: "/Users/test/Other")
        otherWindow.contentTabs.tabs.append(ContentTabItem(
            id: sharedTabID,
            page: .directory,
            anchor: newAnchor,
            isPinned: false,
            title: "New Shared",
            iconName: "folder",
        ))
        otherWindow.contentTabs.selectedTabIDs = [sharedTabID]
        otherWindow.contentTabs.selectionAnchorID = sharedTabID
        let winnerIntentID = otherWindow.contentTabs.markLatestPinnedRecordPersistenceIntent(for: sharedTabID)

        let firstRequest = WindowManagerTopNavigationPersistenceRequest(
            sourceWindowID: sourceWindowID,
            token: .init(value: UUID()),
            operation: .pinnedRecord(
                source: .contentTab,
                request: .init(
                    tabID: sharedTabID,
                    context: .init(
                        intentID: firstIntentID,
                        generation: .init(tabID: sharedTabID),
                    ),
                    rollback: .init(
                        previousIsPinned: true,
                        previousPinnedRecord: oldRecord,
                        previousTabIndex: nil,
                    ),
                    mutation: .remove(recordID: sharedTabID.rawValue),
                    persistenceScopeID: UUID(),
                ),
                discoveredLocationIDs: [],
            ),
        )
        let winnerRequest = WindowManagerTopNavigationPersistenceRequest(
            sourceWindowID: otherWindowID,
            token: .init(value: UUID()),
            operation: .pinnedRecord(
                source: .contentTab,
                request: .init(
                    tabID: sharedTabID,
                    context: .init(
                        intentID: winnerIntentID,
                        generation: .init(tabID: sharedTabID),
                    ),
                    rollback: .init(
                        previousIsPinned: false,
                        previousPinnedRecord: nil,
                        previousTabIndex: nil,
                    ),
                    mutation: .upsert(record: newRecord, dormantSlot: nil),
                    persistenceScopeID: UUID(),
                ),
                discoveredLocationIDs: [],
            ),
        )

        var initialState = WindowManagerFeature.State()
        initialState.windows = [
            WindowSessionState(id: sourceWindowID, window: sourceWindow),
            WindowSessionState(id: otherWindowID, window: otherWindow),
        ]
        initialState.topNavigationPersistenceQueue = [firstRequest]
        initialState.isTopNavigationPersistenceInFlight = true
        let firstPersistedStore = switch firstTerminal {
        case .applied:
            ContentTabPinnedRecordStore()
        case .superseded:
            ContentTabPinnedRecordStore(records: [oldRecord])
        }
        let persistedStore = LockIsolated(firstPersistedStore)
        let mutationCount = LockIsolated(0)
        let committedSnapshotCounts = LockIsolated<[UUID: Int]>([:])
        let store = Store(initialState: initialState) {
            CombineReducers {
                WindowManagerFeature()
                Reduce { _, action in
                    if case let .windows(.element(
                        id: windowID,
                        action: .window(.applyCommittedTopNavigationSnapshot),
                    )) = action {
                        committedSnapshotCounts.withValue { $0[windowID, default: 0] += 1 }
                    }
                    return .none
                }
            }
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 453))
            $0.contentTabPinnedRecordClient.applyPersistenceMutationCommitted = { _, discoveredLocationIDs, mutation in
                let revision = mutationCount.withValue { value in
                    value += 1
                    return UInt64(value + 1)
                }
                let updated = try persistedStore.withValue { currentStore in
                    currentStore = try applying(
                        mutation,
                        to: currentStore,
                        discoveredLocationIDs: discoveredLocationIDs,
                    )
                    return currentStore
                }
                return .init(
                    store: updated,
                    topNavigation: .init(order: updated.topNavigationOrder, revision: revision),
                )
            }
        }

        let firstResult: WindowManagerTopNavigationPersistenceResult = switch firstTerminal {
        case .applied:
            .init(
                request: firstRequest,
                terminal: .committed(.init(order: firstPersistedStore.topNavigationOrder, revision: 1)),
                authoritativePinnedContentTabs: ContentTabState.restoringPinnedRecords(from: firstPersistedStore).state,
            )
        case .superseded:
            .init(
                request: firstRequest,
                terminal: .failed(.superseded),
                authoritativePinnedContentTabs: nil,
            )
        }
        await store.send(.topNavigationPersistenceCompleted(firstResult)).finish()
        XCTAssertEqual(committedSnapshotCounts.value[sourceWindowID, default: 0], 0)
        XCTAssertEqual(committedSnapshotCounts.value[otherWindowID, default: 0], 0)

        await store.send(.topNavigationPersistenceRequested(winnerRequest)).finish()

        XCTAssertEqual(persistedStore.value, ContentTabPinnedRecordStore(
            records: [newRecord],
            topNavigationOrder: .init(items: [.contentTab(sharedTabID)]),
        ))
        XCTAssertEqual(mutationCount.value, 1)
        XCTAssertEqual(committedSnapshotCounts.value[sourceWindowID, default: 0], 1)
        XCTAssertEqual(committedSnapshotCounts.value[otherWindowID, default: 0], 1)
        store.withState { state in
            let source = state.windows[id: sourceWindowID]?.window
            let other = state.windows[id: otherWindowID]?.window
            XCTAssertEqual(source?.contentTabs.pendingPinnedRecordIDs.isEmpty, true)
            XCTAssertEqual(other?.contentTabs.pendingPinnedRecordIDs.isEmpty, true)
            XCTAssertEqual(source?.contentTabs.tabs[id: sharedTabID]?.isPinned, true)
            XCTAssertEqual(source?.contentTabs.tabs[id: sharedTabID]?.anchor, newAnchor)
            XCTAssertEqual(other?.contentTabs.tabs[id: sharedTabID]?.isPinned, true)
            XCTAssertEqual(other?.contentTabs.tabs[id: sharedTabID]?.anchor, newAnchor)
            XCTAssertEqual(source?.contentTabs.selectedTabIDs, [sharedTabID])
            XCTAssertEqual(source?.contentTabs.selectionAnchorID, sharedTabID)
            XCTAssertEqual(other?.contentTabs.selectedTabIDs, [sharedTabID])
            XCTAssertEqual(other?.contentTabs.selectionAnchorID, sharedTabID)
        }
    }

    private struct WindowManagerPinnedCommitFanOutCounts: Equatable {
        var storeChanged = 0
        var committedSnapshotByWindow: [UUID: Int] = [:]
        var authoritativeSyncByWindow: [UUID: Int] = [:]

        mutating func record(_ action: WindowManagerFeature.Action) {
            if case .pinnedContentTabsStoreChanged = action {
                storeChanged += 1
            }
            if case let .windows(.element(
                id: windowID,
                action: .window(.applyCommittedTopNavigationSnapshot),
            )) = action {
                committedSnapshotByWindow[windowID, default: 0] += 1
            }
            if case let .windows(.element(
                id: windowID,
                action: .window(.applyAuthoritativePinnedContentTabs),
            )) = action {
                authoritativeSyncByWindow[windowID, default: 0] += 1
            }
        }
    }

    /// parent pinned commit은 bootstrap cleanup과 달리 파일 존재 검증으로 열린 pinned tab을 갑자기 제거하지 않는다.
    /// - 검증 내용: deleted directory record가 committed snapshot에 있어도 fan-out state에는 유지되고 saveStore compaction이 호출되지 않음
    /// - 사전 조건: 열린 window 1개, global pinned store에 현재 존재하지 않는 directory record 1개
    /// - 기대 결과: parent commit fan-out이 deleted-pin을 포함하고 saveStore를 호출하지 않음
    func testParentPinnedCommitSyncPreservesDeletedDirectoryRecord() async throws {
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
        let deletedPinID = ContentTabID(rawValue: "deleted-pin")
        let persistenceIntentID = try XCTUnwrap(initialState.windows[id: windowID]?.window.contentTabs
            .markLatestPinnedRecordPersistenceIntent(for: deletedPinID))
        let context = ContentTabPinnedRecordTerminalContext(
            intentID: persistenceIntentID,
            generation: ContentTabPinnedRecordMutationGeneration(tabID: deletedPinID),
        )
        let request = WindowManagerTopNavigationPersistenceRequest(
            sourceWindowID: windowID,
            token: .init(value: UUID()),
            operation: .pinnedRecord(
                source: .contentTab,
                request: .init(
                    tabID: deletedPinID,
                    context: context,
                    rollback: .init(
                        previousIsPinned: false,
                        previousPinnedRecord: nil,
                        previousTabIndex: nil,
                    ),
                    mutation: .upsert(
                        record: pinnedStore.records[0],
                        dormantSlot: nil,
                    ),
                    persistenceScopeID: UUID(),
                ),
                discoveredLocationIDs: [],
            ),
        )
        initialState.topNavigationPersistenceQueue = [request]
        initialState.isTopNavigationPersistenceInFlight = true

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
        // parent commit fan-out은 window-local handoff child action을 동반하므로,
        // 이 테스트는 broken record 보존 payload와 saveStore 미호출만 검증한다.
        store.exhaustivity = .off

        await store.send(.topNavigationPersistenceCompleted(.init(
            request: request,
            terminal: .committed(.init(order: pinnedStore.topNavigationOrder, revision: 1)),
            authoritativePinnedContentTabs: ContentTabState.restoringPinnedRecords(from: pinnedStore).state,
        )))
        await store.receive { action in
            guard case let .windows(.element(
                id: id,
                action: .window(.applyCommittedTopNavigationSnapshot(
                    order: order,
                    revision: revision,
                    authoritativePinnedContentTabs: contentTabs,
                )),
            )) = action
            else {
                return false
            }
            return id == windowID
                && order == pinnedStore.topNavigationOrder
                && revision == 1
                && contentTabs?.tabs.filter(\.isPinned).map(\.id.rawValue) == ["deleted-pin"]
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
        let openedIDs = LockIsolated<[UUID]>([])

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
            $0.fileManagerWindowClient.registeredWindowIDs = { [newID] }
            $0.fileManagerWindowClient.open = { id in openedIDs.withValue { $0.append(id) } }
        }
        // 명시적 path window의 부수 window/open action은 완전히 검증하지 않으므로
        // path bypass 조건만 검증한다.
        store.exhaustivity = .off

        let testPath = "/Users/test/Documents"
        await store.send(.file(.newWindow(path: testPath)))
        await store.receive(\.windowOpenCompleted)
        await store.finish()

        XCTAssertFalse(storeLoadCalled.value, "명시적 path window에서는 loadStore가 호출되지 않아야 함")
        XCTAssertEqual(openedIDs.value, [newID])
        XCTAssertTrue(store.state.pendingWindowOpenIDs.isEmpty)
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
        initialState.pendingWindowOpenIDs = [defaultWindowID]

        let store = TestStore(initialState: initialState) {
            WindowManagerFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
            $0.fileManagerWindowClient.registeredWindowIDs = { [defaultWindowID] }
            $0.fileManagerWindowClient.open = { _ in }
        }
        // store.exhaustivity = .off: bootstrap 대상과 explicit-path 제외 경계만 검증한다.
        store.exhaustivity = .off

        await store.send(.defaultWindowBootstrapCompleted(
            requestID: requestID,
            result: .init(
                contentTabs: restoredState,
                fixedLocationItems: [],
                topNavigationOrder: .init(),
                arrangementAvailability: .available,
            ),
        ))
        await store.receive { action in
            guard case let .windows(.element(
                id: id,
                action: .window(.applyBootstrap(bootstrap)),
            )) = action
            else {
                return false
            }
            return id == defaultWindowID
                && bootstrap.authoritativePinnedContentTabs.tabs.filter(\.isPinned).map(\.id.rawValue) == ["global-pin"]
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
        let freshRequestID = UUID()
        let gate = WindowBootstrapSuspensionGate()
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
            $0.uuid = .constant(freshRequestID)
            $0.contentTabPinnedRecordClient.loadStore = { _ in latestStore }
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
            $0.continuousClock = ImmediateClock()
            $0.fileManagerBuiltInCollectionClient.ensureAll = {
                await gate.wait()
                return .init(recents: .failed, allTags: .failed)
            }
            $0.fileManagerClient.fileExistsWithIsDirectory = { path, isDirectory in
                guard path == "/Users/test/Latest" else { return false }
                isDirectory?.pointee = ObjCBool(true)
                return true
            }
            $0.userDefaultsClient.bool = { _ in true }
        }
        // store.exhaustivity = .off: fresh bootstrap 내부 action보다 stale request 무효화와 최신 store 보존을 검증한다.
        store.exhaustivity = .off

        await store.send(.pinnedContentTabsStoreChanged) {
            $0.defaultWindowBootstrapRequestID = freshRequestID
        }
        await gate.waitUntilWaiting()
        await store.receive { action in
            guard case let .windows(.element(
                id: id,
                action: .window(.applyAuthoritativePinnedContentTabs(contentTabs)),
            )) = action
            else { return false }
            return id == windowID
                && contentTabs.tabs.filter(\.isPinned).map(\.id.rawValue) == ["latest-pin"]
        }
        await store.send(.defaultWindowBootstrapCompleted(
            requestID: requestID,
            result: .init(
                contentTabs: staleState,
                fixedLocationItems: [],
                topNavigationOrder: .init(),
                arrangementAvailability: .available,
            ),
        ))
        await gate.open()
        await store.skipReceivedActions()
        await store.finish()

        XCTAssertEqual(
            store.state.windows[id: windowID]?.window.contentTabs.tabs.filter(\.isPinned).map(\.id.rawValue),
            ["latest-pin"],
        )
    }

    /// VOY-470: bootstrap 대기 중 pinned store가 바뀌면 pending window는 최신 bootstrap까지 열리지 않는다.
    /// - 검증 내용: stale request 교체, fresh bootstrap 대기 중 native open 0회, 최신 snapshot 적용 후 open
    /// - 사전 조건: pending default window와 in-flight request, 최신 pinned record 1개
    /// - 기대 결과: fresh request 완료 전 숨김 유지, 완료 후 최신 pinned state로 native open 1회
    func testPinnedStoreChangeRestartsPendingBootstrapBeforeNativeOpen() async {
        let windowID = UUID(47082)
        let staleRequestID = UUID(47083)
        let freshRequestID = UUID(47084)
        let gate = WindowBootstrapSuspensionGate()
        let pinnedTabID = ContentTabID(rawValue: "fresh-preopen-pin")
        let latestStore = ContentTabPinnedRecordStore(records: [
            ContentTabPinnedRecord(
                id: pinnedTabID.rawValue,
                page: .directory,
                anchor: .directory(path: "/Users/test/Fresh"),
                title: "Fresh",
                iconName: "folder",
                pinnedAt: Date(timeIntervalSince1970: 445),
            ),
        ])
        let openedIDs = LockIsolated<[UUID]>([])
        var initialState = WindowManagerFeature.State()
        initialState.windows = [WindowSessionState(id: windowID, window: .makeInitial(path: nil))]
        initialState.pendingWindowOpenIDs = [windowID]
        initialState.defaultWindowBootstrapRequestID = staleRequestID
        initialState.defaultWindowBootstrapWindowIDs = [windowID]

        let store = TestStore(initialState: initialState) {
            WindowManagerFeature()
        } withDependencies: {
            $0.uuid = .constant(freshRequestID)
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
            $0.contentTabPinnedRecordClient.loadStore = { _ in latestStore }
            $0.contentTabPinnedRecordClient.saveStore = { _, _ in }
            $0.fileManagerClient.fileExistsWithIsDirectory = { path, isDirectory in
                guard path == "/Users/test/Fresh" else { return false }
                isDirectory?.pointee = ObjCBool(true)
                return true
            }
            $0.fileManagerBuiltInCollectionClient.ensureAll = {
                await gate.wait()
                return .init(recents: .failed, allTags: .failed)
            }
            $0.userDefaultsClient.bool = { _ in true }
            $0.fileManagerWindowClient.registeredWindowIDs = { [windowID] }
            $0.fileManagerWindowClient.open = { id in openedIDs.withValue { $0.append(id) } }
        }
        // store.exhaustivity = .off: fresh bootstrap 내부 action보다 pre-open 가시성 경계를 검증한다.
        store.exhaustivity = .off

        await store.send(.pinnedContentTabsStoreChanged) {
            $0.defaultWindowBootstrapRequestID = freshRequestID
        }
        await gate.waitUntilWaiting()
        XCTAssertTrue(openedIDs.value.isEmpty)

        await gate.open()
        await store.skipReceivedActions()
        await store.finish()

        XCTAssertEqual(openedIDs.value, [windowID])
        XCTAssertTrue(store.state.pendingWindowOpenIDs.isEmpty)
        XCTAssertEqual(
            store.state.windows[id: windowID]?.window.contentTabs.tabs.filter(\.isPinned).map(\.id),
            [pinnedTabID],
        )
    }

    /// VOY-470: parent-owned pinned commit은 stale bootstrap을 폐기하고 pending window를 최신 store로 다시 hydrate한다.
    /// - 검증 내용: old request ID 무효화, aggregate fan-out 1회, fresh bootstrap 완료 전 native open 차단
    /// - 사전 조건: pending default window, in-flight old bootstrap, committed pinned persistence result
    /// - 기대 결과: old completion은 무시되고 fresh snapshot으로 native open 1회
    func testCommittedPinnedPersistenceRestartsPendingBootstrapBeforeNativeOpen() async {
        let pendingWindowID = UUID(47085)
        let closedSourceWindowID = UUID(47086)
        let staleRequestID = UUID(47087)
        let freshRequestID = UUID(47088)
        let tabID = ContentTabID(rawValue: "fresh-parent-pin")
        let record = ContentTabPinnedRecord(
            id: tabID.rawValue,
            page: .directory,
            anchor: .directory(path: "/Users/test/FreshParentPin"),
            title: "Fresh Parent Pin",
            iconName: "folder",
            pinnedAt: Date(timeIntervalSince1970: 470),
        )
        let latestStore = ContentTabPinnedRecordStore(
            records: [record],
            topNavigationOrder: .init(items: [.contentTab(tabID)]),
        )
        let mutationRequest = ContentTabPinnedRecordPersistenceRequest(
            tabID: tabID,
            context: .init(
                intentID: UUID(47089),
                generation: ContentTabPinnedRecordMutationGeneration(tabID: tabID),
            ),
            rollback: .init(
                previousIsPinned: false,
                previousPinnedRecord: nil,
                previousTabIndex: nil,
            ),
            mutation: .upsert(record: record, dormantSlot: nil),
            persistenceScopeID: UUID(47091),
        )
        let persistenceRequest = WindowManagerTopNavigationPersistenceRequest(
            sourceWindowID: closedSourceWindowID,
            token: .init(value: UUID(47090)),
            operation: .pinnedRecord(
                source: .contentTab,
                request: mutationRequest,
                discoveredLocationIDs: [],
            ),
        )
        let commit = FileManagerTopNavigationCommit(order: latestStore.topNavigationOrder, revision: 2)
        let gate = WindowBootstrapSuspensionGate()
        let openedIDs = LockIsolated<[UUID]>([])
        let bootstrapCallCount = LockIsolated(0)
        var initialState = WindowManagerFeature.State()
        initialState.windows = [.init(id: pendingWindowID, window: .makeInitial(path: nil))]
        initialState.pendingWindowOpenIDs = [pendingWindowID]
        initialState.defaultWindowBootstrapRequestID = staleRequestID
        initialState.defaultWindowBootstrapWindowIDs = [pendingWindowID]
        initialState.topNavigationPersistenceQueue = [persistenceRequest]
        initialState.isTopNavigationPersistenceInFlight = true

        let store = Store(initialState: initialState) { WindowManagerFeature() } withDependencies: {
            $0.uuid = .constant(freshRequestID)
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
            $0.contentTabPinnedRecordClient.loadStore = { _ in latestStore }
            $0.fileManagerClient.fileExistsWithIsDirectory = { path, isDirectory in
                guard path == "/Users/test/FreshParentPin" else { return false }
                isDirectory?.pointee = ObjCBool(true)
                return true
            }
            $0.fileManagerBuiltInCollectionClient.ensureAll = {
                bootstrapCallCount.withValue { $0 += 1 }
                await gate.wait()
                return .init(recents: .failed, allTags: .failed)
            }
            $0.userDefaultsClient.bool = { _ in true }
            $0.fileManagerWindowClient.registeredWindowIDs = { [pendingWindowID] }
            $0.fileManagerWindowClient.open = { id in openedIDs.withValue { $0.append(id) } }
        }

        let completionTask = store.send(.topNavigationPersistenceCompleted(.init(
            request: persistenceRequest,
            terminal: .committed(commit),
            authoritativePinnedContentTabs: ContentTabState.restoringPinnedRecords(from: latestStore).state,
        )))
        await gate.waitUntilWaiting()

        store.withState { state in
            XCTAssertEqual(state.defaultWindowBootstrapRequestID, freshRequestID)
            XCTAssertEqual(state.defaultWindowBootstrapWindowIDs, [pendingWindowID])
            XCTAssertEqual(
                state.windows[id: pendingWindowID]?.window.contentTabs.tabs.filter(\.isPinned).map(\.id),
                [tabID],
            )
        }
        XCTAssertEqual(bootstrapCallCount.value, 1)
        XCTAssertTrue(openedIDs.value.isEmpty)

        await store
            .send(.defaultWindowBootstrapCompleted(
                requestID: staleRequestID,
                result: .init(
                    contentTabs: .withHomeTab(),
                    fixedLocationItems: [],
                    topNavigationOrder: .init(),
                    arrangementAvailability: .available,
                ),
            ))
            .finish()
        XCTAssertTrue(openedIDs.value.isEmpty)

        await gate.open()
        await completionTask.finish()

        XCTAssertEqual(openedIDs.value, [pendingWindowID])
        store.withState { state in
            XCTAssertNil(state.defaultWindowBootstrapRequestID)
            XCTAssertTrue(state.defaultWindowBootstrapWindowIDs.isEmpty)
            XCTAssertTrue(state.pendingWindowOpenIDs.isEmpty)
            XCTAssertEqual(
                state.windows[id: pendingWindowID]?.window.contentTabs.tabs.filter(\.isPinned).map(\.id),
                [tabID],
            )
        }
    }

    /// VOY-470: parent-owned move commit은 stale bootstrap을 폐기하고 pending window를 최신 순서로 다시 hydrate한다.
    /// - 검증 내용: move commit 이후 old request 무효화, fresh bootstrap 완료 전 native open 차단
    /// - 사전 조건: pending default window, in-flight old bootstrap, committed move persistence result
    /// - 기대 결과: old completion은 무시되고 latest moved order로 native open 1회
    func testCommittedMovePersistenceRestartsPendingBootstrapBeforeNativeOpen() async {
        let pendingWindowID = UUID(47091)
        let closedSourceWindowID = UUID(47092)
        let staleRequestID = UUID(47093)
        let freshRequestID = UUID(47094)
        let firstTabID = ContentTabID(rawValue: "move-bootstrap-first")
        let secondTabID = ContentTabID(rawValue: "move-bootstrap-second")
        let firstRecord = ContentTabPinnedRecord(
            id: firstTabID.rawValue,
            page: .directory,
            anchor: .directory(path: "/Users/test/MoveBootstrapFirst"),
            title: "Move Bootstrap First",
            iconName: "folder",
            pinnedAt: Date(timeIntervalSince1970: 471),
        )
        let secondRecord = ContentTabPinnedRecord(
            id: secondTabID.rawValue,
            page: .directory,
            anchor: .directory(path: "/Users/test/MoveBootstrapSecond"),
            title: "Move Bootstrap Second",
            iconName: "folder",
            pinnedAt: Date(timeIntervalSince1970: 472),
        )
        let movedOrder = FileManagerTopNavigationOrder(items: [
            .contentTab(secondTabID),
            .contentTab(firstTabID),
        ])
        let latestStore = ContentTabPinnedRecordStore(
            records: [firstRecord, secondRecord],
            topNavigationOrder: movedOrder,
        )
        let persistenceRequest = WindowManagerTopNavigationPersistenceRequest(
            sourceWindowID: closedSourceWindowID,
            token: .init(value: UUID(47095)),
            operation: .move(
                source: .contentTab(firstTabID),
                destination: .after(.contentTab(secondTabID)),
                discoveredLocationIDs: [],
            ),
        )
        let commit = FileManagerTopNavigationCommit(order: movedOrder, revision: 3)
        let gate = WindowBootstrapSuspensionGate()
        let openedIDs = LockIsolated<[UUID]>([])
        let bootstrapCallCount = LockIsolated(0)
        var initialState = WindowManagerFeature.State()
        initialState.windows = [.init(id: pendingWindowID, window: .makeInitial(path: nil))]
        initialState.pendingWindowOpenIDs = [pendingWindowID]
        initialState.defaultWindowBootstrapRequestID = staleRequestID
        initialState.defaultWindowBootstrapWindowIDs = [pendingWindowID]
        initialState.topNavigationPersistenceQueue = [persistenceRequest]
        initialState.isTopNavigationPersistenceInFlight = true

        let store = Store(initialState: initialState) { WindowManagerFeature() } withDependencies: {
            $0.uuid = .constant(freshRequestID)
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
            $0.contentTabPinnedRecordClient.loadStore = { _ in latestStore }
            $0.fileManagerClient.fileExistsWithIsDirectory = { path, isDirectory in
                guard path == "/Users/test/MoveBootstrapFirst"
                    || path == "/Users/test/MoveBootstrapSecond"
                else { return false }
                isDirectory?.pointee = ObjCBool(true)
                return true
            }
            $0.fileManagerBuiltInCollectionClient.ensureAll = {
                bootstrapCallCount.withValue { $0 += 1 }
                await gate.wait()
                return .init(recents: .failed, allTags: .failed)
            }
            $0.userDefaultsClient.bool = { _ in true }
            $0.fileManagerWindowClient.registeredWindowIDs = { [pendingWindowID] }
            $0.fileManagerWindowClient.open = { id in openedIDs.withValue { $0.append(id) } }
        }

        let completionTask = store.send(.topNavigationPersistenceCompleted(.init(
            request: persistenceRequest,
            terminal: .committed(commit),
            authoritativePinnedContentTabs: nil,
        )))
        await gate.waitUntilWaiting()

        store.withState { state in
            XCTAssertEqual(state.defaultWindowBootstrapRequestID, freshRequestID)
            XCTAssertEqual(state.defaultWindowBootstrapWindowIDs, [pendingWindowID])
            XCTAssertEqual(
                state.windows[id: pendingWindowID]?.window.lastConfirmedTopNavigationOrder,
                movedOrder,
            )
            XCTAssertEqual(
                state.windows[id: pendingWindowID]?.window.lastConfirmedTopNavigationCommitRevision,
                3,
            )
        }
        XCTAssertEqual(bootstrapCallCount.value, 1)
        XCTAssertTrue(openedIDs.value.isEmpty)

        await store
            .send(.defaultWindowBootstrapCompleted(
                requestID: staleRequestID,
                result: .init(
                    contentTabs: .withHomeTab(),
                    fixedLocationItems: [],
                    topNavigationOrder: .init(),
                    arrangementAvailability: .available,
                ),
            ))
            .finish()
        XCTAssertTrue(openedIDs.value.isEmpty)

        await gate.open()
        await completionTask.finish()

        XCTAssertEqual(openedIDs.value, [pendingWindowID])
        store.withState { state in
            XCTAssertNil(state.defaultWindowBootstrapRequestID)
            XCTAssertTrue(state.defaultWindowBootstrapWindowIDs.isEmpty)
            XCTAssertTrue(state.pendingWindowOpenIDs.isEmpty)
            XCTAssertEqual(
                state.windows[id: pendingWindowID]?.window.lastConfirmedTopNavigationOrder,
                movedOrder,
            )
        }
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
        let ensureCallCount = LockIsolated(0)
        let flags = LockIsolated([
            "fileManager.defaultPinnedTabsSeedCompleted": true,
            "fileManager.finderFavoritesPinnedSeedCompleted": true,
        ])

        let store = TestStore(initialState: WindowManagerFeature.State()) {
            WindowManagerFeature()
        } withDependencies: {
            $0.uuid = .constant(windowID)
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
            $0.continuousClock = ImmediateClock()
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
                let callCount = ensureCallCount.withValue {
                    $0 += 1
                    return $0
                }
                guard callCount == 1 else {
                    return .init(recents: .failed, allTags: .failed)
                }
                await gate.wait()
                return .init(
                    recents: .ready(.init(identity: .recents, packageURL: recentsURL)),
                    allTags: .ready(.init(identity: .allTags, packageURL: allTagsURL)),
                )
            }
            $0.userDefaultsClient.bool = { flags.value[$0] ?? false }
            $0.userDefaultsClient.setBool = { value, key in flags.withValue { $0[key] = value } }
            $0.onboardingWindowClient.showIfNeeded = { false }
            $0.fileManagerWindowClient.open = { _ in }
            $0.fileManagerWindowClient.registeredWindowIDs = { [windowID] }
        }
        store.exhaustivity = .off

        await store.send(.file(.newWindow(path: nil)))
        await gate.waitUntilWaiting()
        await store.send(.pinnedContentTabsStoreChanged)
        await gate.open()
        await store.finish()

        XCTAssertEqual(ensureCallCount.value, 2)
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
            $0.fileManagerWindowClient.registeredWindowIDs = { [newID] }
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
            guard case let .windows(.element(id: id, action: .window(.applyBootstrap))) = action
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
            $0.fileManagerWindowClient.registeredWindowIDs = { [newID] }
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
            guard case let .windows(.element(id: id, action: .window(.applyBootstrap))) = action
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
            $0.fileManagerWindowClient.registeredWindowIDs = { [newID] }
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
            guard case let .windows(.element(id: id, action: .window(.applyBootstrap))) = action
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
            $0.fileManagerWindowClient.registeredWindowIDs = { [newID] }
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
            guard case let .windows(.element(id: id, action: .window(.applyBootstrap))) = action
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
            $0.fileManagerWindowClient.registeredWindowIDs = { [newID] }
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
            guard case let .windows(.element(id: id, action: .window(.applyBootstrap))) = action
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
    /// - 기대 결과: Recents → Finder → All Tags canonical 순서로 저장·복원되고 세 완료 플래그가 true
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
            $0.fileManagerWindowClient.registeredWindowIDs = { [windowID] }
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
    /// - 검증 내용: 첫 Finder transaction 실패, built-in 성공, 두 번째 Finder retry와 canonical ordering
    /// - 사전 조건: 첫 update만 throw, 두 번째 실행은 All Tags → Recents residue, duplicate Finder favorite 입력
    /// - 기대 결과: 두 번째 실행은 Recents → Finder → All Tags canonical 순서로 정규화
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
            $0.fileManagerWindowClient.registeredWindowIDs = { [windowID] }
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
            $0["fileManager.builtInCollection.recentsPinnedSeed.v1"] = true
            $0["fileManager.builtInCollection.allTagsPinnedSeed.v1"] = true
        }
        persistedStore.withValue { store in
            store = ContentTabPinnedRecordStore(records: Array(store.records.reversed()))
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
            $0.fileManagerWindowClient.registeredWindowIDs = { [windowID] }
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
            $0.fileManagerWindowClient.registeredWindowIDs = { [windowID] }
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
            $0.fileManagerWindowClient.registeredWindowIDs = { [windowID] }
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
            $0.fileManagerWindowClient.registeredWindowIDs = { [windowID] }
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
            $0.fileManagerWindowClient.registeredWindowIDs = { [windowID] }
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

    /// load·Finder update·built-in ensure·reload이 모두 실패해도 default window는 Home으로 열린다.
    /// - 검증 내용: native registration 뒤 typed bootstrap failure와 Home fallback 적용
    /// - 사전 조건: load/update throw, ensure failed
    /// - 기대 결과: native registration 뒤 failed terminal이 기본 Home state를 유지
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
            $0.fileManagerWindowClient.registeredWindowIDs = { [windowID] }
            $0.fileManagerWindowClient.open = { _ in }
        }
        // store.exhaustivity = .off: 모든 dependency 실패 뒤 completion downstream state만 검증한다.
        store.exhaustivity = .off

        await store.send(.file(.newWindow(path: nil)))
        await store.receive(\.windowOpenCompleted)
        await store.receive(\.defaultWindowBootstrapFailed)
        await store.receive(\.windowReadyToOpen)
        await store.finish()

        let tabs = store.state.windows.first?.window.contentTabs.tabs
        XCTAssertEqual(tabs?.count, 1)
        XCTAssertEqual(tabs?.first?.page, .home)
        XCTAssertFalse(tabs?.contains(where: \.isPinned) ?? true)
    }

    // MARK: - CTM-001-move_content_tab_to_another_window

    /// CTM-001-move_content_tab_to_another_window: frozen ordered batch를 한 transaction으로 이동한다.
    /// 선택된 두 tab이 app owner에서 하나의 Undo batch와 두 registry child commit으로 처리되는지 검증한다.
    /// - 검증 내용: ordered source removal, target insertion, atomic `moveScopes`, package terminal cleanup
    /// - 사전 조건: source에 moved A/B와 remainder가 있고 exact in-flight batch request가 존재한다.
    /// - 기대 결과: A/B가 frozen order로 target에 이동하고 Undo batch와 activation은 각각 한 번 실행된다.
    func testContentTabBatchMoveCommitsFrozenOrderWithOneUndoBatch() async throws {
        let sourceID = UUID(45801)
        let targetID = UUID(45802)
        let operationID = UUID(45803)
        let requestID = UUID(45804)
        let firstID = ContentTabID(rawValue: "batch-first")
        let primaryID = ContentTabID(rawValue: "batch-primary")
        let remainderID = ContentTabID(rawValue: "batch-remainder")
        let targetExistingID = ContentTabID(rawValue: "batch-target-existing")
        let request = ContentTabMoveRequest(
            operationID: operationID,
            requestID: requestID,
            sourceWindowID: sourceID,
            initiatingTabID: primaryID,
            orderedTabIDs: [firstID, primaryID],
            targetWindowID: targetID,
        )
        var source = try Self.makeContentTabMoveWindow(
            id: sourceID,
            tabs: [
                (firstID, "/batch/first"),
                (primaryID, "/batch/primary"),
                (remainderID, "/batch/remainder"),
            ],
        )
        Self.prepareContentTabMoveRequest(request, in: &source)
        let target = try Self.makeContentTabMoveWindow(
            id: targetID,
            tabs: [(targetExistingID, "/batch/target")],
        )
        var initialState = WindowManagerFeature.State()
        initialState.windows = [source, target]
        let undoBatches = LockIsolated<[[FileOperationUndoScopeMoveDescriptor]]>([])
        let legacyUndoCalls = LockIsolated(0)
        let activatedIDs = LockIsolated<[UUID]>([])
        let store = TestStore(initialState: initialState) { WindowManagerFeature() } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 458))
            $0.fileOperationUndoManagerClient.moveScope = { _, _, _ in
                legacyUndoCalls.withValue { $0 += 1 }
                return .moved
            }
            $0.fileOperationUndoManagerClient.moveScopes = { descriptors in
                undoBatches.withValue { $0.append(descriptors) }
                return .moved
            }
            $0.fileManagerWindowClient.activate = { id in
                activatedIDs.withValue { $0.append(id) }
                return .discarded
            }
            $0.notificationCenterClient.notifications = { _, _ in AsyncStream { $0.finish() } }
        }
        // store.exhaustivity = .off: post-commit child lifecycle보다 app transaction의 batch 결과와 호출 횟수를 검증한다.
        store.exhaustivity = .off

        await store.send(.contentTabMoveRequest(request))
        await store.skipReceivedActions()
        await store.finish()

        XCTAssertNil(store.state.windows[id: sourceID]?.window.contentTabs.tabs[id: firstID])
        XCTAssertNil(store.state.windows[id: sourceID]?.window.contentTabs.tabs[id: primaryID])
        XCTAssertNotNil(store.state.windows[id: sourceID]?.window.contentTabs.tabs[id: remainderID])
        XCTAssertEqual(
            store.state.windows[id: targetID]?.window.contentTabs.tabs.map(\.id) ?? [],
            [targetExistingID, firstID, primaryID],
        )
        XCTAssertEqual(undoBatches.value.count, 1)
        XCTAssertEqual(undoBatches.value[0].map(\.source.contentTabID), [firstID.rawValue, primaryID.rawValue])
        XCTAssertEqual(undoBatches.value[0].map(\.target.contentTabID), [firstID.rawValue, primaryID.rawValue])
        XCTAssertEqual(legacyUndoCalls.value, 0)
        XCTAssertEqual(activatedIDs.value, [targetID])
        XCTAssertNil(store.state.windows[id: sourceID]?.window.pendingContentTabMove)
        XCTAssertNil(store.state.windows[id: sourceID]?.window.sidebar.pendingContentTabMoveRequest)
        let terminal = try XCTUnwrap(store.state.contentTabMoveTerminalRecords[requestID])
        XCTAssertEqual(terminal.operationID, operationID)
        XCTAssertEqual(terminal.requestID, requestID)
        XCTAssertEqual(terminal.sourceWindowID, sourceID)
        XCTAssertEqual(terminal.initiatingTabID, primaryID)
        XCTAssertEqual(terminal.orderedTabIDs, [firstID, primaryID])
        XCTAssertEqual(terminal.targetWindowID, targetID)
        XCTAssertEqual(terminal.outcome, .succeeded)
    }

    /// CTM-001-move_content_tab_to_another_window: mixed 표시 순서의 menu batch가 app atomic pipeline까지 연결된다.
    /// 실제 Sidebar sync와 semantic menu action을 거쳐 app owner가 동일 순서의 한 transaction을 commit하는지 검증한다.
    /// - 검증 내용: mixed pinned/unpinned sync, menu ordered IDs, `moveScopes` 순서, source/target commit, success terminal
    /// cleanup
    /// - 사전 조건: source raw tabs U/P1/P2, optimistic pinned order P2/P1, selection P2/U와 clicked U가 있다.
    /// - 기대 결과: frozen `[P2, U]`가 한 batch로 이동하고 source에는 P1만 남으며 exact terminal/pending cleanup이 완료된다.
    func testSelectedMenuBatchUsesSyncedMixedOrderThroughAtomicCommit() async throws {
        let sourceID = UUID(45821)
        let targetID = UUID(45822)
        let requestID = UUID(45823)
        let unpinnedID = ContentTabID(rawValue: "menu-chain-unpinned")
        let pinnedFirstID = ContentTabID(rawValue: "menu-chain-pinned-first")
        let pinnedSecondID = ContentTabID(rawValue: "menu-chain-pinned-second")
        let targetExistingID = ContentTabID(rawValue: "menu-chain-target-existing")
        var source = try Self.makeContentTabMoveWindow(
            id: sourceID,
            tabs: [
                (unpinnedID, "/menu-chain/unpinned"),
                (pinnedFirstID, "/menu-chain/pinned-first"),
                (pinnedSecondID, "/menu-chain/pinned-second"),
            ],
        )
        source.window.contentTabs.tabs[id: pinnedFirstID]?.isPinned = true
        source.window.contentTabs.tabs[id: pinnedSecondID]?.isPinned = true
        source.window.contentTabs.pinnedRecords = [
            pinnedFirstID: ContentTabPinnedRecord(
                id: pinnedFirstID.rawValue,
                page: .directory,
                anchor: .directory(path: "/menu-chain/pinned-first"),
                title: "Pinned First",
                iconName: "folder",
                pinnedAt: Date(timeIntervalSince1970: 457),
            ),
            pinnedSecondID: ContentTabPinnedRecord(
                id: pinnedSecondID.rawValue,
                page: .directory,
                anchor: .directory(path: "/menu-chain/pinned-second"),
                title: "Pinned Second",
                iconName: "folder",
                pinnedAt: Date(timeIntervalSince1970: 458),
            ),
        ]
        source.window.contentTabs.selectedTabIDs = [pinnedSecondID, unpinnedID]
        source.window.sidebar.currentWindowID = sourceID
        source.window.lastConfirmedTopNavigationOrder = FileManagerTopNavigationOrder(items: [
            .contentTab(pinnedSecondID),
            .contentTab(pinnedFirstID),
        ])
        source.window.optimisticTopNavigationOrder = source.window.lastConfirmedTopNavigationOrder
        source.window.syncContentTabSidebarItems()
        XCTAssertEqual(
            source.window.sidebar.contentTabSelectionOrderedIDs,
            [pinnedSecondID, pinnedFirstID, unpinnedID],
        )
        let presentation = ContentTabMoveMenuPresentation(
            clickedTabID: unpinnedID,
            validSelectedTabIDs: source.window.contentTabs.selectedTabIDs,
            displayedOrderedTabIDs: source.window.sidebar.contentTabSelectionOrderedIDs,
        )
        XCTAssertEqual(presentation.orderedTabIDs, [pinnedSecondID, unpinnedID])
        let request = ContentTabMoveRequest(
            operationID: requestID,
            requestID: requestID,
            sourceWindowID: sourceID,
            initiatingTabID: unpinnedID,
            orderedTabIDs: [pinnedSecondID, unpinnedID],
            targetWindowID: targetID,
        )

        let target = try Self.makeContentTabMoveWindow(
            id: targetID,
            tabs: [(targetExistingID, "/menu-chain/target")],
        )
        var initialState = WindowManagerFeature.State()
        initialState.windows = [source, target]
        initialState.refreshContentTabMoveTargets()
        let undoBatches = LockIsolated<[[FileOperationUndoScopeMoveDescriptor]]>([])
        let store = TestStore(initialState: initialState) { WindowManagerFeature() } withDependencies: {
            $0.uuid = .constant(requestID)
            $0.date = .constant(Date(timeIntervalSince1970: 458))
            $0.fileOperationUndoManagerClient.moveScopes = { descriptors in
                undoBatches.withValue { $0.append(descriptors) }
                return .moved
            }
            $0.fileManagerWindowClient.activate = { _ in .discarded }
            $0.notificationCenterClient.notifications = { _, _ in AsyncStream { $0.finish() } }
        }
        // store.exhaustivity = .off: child lifecycle action보다 sync→menu→app atomic composition 결과를 검증한다.
        store.exhaustivity = .off

        await store.send(.windows(.element(
            id: sourceID,
            action: .window(.sidebar(.view(presentation.viewAction(targetWindowID: targetID)))),
        )))
        await store.receive { action in
            guard case let .windows(.element(
                id: id,
                action: .window(.sidebar(.delegate(.requestContentTabMove(receivedRequest)))),
            )) = action else { return false }
            return id == sourceID && receivedRequest == request
        }
        await store.receive { action in
            guard case let .windows(.element(
                id: id,
                action: .window(.delegate(.requestContentTabMove(receivedRequest))),
            )) = action else { return false }
            return id == sourceID && receivedRequest == request
        }
        await store.receive(\.contentTabMoveRequest, request)
        await store.skipReceivedActions()
        await store.finish()

        XCTAssertEqual(store.state.windows[id: sourceID]?.window.contentTabs.tabs.map(\.id), [pinnedFirstID])
        XCTAssertEqual(
            store.state.windows[id: targetID]?.window.contentTabs.tabs.count(where: { $0.id == pinnedSecondID }),
            1,
        )
        XCTAssertEqual(
            store.state.windows[id: targetID]?.window.contentTabs.tabs.count(where: { $0.id == unpinnedID }),
            1,
        )
        XCTAssertEqual(undoBatches.value.count, 1)
        XCTAssertEqual(
            undoBatches.value[0].map(\.source.contentTabID),
            [pinnedSecondID.rawValue, unpinnedID.rawValue],
        )
        let terminal = try XCTUnwrap(store.state.contentTabMoveTerminalRecords[requestID])
        XCTAssertEqual(terminal.operationID, requestID)
        XCTAssertEqual(terminal.initiatingTabID, unpinnedID)
        XCTAssertEqual(terminal.orderedTabIDs, [pinnedSecondID, unpinnedID])
        XCTAssertEqual(terminal.outcome, .succeeded)
        XCTAssertNil(store.state.windows[id: sourceID]?.window.pendingContentTabMove)
        XCTAssertNil(store.state.windows[id: sourceID]?.window.sidebar.pendingContentTabMoveRequest)
    }

    /// CTM-001-move_content_tab_to_another_window: atomic Undo batch rejection은 logical/native effect를 만들지 않는다.
    /// Undo registry가 batch 전체를 거절할 때 immutable token projection이 적용되지 않는지 검증한다.
    /// - 검증 내용: source/target tab snapshot, lifecycle/activation/close 0회, exact package rejection cleanup
    /// - 사전 조건: 두 tab의 exact in-flight request와 target-occupied Undo outcome이 존재한다.
    /// - 기대 결과: 양 window logical state가 유지되고 native effect 없이 generic terminal로 끝난다.
    func testContentTabBatchMoveUndoRejectionHasZeroLogicalLifecycleOrNativeEffects() async throws {
        let sourceID = UUID(45811)
        let targetID = UUID(45812)
        let firstID = ContentTabID(rawValue: "undo-batch-first")
        let primaryID = ContentTabID(rawValue: "undo-batch-primary")
        let targetExistingID = ContentTabID(rawValue: "undo-batch-target")
        let request = ContentTabMoveRequest(
            operationID: UUID(45813),
            requestID: UUID(45814),
            sourceWindowID: sourceID,
            initiatingTabID: primaryID,
            orderedTabIDs: [firstID, primaryID],
            targetWindowID: targetID,
        )
        var source = try Self.makeContentTabMoveWindow(
            id: sourceID,
            tabs: [(firstID, "/undo-batch/first"), (primaryID, "/undo-batch/primary")],
        )
        Self.prepareContentTabMoveRequest(request, in: &source)
        let target = try Self.makeContentTabMoveWindow(
            id: targetID,
            tabs: [(targetExistingID, "/undo-batch/target")],
        )
        let sourceTabs = source.window.contentTabs.tabs
        let targetTabs = target.window.contentTabs.tabs
        var initialState = WindowManagerFeature.State()
        initialState.windows = [source, target]
        let legacyUndoCalls = LockIsolated(0)
        let lifecycleStarts = LockIsolated(0)
        let activatedIDs = LockIsolated<[UUID]>([])
        let closedIDs = LockIsolated<[UUID]>([])
        let rejectedScope = UndoManagerScope(windowID: targetID, contentTabID: primaryID.rawValue)
        let store = TestStore(initialState: initialState) { WindowManagerFeature() } withDependencies: {
            $0.fileOperationUndoManagerClient.moveScope = { _, _, _ in
                legacyUndoCalls.withValue { $0 += 1 }
                return .moved
            }
            $0.fileOperationUndoManagerClient.moveScopes = { _ in .targetOccupied(rejectedScope) }
            $0.notificationCenterClient.notifications = { _, _ in
                lifecycleStarts.withValue { $0 += 1 }
                return AsyncStream { $0.finish() }
            }
            $0.fileManagerWindowClient.activate = { id in
                activatedIDs.withValue { $0.append(id) }
                return .discarded
            }
            $0.fileManagerWindowClient.close = { id in closedIDs.withValue { $0.append(id) } }
        }
        // store.exhaustivity = .off: rejection terminal child action과 zero-effect snapshot만 검증한다.
        store.exhaustivity = .off

        await store.send(.contentTabMoveRequest(request))
        await store.skipReceivedActions()
        await store.finish()

        XCTAssertEqual(store.state.windows[id: sourceID]?.window.contentTabs.tabs, sourceTabs)
        XCTAssertEqual(store.state.windows[id: targetID]?.window.contentTabs.tabs, targetTabs)
        XCTAssertEqual(legacyUndoCalls.value, 0)
        XCTAssertEqual(lifecycleStarts.value, 0)
        XCTAssertTrue(activatedIDs.value.isEmpty)
        XCTAssertTrue(closedIDs.value.isEmpty)
        XCTAssertEqual(
            store.state.windows[id: sourceID]?.window.contentTabMoveFailurePresentation?.category,
            .generic,
        )
    }

    /// CTM-001-move_content_tab_to_another_window: target package busy는 Undo와 app commit 전에 거절한다.
    /// exact source request를 허용하면서 target close/Undo/outgoing move lifecycle을 package preflight에서 차단하는지 검증한다.
    /// - 검증 내용: busy terminal, semantic snapshot, moveScopes/transaction/lifecycle/native/activate/close 0회
    /// - 사전 조건: exact in-flight source와 isClosing, Undo invoking, 또는 pending move target이 존재한다.
    /// - 기대 결과: 세 요청 모두 busy로 끝나고 terminal presentation 외 source/target 및 모든 effect registry가 불변이다.
    func testContentTabMoveRejectsTargetWindowBusyBeforeUndoAndAppCommit() async throws {
        try await Self.assertContentTabMoveTargetBusyRejection(variant: 1) { target in
            target.isClosing = true
        }
        try await Self.assertContentTabMoveTargetBusyRejection(variant: 2) { target in
            target.undoRedoPhase = .invoking(requestID: UUID(45832), direction: .undo)
        }
        try await Self.assertContentTabMoveTargetBusyRejection(variant: 3) { target in
            let targetWindowID = target.windowID ?? UUID(45863)
            let targetTabID = target.contentTabs.activeTabID ?? ContentTabID(rawValue: "target-busy-pending")
            let pendingRequest = ContentTabMoveRequest(
                requestID: UUID(45864),
                sourceWindowID: targetWindowID,
                tabID: targetTabID,
                targetWindowID: UUID(45865),
            )
            target.sidebar.pendingContentTabMoveRequest = pendingRequest
            target.pendingContentTabMove = .init(request: pendingRequest, lifecycle: .inFlight)
        }
    }

    /// CTM-001-move_content_tab_to_another_window: active transaction과 한 window라도 겹치면 busy로 거절한다.
    /// 다른 source가 active target을 재사용하는 교차 방향 overlap도 app lock이 차단하는지 검증한다.
    /// - 검증 내용: full-request busy terminal, Undo/native 0회, active transaction 보존
    /// - 사전 조건: A→B transaction lifecycle 설치 중 C→B exact in-flight batch가 도착한다.
    /// - 기대 결과: C→B는 busy이고 A→B lock과 C/B logical state는 유지된다.
    func testContentTabBatchMoveRejectsAnyOverlappingWindowPairAsBusy() async throws {
        let activeRequest = ContentTabMoveRequest(
            operationID: UUID(45821),
            requestID: UUID(45822),
            sourceWindowID: UUID(45823),
            initiatingTabID: ContentTabID(rawValue: "active-primary"),
            orderedTabIDs: [ContentTabID(rawValue: "active-primary")],
            targetWindowID: UUID(45824),
        )
        let sourceID = UUID(45825)
        let firstID = ContentTabID(rawValue: "overlap-first")
        let primaryID = ContentTabID(rawValue: "overlap-primary")
        let request = ContentTabMoveRequest(
            operationID: UUID(45826),
            requestID: UUID(45827),
            sourceWindowID: sourceID,
            initiatingTabID: primaryID,
            orderedTabIDs: [firstID, primaryID],
            targetWindowID: activeRequest.targetWindowID,
        )
        var source = try Self.makeContentTabMoveWindow(
            id: sourceID,
            tabs: [(firstID, "/overlap/first"), (primaryID, "/overlap/primary")],
        )
        Self.prepareContentTabMoveRequest(request, in: &source)
        let activeSource = try Self.makeContentTabMoveWindow(
            id: activeRequest.sourceWindowID,
            tabs: [(activeRequest.initiatingTabID, "/active/source")],
        )
        let activeTarget = try Self.makeContentTabMoveWindow(
            id: activeRequest.targetWindowID,
            tabs: [(ContentTabID(rawValue: "active-target"), "/active/target")],
        )
        let sourceTabs = source.window.contentTabs.tabs
        let targetTabs = activeTarget.window.contentTabs.tabs
        var initialState = WindowManagerFeature.State()
        initialState.windows = [activeSource, activeTarget, source]
        initialState.contentTabMoveTransactions[activeRequest.requestID] = .init(request: activeRequest)
        let undoCalls = LockIsolated(0)
        let activatedIDs = LockIsolated<[UUID]>([])
        let store = TestStore(initialState: initialState) { WindowManagerFeature() } withDependencies: {
            $0.fileOperationUndoManagerClient.moveScopes = { _ in
                undoCalls.withValue { $0 += 1 }
                return .moved
            }
            $0.fileManagerWindowClient.activate = { id in
                activatedIDs.withValue { $0.append(id) }
                return .discarded
            }
        }
        // store.exhaustivity = .off: exact rejection child action 뒤 app lock과 logical snapshot만 검증한다.
        store.exhaustivity = .off

        await store.send(.contentTabMoveRequest(request))
        await store.skipReceivedActions()
        await store.finish()

        XCTAssertEqual(store.state.windows[id: sourceID]?.window.contentTabs.tabs, sourceTabs)
        XCTAssertEqual(store.state.windows[id: activeRequest.targetWindowID]?.window.contentTabs.tabs, targetTabs)
        XCTAssertEqual(store.state.contentTabMoveTerminalRecords[request.requestID], .init(
            request: request,
            outcome: .rejected(.busy),
        ))
        XCTAssertEqual(store.state.contentTabMoveTransactions[activeRequest.requestID]?.request, activeRequest)
        XCTAssertEqual(undoCalls.value, 0)
        XCTAssertTrue(activatedIDs.value.isEmpty)
    }

    /// CTM-001-move_content_tab_to_another_window: disjoint window pair는 active transaction과 독립 실행한다.
    /// A→B lifecycle lock이 존재해도 C→D batch가 commit되고 A→B lock을 건드리지 않는지 검증한다.
    /// - 검증 내용: disjoint Undo/registry/terminal/native commit과 기존 transaction 보존
    /// - 사전 조건: active A→B와 exact in-flight C→D batch가 서로 다른 네 window를 사용한다.
    /// - 기대 결과: C→D는 성공하고 A→B transaction은 그대로 남는다.
    func testContentTabBatchMoveAllowsFullyDisjointTransaction() async throws {
        let activeRequest = ContentTabMoveRequest(
            operationID: UUID(45831),
            requestID: UUID(45832),
            sourceWindowID: UUID(45833),
            initiatingTabID: ContentTabID(rawValue: "disjoint-active"),
            orderedTabIDs: [ContentTabID(rawValue: "disjoint-active")],
            targetWindowID: UUID(45834),
        )
        let sourceID = UUID(45835)
        let targetID = UUID(45836)
        let firstID = ContentTabID(rawValue: "disjoint-first")
        let primaryID = ContentTabID(rawValue: "disjoint-primary")
        let remainderID = ContentTabID(rawValue: "disjoint-remainder")
        let request = ContentTabMoveRequest(
            operationID: UUID(45837),
            requestID: UUID(45838),
            sourceWindowID: sourceID,
            initiatingTabID: primaryID,
            orderedTabIDs: [firstID, primaryID],
            targetWindowID: targetID,
        )
        var source = try Self.makeContentTabMoveWindow(
            id: sourceID,
            tabs: [
                (firstID, "/disjoint/first"),
                (primaryID, "/disjoint/primary"),
                (remainderID, "/disjoint/remainder"),
            ],
        )
        Self.prepareContentTabMoveRequest(request, in: &source)
        let target = try Self.makeContentTabMoveWindow(
            id: targetID,
            tabs: [(ContentTabID(rawValue: "disjoint-target"), "/disjoint/target")],
        )
        let activeSource = try Self.makeContentTabMoveWindow(
            id: activeRequest.sourceWindowID,
            tabs: [(activeRequest.initiatingTabID, "/disjoint/active-source")],
        )
        let activeTarget = try Self.makeContentTabMoveWindow(
            id: activeRequest.targetWindowID,
            tabs: [(ContentTabID(rawValue: "disjoint-active-target"), "/disjoint/active-target")],
        )
        var initialState = WindowManagerFeature.State()
        initialState.windows = [activeSource, activeTarget, source, target]
        initialState.contentTabMoveTransactions[activeRequest.requestID] = .init(request: activeRequest)
        let undoBatches = LockIsolated<[[FileOperationUndoScopeMoveDescriptor]]>([])
        let activatedIDs = LockIsolated<[UUID]>([])
        let store = TestStore(initialState: initialState) { WindowManagerFeature() } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 458))
            $0.fileOperationUndoManagerClient.moveScopes = { descriptors in
                undoBatches.withValue { $0.append(descriptors) }
                return .moved
            }
            $0.fileManagerWindowClient.activate = { id in
                activatedIDs.withValue { $0.append(id) }
                return .discarded
            }
            $0.notificationCenterClient.notifications = { _, _ in AsyncStream { $0.finish() } }
        }
        // store.exhaustivity = .off: child lifecycle 세부 action보다 disjoint transaction 격리 결과를 검증한다.
        store.exhaustivity = .off

        await store.send(.contentTabMoveRequest(request))
        await store.skipReceivedActions()
        await store.finish()

        XCTAssertNil(store.state.windows[id: sourceID]?.window.contentTabs.tabs[id: firstID])
        XCTAssertNil(store.state.windows[id: sourceID]?.window.contentTabs.tabs[id: primaryID])
        XCTAssertNotNil(store.state.windows[id: targetID]?.window.contentTabs.tabs[id: firstID])
        XCTAssertNotNil(store.state.windows[id: targetID]?.window.contentTabs.tabs[id: primaryID])
        XCTAssertEqual(store.state.contentTabMoveTerminalRecords[request.requestID]?.outcome, .succeeded)
        XCTAssertEqual(store.state.contentTabMoveTransactions[activeRequest.requestID]?.request, activeRequest)
        XCTAssertEqual(undoBatches.value.count, 1)
        XCTAssertEqual(activatedIDs.value, [targetID])
    }

    /// CTM-001-move_content_tab_to_another_window: lifecycle/native registries는 full request와 정확히 일치해야 한다.
    /// 같은 request ID를 재사용한 foreign operation callback과 duplicate native dispatch를 차단하는지 검증한다.
    /// - 검증 내용: transaction/native plan/activation attempt의 exact correlation과 one-shot dispatch
    /// - 사전 조건: batch success registries와 동일 request ID의 다른 operation/target request가 존재한다.
    /// - 기대 결과: foreign callback은 no-op이고 exact lifecycle/native만 각 registry를 한 번 제거한다.
    func testContentTabBatchCallbacksRequireExactRequestAndNativeDispatchIsOneShot() async {
        let requestID = UUID(45841)
        let request = ContentTabMoveRequest(
            operationID: UUID(45842),
            requestID: requestID,
            sourceWindowID: UUID(45843),
            initiatingTabID: ContentTabID(rawValue: "callback-primary"),
            orderedTabIDs: [
                ContentTabID(rawValue: "callback-first"),
                ContentTabID(rawValue: "callback-primary"),
            ],
            targetWindowID: UUID(45844),
        )
        let foreignRequest = ContentTabMoveRequest(
            operationID: UUID(45845),
            requestID: requestID,
            sourceWindowID: request.sourceWindowID,
            initiatingTabID: request.initiatingTabID,
            orderedTabIDs: request.orderedTabIDs,
            targetWindowID: UUID(45846),
        )
        var initialState = WindowManagerFeature.State()
        initialState.windows = [.init(
            id: request.targetWindowID,
            window: .makeInitial(path: "/callback-target"),
        )]
        initialState.recordContentTabMoveTerminal(.init(request: request, outcome: .succeeded))
        initialState.contentTabMoveTransactions[requestID] = .init(request: request)
        initialState.contentTabMoveNativeEffectsPlans[requestID] = .init(
            request: request,
            closesSourceWindow: false,
        )
        initialState.contentTabMoveActivationAttempts[requestID] = .init(request: request)
        let activatedIDs = LockIsolated<[UUID]>([])
        let store = TestStore(initialState: initialState) { WindowManagerFeature() } withDependencies: {
            $0.fileManagerWindowClient.activate = { id in
                activatedIDs.withValue { $0.append(id) }
                return .discarded
            }
        }
        // store.exhaustivity = .off: native result action을 자동 처리하고 registry/call count를 직접 검증한다.
        store.exhaustivity = .off

        await store.send(.contentTabMoveLifecycleCompleted(request: foreignRequest))
        await store.send(.contentTabMoveNativeEffectsRequested(request: foreignRequest))
        XCTAssertEqual(store.state.contentTabMoveTransactions[requestID]?.request, request)
        XCTAssertEqual(store.state.contentTabMoveNativeEffectsPlans[requestID]?.request, request)
        XCTAssertTrue(activatedIDs.value.isEmpty)

        await store.send(.contentTabMoveLifecycleCompleted(request: request))
        await store.send(.contentTabMoveNativeEffectsRequested(request: request))
        await store.skipReceivedActions()
        await store.finish()
        await store.send(.contentTabMoveNativeEffectsRequested(request: request))

        XCTAssertNil(store.state.contentTabMoveTransactions[requestID])
        XCTAssertNil(store.state.contentTabMoveNativeEffectsPlans[requestID])
        XCTAssertNil(store.state.contentTabMoveActivationAttempts[requestID])
        XCTAssertEqual(activatedIDs.value, [request.targetWindowID])
        XCTAssertEqual(store.state.contentTabMoveTerminalRecords[requestID]?.outcome, .succeeded)
    }

    /// CTM-001-move_content_tab_to_another_window: empty-source batch는 activate/close를 각각 한 번만 시도한다.
    /// native activation discard와 duplicate dispatch가 logical move 또는 restore candidate를 바꾸지 않는지 검증한다.
    /// - 검증 내용: two-tab logical commit, one-shot activate/close, recentlyClosed 보존, non-rollback terminal
    /// - 사전 조건: source의 마지막 두 tab과 양 window의 기존 recentlyClosed snapshot이 존재한다.
    /// - 기대 결과: source는 closing이고 target에 두 tab이 남으며 duplicate native action은 호출을 반복하지 않는다.
    func testContentTabBatchLastTabsCloseAndActivateAtMostOnceWithoutRestoreCandidate() async throws {
        let sourceID = UUID(45851)
        let targetID = UUID(45852)
        let firstID = ContentTabID(rawValue: "last-batch-first")
        let primaryID = ContentTabID(rawValue: "last-batch-primary")
        let request = ContentTabMoveRequest(
            operationID: UUID(45853),
            requestID: UUID(45854),
            sourceWindowID: sourceID,
            initiatingTabID: primaryID,
            orderedTabIDs: [firstID, primaryID],
            targetWindowID: targetID,
        )
        let sourceClosed = ClosedContentTabSnapshot(
            page: .directory,
            anchor: .directory(path: "/closed/source"),
            wasPinned: false,
            closedAt: Date(timeIntervalSince1970: 457),
            title: "Source Closed",
            iconName: "folder",
        )
        let targetClosed = ClosedContentTabSnapshot(
            page: .directory,
            anchor: .directory(path: "/closed/target"),
            wasPinned: false,
            closedAt: Date(timeIntervalSince1970: 456),
            title: "Target Closed",
            iconName: "folder",
        )
        var source = try Self.makeContentTabMoveWindow(
            id: sourceID,
            tabs: [(firstID, "/last-batch/first"), (primaryID, "/last-batch/primary")],
        )
        source.window.contentTabs.recentlyClosed = sourceClosed
        Self.prepareContentTabMoveRequest(request, in: &source)
        var target = try Self.makeContentTabMoveWindow(
            id: targetID,
            tabs: [(ContentTabID(rawValue: "last-batch-target"), "/last-batch/target")],
        )
        target.window.contentTabs.recentlyClosed = targetClosed
        var initialState = WindowManagerFeature.State()
        initialState.windows = [source, target]
        let activatedIDs = LockIsolated<[UUID]>([])
        let closedIDs = LockIsolated<[UUID]>([])
        let store = TestStore(initialState: initialState) { WindowManagerFeature() } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 458))
            $0.fileOperationUndoManagerClient.moveScopes = { _ in .moved }
            $0.fileManagerWindowClient.activate = { id in
                activatedIDs.withValue { $0.append(id) }
                return .discarded
            }
            $0.fileManagerWindowClient.close = { id in closedIDs.withValue { $0.append(id) } }
            $0.notificationCenterClient.notifications = { _, _ in AsyncStream { $0.finish() } }
        }
        // store.exhaustivity = .off: post-commit native result action보다 one-shot 호출과 logical state 보존을 검증한다.
        store.exhaustivity = .off

        await store.send(.contentTabMoveRequest(request))
        await store.skipReceivedActions()
        await store.finish()
        await store.send(.contentTabMoveNativeEffectsRequested(request: request))

        XCTAssertTrue(store.state.closingWindowIDs.contains(sourceID))
        XCTAssertEqual(store.state.windows[id: sourceID]?.window.contentTabs.recentlyClosed, sourceClosed)
        XCTAssertEqual(store.state.windows[id: targetID]?.window.contentTabs.recentlyClosed, targetClosed)
        XCTAssertNotNil(store.state.windows[id: targetID]?.window.contentTabs.tabs[id: firstID])
        XCTAssertNotNil(store.state.windows[id: targetID]?.window.contentTabs.tabs[id: primaryID])
        XCTAssertEqual(activatedIDs.value, [targetID])
        XCTAssertEqual(closedIDs.value, [sourceID])
        XCTAssertEqual(store.state.contentTabMoveTerminalRecords[request.requestID]?.outcome, .succeeded)
    }

    /// CTM-001-move_content_tab_to_another_window: 두 registry child를 한 action에서 함께 commit한다.
    /// source delegate request가 source 제거와 target 삽입을 원자적으로 완료하는지 검증한다.
    /// - 검증 내용: source/target tab 수와 source pending terminal
    /// - 사전 조건: 서로 다른 두 live window와 source pending request가 존재한다.
    /// - 기대 결과: source tab은 제거되고 target에는 동일 tab이 정확히 하나 존재한다.
    func testContentTabMoveCommitsSourceAndTargetAtomically() async throws {
        let sourceWindowID = UUID()
        let targetWindowID = UUID()
        let movedTabID = ContentTabID(rawValue: "atomic-moved-tab")
        let targetTabID = ContentTabID(rawValue: "atomic-target-tab")
        let request = ContentTabMoveRequest(
            requestID: UUID(),
            sourceWindowID: sourceWindowID,
            tabID: movedTabID,
            targetWindowID: targetWindowID,
        )
        var source = try XCTUnwrap(FileManagerWindowFeature.State.makeExternalInitial(
            reservations: [.init(id: movedTabID, anchor: .directory(path: "/source"))],
            windowID: sourceWindowID,
        ))
        source.sidebar.pendingContentTabMoveRequest = request
        source.pendingContentTabMove = .init(request: request, lifecycle: .inFlight)
        let target = try XCTUnwrap(FileManagerWindowFeature.State.makeExternalInitial(
            reservations: [.init(id: targetTabID, anchor: .directory(path: "/target"))],
            windowID: targetWindowID,
        ))
        var initialState = WindowManagerFeature.State()
        initialState.windows = [
            .init(id: sourceWindowID, window: source),
            .init(id: targetWindowID, window: target),
        ]
        let store = TestStore(initialState: initialState) {
            WindowManagerFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 450))
            $0.fileManagerWindowClient.activate = { _ in .discarded }
            $0.fileManagerWindowClient.close = { _ in }
            $0.fileOperationUndoManagerClient.moveScopes = { _ in .moved }
            $0.notificationCenterClient.notifications = { _, _ in AsyncStream { $0.finish() } }
        }
        // store.exhaustivity = .off: post-commit lifecycle effect보다 registry의 원자적 결과를 검증한다.
        store.exhaustivity = .off

        await store.send(.windows(.element(
            id: sourceWindowID,
            action: .window(.delegate(.requestContentTabMove(request))),
        )))
        await store.receive(\.contentTabMoveRequest, request)
        await store.skipReceivedActions()

        await store.finish()

        XCTAssertEqual(store.state.windows[id: sourceWindowID]?.window.contentTabs.tabs.count, 0)
        XCTAssertTrue(store.state.closingWindowIDs.contains(sourceWindowID))
        XCTAssertEqual(
            store.state.windows[id: targetWindowID]?.window.contentTabs.tabs.count(where: { $0.id == movedTabID }),
            1,
        )
        XCTAssertEqual(store.state.contentTabMoveTerminalRecords[request.requestID]?.outcome, .succeeded)
    }

    /// CTM-001-move_content_tab_to_another_window: explicit Pin transfer는 durable commit 전 projected window를 publish하지
    /// 않는다.
    /// 성공 후에는 source/target commit, authoritative snapshot fan-out, native/lifecycle one-shot dispatch를 함께 검증한다.
    /// - 검증 내용: gate 전 participant child mutation 차단, 3-tab exact mutation/location 전달, one-call/one-revision,
    /// source/peer authoritative snapshot 1회, peer local runtime 보존
    /// - 사전 조건: source 4-tab, pinned target anchor, idle peer, app-owned write gate
    /// - 기대 결과: gate 전 window 불변, gate 후 source/target/peer가 revision 1개 commit으로 수렴하고 source에도 global pinned
    /// 3개가 표시되며 activation/native dispatch는 각 1회다.
    func testContentTabMoveExplicitPinDefersProjectedWindowCommitUntilDurablePersistenceSucceeds() async throws {
        let sourceID = UUID(46901)
        let targetID = UUID(46902)
        let peerID = UUID(46903)
        let token = FileManagerTopNavigationOperationToken(value: UUID(46904))
        let movedID = ContentTabID(rawValue: "durable-pin-moved")
        let movedSecondID = ContentTabID(rawValue: "durable-pin-moved-second")
        let movedThirdID = ContentTabID(rawValue: "durable-pin-moved-third")
        let sourceRemainderID = ContentTabID(rawValue: "durable-pin-source-remainder")
        let targetPinnedID = ContentTabID(rawValue: "durable-pin-target-pinned")
        let targetUnpinnedID = ContentTabID(rawValue: "durable-pin-target-unpinned")
        let peerLocalID = ContentTabID(rawValue: "durable-pin-peer-local")
        let pinnedAt = Date(timeIntervalSince1970: 697)
        let targetPinnedRecord = ContentTabPinnedRecord(
            id: targetPinnedID.rawValue,
            page: .directory,
            anchor: .directory(path: "/durable-pin/target/pinned"),
            title: "Pinned",
            iconName: "folder",
            pinnedAt: Date(timeIntervalSince1970: 111),
        )
        let request = ContentTabMoveRequest(
            operationID: UUID(46905),
            requestID: UUID(46906),
            sourceWindowID: sourceID,
            initiatingTabID: movedID,
            orderedTabIDs: [movedID, movedSecondID, movedThirdID],
            targetWindowID: targetID,
            sourceDomain: .unpinned,
            targetDomain: .pinned,
            placement: .after(targetPinnedID),
        )
        var source = try Self.makeContentTabMoveWindow(
            id: sourceID,
            tabs: [
                (movedID, "/durable-pin/source/moved"),
                (movedSecondID, "/durable-pin/source/moved-second"),
                (movedThirdID, "/durable-pin/source/moved-third"),
                (sourceRemainderID, "/durable-pin/source/remainder"),
            ],
        )
        Self.prepareContentTabMoveRequest(request, in: &source)
        var target = try Self.makeContentTabMoveWindow(
            id: targetID,
            tabs: [(targetPinnedID, "/durable-pin/target/pinned"), (targetUnpinnedID, "/durable-pin/target/unpinned")],
        )
        target.window.contentTabs.tabs[id: targetPinnedID]?.isPinned = true
        target.window.contentTabs.pinnedRecords[targetPinnedID] = targetPinnedRecord
        target.window.lastConfirmedTopNavigationOrder = .init(items: [
            .location("location-a"),
            .contentTab(targetPinnedID),
            .location("location-b"),
        ])
        target.window.contentTabs.recentlyClosed = .init(
            page: .aiChat,
            anchor: .aiChat(sessionID: "durable-pin-target-closed-chat"),
            wasPinned: false,
            closedAt: Date(timeIntervalSince1970: 511),
            title: "Target Closed",
            iconName: "message",
        )
        target.window.syncContentTabSidebarItems()
        var peer = FileManagerWindowFeature.State.makeInitial(path: "/durable-pin/peer")
        peer.contentTabs.tabs.append(ContentTabItem(
            id: peerLocalID,
            page: .directory,
            anchor: .directory(path: "/durable-pin/peer/local"),
            isPinned: false,
            title: "Peer Local",
            iconName: "folder",
        ))
        peer.contentTabs.activeTabID = peerLocalID
        peer.contentTabs.selectedTabIDs = [peerLocalID]
        peer.contentTabs.selectionAnchorID = peerLocalID
        peer.contentTabs.recentlyClosed = .init(
            page: .directory,
            anchor: .directory(path: "/durable-pin/peer/closed"),
            wasPinned: false,
            closedAt: Date(timeIntervalSince1970: 510),
            title: "Peer Closed",
            iconName: "folder",
        )
        peer.syncContentTabSidebarItems()
        let sourceBefore = source.window
        let targetBefore = target.window
        let peerBefore = peer
        guard case let .success(expectedToken) = ContentTabTransfer.preflight(
            source: source.window,
            target: target.window,
            orderedTabIDs: request.orderedTabIDs,
            primaryTabID: request.initiatingTabID,
            sourceDomain: request.sourceDomain,
            targetDomain: request.targetDomain,
            placement: request.placement,
            pinnedAt: pinnedAt,
        ) else {
            return XCTFail("Expected explicit Pin preflight success")
        }
        guard case .moved = ContentTabTransfer.apply(expectedToken) else {
            return XCTFail("Expected non-empty source postCommit result")
        }
        let expectedMutation = try XCTUnwrap(expectedToken.durablePinnedMutation)
        let committedStore = ContentTabPinnedRecordStore(
            records: [targetPinnedRecord] + expectedMutation.recordsToUpsert,
            topNavigationOrder: .init(items: [
                .location("location-a"),
                .contentTab(targetPinnedID),
                .contentTab(movedID),
                .contentTab(movedSecondID),
                .contentTab(movedThirdID),
                .location("location-b"),
            ]),
        )
        let committedOrder = committedStore.topNavigationOrder
        let committedRevision: UInt64 = 41
        let writeGate = PinnedRecordMutationGate()
        let clientCallCount = LockIsolated(0)
        let activationCalls = LockIsolated<[UUID]>([])
        var initialState = WindowManagerFeature.State()
        initialState.windows = [source, target, .init(id: peerID, window: peer)]
        let store = TestStore(initialState: initialState) { WindowManagerFeature() } withDependencies: {
            $0.date = .constant(pinnedAt)
            $0.uuid = .incrementing
            $0.contentTabPinnedRecordClient.reserveTopNavigationOperationToken = { token }
            $0.fileOperationUndoManagerClient.moveScopes = { _ in .moved }
            $0.contentTabPinnedRecordClient.applyDurablePinnedBatchMutationCommitted = { _, locations, mutation in
                clientCallCount.withValue { $0 += 1 }
                XCTAssertEqual(locations, ["location-a", "location-b"])
                XCTAssertEqual(mutation, expectedMutation)
                await writeGate.wait()
                return .init(
                    store: committedStore,
                    topNavigation: .init(order: committedOrder, revision: committedRevision),
                )
            }
            $0.fileManagerWindowClient.activate = { id in
                activationCalls.withValue { $0.append(id) }
                return .discarded
            }
            $0.notificationCenterClient.notifications = { _, _ in AsyncStream { $0.finish() } }
        }
        store.exhaustivity = .off

        await store.send(.contentTabMoveRequest(request))
        await store.receive { action in
            guard case let .topNavigationPersistenceRequested(receivedRequest) = action,
                  case let .contentTabMove(receivedMoveRequest, mutation, discoveredLocationIDs) = receivedRequest
                  .operation
            else { return false }
            return receivedRequest.sourceWindowID == sourceID
                && receivedRequest.token == token
                && receivedMoveRequest == request
                && mutation == expectedMutation
                && discoveredLocationIDs == ["location-a", "location-b"]
        }
        await writeGate.waitUntilWaiting()

        var sourceDuringPersistence = sourceBefore
        sourceDuringPersistence.contentTabMoveParticipantRequestID = request.requestID
        var targetDuringPersistence = targetBefore
        targetDuringPersistence.contentTabMoveParticipantRequestID = request.requestID
        XCTAssertEqual(store.state.windows[id: sourceID]?.window, sourceDuringPersistence)
        XCTAssertEqual(store.state.windows[id: targetID]?.window, targetDuringPersistence)
        XCTAssertEqual(store.state.windows[id: peerID]?.window, peerBefore)
        XCTAssertEqual(store.state.topNavigationPersistenceQueue.count, 1)
        XCTAssertEqual(store.state.topNavigationPersistenceQueue.first?.sourceWindowID, sourceID)
        XCTAssertTrue(store.state.isTopNavigationPersistenceInFlight)
        XCTAssertEqual(store.state.contentTabMoveTransactions[request.requestID]?.request, request)
        XCTAssertNil(store.state.contentTabMoveTerminalRecords[request.requestID])
        XCTAssertTrue(store.state.contentTabMoveNativeEffectsPlans.isEmpty)
        XCTAssertEqual(clientCallCount.value, 1)
        XCTAssertTrue(activationCalls.value.isEmpty)

        let targetInspectorVisibility = store.state.windows[id: targetID]?.window.inspector.inspectorVisible
        let targetSidebarVisibility = store.state.windows[id: targetID]?.window.sidebar.sidebarVisible
        await store.send(.windows(.element(
            id: targetID,
            action: .window(.inspector(.toggleInspector)),
        )))
        await store.send(.windows(.element(
            id: targetID,
            action: .window(.sidebar(.view(.setSidebarVisible(false)))),
        )))
        XCTAssertEqual(
            store.state.windows[id: targetID]?.window.inspector.inspectorVisible,
            targetInspectorVisibility,
        )
        XCTAssertEqual(
            store.state.windows[id: targetID]?.window.sidebar.sidebarVisible,
            targetSidebarVisibility,
        )

        await store.send(.windows(.element(
            id: targetID,
            action: .window(.contentTabs(.pin(targetUnpinnedID))),
        )))
        XCTAssertEqual(
            store.state.windows[id: targetID]?.window.contentTabs.tabs[id: targetUnpinnedID]?.isPinned,
            false,
        )
        await store.send(.windows(.element(
            id: targetID,
            action: .window(.contentTabs(.commitClose(targetUnpinnedID))),
        )))
        XCTAssertNotNil(store.state.windows[id: targetID]?.window.contentTabs.tabs[id: targetUnpinnedID])
        let updatedTargetPinnedAnchor = ContentTabPageAnchor.directory(path: "/durable-pin/target/updated")
        await store.send(.windows(.element(
            id: targetID,
            action: .window(.contentTabs(.updateActivePageAnchor(targetPinnedID, updatedTargetPinnedAnchor))),
        )))
        XCTAssertEqual(
            store.state.windows[id: targetID]?.window.contentTabs.tabs[id: targetPinnedID]?.anchor,
            targetPinnedRecord.anchor,
        )
        let targetTabCountDuringPersistence = store.state.windows[id: targetID]?.window.contentTabs.tabs.count
        let targetRecentlyClosedDuringPersistence = store.state.windows[id: targetID]?.window.contentTabs.recentlyClosed
        await store.send(.windows(.element(
            id: targetID,
            action: .window(.contentTabs(.open(.directory(path: "/durable-pin/target/open-blocked")))),
        )))
        await store.send(.windows(.element(
            id: targetID,
            action: .window(.contentTabs(.restore)),
        )))
        await store.send(.windows(.element(
            id: targetID,
            action: .window(.request(.restoreLastClosedContentTab)),
        )))
        XCTAssertEqual(
            store.state.windows[id: targetID]?.window.contentTabs.tabs.count,
            targetTabCountDuringPersistence,
        )
        XCTAssertEqual(
            store.state.windows[id: targetID]?.window.contentTabs.recentlyClosed,
            targetRecentlyClosedDuringPersistence,
        )

        await writeGate.open()
        await store.skipReceivedActions()
        await store.finish()
        let sourceWindow = store.state.windows[id: sourceID]?.window
        let targetWindow = store.state.windows[id: targetID]?.window
        let peerWindow = store.state.windows[id: peerID]?.window
        XCTAssertEqual(store.state.topNavigationPersistenceQueue.count, 0)
        XCTAssertFalse(store.state.isTopNavigationPersistenceInFlight)
        XCTAssertNil(store.state.contentTabMoveTransactions[request.requestID])
        XCTAssertNil(store.state.contentTabMoveNativeEffectsPlans[request.requestID])
        XCTAssertNil(store.state.contentTabMoveActivationAttempts[request.requestID])
        XCTAssertNil(sourceWindow?.contentTabMoveParticipantRequestID)
        XCTAssertNil(targetWindow?.contentTabMoveParticipantRequestID)
        XCTAssertEqual(store.state.contentTabMoveTerminalRecords[request.requestID]?.outcome, .succeeded)
        XCTAssertNotNil(sourceWindow?.contentTabs.tabs[id: sourceRemainderID])
        XCTAssertEqual(targetWindow?.contentTabs.activeTabID, movedID)
        XCTAssertEqual(targetWindow?.contentTabs.selectionAnchorID, movedID)
        XCTAssertNotNil(targetWindow?.contentTabs.tabs[id: movedID])
        XCTAssertNotNil(targetWindow?.contentTabs.tabs[id: movedSecondID])
        XCTAssertNotNil(targetWindow?.contentTabs.tabs[id: movedThirdID])
        XCTAssertEqual(targetWindow?.contentTabs.tabs[id: movedID]?.isPinned, true)
        XCTAssertEqual(targetWindow?.contentTabs.tabs[id: movedSecondID]?.isPinned, true)
        XCTAssertEqual(targetWindow?.contentTabs.tabs[id: movedThirdID]?.isPinned, true)
        XCTAssertEqual(targetWindow?.contentTabs.tabs[id: targetUnpinnedID]?.isPinned, false)
        XCTAssertEqual(sourceWindow?.lastConfirmedTopNavigationOrder, committedOrder)
        XCTAssertEqual(targetWindow?.lastConfirmedTopNavigationOrder, committedOrder)
        XCTAssertEqual(peerWindow?.lastConfirmedTopNavigationOrder, committedOrder)
        XCTAssertEqual(peerWindow?.lastConfirmedTopNavigationCommitRevision, committedRevision)
        XCTAssertEqual(peerWindow?.contentTabs.activeTabID, peerLocalID)
        XCTAssertEqual(peerWindow?.contentTabs.selectedTabIDs, [peerLocalID])
        XCTAssertEqual(peerWindow?.contentTabs.selectionAnchorID, peerLocalID)
        XCTAssertEqual(peerWindow?.contentTabs.recentlyClosed, peerBefore.contentTabs.recentlyClosed)
        let expectedPinnedIDs = [targetPinnedID, movedID, movedSecondID, movedThirdID]
        XCTAssertEqual(sourceWindow?.contentTabs.tabs.filter(\.isPinned).map(\.id), expectedPinnedIDs)
        XCTAssertEqual(peerWindow?.contentTabs.tabs.filter(\.isPinned).map(\.id), expectedPinnedIDs)
        XCTAssertEqual(clientCallCount.value, 1)
        XCTAssertEqual(activationCalls.value, [targetID])
    }

    /// CTM-001-move_content_tab_to_another_window: opposite-domain Unpin은 remove-only durable mutation만 저장한다.
    /// target runtime unpinned placement는 반영하지만 durable order에는 남기지 않는지 검증한다.
    /// - 검증 내용: remove-only mutation, pinnedPlacement nil, target runtime placement, committed durable order에서 moved
    /// tab 제외
    /// - 사전 조건: source pinned tab 1개와 target unpinned anchor 2개
    /// - 기대 결과: moved tab은 target unpinned placement로 이동하고 persistent pinned records/order에서는 제거된다.
    func testContentTabMoveExplicitUnpinPersistsRemoveOnlyAndKeepsRuntimePlacementOnly() async throws {
        let sourceID = UUID(46911)
        let targetID = UUID(46912)
        let movedID = ContentTabID(rawValue: "durable-unpin-moved")
        let targetFirstID = ContentTabID(rawValue: "durable-unpin-target-first")
        let targetSecondID = ContentTabID(rawValue: "durable-unpin-target-second")
        let movedRecord = ContentTabPinnedRecord(
            id: movedID.rawValue,
            page: .directory,
            anchor: .directory(path: "/durable-unpin/source/moved"),
            title: "Moved",
            iconName: "folder",
            pinnedAt: Date(timeIntervalSince1970: 211),
        )
        let request = ContentTabMoveRequest(
            operationID: UUID(46913),
            requestID: UUID(46914),
            sourceWindowID: sourceID,
            initiatingTabID: movedID,
            orderedTabIDs: [movedID],
            targetWindowID: targetID,
            sourceDomain: .pinned,
            targetDomain: .unpinned,
            placement: .before(targetSecondID),
        )
        var source = try Self.makeContentTabMoveWindow(id: sourceID, tabs: [(movedID, "/durable-unpin/source/moved")])
        source.window.contentTabs.tabs[id: movedID]?.isPinned = true
        source.window.contentTabs.pinnedRecords[movedID] = movedRecord
        source.window.syncContentTabSidebarItems()
        Self.prepareContentTabMoveRequest(request, in: &source)
        let target = try Self.makeContentTabMoveWindow(
            id: targetID,
            tabs: [(targetFirstID, "/durable-unpin/target/first"), (targetSecondID, "/durable-unpin/target/second")],
        )
        guard case let .success(expectedToken) = ContentTabTransfer.preflight(
            source: source.window,
            target: target.window,
            orderedTabIDs: request.orderedTabIDs,
            primaryTabID: request.initiatingTabID,
            sourceDomain: request.sourceDomain,
            targetDomain: request.targetDomain,
            placement: request.placement,
            pinnedAt: nil,
        ) else {
            return XCTFail("Expected explicit Unpin preflight success")
        }
        let expectedMutation = try XCTUnwrap(expectedToken.durablePinnedMutation)
        guard case .closeSourceWindow = ContentTabTransfer.apply(expectedToken) else {
            return XCTFail("Expected close-source unpin result")
        }
        let committedOrder = FileManagerTopNavigationOrder(items: [.location("location-a")])
        let committedStore = ContentTabPinnedRecordStore(records: [], topNavigationOrder: committedOrder)
        var initialState = WindowManagerFeature.State()
        initialState.windows = [source, target]
        let store = TestStore(initialState: initialState) { WindowManagerFeature() } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 212))
            $0.contentTabPinnedRecordClient.reserveTopNavigationOperationToken = { .init(value: UUID(46915)) }
            $0.fileOperationUndoManagerClient.moveScopes = { _ in .moved }
            $0.contentTabPinnedRecordClient.applyDurablePinnedBatchMutationCommitted = { _, _, mutation in
                XCTAssertEqual(mutation.recordsToUpsert, [])
                XCTAssertEqual(mutation.recordIDsToRemove, [movedID.rawValue])
                XCTAssertEqual(mutation.orderedTabIDs, [movedID])
                XCTAssertNil(mutation.pinnedPlacement)
                XCTAssertEqual(mutation, expectedMutation)
                return .init(
                    store: committedStore,
                    topNavigation: .init(order: committedOrder, revision: 51),
                )
            }
            $0.fileManagerWindowClient.activate = { _ in .discarded }
            $0.fileManagerWindowClient.close = { _ in }
            $0.notificationCenterClient.notifications = { _, _ in AsyncStream { $0.finish() } }
        }
        store.exhaustivity = .off

        await store.send(.contentTabMoveRequest(request))
        await store.receive { action in
            guard case let .topNavigationPersistenceRequested(receivedRequest) = action,
                  case let .contentTabMove(receivedMoveRequest, mutation, discoveredLocationIDs) = receivedRequest
                  .operation
            else { return false }
            return receivedRequest.sourceWindowID == sourceID
                && receivedMoveRequest == request
                && mutation.recordsToUpsert.isEmpty
                && mutation.recordIDsToRemove == [movedID.rawValue]
                && mutation.orderedTabIDs == [movedID]
                && mutation.pinnedPlacement == nil
                && mutation == expectedMutation
                && discoveredLocationIDs.isEmpty
        }
        await store.skipReceivedActions()
        await store.finish()

        XCTAssertTrue(store.state.closingWindowIDs.contains(sourceID) || store.state.windows[id: sourceID] == nil)
        XCTAssertEqual(
            store.state.windows[id: targetID]?.window.contentTabs.tabs.map(\.id),
            [targetFirstID, movedID, targetSecondID],
        )
        XCTAssertEqual(store.state.windows[id: targetID]?.window.contentTabs.tabs[id: movedID]?.isPinned, false)
        XCTAssertFalse(committedStore.topNavigationOrder.items.contains(.contentTab(movedID)))
        XCTAssertEqual(store.state.contentTabMoveTerminalRecords[request.requestID]?.outcome, .succeeded)
    }

    /// CTM-001-move_content_tab_to_another_window: persistence failure는 forward undo 뒤 exact reverse undo로 동기 보상한다.
    /// 성공 fan-out/native activation 없이 pre-state와 queue/transaction cleanup만 남겨야 한다.
    /// - 검증 내용: moveScopes forward→reverse descriptor, rejection terminal 1회, snapshot/native 0회
    /// - 사전 조건: explicit Pin request와 save failure
    /// - 기대 결과: source/target exact pre-state 유지, generic rejection, queue/transaction empty
    func testContentTabMoveDurablePersistenceFailureRollsBackUndoAndLeavesWindowsUnchanged() async throws {
        let sourceID = UUID(46921)
        let targetID = UUID(46922)
        let movedID = ContentTabID(rawValue: "durable-failure-moved")
        let targetPinnedID = ContentTabID(rawValue: "durable-failure-target-pinned")
        let request = ContentTabMoveRequest(
            operationID: UUID(46923),
            requestID: UUID(46924),
            sourceWindowID: sourceID,
            initiatingTabID: movedID,
            orderedTabIDs: [movedID],
            targetWindowID: targetID,
            sourceDomain: .unpinned,
            targetDomain: .pinned,
            placement: .after(targetPinnedID),
        )
        var source = try Self.makeContentTabMoveWindow(id: sourceID, tabs: [(movedID, "/durable-failure/source/moved")])
        Self.prepareContentTabMoveRequest(request, in: &source)
        var target = try Self.makeContentTabMoveWindow(
            id: targetID,
            tabs: [(targetPinnedID, "/durable-failure/target/pinned")],
        )
        target.window.contentTabs.tabs[id: targetPinnedID]?.isPinned = true
        target.window.contentTabs.pinnedRecords[targetPinnedID] = ContentTabPinnedRecord(
            id: targetPinnedID.rawValue,
            page: .directory,
            anchor: .directory(path: "/durable-failure/target/pinned"),
            title: "Pinned",
            iconName: "folder",
            pinnedAt: Date(timeIntervalSince1970: 301),
        )
        let sourceBefore = source.window
        let targetBefore = target.window
        guard case let .success(expectedToken) = ContentTabTransfer.preflight(
            source: source.window,
            target: target.window,
            orderedTabIDs: request.orderedTabIDs,
            primaryTabID: request.initiatingTabID,
            sourceDomain: request.sourceDomain,
            targetDomain: request.targetDomain,
            placement: request.placement,
            pinnedAt: Date(timeIntervalSince1970: 302),
        ) else {
            return XCTFail("Expected failure-path preflight success")
        }
        let expectedMutation = try XCTUnwrap(expectedToken.durablePinnedMutation)
        let expectedForwardUndo = [FileOperationUndoScopeMoveDescriptor(
            source: UndoManagerScope(windowID: sourceID, contentTabID: movedID.rawValue),
            target: UndoManagerScope(windowID: targetID, contentTabID: movedID.rawValue),
            targetPolicy: .requireVacant,
        )]
        let expectedReverseUndo = [FileOperationUndoScopeMoveDescriptor(
            source: UndoManagerScope(windowID: targetID, contentTabID: movedID.rawValue),
            target: UndoManagerScope(windowID: sourceID, contentTabID: movedID.rawValue),
            targetPolicy: .requireVacant,
        )]
        let undoBatches = LockIsolated<[[FileOperationUndoScopeMoveDescriptor]]>([])
        let activationCalls = LockIsolated(0)
        var initialState = WindowManagerFeature.State()
        initialState.windows = [source, target]
        let store = TestStore(initialState: initialState) { WindowManagerFeature() } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 302))
            $0.contentTabPinnedRecordClient.reserveTopNavigationOperationToken = { .init(value: UUID(46925)) }
            $0.fileOperationUndoManagerClient.moveScopes = { descriptors in
                undoBatches.withValue { $0.append(descriptors) }
                return .moved
            }
            $0.contentTabPinnedRecordClient.applyDurablePinnedBatchMutationCommitted = { _, _, mutation in
                XCTAssertEqual(mutation, expectedMutation)
                throw NSError(domain: "Task5", code: 1)
            }
            $0.fileManagerWindowClient.activate = { _ in
                activationCalls.withValue { $0 += 1 }
                return .discarded
            }
        }
        store.exhaustivity = .off

        await store.send(.contentTabMoveRequest(request))
        await store.receive { action in
            guard case let .contentTabMoveWindowActionRequested(
                receivedRequest,
                windowID,
                .contentTabMoveRejected(terminalRequest, category),
            ) = action
            else { return false }
            return receivedRequest == request
                && windowID == sourceID
                && terminalRequest == request
                && category == .generic
        }
        await store.receive { action in
            guard case let .contentTabMoveLifecycleCompleted(receivedRequest) = action else { return false }
            return receivedRequest == request
        }
        await store.receive { action in
            guard case let .windows(.element(
                id: id,
                action: .window(.contentTabMoveRejected(receivedRequest, category)),
            )) = action
            else { return false }
            return id == sourceID && receivedRequest == request && category == .generic
        }
        await store.finish()

        XCTAssertEqual(undoBatches.value, [expectedForwardUndo, expectedReverseUndo])
        XCTAssertEqual(activationCalls.value, 0)
        XCTAssertEqual(store.state.windows[id: sourceID]?.window.contentTabs.tabs, sourceBefore.contentTabs.tabs)
        XCTAssertEqual(store.state.windows[id: targetID]?.window.contentTabs.tabs, targetBefore.contentTabs.tabs)
        XCTAssertNil(store.state.windows[id: sourceID]?.window.pendingContentTabMove)
        XCTAssertEqual(store.state.contentTabMoveTerminalRecords[request.requestID]?.outcome, .rejected(.generic))
        XCTAssertTrue(store.state.topNavigationPersistenceQueue.isEmpty)
        XCTAssertFalse(store.state.isTopNavigationPersistenceInFlight)
        XCTAssertNil(store.state.contentTabMoveTransactions[request.requestID])
    }

    /// CTM-001-move_content_tab_to_another_window: reverse Undo scope 이동 실패는 history loss를 명시하고 close 전 수렴한다.
    /// durable failure와 target close가 겹쳐도 generation-qualified reconciliation이 participant 해제보다 먼저 수행되는지 검증한다.
    /// - 검증 내용: forward receipt, typed reverse failure, reconciliation→Undo invalidation→native finalize 순서, terminal
    /// recovery
    /// - 사전 조건: explicit Pin persistence failure, target native close callback, reverse target occupied
    /// - 기대 결과: logical pre-state 유지, history loss 기록, transaction 정리 후 target close 완료, success/native activation 없음
    func testContentTabMoveRollbackFailureReconcilesUndoBeforeDeferredTargetClose() async throws {
        let sourceID = UUID(46926)
        let targetID = UUID(46927)
        let movedID = ContentTabID(rawValue: "rollback-recovery-moved")
        let targetPinnedID = ContentTabID(rawValue: "rollback-recovery-target-pinned")
        let request = ContentTabMoveRequest(
            operationID: UUID(46928),
            requestID: UUID(46929),
            sourceWindowID: sourceID,
            initiatingTabID: movedID,
            orderedTabIDs: [movedID],
            targetWindowID: targetID,
            sourceDomain: .unpinned,
            targetDomain: .pinned,
            placement: .after(targetPinnedID),
        )
        var source = try Self.makeContentTabMoveWindow(
            id: sourceID,
            tabs: [(movedID, "/rollback-recovery/source/moved")],
        )
        Self.prepareContentTabMoveRequest(request, in: &source)
        var target = try Self.makeContentTabMoveWindow(
            id: targetID,
            tabs: [(targetPinnedID, "/rollback-recovery/target/pinned")],
        )
        target.window.contentTabs.tabs[id: targetPinnedID]?.isPinned = true
        target.window.contentTabs.pinnedRecords[targetPinnedID] = ContentTabPinnedRecord(
            id: targetPinnedID.rawValue,
            page: .directory,
            anchor: .directory(path: "/rollback-recovery/target/pinned"),
            title: "Pinned",
            iconName: "folder",
            pinnedAt: Date(timeIntervalSince1970: 303),
        )
        let sourceBefore = source.window
        let forwardDescriptor = FileOperationUndoScopeMoveDescriptor(
            source: UndoManagerScope(windowID: sourceID, contentTabID: movedID.rawValue),
            target: UndoManagerScope(windowID: targetID, contentTabID: movedID.rawValue),
        )
        let reverseOutcome = FileOperationUndoScopesMoveOutcome.targetOccupied(forwardDescriptor.source)
        let writeGate = PinnedRecordMutationGate()
        let moveCallCount = LockIsolated(0)
        let lifecycleCalls = LockIsolated<[String]>([])
        let activationCalls = LockIsolated(0)
        var initialState = WindowManagerFeature.State()
        initialState.windows = [source, target]
        let store = TestStore(initialState: initialState) { WindowManagerFeature() } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 304))
            $0.contentTabPinnedRecordClient.reserveTopNavigationOperationToken = { .init(value: UUID(46930)) }
            $0.fileOperationUndoManagerClient.moveScopes = { descriptors in
                let call = moveCallCount.withValue { value in
                    value += 1
                    return value
                }
                XCTAssertEqual(descriptors, call == 1 ? [forwardDescriptor] : [
                    .init(source: forwardDescriptor.target, target: forwardDescriptor.source),
                ])
                return call == 1 ? .moved : reverseOutcome
            }
            $0.fileOperationUndoManagerClient.generation = { scope in
                scope == forwardDescriptor.target ? 91 : nil
            }
            $0.fileOperationUndoManagerClient.reconcileFailedScopeMove = { receipts, outcome in
                XCTAssertEqual(receipts, [
                    .init(descriptor: forwardDescriptor, targetGeneration: 91),
                ])
                XCTAssertEqual(outcome, reverseOutcome)
                lifecycleCalls.withValue { $0.append("reconcile") }
                return .historyLost(outcome)
            }
            $0.contentTabPinnedRecordClient.applyDurablePinnedBatchMutationCommitted = { _, _, _ in
                await writeGate.wait()
                throw NSError(domain: "UndoRollbackRecovery", code: 1)
            }
            $0.undoManagerClient.invalidateWindow = { id in
                lifecycleCalls.withValue { $0.append("invalidate:\(id)") }
                return .init(succeeded: true, availability: .init())
            }
            $0.fileManagerWindowClient.finalizeClose = { id in
                lifecycleCalls.withValue { $0.append("finalize:\(id)") }
            }
            $0.fileManagerWindowClient.activate = { _ in
                activationCalls.withValue { $0 += 1 }
                return .discarded
            }
        }
        // store.exhaustivity = .off: recovery와 deferred close terminal의 observable ordering만 검증한다.
        store.exhaustivity = .off

        await store.send(.contentTabMoveRequest(request))
        await writeGate.waitUntilWaiting()
        await store.send(.event(.windowClosed(targetID)))
        XCTAssertNotNil(store.state.windows[id: targetID])
        XCTAssertTrue(store.state.deferredClosedWindowIDs.contains(targetID))

        await writeGate.open()
        await store.skipReceivedActions()
        await store.finish()

        XCTAssertEqual(moveCallCount.value, 2)
        XCTAssertEqual(
            lifecycleCalls.value,
            ["reconcile", "invalidate:\(targetID)", "finalize:\(targetID)"],
        )
        XCTAssertEqual(store.state.windows[id: sourceID]?.window.contentTabs.tabs, sourceBefore.contentTabs.tabs)
        XCTAssertNil(store.state.windows[id: targetID])
        XCTAssertEqual(store.state.contentTabMoveTerminalRecords[request.requestID]?.outcome, .rejected(.generic))
        XCTAssertEqual(
            store.state.contentTabMoveTerminalRecords[request.requestID]?.undoRecovery,
            .historyLost(reverseOutcome),
        )
        XCTAssertNil(store.state.contentTabMoveTransactions[request.requestID])
        XCTAssertEqual(activationCalls.value, 0)
    }

    /// CTM-001-move_content_tab_to_another_window: queue head와 exact request/token이 맞지 않는 completion은 전체 no-op이다.
    /// exact completion은 target의 선행 authoritative Pin을 보존하고 duplicate terminal은 두 번째 fan-out을 만들지 않는다.
    /// - 검증 내용: foreign no-op, target authoritative rebase, moved runtime owner 보존, duplicate no-op
    /// - 사전 조건: pending correlated transaction, queue head exact request, target에 선행 global Pin projection 반영
    /// - 기대 결과: exact commit 뒤 target은 선행 Pin과 moved tab을 모두 보존하고 foreign/duplicate는 상태를 바꾸지 않는다.
    func testContentTabMovePersistenceCompletionRequiresExactQueueHeadAndIgnoresDuplicateTerminal() async throws {
        let sourceID = UUID(46931)
        let targetID = UUID(46932)
        let peerID = UUID(46933)
        let remainderID = ContentTabID(rawValue: "correlated-remainder")
        let globalPinnedID = ContentTabID(rawValue: "correlated-global-pinned")
        let globalPinnedRecord = ContentTabPinnedRecord(
            id: globalPinnedID.rawValue,
            page: .directory,
            anchor: .directory(path: "/correlated/global-pinned"),
            title: "Global Pinned",
            iconName: "folder",
            pinnedAt: Date(timeIntervalSince1970: 400),
        )
        let request = ContentTabMoveRequest(
            operationID: UUID(46934),
            requestID: UUID(46935),
            sourceWindowID: sourceID,
            initiatingTabID: ContentTabID(rawValue: "correlated-primary"),
            orderedTabIDs: [ContentTabID(rawValue: "correlated-primary")],
            targetWindowID: targetID,
            sourceDomain: .unpinned,
            targetDomain: .pinned,
            placement: .empty,
        )
        let source = try Self.makeContentTabMoveWindow(
            id: sourceID,
            tabs: [
                (request.initiatingTabID, "/correlated/source"),
                (remainderID, "/correlated/remainder"),
            ],
        )
        var target = WindowSessionState(
            id: targetID,
            window: .makeInitial(path: "/correlated/target", windowID: targetID),
        )
        let peer = FileManagerWindowFeature.State.makeInitial(path: "/correlated/peer")
        guard case let .success(token) = ContentTabTransfer.preflight(
            source: source.window,
            target: target.window,
            orderedTabIDs: request.orderedTabIDs,
            primaryTabID: request.initiatingTabID,
            sourceDomain: request.sourceDomain,
            targetDomain: request.targetDomain,
            placement: request.placement,
            pinnedAt: Date(timeIntervalSince1970: 401),
        ), case .moved = ContentTabTransfer.apply(token) else {
            return XCTFail("Expected correlated preflight success")
        }
        let exactMutation = try XCTUnwrap(token.durablePinnedMutation)
        target.window.applyPinnedContentTabs(
            ContentTabState.restoringPinnedRecords(from: .init(records: [globalPinnedRecord])).state,
        )
        target.window.lastConfirmedTopNavigationOrder = .init(items: [.contentTab(globalPinnedID)])
        target.window.lastConfirmedTopNavigationCommitRevision = 60
        let exactRequest = WindowManagerTopNavigationPersistenceRequest(
            sourceWindowID: sourceID,
            token: .init(value: UUID(46936)),
            operation: .contentTabMove(
                request: request,
                mutation: exactMutation,
                discoveredLocationIDs: [],
            ),
        )
        let foreignRequest = WindowManagerTopNavigationPersistenceRequest(
            sourceWindowID: sourceID,
            token: .init(value: UUID(46937)),
            operation: .contentTabMove(
                request: request,
                mutation: exactMutation,
                discoveredLocationIDs: [],
            ),
        )
        let movedPinnedRecord = ContentTabPinnedRecord(
            id: request.initiatingTabID.rawValue,
            page: .directory,
            anchor: .directory(path: "/correlated/source"),
            title: nil,
            iconName: nil,
            pinnedAt: Date(timeIntervalSince1970: 401),
        )
        let committedOrder = FileManagerTopNavigationOrder(items: [
            .contentTab(globalPinnedID),
            .contentTab(request.initiatingTabID),
        ])
        let committedResult = WindowManagerTopNavigationPersistenceResult(
            request: exactRequest,
            terminal: .committed(.init(order: committedOrder, revision: 61)),
            authoritativePinnedContentTabs: ContentTabState
                .restoringPinnedRecords(from: .init(records: [globalPinnedRecord, movedPinnedRecord])).state,
        )
        let foreignResult = WindowManagerTopNavigationPersistenceResult(
            request: foreignRequest,
            terminal: committedResult.terminal,
            authoritativePinnedContentTabs: committedResult.authoritativePinnedContentTabs,
        )
        var initialState = WindowManagerFeature.State()
        initialState.windows = [source, target, .init(id: peerID, window: peer)]
        initialState.topNavigationPersistenceQueue = [exactRequest]
        initialState.isTopNavigationPersistenceInFlight = true
        initialState.contentTabMoveTransactions[request.requestID] = .init(
            request: request,
            pendingPersistence: .init(
                postCommit: {
                    switch ContentTabTransfer.apply(token) {
                    case let .moved(postCommit): postCommit
                    case let .closeSourceWindow(postCommit): postCommit
                    case .rejected: preconditionFailure("Expected validated token")
                    }
                }(),
                closesSourceWindow: false,
                undoDescriptors: [],
            ),
        )
        let store = TestStore(initialState: initialState) { WindowManagerFeature() } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 401))
            $0.fileManagerWindowClient.activate = { _ in .discarded }
            $0.fileManagerWindowClient.close = { _ in }
            $0.notificationCenterClient.notifications = { _, _ in AsyncStream { $0.finish() } }
        }
        store.exhaustivity = .off
        let stateBeforeForeign = store.state

        await store.send(.topNavigationPersistenceCompleted(foreignResult))
        XCTAssertEqual(store.state, stateBeforeForeign)

        await store.send(.topNavigationPersistenceCompleted(committedResult))
        await store.skipReceivedActions()
        await store.finish()
        XCTAssertEqual(store.state.contentTabMoveTerminalRecords[request.requestID]?.outcome, .succeeded)
        XCTAssertTrue(store.state.topNavigationPersistenceQueue.isEmpty)
        XCTAssertFalse(store.state.isTopNavigationPersistenceInFlight)
        let targetWindow = try XCTUnwrap(store.state.windows[id: targetID]?.window)
        XCTAssertEqual(
            targetWindow.contentTabs.tabs.filter(\.isPinned).map(\.id),
            [globalPinnedID, request.initiatingTabID],
        )
        XCTAssertEqual(targetWindow.lastConfirmedTopNavigationOrder, committedOrder)
        XCTAssertEqual(
            targetWindow.tabContentStates[request.initiatingTabID]?.entryViewLayout.entryOperations.windowID,
            targetID,
        )
        let stateAfterExact = store.state

        await store.send(.topNavigationPersistenceCompleted(committedResult))
        XCTAssertEqual(store.state, stateAfterExact)
    }

    /// CTM-001-move_content_tab_to_another_window: source close after enqueue는 app-owned persistence를 취소하지 않는다.
    /// completion 뒤 source는 재생성되지 않고 target/peer만 authoritative snapshot으로 수렴해야 한다.
    /// - 검증 내용: deferred close 유지, completion 뒤 undo/native teardown과 source 제거, target/peer converge
    /// - 사전 조건: empty-source explicit Pin과 persistence gate, live peer 존재
    /// - 기대 결과: close 전 source 유지, gate 후 source 제거, target/peer pinned state converge, source recreation 없음
    func testContentTabMoveSourceCloseAfterEnqueueDoesNotCancelCorrelatedPersistence() async throws {
        let sourceID = UUID(46941)
        let targetID = UUID(46942)
        let peerID = UUID(46943)
        let movedID = ContentTabID(rawValue: "close-after-enqueue-moved")
        let targetPinnedID = ContentTabID(rawValue: "close-after-enqueue-target-pinned")
        let request = ContentTabMoveRequest(
            operationID: UUID(46944),
            requestID: UUID(46945),
            sourceWindowID: sourceID,
            initiatingTabID: movedID,
            orderedTabIDs: [movedID],
            targetWindowID: targetID,
            sourceDomain: .unpinned,
            targetDomain: .pinned,
            placement: .after(targetPinnedID),
        )
        var source = try Self.makeContentTabMoveWindow(
            id: sourceID,
            tabs: [(movedID, "/close-after-enqueue/source/moved")],
        )
        Self.prepareContentTabMoveRequest(request, in: &source)
        var target = try Self.makeContentTabMoveWindow(
            id: targetID,
            tabs: [(targetPinnedID, "/close-after-enqueue/target/pinned")],
        )
        target.window.contentTabs.tabs[id: targetPinnedID]?.isPinned = true
        target.window.contentTabs.pinnedRecords[targetPinnedID] = ContentTabPinnedRecord(
            id: targetPinnedID.rawValue,
            page: .directory,
            anchor: .directory(path: "/close-after-enqueue/target/pinned"),
            title: nil,
            iconName: nil,
            pinnedAt: Date(timeIntervalSince1970: 601),
        )
        target.window.lastConfirmedTopNavigationOrder = .init(items: [.contentTab(targetPinnedID)])
        let peer = FileManagerWindowFeature.State.makeInitial(path: "/close-after-enqueue/peer")
        let writeGate = PinnedRecordMutationGate()
        let teardownCalls = LockIsolated<[String]>([])
        let pinnedRecord = try XCTUnwrap(target.window.contentTabs.pinnedRecords[targetPinnedID])
        var initialState = WindowManagerFeature.State()
        initialState.windows = [source, target, .init(id: peerID, window: peer)]
        let store = TestStore(initialState: initialState) { WindowManagerFeature() } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 602))
            $0.contentTabPinnedRecordClient.reserveTopNavigationOperationToken = { .init(value: UUID(46946)) }
            $0.fileOperationUndoManagerClient.moveScopes = { _ in .moved }
            $0.contentTabPinnedRecordClient.applyDurablePinnedBatchMutationCommitted = { _, _, _ in
                await writeGate.wait()
                return .init(
                    store: .init(records: [
                        pinnedRecord,
                        ContentTabPinnedRecord(
                            id: movedID.rawValue,
                            page: .directory,
                            anchor: .directory(path: "/close-after-enqueue/source/moved"),
                            title: nil,
                            iconName: nil,
                            pinnedAt: Date(timeIntervalSince1970: 602),
                        ),
                    ], topNavigationOrder: .init(items: [.contentTab(targetPinnedID), .contentTab(movedID)])),
                    topNavigation: .init(
                        order: .init(items: [.contentTab(targetPinnedID), .contentTab(movedID)]),
                        revision: 71,
                    ),
                )
            }
            $0.fileManagerWindowClient.activate = { _ in .discarded }
            $0.fileManagerWindowClient.close = { _ in }
            $0.fileManagerWindowClient.finalizeClose = { id in
                teardownCalls.withValue { $0.append("finalize:\(id)") }
            }
            $0.undoManagerClient.invalidateWindow = { id in
                teardownCalls.withValue { $0.append("invalidate:\(id)") }
                return .init(succeeded: true, availability: .init())
            }
            $0.notificationCenterClient.notifications = { _, _ in AsyncStream { $0.finish() } }
        }
        store.exhaustivity = .off

        await store.send(.contentTabMoveRequest(request))
        await store.receive { action in
            guard case let .topNavigationPersistenceRequested(receivedRequest) = action,
                  case .contentTabMove = receivedRequest.operation
            else { return false }
            return receivedRequest.sourceWindowID == sourceID
        }
        await writeGate.waitUntilWaiting()
        await store.send(.event(.windowClosed(sourceID)))
        XCTAssertNotNil(store.state.windows[id: sourceID])
        XCTAssertTrue(store.state.closingWindowIDs.contains(sourceID))
        XCTAssertTrue(store.state.deferredClosedWindowIDs.contains(sourceID))

        await writeGate.open()
        await store.skipReceivedActions()
        await store.finish()

        XCTAssertNil(store.state.windows[id: sourceID])
        XCTAssertEqual(teardownCalls.value, ["invalidate:\(sourceID)", "finalize:\(sourceID)"])
        XCTAssertNotNil(store.state.windows[id: targetID]?.window.contentTabs.tabs[id: movedID])
        XCTAssertEqual(
            store.state.windows[id: peerID]?.window.contentTabs.tabs.filter(\.isPinned).map(\.id),
            [targetPinnedID, movedID],
        )
    }

    /// CTM-001-move_content_tab_to_another_window: target close fallback의 Undo 역이동 실패를 수렴한다.
    /// durable success를 surviving source에 fan-out한 뒤 generation-qualified reconciliation을 기록해야 한다.
    /// - 검증 내용: target deferred close, commit fan-out, source runtime 보존, Undo reconciliation, target 제거
    /// - 사전 조건: explicit Pin request와 persistence gate, target native close callback, reverse target occupied
    /// - 기대 결과: commit 뒤 source pinned tab 보존, history loss 기록, target 제거, transaction empty
    func testContentTabMoveTargetCloseFallbackReconcilesUndoBeforeRemoval() async throws {
        let sourceID = UUID(46947)
        let targetID = UUID(46948)
        let sourceLoadingOwnerID = UUID(46963)
        let sourceComposerOwnerID = UUID(46964)
        let movedID = ContentTabID(rawValue: "target-close-during-persistence-moved")
        let targetPinnedID = ContentTabID(rawValue: "target-close-during-persistence-pinned")
        let request = ContentTabMoveRequest(
            operationID: UUID(46949),
            requestID: UUID(46950),
            sourceWindowID: sourceID,
            initiatingTabID: movedID,
            orderedTabIDs: [movedID],
            targetWindowID: targetID,
            sourceDomain: .unpinned,
            targetDomain: .pinned,
            placement: .after(targetPinnedID),
        )
        let forwardDescriptor = FileOperationUndoScopeMoveDescriptor(
            source: UndoManagerScope(windowID: sourceID, contentTabID: movedID.rawValue),
            target: UndoManagerScope(windowID: targetID, contentTabID: movedID.rawValue),
        )
        let reverseOutcome = FileOperationUndoScopesMoveOutcome.targetOccupied(forwardDescriptor.source)
        var source = try Self.makeContentTabMoveWindow(
            id: sourceID,
            tabs: [(movedID, "/target-close-during-persistence/source/moved")],
        )
        var movedContent = try XCTUnwrap(source.window.tabContentStates[movedID])
        movedContent.entryViewLayout.entryOperations.windowID = sourceID
        movedContent.entryViewLayout.entryOperations.loadingCancellationOwnerID = sourceLoadingOwnerID
        movedContent.composer.cancellationOwnerID = sourceComposerOwnerID
        source.window.content = movedContent
        source.window.tabContentStates[movedID] = movedContent
        Self.prepareContentTabMoveRequest(request, in: &source)
        var target = try Self.makeContentTabMoveWindow(
            id: targetID,
            tabs: [(targetPinnedID, "/target-close-during-persistence/target/pinned")],
        )
        target.window.contentTabs.tabs[id: targetPinnedID]?.isPinned = true
        target.window.contentTabs.pinnedRecords[targetPinnedID] = ContentTabPinnedRecord(
            id: targetPinnedID.rawValue,
            page: .directory,
            anchor: .directory(path: "/target-close-during-persistence/target/pinned"),
            title: nil,
            iconName: nil,
            pinnedAt: Date(timeIntervalSince1970: 603),
        )
        target.window.lastConfirmedTopNavigationOrder = .init(items: [.contentTab(targetPinnedID)])
        let writeGate = PinnedRecordMutationGate()
        let moveCallCount = LockIsolated(0)
        let activationWindowIDs = LockIsolated<[WindowManagerFeature.State.WindowID]>([])
        let targetPinnedRecord = try XCTUnwrap(target.window.contentTabs.pinnedRecords[targetPinnedID])
        var initialState = WindowManagerFeature.State()
        initialState.windows = [source, target]
        let store = TestStore(initialState: initialState) { WindowManagerFeature() } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 604))
            $0.contentTabPinnedRecordClient.reserveTopNavigationOperationToken = { .init(value: UUID(46951)) }
            $0.fileOperationUndoManagerClient.moveScopes = { descriptors in
                let call = moveCallCount.withValue { value in
                    value += 1
                    return value
                }
                XCTAssertEqual(descriptors, call == 1 ? [forwardDescriptor] : [
                    .init(source: forwardDescriptor.target, target: forwardDescriptor.source),
                ])
                return call == 1 ? .moved : reverseOutcome
            }
            $0.fileOperationUndoManagerClient.generation = { scope in
                scope == forwardDescriptor.target ? 92 : nil
            }
            $0.fileOperationUndoManagerClient.reconcileFailedScopeMove = { receipts, outcome in
                XCTAssertEqual(receipts, [
                    .init(descriptor: forwardDescriptor, targetGeneration: 92),
                ])
                XCTAssertEqual(outcome, reverseOutcome)
                return .historyLost(outcome)
            }
            $0.contentTabPinnedRecordClient.applyDurablePinnedBatchMutationCommitted = { _, _, _ in
                await writeGate.wait()
                return .init(
                    store: .init(
                        records: [
                            targetPinnedRecord,
                            ContentTabPinnedRecord(
                                id: movedID.rawValue,
                                page: .directory,
                                anchor: .directory(path: "/target-close-during-persistence/source/moved"),
                                title: nil,
                                iconName: nil,
                                pinnedAt: Date(timeIntervalSince1970: 604),
                            ),
                        ],
                        topNavigationOrder: .init(items: [.contentTab(targetPinnedID), .contentTab(movedID)]),
                    ),
                    topNavigation: .init(
                        order: .init(items: [.contentTab(targetPinnedID), .contentTab(movedID)]),
                        revision: 72,
                    ),
                )
            }
            $0.fileManagerWindowClient.activate = { windowID in
                activationWindowIDs.withValue { $0.append(windowID) }
                return .discarded
            }
            $0.fileManagerWindowClient.close = { _ in }
            $0.notificationCenterClient.notifications = { _, _ in AsyncStream { $0.finish() } }
        }
        // store.exhaustivity = .off: cross-window persistence와 close lifecycle의 경계 상태만 검증
        store.exhaustivity = .off

        await store.send(.contentTabMoveRequest(request))
        await store.receive { action in
            guard case let .topNavigationPersistenceRequested(receivedRequest) = action,
                  case .contentTabMove = receivedRequest.operation
            else { return false }
            return receivedRequest.sourceWindowID == sourceID
        }
        await writeGate.waitUntilWaiting()

        await store.send(.event(.windowClosed(targetID)))
        XCTAssertNotNil(store.state.windows[id: targetID])
        XCTAssertTrue(store.state.closingWindowIDs.contains(targetID))
        XCTAssertTrue(store.state.deferredClosedWindowIDs.contains(targetID))
        XCTAssertTrue(store.state.isTopNavigationPersistenceInFlight)
        XCTAssertNotNil(store.state.contentTabMoveTransactions[request.requestID]?.pendingPersistence)

        await writeGate.open()
        await store.skipReceivedActions()
        await store.finish()

        XCTAssertEqual(moveCallCount.value, 2)
        XCTAssertEqual(store.state.windows[id: sourceID]?.window.contentTabs.tabs[id: movedID]?.isPinned, true)
        let preservedContent = try XCTUnwrap(store.state.windows[id: sourceID]?.window.tabContentStates[movedID])
        XCTAssertEqual(
            preservedContent.entryViewLayout.entryOperations.loadingCancellationOwnerID,
            sourceLoadingOwnerID,
        )
        XCTAssertEqual(preservedContent.composer.cancellationOwnerID, sourceComposerOwnerID)
        XCTAssertNil(store.state.windows[id: targetID])
        XCTAssertFalse(store.state.closingWindowIDs.contains(targetID))
        XCTAssertFalse(store.state.deferredClosedWindowIDs.contains(targetID))
        XCTAssertTrue(store.state.topNavigationPersistenceQueue.isEmpty)
        XCTAssertFalse(store.state.isTopNavigationPersistenceInFlight)
        XCTAssertNil(store.state.contentTabMoveTransactions[request.requestID])
        XCTAssertEqual(store.state.contentTabMoveTerminalRecords[request.requestID]?.outcome, .succeeded)
        XCTAssertEqual(
            store.state.contentTabMoveTerminalRecords[request.requestID]?.undoRecovery,
            .historyLost(reverseOutcome),
        )
        XCTAssertTrue(activationWindowIDs.value.isEmpty)
    }

    /// CTM-001-move_content_tab_to_another_window: target close 중 durable Unpin은 source runtime을 보존한다.
    /// remove-only commit 뒤 target tombstone이 제거되어도 moved tab의 유일한 runtime owner가 사라지지 않아야 한다.
    /// - 검증 내용: target deferred close, remove-only commit, source unpinned fallback, undo scope 복귀, native effect 억제
    /// - 사전 조건: 마지막 source pinned tab의 explicit Unpin과 persistence gate, target native close callback
    /// - 기대 결과: target은 제거되고 moved tab은 source에 unpinned로 남으며 source close와 target activation은 실행되지 않는다.
    func testContentTabMoveTargetCloseDuringDurableUnpinPreservesRuntimeInSource() async throws {
        let sourceID = UUID(46956)
        let targetID = UUID(46957)
        let movedID = ContentTabID(rawValue: "target-close-during-unpin-moved")
        let targetUnpinnedID = ContentTabID(rawValue: "target-close-during-unpin-anchor")
        let targetLoadingOwnerID = UUID(46961)
        let targetProbeRequestID = UUID(46962)
        let request = ContentTabMoveRequest(
            operationID: UUID(46958),
            requestID: UUID(46959),
            sourceWindowID: sourceID,
            initiatingTabID: movedID,
            orderedTabIDs: [movedID],
            targetWindowID: targetID,
            sourceDomain: .pinned,
            targetDomain: .unpinned,
            placement: .before(targetUnpinnedID),
        )
        var source = try Self.makeContentTabMoveWindow(
            id: sourceID,
            tabs: [(movedID, "/target-close-during-unpin/source/moved")],
        )
        source.window.contentTabs.tabs[id: movedID]?.isPinned = true
        let movedRecord = ContentTabPinnedRecord(
            id: movedID.rawValue,
            page: .directory,
            anchor: .directory(path: "/target-close-during-unpin/source/moved"),
            title: nil,
            iconName: nil,
            pinnedAt: Date(timeIntervalSince1970: 605),
        )
        source.window.contentTabs.pinnedRecords[movedID] = movedRecord
        source.window.lastConfirmedTopNavigationOrder = .init(items: [.contentTab(movedID)])
        source.window.syncContentTabSidebarItems()
        Self.prepareContentTabMoveRequest(request, in: &source)
        var target = try Self.makeContentTabMoveWindow(
            id: targetID,
            tabs: [(targetUnpinnedID, "/target-close-during-unpin/target/anchor")],
        )
        target.window.content.entryViewLayout.entryOperations.windowID = targetID
        target.window.content.entryViewLayout.entryOperations.loadingCancellationOwnerID = targetLoadingOwnerID
        target.window.tabContentStates[targetUnpinnedID] = target.window.content
        let writeGate = PinnedRecordMutationGate()
        let undoBatches = LockIsolated<[[FileOperationUndoScopeMoveDescriptor]]>([])
        let activationWindowIDs = LockIsolated<[WindowManagerFeature.State.WindowID]>([])
        let closedWindowIDs = LockIsolated<[WindowManagerFeature.State.WindowID]>([])
        let targetProbeStarted = expectation(description: "target outgoing loading probe started")
        let targetProbeCancelled = expectation(description: "target outgoing loading probe cancelled")
        var initialState = WindowManagerFeature.State()
        initialState.windows = [source, target]
        let targetCancelID = EntryOperationsLoadingCancelID.loadItems(
            windowID: targetID,
            ownerID: targetLoadingOwnerID,
        )
        let store = TestStore(initialState: initialState) {
            CombineReducers {
                WindowManagerFeature()
                Reduce { _, action in
                    guard case let .windows(.element(
                        id: windowID,
                        action: .window(.view(.dismissContentTabMoveFailure(requestID: probeRequestID))),
                    )) = action,
                        windowID == targetID,
                        probeRequestID == targetProbeRequestID
                    else { return .none }
                    return .run { _ in
                        targetProbeStarted.fulfill()
                        try await withTaskCancellationHandler {
                            try await Task.sleep(for: .seconds(60))
                        } onCancel: {
                            targetProbeCancelled.fulfill()
                        }
                    }
                    .cancellable(id: targetCancelID)
                }
            }
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 606))
            $0.contentTabPinnedRecordClient.reserveTopNavigationOperationToken = { .init(value: UUID(46960)) }
            $0.fileOperationUndoManagerClient.moveScopes = { descriptors in
                undoBatches.withValue { $0.append(descriptors) }
                return .moved
            }
            $0.contentTabPinnedRecordClient.applyDurablePinnedBatchMutationCommitted = { _, _, mutation in
                XCTAssertEqual(mutation.recordsToUpsert, [])
                XCTAssertEqual(mutation.recordIDsToRemove, [movedID.rawValue])
                XCTAssertNil(mutation.pinnedPlacement)
                await writeGate.wait()
                return .init(
                    store: .init(records: [], topNavigationOrder: .init()),
                    topNavigation: .init(order: .init(), revision: 73),
                )
            }
            $0.fileManagerWindowClient.activate = { windowID in
                activationWindowIDs.withValue { $0.append(windowID) }
                return .discarded
            }
            $0.fileManagerWindowClient.close = { windowID in
                closedWindowIDs.withValue { $0.append(windowID) }
            }
            $0.notificationCenterClient.notifications = { _, _ in AsyncStream { $0.finish() } }
        }
        // store.exhaustivity = .off: remove-only persistence와 target close fallback의 최종 ownership만 검증
        store.exhaustivity = .off

        await store.send(.windows(.element(
            id: targetID,
            action: .window(.view(.dismissContentTabMoveFailure(requestID: targetProbeRequestID))),
        )))
        await fulfillment(of: [targetProbeStarted], timeout: 1)
        await store.send(.contentTabMoveRequest(request))
        await store.receive { action in
            guard case let .topNavigationPersistenceRequested(receivedRequest) = action,
                  case .contentTabMove = receivedRequest.operation
            else { return false }
            return receivedRequest.sourceWindowID == sourceID
        }
        await writeGate.waitUntilWaiting()

        await store.send(.event(.windowClosed(targetID)))
        XCTAssertNotNil(store.state.windows[id: targetID])
        XCTAssertTrue(store.state.deferredClosedWindowIDs.contains(targetID))

        await writeGate.open()
        await fulfillment(of: [targetProbeCancelled], timeout: 1)
        await store.skipReceivedActions()
        await store.finish()

        let sourceWindow = try XCTUnwrap(store.state.windows[id: sourceID]?.window)
        XCTAssertEqual(sourceWindow.contentTabs.tabs.map(\.id), [movedID])
        XCTAssertEqual(sourceWindow.contentTabs.tabs[id: movedID]?.isPinned, false)
        XCTAssertEqual(sourceWindow.contentTabs.activeTabID, movedID)
        XCTAssertNotNil(sourceWindow.tabContentStates[movedID])
        XCTAssertNil(store.state.windows[id: targetID])
        XCTAssertEqual(undoBatches.value.count, 2)
        XCTAssertTrue(activationWindowIDs.value.isEmpty)
        XCTAssertTrue(closedWindowIDs.value.isEmpty)
        XCTAssertEqual(store.state.contentTabMoveTerminalRecords[request.requestID]?.outcome, .succeeded)
        XCTAssertNil(store.state.contentTabMoveTransactions[request.requestID])
    }

    /// CTM-001-move_content_tab_to_another_window: queue 제거 뒤 lifecycle 완료 전에도 target close를 유예한다.
    /// active transaction이 남은 commit-to-lifecycle 구간을 persistence participant로 유지해야 한다.
    /// - 검증 내용: queue 없는 active transaction의 target tombstone 유지와 lifecycle 완료 시 원자적 제거
    /// - 사전 조건: source/target window와 pending persistence가 제거된 exact-correlated transaction
    /// - 기대 결과: target close는 deferred 상태를 유지하고 lifecycle 완료가 transaction과 window를 함께 정리한다.
    func testContentTabMoveTargetCloseAfterPersistenceQueueRemovalDefersUntilLifecycleCompletion() async throws {
        let sourceID = UUID(46952)
        let targetID = UUID(46953)
        let movedID = ContentTabID(rawValue: "target-close-after-persistence-moved")
        let request = ContentTabMoveRequest(
            operationID: UUID(46954),
            requestID: UUID(46955),
            sourceWindowID: sourceID,
            initiatingTabID: movedID,
            orderedTabIDs: [movedID],
            targetWindowID: targetID,
        )
        let source = try Self.makeContentTabMoveWindow(
            id: sourceID,
            tabs: [(movedID, "/target-close-after-persistence/source/moved")],
        )
        let target = try Self.makeContentTabMoveWindow(
            id: targetID,
            tabs: [(movedID, "/target-close-after-persistence/target/moved")],
        )
        var initialState = WindowManagerFeature.State()
        initialState.windows = [source, target]
        initialState.contentTabMoveTransactions[request.requestID] = .init(request: request)
        let store = TestStore(initialState: initialState) { WindowManagerFeature() } withDependencies: {
            $0.undoManagerClient.invalidateWindow = { _ in
                .init(succeeded: true, availability: .init())
            }
            $0.fileManagerWindowClient.finalizeClose = { _ in }
        }
        // store.exhaustivity = .off: commit-to-lifecycle participant와 deferred removal 경계만 검증
        store.exhaustivity = .off

        await store.send(.event(.windowClosed(targetID)))

        XCTAssertNotNil(store.state.windows[id: targetID])
        XCTAssertTrue(store.state.closingWindowIDs.contains(targetID))
        XCTAssertTrue(store.state.deferredClosedWindowIDs.contains(targetID))
        XCTAssertEqual(store.state.contentTabMoveTransactions[request.requestID]?.request, request)

        await store.send(.contentTabMoveLifecycleCompleted(request: request))
        await store.skipReceivedActions()
        await store.finish()

        XCTAssertNil(store.state.contentTabMoveTransactions[request.requestID])
        XCTAssertNil(store.state.windows[id: targetID])
        XCTAssertFalse(store.state.closingWindowIDs.contains(targetID))
        XCTAssertFalse(store.state.deferredClosedWindowIDs.contains(targetID))
    }

    /// CTM-001-move_content_tab_to_another_window: commit 뒤 닫힌 participant에는 예약된 action을 전달하지 않는다.
    /// child action 방출 직전 transaction correlation과 window readiness를 다시 검증해야 한다.
    /// - 검증 내용: closing source/target에 대한 committed snapshot action 억제
    /// - 사전 조건: exact-correlated active transaction과 deferred participant tombstone
    /// - 기대 결과: source/target의 confirmed revision이 변경되지 않는다.
    func testContentTabMoveQueuedParticipantActionRevalidatesClosingWindowBeforeDelivery() async throws {
        let sourceID = UUID(46956)
        let targetID = UUID(46957)
        let movedID = ContentTabID(rawValue: "target-close-before-action-moved")
        let request = ContentTabMoveRequest(
            operationID: UUID(46958),
            requestID: UUID(46959),
            sourceWindowID: sourceID,
            initiatingTabID: movedID,
            orderedTabIDs: [movedID],
            targetWindowID: targetID,
        )
        let source = try Self.makeContentTabMoveWindow(
            id: sourceID,
            tabs: [(movedID, "/target-close-before-action/source/moved")],
        )
        let target = try Self.makeContentTabMoveWindow(
            id: targetID,
            tabs: [(movedID, "/target-close-before-action/target/moved")],
        )
        var initialState = WindowManagerFeature.State()
        initialState.windows = [source, target]
        initialState.closingWindowIDs.insert(sourceID)
        initialState.deferredClosedWindowIDs.insert(sourceID)
        initialState.closingWindowIDs.insert(targetID)
        initialState.deferredClosedWindowIDs.insert(targetID)
        initialState.contentTabMoveTransactions[request.requestID] = .init(request: request)
        let store = TestStore(initialState: initialState) { WindowManagerFeature() }
        // store.exhaustivity = .off: closing target에 대한 correlated child action 억제만 검증
        store.exhaustivity = .off

        await store.send(.contentTabMoveWindowActionRequested(
            request: request,
            windowID: targetID,
            action: .applyCommittedTopNavigationSnapshot(
                order: .init(items: [.contentTab(movedID)]),
                revision: 73,
                authoritativePinnedContentTabs: nil,
            ),
        ))
        await store.send(.contentTabMoveWindowActionRequested(
            request: request,
            windowID: sourceID,
            action: .applyCommittedTopNavigationSnapshot(
                order: .init(items: [.contentTab(movedID)]),
                revision: 74,
                authoritativePinnedContentTabs: nil,
            ),
        ))
        await store.finish()

        XCTAssertNil(store.state.windows[id: sourceID]?.window.lastConfirmedTopNavigationCommitRevision)
        XCTAssertNil(store.state.windows[id: targetID]?.window.lastConfirmedTopNavigationCommitRevision)
    }

    /// CTM-001-move_content_tab_to_another_window: newer peer revision은 older correlated completion으로 덮어쓰지 않는다.
    /// source/target commit은 진행하되 peer local selection·active·recentlyClosed는 그대로 남아야 한다.
    /// - 검증 내용: peer older snapshot ignore, source/target commit success, peer local state 보존
    /// - 사전 조건: peer가 더 최신 revision 100을 이미 보유한 상태에서 commit revision 81 도착
    /// - 기대 결과: peer revision/state unchanged, source/target는 81로 commit된다.
    func testContentTabMoveOlderCorrelatedCommitDoesNotOverwriteNewerPeerRevision() async throws {
        let sourceID = UUID(46951)
        let targetID = UUID(46952)
        let peerID = UUID(46953)
        let movedID = ContentTabID(rawValue: "older-peer-moved")
        let remainderID = ContentTabID(rawValue: "older-peer-remainder")
        let request = ContentTabMoveRequest(
            operationID: UUID(46954),
            requestID: UUID(46955),
            sourceWindowID: sourceID,
            initiatingTabID: movedID,
            orderedTabIDs: [movedID],
            targetWindowID: targetID,
            sourceDomain: .unpinned,
            targetDomain: .pinned,
            placement: .empty,
        )
        let source = try Self.makeContentTabMoveWindow(
            id: sourceID,
            tabs: [(movedID, "/older-peer/source/moved"), (remainderID, "/older-peer/source/remainder")],
        )
        let target = WindowSessionState(
            id: targetID,
            window: .makeInitial(path: "/older-peer/target", windowID: targetID),
        )
        var peer = FileManagerWindowFeature.State.makeInitial(path: "/older-peer/peer")
        let peerLocalID = ContentTabID(rawValue: "older-peer-local")
        peer.contentTabs.tabs.append(ContentTabItem(
            id: peerLocalID,
            page: .directory,
            anchor: .directory(path: "/older-peer/local"),
            isPinned: false,
            title: "Local",
            iconName: "folder",
        ))
        peer.contentTabs.activeTabID = peerLocalID
        peer.contentTabs.selectedTabIDs = [peerLocalID]
        peer.contentTabs.selectionAnchorID = peerLocalID
        peer.contentTabs.recentlyClosed = .init(
            page: .directory,
            anchor: .directory(path: "/older-peer/closed"),
            wasPinned: false,
            closedAt: Date(timeIntervalSince1970: 801),
            title: "Closed",
            iconName: "folder",
        )
        peer.lastConfirmedTopNavigationOrder = .init(items: [.location("latest-peer")])
        peer.lastConfirmedTopNavigationCommitRevision = 100
        peer.syncContentTabSidebarItems()
        let peerBefore = peer
        guard case let .success(token) = ContentTabTransfer.preflight(
            source: source.window,
            target: target.window,
            orderedTabIDs: request.orderedTabIDs,
            primaryTabID: request.initiatingTabID,
            sourceDomain: request.sourceDomain,
            targetDomain: request.targetDomain,
            placement: request.placement,
            pinnedAt: Date(timeIntervalSince1970: 802),
        ), case .moved = ContentTabTransfer.apply(token) else {
            return XCTFail("Expected peer revision preflight success")
        }
        let exactRequest = try WindowManagerTopNavigationPersistenceRequest(
            sourceWindowID: sourceID,
            token: .init(value: UUID(46956)),
            operation: .contentTabMove(
                request: request,
                mutation: XCTUnwrap(token.durablePinnedMutation),
                discoveredLocationIDs: [],
            ),
        )
        let result = WindowManagerTopNavigationPersistenceResult(
            request: exactRequest,
            terminal: .committed(.init(order: .init(items: [.contentTab(movedID)]), revision: 81)),
            authoritativePinnedContentTabs: ContentTabState.restoringPinnedRecords(from: .init(records: [
                ContentTabPinnedRecord(
                    id: movedID.rawValue,
                    page: .directory,
                    anchor: .directory(path: "/older-peer/source/moved"),
                    title: nil,
                    iconName: nil,
                    pinnedAt: Date(timeIntervalSince1970: 802),
                ),
            ])).state,
        )
        var initialState = WindowManagerFeature.State()
        initialState.windows = [source, target, .init(id: peerID, window: peer)]
        initialState.topNavigationPersistenceQueue = [exactRequest]
        initialState.isTopNavigationPersistenceInFlight = true
        initialState.contentTabMoveTransactions[request.requestID] = .init(
            request: request,
            pendingPersistence: .init(
                postCommit: {
                    switch ContentTabTransfer.apply(token) {
                    case let .moved(postCommit): postCommit
                    case let .closeSourceWindow(postCommit): postCommit
                    case .rejected: preconditionFailure("Expected validated token")
                    }
                }(),
                closesSourceWindow: false,
                undoDescriptors: [],
            ),
        )
        let store = TestStore(initialState: initialState) { WindowManagerFeature() } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 802))
            $0.fileManagerWindowClient.activate = { _ in .discarded }
            $0.fileManagerWindowClient.close = { _ in }
            $0.notificationCenterClient.notifications = { _, _ in AsyncStream { $0.finish() } }
        }
        store.exhaustivity = .off

        await store.send(.topNavigationPersistenceCompleted(result))
        await store.finish()

        XCTAssertEqual(store.state.windows[id: peerID]?.window.lastConfirmedTopNavigationCommitRevision, 100)
        XCTAssertEqual(
            store.state.windows[id: peerID]?.window.lastConfirmedTopNavigationOrder,
            peerBefore.lastConfirmedTopNavigationOrder,
        )
        XCTAssertEqual(store.state.windows[id: peerID]?.window.contentTabs.activeTabID, peerLocalID)
        XCTAssertEqual(store.state.windows[id: peerID]?.window.contentTabs.selectedTabIDs, [peerLocalID])
        XCTAssertEqual(store.state.windows[id: peerID]?.window.contentTabs.selectionAnchorID, peerLocalID)
        XCTAssertEqual(
            store.state.windows[id: peerID]?.window.contentTabs.recentlyClosed,
            peerBefore.contentTabs.recentlyClosed,
        )
    }

    /// CTM-001-move_content_tab_to_another_window: native undo scope 이전 실패는 logical transfer를 commit하지 않는다.
    /// synchronous precondition 실패 뒤 source/target state와 native window effect가 그대로인지 검증한다.
    /// - 검증 내용: source tab/pending failure, target 부재, terminal rejection, activate/close 호출 횟수
    /// - 사전 조건: source에는 이동 tab과 잔여 tab이 있고 undo registry가 source missing을 반환한다.
    /// - 기대 결과: 탭은 source에 남고 target에 추가되지 않으며 window activate/close effect가 실행되지 않는다.
    func testContentTabMoveUndoScopeFailureRejectsBeforeStateCommitAndEffects() async throws {
        let sourceID = UUID()
        let targetID = UUID()
        let movedTabID = ContentTabID(rawValue: "undo-failure-moved")
        let request = ContentTabMoveRequest(
            requestID: UUID(),
            sourceWindowID: sourceID,
            tabID: movedTabID,
            targetWindowID: targetID,
        )
        var source = try Self.makeContentTabMoveWindow(
            id: sourceID,
            tabs: [
                (movedTabID, "/undo-failure/moved"),
                (ContentTabID(rawValue: "undo-failure-remainder"), "/undo-failure/remainder"),
            ],
        )
        source.window.sidebar.pendingContentTabMoveRequest = request
        source.window.pendingContentTabMove = .init(request: request, lifecycle: .inFlight)
        let target = try Self.makeContentTabMoveWindow(
            id: targetID,
            tabs: [(ContentTabID(rawValue: "undo-failure-target"), "/undo-failure/target")],
        )
        var initialState = WindowManagerFeature.State()
        initialState.windows = [source, target]
        let moveCalls = LockIsolated<[(UndoManagerScope, UndoManagerScope)]>([])
        let activatedIDs = LockIsolated<[UUID]>([])
        let closedIDs = LockIsolated<[UUID]>([])
        let store = TestStore(initialState: initialState) {
            WindowManagerFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 450))
            $0.fileOperationUndoManagerClient.moveScopes = { descriptors in
                guard let descriptor = descriptors.first else { return .emptyBatch }
                moveCalls.withValue { $0.append((descriptor.source, descriptor.target)) }
                return .sourceMissing(descriptor.source)
            }
            $0.fileManagerWindowClient.activate = { id in
                activatedIDs.withValue { $0.append(id) }
                return .discarded
            }
            $0.fileManagerWindowClient.close = { id in closedIDs.withValue { $0.append(id) } }
        }
        store.exhaustivity = .off

        await store.send(.contentTabMoveRequest(request))
        await store.receive { Self.isContentTabMoveRejection($0, request: request, category: .unavailable) }

        XCTAssertEqual(moveCalls.value.count, 1)
        XCTAssertNotNil(store.state.windows[id: sourceID]?.window.contentTabs.tabs[id: movedTabID])
        XCTAssertNil(store.state.windows[id: targetID]?.window.contentTabs.tabs[id: movedTabID])
        XCTAssertEqual(
            store.state.windows[id: sourceID]?.window.contentTabMoveFailurePresentation?.category,
            .unavailable,
        )
        XCTAssertEqual(
            store.state.contentTabMoveTerminalRecords[request.requestID]?.outcome,
            .rejected(.unavailable),
        )
        XCTAssertTrue(activatedIDs.value.isEmpty)
        XCTAssertTrue(closedIDs.value.isEmpty)
    }

    /// CTM-001-move_content_tab_to_another_window: normal window bootstrap과 Sidebar intent가 manager transfer까지 연결된다.
    /// live `.file(.newWindow...)` composition에서 synchronous identity, restored target owner, nested request routing을
    /// 검증한다.
    /// - 검증 내용: 두 child identity, bootstrap pinned owner, Sidebar delegate/request chain, atomic source/target commit과
    /// owner rebind
    /// - 사전 조건: deterministic UUID 네 개, source explicit-path window, target default window의 restored Directory pin
    /// - 기대 결과: terminal success, source에서 tab 제거, target 단일 copy, moved owner의 window/composer context가 target이다.
    func testNormalWindowsMoveContentTabFromSidebarThroughManagerTransfer() async throws {
        let sourceWindowID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000004501"))
        let targetWindowID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000004502"))
        let bootstrapRequestID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000004503"))
        let sourceAppearRequestID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000004504"))
        let targetAppearRequestID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000004505"))
        let moveRequestID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000004506"))
        let generatedUUIDs = LockIsolated([
            sourceWindowID,
            targetWindowID,
            bootstrapRequestID,
            sourceAppearRequestID,
            targetAppearRequestID,
            moveRequestID,
        ])
        let restoredTargetTabID = ContentTabID(rawValue: "restored-target-pin")
        let restoredTargetPath = "/Users/test/TargetPinned"
        let pinnedStore = ContentTabPinnedRecordStore(records: [
            ContentTabPinnedRecord(
                id: restoredTargetTabID.rawValue,
                page: .directory,
                anchor: .directory(path: restoredTargetPath),
                title: "Target Pinned",
                iconName: "folder",
                pinnedAt: Date(timeIntervalSince1970: 450),
            ),
        ])
        let store = TestStore(initialState: WindowManagerFeature.State()) {
            WindowManagerFeature()
        } withDependencies: {
            $0.uuid = UUIDGenerator {
                generatedUUIDs.withValue { values in
                    guard !values.isEmpty else {
                        XCTFail("예상보다 많은 UUID가 요청됨")
                        return UUID(4599)
                    }
                    return values.removeFirst()
                }
            }
            $0.date = .constant(Date(timeIntervalSince1970: 450))
            $0.contentTabPinnedRecordClient.loadStore = { _ in pinnedStore }
            $0.contentTabPinnedRecordClient.saveStore = { _, _ in }
            $0.fileManagerClient.fileExistsWithIsDirectory = { path, isDirectory in
                guard path == restoredTargetPath else { return false }
                isDirectory?.pointee = ObjCBool(true)
                return true
            }
            $0.fileManagerLocationsClient.loadLocations = { _ in [] }
            $0.fileManagerFavoritesClient.loadFavorites = { _, _ in [] }
            $0.fileChangeGatewayClient.observeEvents = { AsyncStream { $0.finish() } }
            $0.onboardingWindowClient.showIfNeeded = { false }
            $0.fileManagerWindowClient.open = { _ in }
            $0.fileManagerWindowClient.registeredWindowIDs = { [sourceWindowID, targetWindowID] }
            $0.fileManagerWindowClient.activate = { _ in .discarded }
            $0.fileManagerWindowClient.close = { _ in }
            $0.fileOperationUndoManagerClient.moveScopes = { _ in .moved }
            $0.notificationCenterClient.notifications = { _, _ in AsyncStream { $0.finish() } }
        }
        // store.exhaustivity = .off: production composition의 lifecycle/app-preference action보다 move terminal과 registry
        // commit을 검증함
        store.exhaustivity = .off

        await store.send(.file(.newWindow(path: "/Users/test/Source")))
        XCTAssertEqual(store.state.windows[id: sourceWindowID]?.window.windowID, sourceWindowID)
        await store.skipReceivedActions()

        await store.send(.file(.newWindow(path: nil)))
        XCTAssertEqual(store.state.windows[id: targetWindowID]?.window.windowID, targetWindowID)
        await store.receive(\.defaultWindowBootstrapCompleted)
        await store.receive { action in
            guard case let .windows(.element(
                id: id,
                action: .window(.applyPinnedContentTabs(contentTabs)),
            )) = action else { return false }
            return id == targetWindowID && contentTabs.tabs[id: restoredTargetTabID] != nil
        }

        let sourceInitialTabID = try XCTUnwrap(store.state.windows[id: sourceWindowID]?.window.contentTabs.activeTabID)
        await store.send(.windows(.element(
            id: sourceWindowID,
            action: .window(.contentTabs(.open(.directory(path: "/Users/test/Source/Remainder")))),
        )))
        await store.skipReceivedActions()
        XCTAssertNotEqual(
            store.state.windows[id: sourceWindowID]?.window.contentTabs.activeTabID,
            sourceInitialTabID,
        )

        await store.send(.windows(.element(id: sourceWindowID, action: .window(.onAppear))))
        await store.send(.windows(.element(id: targetWindowID, action: .window(.onAppear))))
        await store.skipReceivedActions()

        let request = ContentTabMoveRequest(
            requestID: moveRequestID,
            sourceWindowID: sourceWindowID,
            tabID: sourceInitialTabID,
            targetWindowID: targetWindowID,
        )
        await store.send(.windows(.element(
            id: sourceWindowID,
            action: .window(.sidebar(.view(.moveContentTab(
                tabID: sourceInitialTabID,
                targetWindowID: targetWindowID,
            )))),
        )))
        await store.receive { action in
            guard case let .windows(.element(
                id: id,
                action: .window(.sidebar(.delegate(.requestContentTabMove(receivedRequest)))),
            )) = action else { return false }
            return id == sourceWindowID && receivedRequest == request
        }
        await store.receive { action in
            guard case let .windows(.element(
                id: id,
                action: .window(.delegate(.requestContentTabMove(receivedRequest))),
            )) = action else { return false }
            return id == sourceWindowID && receivedRequest == request
        }
        await store.receive(\.contentTabMoveRequest, request)
        await store.skipReceivedActions()
        await store.finish()

        let sourceWindow = try XCTUnwrap(store.state.windows[id: sourceWindowID]?.window)
        let targetWindow = try XCTUnwrap(store.state.windows[id: targetWindowID]?.window)
        XCTAssertNil(sourceWindow.contentTabs.tabs[id: sourceInitialTabID])
        XCTAssertEqual(targetWindow.contentTabs.tabs.count(where: { $0.id == sourceInitialTabID }), 1)
        XCTAssertEqual(
            targetWindow.tabContentStates[sourceInitialTabID]?.entryViewLayout.entryOperations.windowID,
            targetWindowID,
        )
        XCTAssertEqual(targetWindow.tabContentStates[sourceInitialTabID]?.composer.cancellationOwnerID, targetWindowID)
        XCTAssertEqual(store.state.contentTabMoveTerminalRecords[moveRequestID]?.outcome, .succeeded)
        XCTAssertNil(sourceWindow.sidebar.pendingContentTabMoveRequest)
        XCTAssertEqual(generatedUUIDs.value, [])
    }

    /// CTM-001-move_content_tab_to_another_window: app-global pinned projection을 menu로 이동한 뒤 store 재동기화가
    /// source에 재삽입하지 않는다.
    /// source의 exact runtime work unit이 passive target projection을 대체하고 window-local suppression이 sync 경계를 지키는지 검증한다.
    /// - 검증 내용: Sidebar menu 전체 chain, same-ID pinned adoption, source suppression, store resync 후 단일 소유권
    /// - 사전 조건: 두 window에 같은 durable pinned record가 projection되고 source runtime title만 변경되어 있다.
    /// - 기대 결과: 이동과 재동기화 후 source에는 tab이 없고 target에는 source runtime title의 단일 pinned tab이 남는다.
    func testPinnedContentTabMoveSuppressesSourceProjectionAcrossStoreResync() async throws {
        let sourceWindowID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000004507"))
        let targetWindowID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000004508"))
        let requestID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000004509"))
        let pinnedTabID = ContentTabID(rawValue: "global-pinned-move")
        let record = ContentTabPinnedRecord(
            id: pinnedTabID.rawValue,
            page: .directory,
            anchor: .directory(path: "/global/pinned"),
            title: "Durable Projection",
            iconName: "folder",
            pinnedAt: Date(timeIntervalSince1970: 450),
        )
        let pinnedStore = ContentTabPinnedRecordStore(records: [record])
        let undoRegistry = FileOperationUndoManagerRegistry()
        let undoClient = FileOperationUndoManagerClient.live(registry: undoRegistry)
        let sourceUndoScope = UndoManagerScope(windowID: sourceWindowID, contentTabID: pinnedTabID.rawValue)
        let targetUndoScope = UndoManagerScope(windowID: targetWindowID, contentTabID: pinnedTabID.rawValue)
        let sourceUndoManager = try XCTUnwrap(undoClient.activate(sourceUndoScope))
        let replacedTargetUndoManager = try XCTUnwrap(undoClient.activate(targetUndoScope))
        let sourceUndoGeneration = try XCTUnwrap(undoClient.generation(sourceUndoScope))
        let sourceUndoRecord = EntryActionRecord(operationKind: .rename, targets: [])
        XCTAssertTrue(undoClient.registerUndo(sourceUndoScope, sourceUndoGeneration, sourceUndoRecord))
        let restoredPinnedState = ContentTabState.restoringPinnedRecords(
            from: pinnedStore,
            isRestorableAnchor: { _ in true },
        ).state
        var source = FileManagerWindowFeature.State.makeInitial(
            path: "/source/remainder",
            windowID: sourceWindowID,
        )
        var target = FileManagerWindowFeature.State.makeInitial(
            path: "/target/remainder",
            windowID: targetWindowID,
        )
        source.applyPinnedContentTabs(restoredPinnedState)
        target.applyPinnedContentTabs(restoredPinnedState)
        source.contentTabs.tabs[id: pinnedTabID]?.title = "Source Runtime"

        let request = ContentTabMoveRequest(
            requestID: requestID,
            sourceWindowID: sourceWindowID,
            tabID: pinnedTabID,
            targetWindowID: targetWindowID,
        )
        var initialState = WindowManagerFeature.State()
        initialState.windows = [
            .init(id: sourceWindowID, window: source),
            .init(id: targetWindowID, window: target),
        ]
        initialState.refreshContentTabMoveTargets()

        let store = TestStore(initialState: initialState) {
            WindowManagerFeature()
        } withDependencies: {
            $0.uuid = .constant(requestID)
            $0.date = .constant(Date(timeIntervalSince1970: 450))
            $0.contentTabPinnedRecordClient.loadStore = { _ in pinnedStore }
            $0.fileManagerWindowClient.activate = { _ in .discarded }
            $0.fileOperationUndoManagerClient = undoClient
            $0.notificationCenterClient.notifications = { _, _ in AsyncStream { $0.finish() } }
        }
        // store.exhaustivity = .off: post-commit runtime effect보다 registry commit과 pinned-store 재동기화 결과를 검증한다.
        store.exhaustivity = .off

        await store.send(.windows(.element(
            id: sourceWindowID,
            action: .window(.sidebar(.view(.moveContentTab(
                tabID: pinnedTabID,
                targetWindowID: targetWindowID,
            )))),
        )))
        await store.receive { action in
            guard case let .windows(.element(
                id: id,
                action: .window(.sidebar(.delegate(.requestContentTabMove(receivedRequest)))),
            )) = action else { return false }
            return id == sourceWindowID && receivedRequest == request
        }
        await store.receive { action in
            guard case let .windows(.element(
                id: id,
                action: .window(.delegate(.requestContentTabMove(receivedRequest))),
            )) = action else { return false }
            return id == sourceWindowID && receivedRequest == request
        }
        await store.receive(\.contentTabMoveRequest, request)
        await store.skipReceivedActions()

        XCTAssertNil(store.state.windows[id: sourceWindowID]?.window.contentTabs.tabs[id: pinnedTabID])
        XCTAssertEqual(
            store.state.windows[id: sourceWindowID]?.window.suppressedPinnedTabIDs,
            [pinnedTabID],
        )
        XCTAssertEqual(
            store.state.windows[id: targetWindowID]?.window.contentTabs.tabs[id: pinnedTabID]?.title,
            "Source Runtime",
        )
        XCTAssertEqual(store.state.contentTabMoveTerminalRecords[requestID]?.outcome, .succeeded)

        await store.send(.pinnedContentTabsStoreChanged)
        await store.skipReceivedActions()
        await store.finish()

        XCTAssertNil(store.state.windows[id: sourceWindowID]?.window.contentTabs.tabs[id: pinnedTabID])
        XCTAssertEqual(
            store.state.windows[id: sourceWindowID]?.window.suppressedPinnedTabIDs,
            [pinnedTabID],
        )
        XCTAssertEqual(
            store.state.windows[id: targetWindowID]?.window.contentTabs.tabs.count(where: { $0.id == pinnedTabID }),
            1,
        )
        XCTAssertEqual(
            store.state.windows[id: targetWindowID]?.window.contentTabs.tabs[id: pinnedTabID]?.title,
            "Source Runtime",
        )
        XCTAssertEqual(
            store.state.windows[id: targetWindowID]?.window.suppressedPinnedTabIDs,
            [],
        )
        let removedSourceUndoManager = await undoClient.undoManager(sourceUndoScope)
        let movedTargetUndoManagerValue = await undoClient.undoManager(targetUndoScope)
        let movedTargetUndoManager = try XCTUnwrap(movedTargetUndoManagerValue)
        XCTAssertNil(removedSourceUndoManager)
        XCTAssertIdentical(sourceUndoManager, movedTargetUndoManager)
        XCTAssertNotIdentical(replacedTargetUndoManager, movedTargetUndoManager)
        XCTAssertEqual(undoClient.generation(targetUndoScope), sourceUndoGeneration)
        XCTAssertEqual(
            undoClient.performUndoRedo(targetUndoScope, sourceUndoGeneration, .undo, sourceUndoRecord.id),
            .applied,
        )
    }

    /// CTM-001-move_content_tab_to_another_window: target drop delegate가 source-owned request와 atomic transfer를 구동한다.
    /// drag payload는 locator로만 사용되고 target window ID는 nested identified action에서 도출되는 전체 chain을 검증한다.
    /// - 검증 내용: target delegate, source Sidebar 기존 move action, source UUID/pending, request, atomic terminal success.
    /// - 사전 조건: source에 moved/remainder tab, target에 기존 tab, stale하지 않은 target projection이 있다.
    /// - 기대 결과: source에서 moved tab이 제거되고 target에 정확히 한 copy와 success terminal이 남는다.
    func testContentTabDropRoutesToSourceOwnedAtomicMovePipeline() async throws {
        let sourceWindowID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000004511"))
        let targetWindowID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000004512"))
        let requestID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000004513"))
        let movedTabID = ContentTabID(rawValue: "drop-chain-moved")
        let remainderTabID = ContentTabID(rawValue: "drop-chain-remainder")
        let targetTabID = ContentTabID(rawValue: "drop-chain-target")
        let payload = ContentTabDragPayload(
            schemaVersion: ContentTabDragPayload.supportedSchemaVersion,
            sourceWindowID: sourceWindowID,
            tabID: movedTabID,
        )
        let request = try ContentTabMoveRequest(
            operationID: XCTUnwrap(payload.operationID),
            requestID: requestID,
            sourceWindowID: sourceWindowID,
            initiatingTabID: movedTabID,
            orderedTabIDs: [movedTabID],
            targetWindowID: targetWindowID,
        )
        var source = try Self.makeContentTabMoveWindow(
            id: sourceWindowID,
            tabs: [(movedTabID, "/drop/source"), (remainderTabID, "/drop/remainder")],
        )
        source.window.sidebar.contentTabDragSnapshot = try ContentTabDragSnapshot(
            operationID: XCTUnwrap(payload.operationID),
            sourceWindowID: sourceWindowID,
            initiatingTabID: movedTabID,
            orderedTabIDs: [movedTabID],
            lifecycle: .inFlight,
        )
        let target = try Self.makeContentTabMoveWindow(
            id: targetWindowID,
            tabs: [(targetTabID, "/drop/target")],
        )
        var initialState = WindowManagerFeature.State()
        initialState.windows = [source, target]
        initialState.refreshContentTabMoveTargets()
        let store = TestStore(initialState: initialState) {
            WindowManagerFeature()
        } withDependencies: {
            $0.uuid = .constant(requestID)
            $0.date = .constant(Date(timeIntervalSince1970: 450))
            $0.fileManagerLocationsClient.loadLocations = { _ in [] }
            $0.fileManagerFavoritesClient.loadFavorites = { _, _ in [] }
            $0.fileChangeGatewayClient.observeEvents = { AsyncStream { $0.finish() } }
            $0.fileManagerWindowClient.activate = { _ in .discarded }
            $0.fileOperationUndoManagerClient.moveScopes = { _ in .moved }
            $0.notificationCenterClient.notifications = { _, _ in AsyncStream { $0.finish() } }
        }
        // store.exhaustivity = .off: post-commit lifecycle보다 drop routing 경계와 atomic registry 결과를 검증한다.
        store.exhaustivity = .off

        await store.send(.windows(.element(id: sourceWindowID, action: .window(.onAppear))))
        await store.send(.windows(.element(id: targetWindowID, action: .window(.onAppear))))
        await store.skipReceivedActions()

        await assertContentTabDropRoute(store, payload: payload, request: request)
        await store.skipReceivedActions()
        await store.finish()

        XCTAssertNil(store.state.windows[id: sourceWindowID]?.window.contentTabs.tabs[id: movedTabID])
        XCTAssertEqual(
            store.state.windows[id: targetWindowID]?.window.contentTabs.tabs.count(where: { $0.id == movedTabID }),
            1,
        )
        XCTAssertEqual(store.state.contentTabMoveTerminalRecords[requestID]?.outcome, .succeeded)
    }

    /// CTM-001-move_content_tab_to_another_window: app Info.plist는 drag payload UTI를 public.json으로 export한다.
    /// 코드의 Transferable UTI와 LaunchServices bundle declaration이 동일한 계약을 제공하는지 검증한다.
    /// - 검증 내용: identifier, public.json 단일 conformance, filename/MIME tag 부재.
    /// - 사전 조건: Voyager app target의 canonical Config/Info.plist를 읽을 수 있다.
    /// - 기대 결과: matching exported declaration이 있고 tag specification은 존재하지 않는다.
    func testContentTabDragUTIDeclarationExportsPublicJSONWithoutFilenameOrMIMETags() throws {
        let voyagerProjectRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let infoPlistURL = voyagerProjectRoot.appendingPathComponent("Voyager/Config/Info.plist")
        let data = try Data(contentsOf: infoPlistURL)
        let plist = try XCTUnwrap(
            PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
        )
        let declarations = try XCTUnwrap(plist["UTExportedTypeDeclarations"] as? [[String: Any]])
        let declaration = try XCTUnwrap(declarations.first {
            $0["UTTypeIdentifier"] as? String == "com.voyager.app.content-tab-drag-payload"
        })

        XCTAssertEqual(declaration["UTTypeConformsTo"] as? [String], ["public.json"])
        XCTAssertNil(declaration["UTTypeTagSpecification"])
    }

    /// CTM-001-move_content_tab_to_another_window: pending duplicate와 committed repeat drop은 request/copy를 추가하지 않는다.
    /// source Sidebar의 single pending ownership과 source tab 소멸 후 locator 무효화를 각각 검증한다.
    /// - 검증 내용: pending request identity 보존, terminal/effect 미생성, committed target copy count 유지.
    /// - 사전 조건: matching pending source 상태와 이미 moved tab이 target에만 있는 post-commit 상태를 각각 구성한다.
    /// - 기대 결과: 두 callback 모두 source move action 이후 no-op이며 새 request UUID나 copy가 생기지 않는다.
    func testContentTabDropDuplicateWhilePendingAndRepeatAfterCommitAreNoOps() async throws {
        let sourceWindowID = UUID()
        let targetWindowID = UUID()
        let movedTabID = ContentTabID(rawValue: "drop-duplicate-moved")
        let remainderTabID = ContentTabID(rawValue: "drop-duplicate-remainder")
        let targetTabID = ContentTabID(rawValue: "drop-duplicate-target")
        let payload = ContentTabDragPayload(
            schemaVersion: ContentTabDragPayload.supportedSchemaVersion,
            sourceWindowID: sourceWindowID,
            tabID: movedTabID,
        )
        let pendingRequest = try ContentTabMoveRequest(
            operationID: XCTUnwrap(payload.operationID),
            requestID: UUID(),
            sourceWindowID: sourceWindowID,
            initiatingTabID: movedTabID,
            orderedTabIDs: [movedTabID],
            targetWindowID: targetWindowID,
        )

        try await assertPendingContentTabDropIsNoOp(
            payload: payload,
            pendingRequest: pendingRequest,
            remainderTabID: remainderTabID,
            targetTabID: targetTabID,
        )
        try await assertCommittedContentTabDropIsNoOp(
            payload: payload,
            targetWindowID: targetWindowID,
            remainderTabID: remainderTabID,
            targetTabID: targetTabID,
        )
    }

    /// CTM-001-move_content_tab_to_another_window: closing source 또는 target drop은 request 전에 거부한다.
    /// stale projection이 남아 있어도 registry readiness가 닫히는 창으로 semantic request를 전달하지 않는지 검증한다.
    /// - 검증 내용: source/target closing 각각의 whole-state no-op과 pending/terminal 미생성
    /// - 사전 조건: 두 live window 중 하나가 closing set에 있고 target delegate가 v2 payload를 전달한다.
    /// - 기대 결과: 두 경우 모두 source/target/pending/terminal state가 정확히 보존된다.
    func testContentTabDropWithClosingSourceOrTargetIsNoOp() async throws {
        let sourceWindowID = UUID()
        let targetWindowID = UUID()
        let movedTabID = ContentTabID(rawValue: "drop-closing-moved")
        let remainderTabID = ContentTabID(rawValue: "drop-closing-remainder")
        let targetTabID = ContentTabID(rawValue: "drop-closing-target")
        let payload = ContentTabDragPayload(
            schemaVersion: ContentTabDragPayload.supportedSchemaVersion,
            sourceWindowID: sourceWindowID,
            tabID: movedTabID,
        )
        let source = try Self.makeContentTabMoveWindow(
            id: sourceWindowID,
            tabs: [(movedTabID, "/drop/closing/moved"), (remainderTabID, "/drop/closing/remainder")],
        )
        let target = try Self.makeContentTabMoveWindow(
            id: targetWindowID,
            tabs: [(targetTabID, "/drop/closing/target")],
        )

        for closingWindowID in [sourceWindowID, targetWindowID] {
            var initialState = WindowManagerFeature.State()
            initialState.windows = [source, target]
            initialState.closingWindowIDs = [closingWindowID]
            initialState.windows[id: sourceWindowID]?.window.sidebar.currentWindowID = sourceWindowID
            initialState.windows[id: sourceWindowID]?.window.sidebar.contentTabMoveTargets = [
                ContentTabMoveTarget(windowID: targetWindowID, displayTitle: "Closing"),
            ]
            let store = TestStore(initialState: initialState) { WindowManagerFeature() }
            let beforeDrop = store.state

            await store.send(.windows(.element(
                id: targetWindowID,
                action: .window(.delegate(.receiveContentTabDrag(payload))),
            )))
            XCTAssertEqual(store.state, beforeDrop)
            await store.finish()
        }
    }

    private func assertContentTabDropRoute(
        _ store: TestStoreOf<WindowManagerFeature>,
        payload: ContentTabDragPayload,
        request: ContentTabMoveRequest,
    ) async {
        await store.send(.windows(.element(
            id: request.targetWindowID,
            action: .window(.delegate(.receiveContentTabDrag(payload))),
        )))
        await store.receive {
            Self.isContentTabDropSourceMove($0, request: request)
        }
        XCTAssertEqual(
            store.state.windows[id: request.sourceWindowID]?.window.sidebar.pendingContentTabMoveRequest,
            request,
        )
        await store.receive {
            guard case let .windows(.element(
                id: id,
                action: .window(.sidebar(.delegate(.requestContentTabMove(receivedRequest)))),
            )) = $0 else { return false }
            return id == request.sourceWindowID && receivedRequest == request
        }
        await store.receive {
            guard case let .windows(.element(
                id: id,
                action: .window(.delegate(.requestContentTabMove(receivedRequest))),
            )) = $0 else { return false }
            return id == request.sourceWindowID && receivedRequest == request
        }
        await store.receive(\.contentTabMoveRequest, request)
    }

    private func assertPendingContentTabDropIsNoOp(
        payload: ContentTabDragPayload,
        pendingRequest: ContentTabMoveRequest,
        remainderTabID: ContentTabID,
        targetTabID: ContentTabID,
    ) async throws {
        var source = try Self.makeContentTabMoveWindow(
            id: pendingRequest.sourceWindowID,
            tabs: [(payload.tabID, "/drop/duplicate/moved"), (remainderTabID, "/drop/duplicate/remainder")],
        )
        source.window.sidebar.pendingContentTabMoveRequest = pendingRequest
        source.window.pendingContentTabMove = .init(request: pendingRequest, lifecycle: .inFlight)
        let target = try Self.makeContentTabMoveWindow(
            id: pendingRequest.targetWindowID,
            tabs: [(targetTabID, "/drop/duplicate/target")],
        )
        var state = WindowManagerFeature.State()
        state.windows = [source, target]
        state.refreshContentTabMoveTargets()
        state.windows[id: pendingRequest.sourceWindowID]?.window.sidebar.pendingContentTabMoveRequest = pendingRequest
        state.windows[id: pendingRequest.sourceWindowID]?.window.pendingContentTabMove = .init(
            request: pendingRequest,
            lifecycle: .inFlight,
        )
        let store = TestStore(initialState: state) { WindowManagerFeature() }

        await store.send(.windows(.element(
            id: pendingRequest.targetWindowID,
            action: .window(.delegate(.receiveContentTabDrag(payload))),
        )))
        await store.receive { Self.isContentTabDropSourceMove($0, request: pendingRequest) }
        await store.finish()
        XCTAssertEqual(
            store.state.windows[id: pendingRequest.sourceWindowID]?.window.sidebar.pendingContentTabMoveRequest,
            pendingRequest,
        )
        XCTAssertTrue(store.state.contentTabMoveTerminalRecords.isEmpty)
        XCTAssertNil(store.state.windows[id: pendingRequest.targetWindowID]?.window.contentTabs.tabs[id: payload.tabID])
    }

    private func assertCommittedContentTabDropIsNoOp(
        payload: ContentTabDragPayload,
        targetWindowID: UUID,
        remainderTabID: ContentTabID,
        targetTabID: ContentTabID,
    ) async throws {
        let source = try Self.makeContentTabMoveWindow(
            id: payload.sourceWindowID,
            tabs: [(remainderTabID, "/drop/committed/remainder")],
        )
        let target = try Self.makeContentTabMoveWindow(
            id: targetWindowID,
            tabs: [(targetTabID, "/drop/committed/target"), (payload.tabID, "/drop/committed/moved")],
        )
        var state = WindowManagerFeature.State()
        state.windows = [source, target]
        state.refreshContentTabMoveTargets()
        let store = TestStore(initialState: state) { WindowManagerFeature() }
        let request = ContentTabMoveRequest(
            operationID: payload.operationID ?? UUID(),
            requestID: UUID(),
            sourceWindowID: payload.sourceWindowID,
            initiatingTabID: payload.initiatingTabID,
            orderedTabIDs: payload.orderedTabIDs,
            targetWindowID: targetWindowID,
        )

        await store.send(.windows(.element(
            id: targetWindowID,
            action: .window(.delegate(.receiveContentTabDrag(payload))),
        )))
        await store.receive { Self.isContentTabDropSourceMove($0, request: request) }
        await store.finish()
        XCTAssertTrue(store.state.contentTabMoveTerminalRecords.isEmpty)
        XCTAssertEqual(
            store.state.windows[id: targetWindowID]?.window.contentTabs.tabs.count(where: { $0.id == payload.tabID }),
            1,
        )
    }

    private static func isContentTabDropSourceMove(
        _ action: WindowManagerFeature.Action,
        request: ContentTabMoveRequest,
    ) -> Bool {
        guard case let .windows(.element(
            id: id,
            action: .window(.sidebar(.view(.moveContentTabs(
                payload: payload, targetWindowID: targetID, targetDomain: _, placement: _,
            )))),
        )) = action else { return false }
        return id == request.sourceWindowID
            && payload.operationID == request.operationID
            && payload.sourceWindowID == request.sourceWindowID
            && payload.initiatingTabID == request.initiatingTabID
            && payload.orderedTabIDs == request.orderedTabIDs
            && targetID == request.targetWindowID
    }

    private static func isContentTabMoveRejection(
        _ action: WindowManagerFeature.Action,
        request: ContentTabMoveRequest,
        category: ContentTabMoveFailurePresentation.Category,
    ) -> Bool {
        guard case let .windows(.element(
            id: id,
            action: .window(.contentTabMoveRejected(receivedRequest, receivedCategory)),
        )) = action else { return false }
        return id == request.sourceWindowID
            && receivedRequest == request
            && receivedCategory == category
    }

    /// CTM-001-move_content_tab_to_another_window: live MRU와 registry fallback으로 target projection을 만든다.
    /// focus callback 뒤 모든 live child가 동일한 canonical 순서를 투영하는지 검증한다.
    /// - 검증 내용: source 제외 target ID 순서와 중복 title 구분
    /// - 사전 조건: 같은 title의 세 live File Manager window가 존재한다.
    /// - 기대 결과: MRU 우선 순서와 안정적 registry fallback이 각 source projection에 반영된다.
    func testContentTabMoveTargetsUseLiveMRUThenRegistryFallback() async throws {
        let firstID = UUID()
        let secondID = UUID()
        let thirdID = UUID()
        let firstTabID = ContentTabID(rawValue: "projection-first")
        let secondTabID = ContentTabID(rawValue: "projection-second")
        let thirdTabID = ContentTabID(rawValue: "projection-third")
        var first = try XCTUnwrap(FileManagerWindowFeature.State.makeExternalInitial(
            reservations: [.init(id: firstTabID, anchor: .directory(path: "/shared"))],
            windowID: firstID,
        ))
        var second = try XCTUnwrap(FileManagerWindowFeature.State.makeExternalInitial(
            reservations: [.init(id: secondTabID, anchor: .directory(path: "/shared"))],
            windowID: secondID,
        ))
        var third = try XCTUnwrap(FileManagerWindowFeature.State.makeExternalInitial(
            reservations: [.init(id: thirdTabID, anchor: .directory(path: "/shared"))],
            windowID: thirdID,
        ))
        first.contentTabs.tabs[id: firstTabID]?.title = "Shared"
        second.contentTabs.tabs[id: secondTabID]?.title = "Shared"
        third.contentTabs.tabs[id: thirdTabID]?.title = "Shared"
        var initialState = WindowManagerFeature.State()
        initialState.windows = [
            .init(id: firstID, window: first),
            .init(id: secondID, window: second),
            .init(id: thirdID, window: third),
        ]
        initialState.lastUsedWindowIDs = [thirdID]
        let store = TestStore(initialState: initialState) {
            WindowManagerFeature()
        }

        await store.send(.event(.windowBecameKey(secondID))) {
            $0.focusedWindowID = secondID
            $0.lastUsedWindowIDs = [secondID, thirdID]
            $0.refreshContentTabMoveTargets()
        }

        XCTAssertEqual(
            store.state.windows[id: firstID]?.window.sidebar.contentTabMoveTargets.map(\.windowID),
            [secondID, thirdID],
        )
        XCTAssertEqual(
            store.state.windows[id: firstID]?.window.sidebar.contentTabMoveTargets.map(\.displayTitle),
            ["Shared — Window 1", "Shared — Window 2"],
        )
    }

    /// CTM-001-move_content_tab_to_another_window: projection 뒤 사라진 target은 unavailable로 종료한다.
    /// - 검증 내용: source semantic state 보존, matching pending terminal, rejection ledger
    /// - 사전 조건: source가 stale target을 가리키는 matching pending request를 보유한다.
    /// - 기대 결과: tab registry는 불변이고 source에 unavailable presentation만 남는다.
    func testContentTabMoveRejectsStaleTargetWithoutSemanticMutation() async throws {
        let sourceID = UUID()
        let staleTargetID = UUID()
        let tabID = ContentTabID(rawValue: "stale-target-tab")
        let request = ContentTabMoveRequest(
            requestID: UUID(),
            sourceWindowID: sourceID,
            tabID: tabID,
            targetWindowID: staleTargetID,
        )
        var source = try Self.makeContentTabMoveWindow(
            id: sourceID,
            tabs: [(tabID, "/stale/source")],
        )
        source.window.sidebar.pendingContentTabMoveRequest = request
        source.window.pendingContentTabMove = .init(request: request, lifecycle: .inFlight)
        let originalTabs = source.window.contentTabs.tabs
        var initialState = WindowManagerFeature.State()
        initialState.windows = [source]
        let store = TestStore(initialState: initialState) { WindowManagerFeature() }
        // store.exhaustivity = .off: rejection의 semantic state와 terminal 결과만 검증한다.
        store.exhaustivity = .off

        await store.send(.contentTabMoveRequest(request))
        await store.receive { Self.isContentTabMoveRejection($0, request: request, category: .unavailable) }

        XCTAssertEqual(store.state.windows[id: sourceID]?.window.contentTabs.tabs, originalTabs)
        XCTAssertNil(store.state.windows[id: sourceID]?.window.sidebar.pendingContentTabMoveRequest)
        XCTAssertEqual(
            store.state.windows[id: sourceID]?.window.contentTabMoveFailurePresentation,
            .init(requestID: request.requestID, category: .unavailable),
        )
        XCTAssertEqual(
            store.state.contentTabMoveTerminalRecords[request.requestID]?.outcome,
            .rejected(.unavailable),
        )
    }

    /// CTM-001-move_content_tab_to_another_window: stale request는 newer pending identity를 지우지 않는다.
    /// - 검증 내용: full request identity 재검증과 stale presentation 차단
    /// - 사전 조건: source pending request ID가 전달된 request와 다르다.
    /// - 기대 결과: newer pending은 유지되고 stale request만 ledger에 unavailable로 기록된다.
    func testContentTabMovePreservesNewerPendingIdentityOnStaleRequest() async throws {
        let sourceID = UUID()
        let targetID = UUID()
        let tabID = ContentTabID(rawValue: "stale-pending-tab")
        let staleRequest = ContentTabMoveRequest(
            requestID: UUID(),
            sourceWindowID: sourceID,
            tabID: tabID,
            targetWindowID: targetID,
        )
        let currentRequest = ContentTabMoveRequest(
            requestID: UUID(),
            sourceWindowID: sourceID,
            tabID: tabID,
            targetWindowID: targetID,
        )
        var source = try Self.makeContentTabMoveWindow(id: sourceID, tabs: [(tabID, "/pending/source")])
        source.window.sidebar.pendingContentTabMoveRequest = currentRequest
        source.window.pendingContentTabMove = .init(request: currentRequest, lifecycle: .inFlight)
        let target = try Self.makeContentTabMoveWindow(
            id: targetID,
            tabs: [(ContentTabID(rawValue: "pending-target"), "/pending/target")],
        )
        var initialState = WindowManagerFeature.State()
        initialState.windows = [source, target]
        let store = TestStore(initialState: initialState) { WindowManagerFeature() }

        await store.send(.contentTabMoveRequest(staleRequest)) {
            $0.recordContentTabMoveTerminal(.init(request: staleRequest, outcome: .rejected(.unavailable)))
        }
        await store.receive {
            Self.isContentTabMoveRejection($0, request: staleRequest, category: .unavailable)
        }

        XCTAssertEqual(store.state.windows[id: sourceID]?.window.sidebar.pendingContentTabMoveRequest, currentRequest)
        XCTAssertNil(store.state.windows[id: sourceID]?.window.contentTabMoveFailurePresentation)
    }

    /// CTM-001-move_content_tab_to_another_window: Task 2 rejection을 네 presentation category로 제한한다.
    /// - 검증 내용: capacity, busy, generic mapping과 terminal ledger
    /// - 사전 조건: full target, pending pin source, target tab collision을 각각 구성한다.
    /// - 기대 결과: invariant identifier를 노출하지 않고 지정된 category만 전달한다.
    func testContentTabMoveMapsStructuredRejectionsToPresentationCategories() async throws {
        let movedTabID = ContentTabID(rawValue: "mapped-rejection-tab")

        func assertRejection(
            source: WindowSessionState,
            target: WindowSessionState,
            category: ContentTabMoveFailurePresentation.Category,
        ) async {
            let request = ContentTabMoveRequest(
                requestID: UUID(),
                sourceWindowID: source.id,
                tabID: movedTabID,
                targetWindowID: target.id,
            )
            var source = source
            source.window.sidebar.pendingContentTabMoveRequest = request
            source.window.pendingContentTabMove = .init(request: request, lifecycle: .inFlight)
            let sourceBefore = source.window
            let targetBefore = target.window
            var initialState = WindowManagerFeature.State()
            initialState.windows = [source, target]
            let store = TestStore(initialState: initialState) { WindowManagerFeature() }
            // store.exhaustivity = .off: presentation terminal과 semantic atomicity만 검증한다.
            store.exhaustivity = .off

            await store.send(.contentTabMoveRequest(request))
            await store.receive { Self.isContentTabMoveRejection($0, request: request, category: category) }

            var expectedSource = sourceBefore
            expectedSource.sidebar.pendingContentTabMoveRequest = nil
            expectedSource.pendingContentTabMove = nil
            expectedSource.contentTabMoveFailurePresentation = .init(
                requestID: request.requestID,
                category: category,
            )
            XCTAssertEqual(store.state.windows[id: source.id]?.window, expectedSource)
            XCTAssertEqual(store.state.windows[id: target.id]?.window, targetBefore)
            XCTAssertEqual(store.state.contentTabMoveTerminalRecords[request.requestID]?.outcome, .rejected(category))
        }

        let capacitySource = try Self.makeContentTabMoveWindow(
            id: UUID(),
            tabs: [(movedTabID, "/mapping/capacity/source")],
        )
        let fullTabs = (0 ..< ContentTabConstants.maxTabs).map { index in
            (ContentTabID(rawValue: "mapping-capacity-\(index)"), "/mapping/capacity/\(index)")
        }
        let capacityTarget = try Self.makeContentTabMoveWindow(id: UUID(), tabs: fullTabs)
        await assertRejection(source: capacitySource, target: capacityTarget, category: .capacity)

        var busySource = try Self.makeContentTabMoveWindow(
            id: UUID(),
            tabs: [(movedTabID, "/mapping/busy/source")],
        )
        busySource.window.contentTabs.pendingPinnedRecordIDs = [movedTabID]
        let busyTarget = try Self.makeContentTabMoveWindow(
            id: UUID(),
            tabs: [(ContentTabID(rawValue: "mapping-busy-target"), "/mapping/busy/target")],
        )
        await assertRejection(source: busySource, target: busyTarget, category: .busy)

        let restoringSessionID = AiChatSessionID(rawValue: UUID())
        var restoringSource = try Self.makeContentTabMoveWindow(
            id: UUID(),
            tabs: [(movedTabID, "/mapping/restoring/source")],
        )
        restoringSource.window.content.aiChat.sessionID = restoringSessionID
        restoringSource.window.content.aiChat.restoreSessionID = restoringSessionID
        restoringSource.window.content.aiChat.sessionStatus = .restoring
        restoringSource.window.tabContentStates[movedTabID] = restoringSource.window.content
        let restoringTarget = try Self.makeContentTabMoveWindow(
            id: UUID(),
            tabs: [(ContentTabID(rawValue: "mapping-restoring-target"), "/mapping/restoring/target")],
        )
        await assertRejection(source: restoringSource, target: restoringTarget, category: .busy)

        var composerBusySource = try Self.makeContentTabMoveWindow(
            id: UUID(),
            tabs: [(movedTabID, "/mapping/composer/source")],
        )
        composerBusySource.window.content.composer.activeSearchRequestID = UUID()
        composerBusySource.window.content.composer.isLoadingSearch = true
        composerBusySource.window.tabContentStates[movedTabID] = composerBusySource.window.content
        let composerBusyTarget = try Self.makeContentTabMoveWindow(
            id: UUID(),
            tabs: [(ContentTabID(rawValue: "mapping-composer-target"), "/mapping/composer/target")],
        )
        await assertRejection(source: composerBusySource, target: composerBusyTarget, category: .busy)

        let inspectorBusySource = try Self.makeContentTabMoveWindow(
            id: UUID(),
            tabs: [(movedTabID, "/mapping/inspector/source")],
        )
        let inspectorBusyTargetID = ContentTabID(rawValue: "mapping-inspector-target")
        var inspectorBusyTarget = try Self.makeContentTabMoveWindow(
            id: UUID(),
            tabs: [(inspectorBusyTargetID, "/mapping/inspector/target")],
        )
        inspectorBusyTarget.window.inspector.aiChat.modelListRequestID = UUID()
        inspectorBusyTarget.window.tabInspectorStates[inspectorBusyTargetID] = inspectorBusyTarget.window.inspector
            .tabSnapshot()
        await assertRejection(source: inspectorBusySource, target: inspectorBusyTarget, category: .busy)

        var malformedSource = try Self.makeContentTabMoveWindow(
            id: UUID(),
            tabs: [(movedTabID, "/mapping/malformed/source")],
        )
        malformedSource.window.content.pendingSelectEntryID = "ambiguous-live-owner"
        let malformedTarget = try Self.makeContentTabMoveWindow(
            id: UUID(),
            tabs: [(ContentTabID(rawValue: "mapping-malformed-target"), "/mapping/malformed/target")],
        )
        await assertRejection(source: malformedSource, target: malformedTarget, category: .generic)

        let genericSource = try Self.makeContentTabMoveWindow(
            id: UUID(),
            tabs: [(movedTabID, "/mapping/generic/source")],
        )
        let genericTarget = try Self.makeContentTabMoveWindow(
            id: UUID(),
            tabs: [(movedTabID, "/mapping/generic/target")],
        )
        await assertRejection(source: genericSource, target: genericTarget, category: .generic)
    }

    /// CTM-001-move_content_tab_to_another_window: 다른 창의 전역 pin 저장 중에는 이동을 busy로 거부한다.
    /// mutation source가 이동 source와 달라도 같은 tab의 authoritative store sync race를 차단하는지 검증한다.
    /// - 검증 내용: upsert/remove별 source/target/owner/global mutation 보존과 move/activate/close 미호출
    /// - 사전 조건: 별도 owner window가 이동 tab과 같은 ID의 전역 pinned record mutation을 소유한다.
    /// - 기대 결과: move는 busy로 reject되고 pending/presentation/terminal 외 semantic state와 effect는 변하지 않는다.
    func testContentTabMoveRejectsWhenSameTabPinnedRecordMutationIsInFlightInAnyWindow() async throws {
        let movedTabID = ContentTabID(rawValue: "global-pin-mutation-moved")
        let pinnedRecord = ContentTabPinnedRecord(
            id: movedTabID.rawValue,
            page: .directory,
            anchor: .directory(path: "/global-pin-mutation/moved"),
            title: "Moved",
            iconName: "folder",
            pinnedAt: Date(timeIntervalSince1970: 450),
        )
        let mutations: [ContentTabPinnedRecordPersistenceMutation] = [
            .upsert(record: pinnedRecord, dormantSlot: nil),
            .remove(recordID: movedTabID.rawValue),
        ]

        for mutation in mutations {
            let sourceID = UUID()
            let targetID = UUID()
            let mutationOwnerID = UUID()
            let mutationID = UUID()
            let request = ContentTabMoveRequest(
                requestID: UUID(),
                sourceWindowID: sourceID,
                tabID: movedTabID,
                targetWindowID: targetID,
            )
            var source = try Self.makeContentTabMoveWindow(
                id: sourceID,
                tabs: [(movedTabID, "/global-pin-mutation/moved")],
            )
            source.window.contentTabs.tabs[id: movedTabID]?.isPinned = true
            source.window.sidebar.pendingContentTabMoveRequest = request
            source.window.pendingContentTabMove = .init(request: request, lifecycle: .inFlight)
            let target = try Self.makeContentTabMoveWindow(
                id: targetID,
                tabs: [(ContentTabID(rawValue: "global-pin-mutation-target"), "/global-pin-mutation/target")],
            )
            var mutationOwner = try Self.makeContentTabMoveWindow(
                id: mutationOwnerID,
                tabs: [(movedTabID, "/global-pin-mutation/moved")],
            )
            mutationOwner.window.contentTabs.tabs[id: movedTabID]?.isPinned = true
            let intentID = mutationOwner.window.contentTabs.markLatestPinnedRecordPersistenceIntent(for: movedTabID)
            let persistenceRequest = ContentTabPinnedRecordPersistenceRequest(
                tabID: movedTabID,
                context: .init(
                    intentID: intentID,
                    generation: ContentTabPinnedRecordMutationGeneration(tabID: movedTabID),
                ),
                rollback: ContentTabPinnedRecordRollbackSnapshot(
                    previousIsPinned: true,
                    previousPinnedRecord: pinnedRecord,
                    previousTabIndex: 0,
                ),
                mutation: mutation,
                persistenceScopeID: UUID(),
            )
            let queuedMutation = WindowManagerTopNavigationPersistenceRequest(
                sourceWindowID: mutationOwnerID,
                token: .init(value: mutationID),
                operation: .pinnedRecord(
                    source: .contentTab,
                    request: persistenceRequest,
                    discoveredLocationIDs: [],
                ),
            )
            let sourceBefore = source.window
            let targetBefore = target.window
            let mutationOwnerBefore = mutationOwner.window
            var initialState = WindowManagerFeature.State()
            initialState.windows = [source, target, mutationOwner]
            initialState.topNavigationPersistenceQueue = [queuedMutation]
            initialState.isTopNavigationPersistenceInFlight = true
            let moveCalls = LockIsolated(0)
            let activatedIDs = LockIsolated<[UUID]>([])
            let closedIDs = LockIsolated<[UUID]>([])
            let store = TestStore(initialState: initialState) { WindowManagerFeature() } withDependencies: {
                $0.fileOperationUndoManagerClient.moveScopes = { _ in
                    moveCalls.withValue { $0 += 1 }
                    return .moved
                }
                $0.fileManagerWindowClient.activate = { id in
                    activatedIDs.withValue { $0.append(id) }
                    return .discarded
                }
                $0.fileManagerWindowClient.close = { id in closedIDs.withValue { $0.append(id) } }
            }
            // store.exhaustivity = .off: global mutation gate의 semantic atomicity와 effect 미호출만 검증한다.
            store.exhaustivity = .off

            await store.send(.contentTabMoveRequest(request))
            await store.receive { Self.isContentTabMoveRejection($0, request: request, category: .busy) }

            var expectedSource = sourceBefore
            expectedSource.sidebar.pendingContentTabMoveRequest = nil
            expectedSource.pendingContentTabMove = nil
            expectedSource.contentTabMoveFailurePresentation = .init(
                requestID: request.requestID,
                category: .busy,
            )
            XCTAssertEqual(store.state.windows[id: sourceID]?.window, expectedSource)
            XCTAssertEqual(store.state.windows[id: targetID]?.window, targetBefore)
            XCTAssertEqual(store.state.windows[id: mutationOwnerID]?.window, mutationOwnerBefore)
            XCTAssertEqual(store.state.topNavigationPersistenceQueue, [queuedMutation])
            XCTAssertTrue(store.state.isTopNavigationPersistenceInFlight)
            XCTAssertEqual(store.state.contentTabMoveTerminalRecords[request.requestID]?.outcome, .rejected(.busy))
            XCTAssertEqual(moveCalls.value, 0)
            XCTAssertTrue(activatedIDs.value.isEmpty)
            XCTAssertTrue(closedIDs.value.isEmpty)
        }
    }

    /// CTM-001-move_content_tab_to_another_window: destination ambiguous AI provenance는 generic으로 종료한다.
    /// destination mutation 전에 window-wide provenance를 검증하고 app terminal 계약으로 매핑하는지 검증한다.
    /// - 검증 내용: generic presentation/ledger와 source/target semantic snapshot equality
    /// - 사전 조건: destination의 두 open tab이 같은 processing background AI session을 소유한다.
    /// - 기대 결과: move는 reject되고 source pending/presentation/ledger 외 semantic state는 변경되지 않는다.
    func testContentTabMoveMapsAmbiguousDestinationAiProvenanceToGenericWithoutMutation() async throws {
        let sourceID = UUID(4501)
        let targetID = UUID(4502)
        let movedTabID = ContentTabID(rawValue: "destination-provenance-source")
        let firstTargetID = ContentTabID(rawValue: "destination-provenance-first")
        let secondTargetID = ContentTabID(rawValue: "destination-provenance-second")
        let request = ContentTabMoveRequest(
            requestID: UUID(4503),
            sourceWindowID: sourceID,
            tabID: movedTabID,
            targetWindowID: targetID,
        )
        var source = try Self.makeContentTabMoveWindow(
            id: sourceID,
            tabs: [(movedTabID, "/provenance/source")],
        )
        source.window.sidebar.pendingContentTabMoveRequest = request
        source.window.pendingContentTabMove = .init(request: request, lifecycle: .inFlight)
        var target = try Self.makeContentTabMoveWindow(
            id: targetID,
            tabs: [
                (firstTargetID, "/provenance/target/first"),
                (secondTargetID, "/provenance/target/second"),
            ],
        )
        let sessionID = AiChatSessionID(rawValue: UUID(4504))
        target.window.tabContentStates[firstTargetID]?.aiChat.sessionID = sessionID
        target.window.tabContentStates[secondTargetID]?.aiChat.sessionID = sessionID
        target.window.content = try XCTUnwrap(target.window.tabContentStates[firstTargetID])
        var background = FileManagerContentFeature.State.initialContent(
            for: .aiChat(sessionID: sessionID.rawValue.uuidString),
        )
        background.aiChat.streamingAssistantDraft = "processing"
        target.window.backgroundAiChatStates[sessionID] = background
        let sourceBefore = source.window
        let targetBefore = target.window
        var initialState = WindowManagerFeature.State()
        initialState.windows = [source, target]
        let store = TestStore(initialState: initialState) { WindowManagerFeature() }
        // store.exhaustivity = .off: app terminal mapping과 semantic atomicity만 검증한다.
        store.exhaustivity = .off

        await store.send(.contentTabMoveRequest(request))
        await store.receive { Self.isContentTabMoveRejection($0, request: request, category: .generic) }

        var expectedSource = sourceBefore
        expectedSource.sidebar.pendingContentTabMoveRequest = nil
        expectedSource.pendingContentTabMove = nil
        expectedSource.contentTabMoveFailurePresentation = .init(requestID: request.requestID, category: .generic)
        XCTAssertEqual(store.state.windows[id: sourceID]?.window, expectedSource)
        XCTAssertEqual(store.state.windows[id: targetID]?.window, targetBefore)
        XCTAssertEqual(
            store.state.contentTabMoveTerminalRecords[request.requestID]?.outcome,
            .rejected(.generic),
        )
    }

    /// CTM-001-move_content_tab_to_another_window: pending final snapshot은 busy로 종료하고 semantic state를 보존한다.
    /// persistence terminal이 이전 source path로 돌아오기 전에 tab 소유권이 이동하지 않도록 app mapping을 검증한다.
    /// - 검증 내용: pending AI eligibility의 busy presentation/ledger와 source/target 전체 semantic snapshot equality
    /// - 사전 조건: source active content의 completed request lock에 final snapshot이 남아 있다.
    /// - 기대 결과: move는 busy로 reject되고 pending/presentation/ledger 외 source와 target state는 변하지 않는다.
    func testContentTabMoveMapsCompletedFinalSnapshotToBusyWithoutSemanticMutation() async throws {
        let sourceID = UUID(4505)
        let targetID = UUID(4506)
        let movedTabID = ContentTabID(rawValue: "final-snapshot-source")
        let targetTabID = ContentTabID(rawValue: "final-snapshot-target")
        let sessionID = AiChatSessionID(rawValue: UUID(4507))
        let modelHandle = AiModelHandle(provider: .openai, rawValue: "gpt-4.1-mini")
        let modelRow = AiModelCatalogRow(
            handle: modelHandle,
            displayName: "GPT-4.1 Mini",
            authMethod: .apiKey,
            sortOrder: 10,
        )
        let requestID = AiChatRequestID(rawValue: UUID(4508))
        let runID = AiChatRunID(rawValue: UUID(4509))
        let context = AiChatRequestContextSnapshot(
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
            selectedModelRow: modelRow,
            sessionStatus: .active,
            promptSummary: "persist before move",
            submittedAtMs: 0,
        )
        let lock = AiChatRequestLock(
            kind: .submit,
            requestID: requestID,
            runID: runID,
            context: context,
            request: AiChatRequest(
                context: context,
                messages: [AiChatMessage(role: .user, content: "persist before move")],
            ),
            selectedModelHandle: modelHandle,
            selectedModelRow: modelRow,
            assistantReplacementIndex: nil,
        )
        let completedLock = lock.recordingFinalSnapshot(AiChatSessionSnapshot(
            sessionID: sessionID,
            status: .active,
            provider: .openai,
            model: modelHandle,
            transcriptHistory: lock.request.messages + [AiChatMessage(role: .assistant, content: "done")],
            lastRequestID: requestID,
            lastRunID: runID,
            updatedAtMs: 1_234_567_891_000,
        ))
        let request = ContentTabMoveRequest(
            requestID: UUID(4510),
            sourceWindowID: sourceID,
            tabID: movedTabID,
            targetWindowID: targetID,
        )
        var source = try Self.makeContentTabMoveWindow(
            id: sourceID,
            tabs: [(movedTabID, "/snapshot/source")],
        )
        source.window.content.aiChat.sessionID = sessionID
        source.window.content.aiChat.executionPhase = .completed(completedLock)
        source.window.tabContentStates[movedTabID] = source.window.content
        source.window.sidebar.pendingContentTabMoveRequest = request
        source.window.pendingContentTabMove = .init(request: request, lifecycle: .inFlight)
        let target = try Self.makeContentTabMoveWindow(
            id: targetID,
            tabs: [(targetTabID, "/snapshot/target")],
        )
        let sourceBefore = source.window
        let targetBefore = target.window
        var initialState = WindowManagerFeature.State()
        initialState.windows = [source, target]
        let store = TestStore(initialState: initialState) { WindowManagerFeature() }
        // store.exhaustivity = .off: app terminal mapping과 양 window semantic atomicity만 검증한다.
        store.exhaustivity = .off

        await store.send(.contentTabMoveRequest(request))
        await store.receive { Self.isContentTabMoveRejection($0, request: request, category: .busy) }

        var expectedSource = sourceBefore
        expectedSource.sidebar.pendingContentTabMoveRequest = nil
        expectedSource.pendingContentTabMove = nil
        expectedSource.contentTabMoveFailurePresentation = .init(requestID: request.requestID, category: .busy)
        XCTAssertEqual(store.state.windows[id: sourceID]?.window, expectedSource)
        XCTAssertEqual(store.state.windows[id: targetID]?.window, targetBefore)
        XCTAssertEqual(
            store.state.contentTabMoveTerminalRecords[request.requestID]?.outcome,
            .rejected(.busy),
        )
    }

    /// CTM-001-move_content_tab_to_another_window: cross-window move는 양 active destination observation을 rebind한다.
    /// old source/target watcher를 window-scoped cancellation으로 supersede하고 post-commit route를 다시 적용한다.
    /// - 검증 내용: source fallback/target moved stop-start-apply, old interest 제거, new interest event 전달
    /// - 사전 조건: source moved/fallback과 target previous-active가 모두 directory watcher를 가진다.
    /// - 기대 결과: old interest 2개가 제거되고 새 두 route가 등록되어 각 tab으로 filesystem event를 전달한다.
    func testContentTabMoveRebindsSourceFallbackAndTargetMovedObservation() async throws {
        let sourceID = UUID(4511)
        let targetID = UUID(4512)
        let movedTabID = ContentTabID(rawValue: "watcher-moved")
        let fallbackTabID = ContentTabID(rawValue: "watcher-fallback")
        let previousTargetTabID = ContentTabID(rawValue: "watcher-target-previous")
        let movedPath = "/watch/source-moved"
        let fallbackPath = "/watch/source-fallback"
        let previousTargetPath = "/watch/target-previous"
        let request = ContentTabMoveRequest(
            requestID: UUID(4513),
            sourceWindowID: sourceID,
            tabID: movedTabID,
            targetWindowID: targetID,
        )
        var source = try Self.makeContentTabMoveWindow(
            id: sourceID,
            tabs: [(movedTabID, movedPath), (fallbackTabID, fallbackPath)],
        )
        source.window.contentTabs.activeTabID = movedTabID
        source.window.contentTabs.previousActiveTabID = fallbackTabID
        source.window.content = try XCTUnwrap(source.window.tabContentStates[movedTabID])
        source.window.inspector = try XCTUnwrap(source.window.tabInspectorStates[movedTabID])
        source.window.sidebar.pendingContentTabMoveRequest = request
        source.window.pendingContentTabMove = .init(request: request, lifecycle: .inFlight)
        let target = try Self.makeContentTabMoveWindow(
            id: targetID,
            tabs: [(previousTargetTabID, previousTargetPath)],
        )
        var initialState = WindowManagerFeature.State()
        initialState.windows = [source, target]

        let allInterests = LockIsolated<[FileChangeWatchInterest]>([])
        let pendingInterests = LockIsolated<[FileChangeWatchInterest]>([])
        let removedInterestIDs = LockIsolated<Set<String>>([])
        let eventContinuations = LockIsolated<[String: [AsyncStream<FileChangeGatewayEventBatch>.Continuation]]>([:])
        let notificationStarts = LockIsolated(0)
        let notificationStops = LockIsolated(0)
        let observedStreamStarts = LockIsolated(0)
        let initialWatchersRegistered = expectation(description: "initial source and target watchers")
        initialWatchersRegistered.expectedFulfillmentCount = 2
        let initialNotificationsStopped = expectation(description: "initial source and target notifications stopped")
        initialNotificationsStopped.expectedFulfillmentCount = 2
        let reboundWatchersRegistered = expectation(description: "source fallback and target moved watchers")
        reboundWatchersRegistered.expectedFulfillmentCount = 2
        let reboundStreamsStarted = expectation(description: "source fallback and target moved streams")
        reboundStreamsStarted.expectedFulfillmentCount = 2
        let sourceEventReceived = expectation(description: "source fallback event")
        let targetEventReceived = expectation(description: "target moved event")
        let activationCalled = expectation(description: "target activation")
        let store = TestStore(initialState: initialState) {
            CombineReducers {
                WindowManagerFeature()
                Reduce { _, action in
                    guard case let .windows(.element(
                        id: windowID,
                        action: .window(.tabContent(tabID: tabID, action: .externalFileSystemChanged(paths, _))),
                    )) = action else { return .none }
                    if windowID == sourceID, tabID == fallbackTabID, paths.map(\.path) == ["\(fallbackPath)/changed"] {
                        sourceEventReceived.fulfill()
                    }
                    if windowID == targetID, tabID == movedTabID, paths.map(\.path) == ["\(movedPath)/changed"] {
                        targetEventReceived.fulfill()
                    }
                    return .none
                }
            }
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 450))
            $0.entryLoadingClient.loadItems = { _, _ in [] }
            $0.fileChangeGatewayClient.updateInterests = { interests in
                pendingInterests.withValue { $0.append(contentsOf: interests) }
                let count = allInterests.withValue { recorded in
                    recorded.append(contentsOf: interests)
                    return recorded.count
                }
                if count <= 2 {
                    initialWatchersRegistered.fulfill()
                } else {
                    reboundWatchersRegistered.fulfill()
                }
            }
            $0.fileChangeGatewayClient.removeInterests = { ids in
                removedInterestIDs.withValue { $0.formUnion(ids) }
            }
            $0.fileChangeGatewayClient.observeEvents = {
                let interest = pendingInterests.withValue { $0.removeFirst() }
                let root = interest.roots[0]
                let streamStart = observedStreamStarts.withValue { count in
                    count += 1
                    return count
                }
                return AsyncStream { continuation in
                    eventContinuations.withValue { $0[root, default: []].append(continuation) }
                    if streamStart > 2 {
                        reboundStreamsStarted.fulfill()
                    }
                }
            }
            $0.notificationCenterClient.notifications = { _, _ in
                let generation = notificationStarts.withValue { starts in
                    starts += 1
                    return starts
                }
                return AsyncStream { continuation in
                    continuation.onTermination = { _ in
                        notificationStops.withValue { $0 += 1 }
                        if generation <= 2 {
                            initialNotificationsStopped.fulfill()
                        }
                    }
                }
            }
            $0.fileManagerWindowClient.activate = { _ in
                activationCalled.fulfill()
                return .discarded
            }
            $0.fileOperationUndoManagerClient.moveScopes = { _ in .moved }
        }
        // store.exhaustivity = .off: long-lived watcher 내부 action보다 lifecycle supersession과 event route를 검증한다.
        store.exhaustivity = .off

        await store.send(.windows(.element(
            id: sourceID,
            action: .window(.tabContent(
                tabID: movedTabID,
                action: .internal(.startObservingSystemNotifications),
            )),
        )))
        await store.send(.windows(.element(
            id: sourceID,
            action: .window(.tabContent(
                tabID: movedTabID,
                action: .internal(.applyNavigationState(.folder(movedPath))),
            )),
        )))
        await store.send(.windows(.element(
            id: targetID,
            action: .window(.tabContent(
                tabID: previousTargetTabID,
                action: .internal(.startObservingSystemNotifications),
            )),
        )))
        await store.send(.windows(.element(
            id: targetID,
            action: .window(.tabContent(
                tabID: previousTargetTabID,
                action: .internal(.applyNavigationState(.folder(previousTargetPath))),
            )),
        )))
        await fulfillment(of: [initialWatchersRegistered], timeout: 1)
        let oldInterestIDs = Set(allInterests.value.prefix(2).map(\.id))

        await store.send(.contentTabMoveRequest(request))
        await fulfillment(
            of: [
                reboundWatchersRegistered,
                reboundStreamsStarted,
                initialNotificationsStopped,
                activationCalled,
            ],
            timeout: 1,
        )

        XCTAssertEqual(allInterests.value.map(\.roots), [
            [movedPath],
            [previousTargetPath],
            [fallbackPath],
            [movedPath],
        ])
        XCTAssertTrue(oldInterestIDs.isSubset(of: removedInterestIDs.value))
        XCTAssertEqual(notificationStarts.value, 4)
        XCTAssertGreaterThanOrEqual(notificationStops.value, 2)

        eventContinuations.value[fallbackPath]?.last?.yield(.init(events: [
            FileChangeGatewayEvent(
                path: "\(fallbackPath)/changed",
                flags: FSEventStreamEventFlags(kFSEventStreamEventFlagItemModified),
            ),
        ]))
        eventContinuations.value[movedPath]?.last?.yield(.init(events: [
            FileChangeGatewayEvent(
                path: "\(movedPath)/changed",
                flags: FSEventStreamEventFlags(kFSEventStreamEventFlagItemModified),
            ),
        ]))
        await fulfillment(of: [sourceEventReceived, targetEventReceived], timeout: 1)

        await store.send(.windows(.element(
            id: sourceID,
            action: .window(.tabContent(
                tabID: fallbackTabID,
                action: .internal(.stopObservingSystemNotifications),
            )),
        )))
        await store.send(.windows(.element(
            id: targetID,
            action: .window(.tabContent(
                tabID: movedTabID,
                action: .internal(.stopObservingSystemNotifications),
            )),
        )))
        await store.finish()
    }

    func testContentTabMoveCancelsExactOutgoingOwnersBeforeObservationRebind() async throws {
        let sourceID = UUID(4521)
        let targetID = UUID(4522)
        let movedTabID = ContentTabID(rawValue: "teardown-moved")
        let fallbackTabID = ContentTabID(rawValue: "teardown-fallback")
        let targetOutgoingTabID = ContentTabID(rawValue: "teardown-target-outgoing")
        let sourceLoadingWindowID = sourceID
        let sourceLoadingOwnerID = UUID(4524)
        let sourceComposerOwnerID = UUID(4525)
        let targetLoadingWindowID = targetID
        let targetLoadingOwnerID = UUID(4527)
        let sourceProbeRequestID = UUID(4530)
        let targetProbeRequestID = UUID(4531)
        let request = ContentTabMoveRequest(
            requestID: UUID(4529),
            sourceWindowID: sourceID,
            tabID: movedTabID,
            targetWindowID: targetID,
        )
        var source = try Self.makeContentTabMoveWindow(
            id: sourceID,
            tabs: [(movedTabID, "/teardown/moved"), (fallbackTabID, "/teardown/fallback")],
        )
        source.window.contentTabs.activeTabID = movedTabID
        source.window.contentTabs.previousActiveTabID = fallbackTabID
        source.window.content = try XCTUnwrap(source.window.tabContentStates[movedTabID])
        source.window.inspector = try XCTUnwrap(source.window.tabInspectorStates[movedTabID])
        var movedContent = source.window.content
        movedContent.entryViewLayout.entryOperations.windowID = sourceLoadingWindowID
        movedContent.entryViewLayout.entryOperations.loadingCancellationOwnerID = sourceLoadingOwnerID
        movedContent.composer.cancellationOwnerID = sourceComposerOwnerID
        source.window.tabContentStates[movedTabID] = movedContent
        if source.window.contentTabs.activeTabID == movedTabID {
            source.window.content = movedContent
        }
        source.window.sidebar.pendingContentTabMoveRequest = request
        source.window.pendingContentTabMove = .init(request: request, lifecycle: .inFlight)
        var target = try Self.makeContentTabMoveWindow(
            id: targetID,
            tabs: [(targetOutgoingTabID, "/teardown/target")],
        )
        target.window.content.entryViewLayout.entryOperations.windowID = targetLoadingWindowID
        target.window.content.entryViewLayout.entryOperations.loadingCancellationOwnerID = targetLoadingOwnerID
        target.window.tabContentStates[targetOutgoingTabID] = target.window.content
        var initialState = WindowManagerFeature.State()
        initialState.windows = [source, target]

        let events = LockIsolated<[String]>([])
        let probesStarted = expectation(description: "outgoing lifecycle probes started")
        probesStarted.expectedFulfillmentCount = 2
        let probesCancelled = expectation(description: "outgoing lifecycle probes cancelled")
        probesCancelled.expectedFulfillmentCount = 2
        let rebindCompleted = expectation(description: "observation rebind completed")

        func probe(id: EntryOperationsLoadingCancelID, event: String) -> Effect<WindowManagerAction> {
            .run { _ in
                probesStarted.fulfill()
                try await withTaskCancellationHandler {
                    try await Task.sleep(for: .seconds(60))
                } onCancel: {
                    events.withValue { $0.append(event) }
                    probesCancelled.fulfill()
                }
            }
            .cancellable(id: id)
        }

        let store = TestStore(initialState: initialState) {
            CombineReducers {
                WindowManagerFeature()
                Reduce { _, action in
                    if case let .windows(.element(
                        id: windowID,
                        action: .window(.view(.dismissContentTabMoveFailure(requestID: probeRequestID))),
                    )) = action {
                        if windowID == sourceID, probeRequestID == sourceProbeRequestID {
                            return probe(
                                id: EntryOperationsLoadingCancelID.loadItems(
                                    windowID: sourceLoadingWindowID,
                                    ownerID: sourceLoadingOwnerID,
                                ),
                                event: "cancel-source-loading",
                            )
                        }
                        if windowID == targetID, probeRequestID == targetProbeRequestID {
                            return probe(
                                id: EntryOperationsLoadingCancelID.loadItems(
                                    windowID: targetLoadingWindowID,
                                    ownerID: targetLoadingOwnerID,
                                ),
                                event: "cancel-target-loading",
                            )
                        }
                    }
                    guard case let .windows(.element(
                        id: windowID,
                        action: .window(.tabContent(tabID: tabID, action: contentAction)),
                    )) = action else { return .none }
                    if windowID == targetID,
                       case .composer(.internal(.cleanupCollectionWork)) = contentAction
                    {
                        if tabID == movedTabID {
                            events.withValue { $0.append("cleanup-source-composer") }
                        }
                        if tabID == targetOutgoingTabID {
                            events.withValue { $0.append("cleanup-target-composer") }
                        }
                    }
                    if windowID == sourceID,
                       tabID == fallbackTabID,
                       case .internal(.stopObservingSystemNotifications) = contentAction
                    {
                        events.withValue { $0.append("rebind-start") }
                    }
                    if windowID == targetID,
                       tabID == movedTabID,
                       case .internal(.applyNavigationState) = contentAction
                    {
                        events.withValue { $0.append("rebind-complete") }
                        rebindCompleted.fulfill()
                    }
                    return .none
                }
            }
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 450))
            $0.entryLoadingClient.loadItems = { _, _ in [] }
            $0.fileChangeGatewayClient.observeEvents = { AsyncStream { $0.finish() } }
            $0.notificationCenterClient.notifications = { _, _ in AsyncStream { $0.finish() } }
            $0.fileManagerWindowClient.activate = { _ in .discarded }
            $0.fileOperationUndoManagerClient.moveScopes = { _ in .moved }
        }
        store.exhaustivity = .off

        await store.send(.windows(.element(
            id: sourceID,
            action: .window(.view(.dismissContentTabMoveFailure(requestID: sourceProbeRequestID))),
        )))
        await store.send(.windows(.element(
            id: targetID,
            action: .window(.view(.dismissContentTabMoveFailure(requestID: targetProbeRequestID))),
        )))
        await fulfillment(of: [probesStarted], timeout: 1)

        await store.send(.contentTabMoveRequest(request))
        XCTAssertEqual(store.state.contentTabMoveTerminalRecords[request.requestID]?.outcome, .succeeded)
        await fulfillment(of: [probesCancelled, rebindCompleted], timeout: 1)
        await store.skipReceivedActions()
        await store.finish()

        XCTAssertEqual(events.value, [
            "cancel-source-loading",
            "cancel-target-loading",
            "cleanup-source-composer",
            "cleanup-target-composer",
            "rebind-start",
            "rebind-complete",
        ])
    }

    /// CTM-001-move_content_tab_to_another_window: cross-window folder·collection load lifecycle를 보장한다.
    /// projectTarget가 moved tab의 entryOperations.windowID를 이미 target으로 재지정한 뒤에도, 복사된
    /// folderLoadingContexts에서 유도한 source-keyed cancel이 원본 source folder stream을 실제로 취소하고,
    /// 그 후 cancelAllFolderItems가 target의 folderLoadingContexts를 비우며, restart·observation rebind 순서를
    /// 지키고, 무관한 source tab의 folder stream은 보존하는지 검증한다.
    /// - 검증 내용: held source folder stream .cancelled, target restart, context clearing, 무관 tab isolation,
    ///   folder-cancel → window-rebind → hierarchy-restart → observation rebind 순서
    /// - 사전 조건: moved tab과 무관 fallback tab이 각각 held folder stream을 갖고 move가 성공한다.
    /// - 기대 결과: moved tab의 source-keyed stream이 취소되고, fallback stream은 유지되며, target moved tab의
    ///   folderLoadingContexts가 비워지고, hierarchy·collection restart/rebind 순서가 지켜진다.
    func testContentTabMoveOrdersLoadingCancellationBeforeOwnerRebindAndRestartsAfter() async throws {
        let sourceID = UUID(4560)
        let targetID = UUID(4561)
        let movedTabID = ContentTabID(rawValue: "folder-lifecycle-moved")
        let fallbackTabID = ContentTabID(rawValue: "folder-lifecycle-fallback")
        let targetOutgoingTabID = ContentTabID(rawValue: "folder-lifecycle-target-outgoing")
        let movedOwnerID = UUID(4563)
        let fallbackOwnerID = UUID(4564)
        let request = ContentTabMoveRequest(
            requestID: UUID(4562),
            sourceWindowID: sourceID,
            tabID: movedTabID,
            targetWindowID: targetID,
        )
        let movedFolderRequest = EntryFolderLoadRequest(
            rootContextGeneration: 1,
            folderID: "/folder-lifecycle/moved/child",
            folderGeneration: 1,
            path: "/folder-lifecycle/moved/child",
            showHidden: false,
            priority: .none,
        )
        let fallbackFolderRequest = EntryFolderLoadRequest(
            rootContextGeneration: 1,
            folderID: "/folder-lifecycle/fallback/child",
            folderGeneration: 1,
            path: "/folder-lifecycle/fallback/child",
            showHidden: false,
            priority: .none,
        )
        var source = try Self.makeContentTabMoveWindow(
            id: sourceID,
            tabs: [(movedTabID, "/folder-lifecycle/moved"), (fallbackTabID, "/folder-lifecycle/fallback")],
        )
        source.window.contentTabs.activeTabID = movedTabID
        source.window.contentTabs.previousActiveTabID = fallbackTabID
        source.window.content = try XCTUnwrap(source.window.tabContentStates[movedTabID])
        source.window.inspector = try XCTUnwrap(source.window.tabInspectorStates[movedTabID])
        var movedContent = source.window.content
        movedContent.entryViewLayout.entryOperations.windowID = sourceID
        movedContent.entryViewLayout.entryOperations.loadingCancellationOwnerID = movedOwnerID
        movedContent.entryViewLayout.isCollectionMode = true
        movedContent.entryViewLayout.collectionReplaceEpoch = 3
        movedContent.entryViewLayout.activeCollectionReplacePaths = ["/collection-lifecycle/replace.txt"]
        movedContent.entryViewLayout.activeAppendExpectedBatchIndices = [7: 0]
        movedContent.entryViewLayout.activeCollectionAppendPaths = [7: ["/collection-lifecycle/append.txt"]]
        movedContent.entryViewLayout.nextCollectionAppendToken = 7
        // target restart가 같은 moved URL을 두 번째로 재호출하도록, moved folder를 expanded .loadingCore로 시드한다.
        // folderGeneration은 source request(movedFolderRequest.folderGeneration == 1)와 일치시킨다.
        let movedFolder = EntryModel.temporaryFolder(
            id: "/folder-lifecycle/moved/child",
            name: "child",
        )
        movedContent.entryViewLayout.entries.append(movedFolder)
        movedContent.entryViewLayout.hierarchy.nodesByID["/folder-lifecycle/moved/child"] = FolderNodeState(
            expansionIntent: true,
            generation: 1,
            loadPhase: .loadingCore,
        )
        source.window.tabContentStates[movedTabID] = movedContent
        source.window.content = movedContent
        var fallbackContent = try XCTUnwrap(source.window.tabContentStates[fallbackTabID])
        fallbackContent.entryViewLayout.entryOperations.windowID = sourceID
        fallbackContent.entryViewLayout.entryOperations.loadingCancellationOwnerID = fallbackOwnerID
        source.window.tabContentStates[fallbackTabID] = fallbackContent
        source.window.sidebar.pendingContentTabMoveRequest = request
        source.window.pendingContentTabMove = .init(request: request, lifecycle: .inFlight)
        let target = try Self.makeContentTabMoveWindow(
            id: targetID,
            tabs: [(targetOutgoingTabID, "/folder-lifecycle/target/outgoing")],
        )
        var initialState = WindowManagerFeature.State()
        initialState.windows = [source, target]

        let events = LockIsolated<[String]>([])
        let movedLoadStarted = expectation(description: "moved folder load started")
        let fallbackLoadStarted = expectation(description: "fallback folder load started")
        let movedLoadCancelled = expectation(description: "moved source-keyed folder load cancelled")
        let movedLoadCount = LockIsolated(0)
        let movedCancellationCount = LockIsolated(0)
        let fallbackCancellationCount = LockIsolated(0)
        let targetContentContextsAtCancel = LockIsolated<[Bool?]>([])
        let movedGate = AsyncStream<Void>.makeStream()
        let fallbackGate = AsyncStream<Void>.makeStream()

        let store = TestStore(initialState: initialState) {
            CombineReducers {
                WindowManagerFeature()
                Reduce { state, action in
                    guard case let .windows(.element(
                        id: windowID,
                        action: .window(.tabContent(tabID: tabID, action: contentAction)),
                    )) = action,
                        windowID == targetID, tabID == movedTabID,
                        let event = contentTabMoveFolderLifecycleEvent(contentAction)
                    else { return .none }
                    if event == .folderCancel {
                        // cancelAllFolderItems 처리 시점의 target active content folderLoadingContexts가
                        // 이미 비워졌는지를 recorder에서 기록한다.
                        let isEmpty = MainActor.assumeIsolated {
                            state.windows[id: targetID]?.window.content.entryViewLayout.entryOperations
                                .folderLoadingContexts.isEmpty
                        }
                        targetContentContextsAtCancel.withValue { $0.append(isEmpty) }
                    }
                    events.withValue { $0.append(event.rawValue) }
                    return .none
                }
            }
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 450))
            $0.entryLoadingClient.loadItems = { url, _ in
                if url.path == "/folder-lifecycle/moved/child" {
                    // 첫 invocation만 source-keyed held stream으로 취급하고, cancel 뒤 target restart가
                    // 같은 URL을 다시 로드하면 즉시 완료(빈 결과)로 두어 over-fulfill/교착을 피한다.
                    let isFirstLoad = movedLoadCount.withValue { count -> Bool in
                        count += 1
                        return count == 1
                    }
                    guard isFirstLoad else { return [] }
                    movedLoadStarted.fulfill()
                    return await withTaskCancellationHandler {
                        for await _ in movedGate.stream {}
                        return []
                    } onCancel: {
                        movedCancellationCount.withValue { $0 += 1 }
                        movedGate.continuation.finish()
                        movedLoadCancelled.fulfill()
                    }
                }
                if url.path == "/folder-lifecycle/fallback/child" {
                    fallbackLoadStarted.fulfill()
                    return await withTaskCancellationHandler {
                        for await _ in fallbackGate.stream {}
                        return []
                    } onCancel: {
                        fallbackCancellationCount.withValue { $0 += 1 }
                        fallbackGate.continuation.finish()
                    }
                }
                return []
            }
            $0.fileChangeGatewayClient.observeEvents = { AsyncStream { $0.finish() } }
            $0.notificationCenterClient.notifications = { _, _ in AsyncStream { $0.finish() } }
            $0.fileManagerWindowClient.activate = { _ in .discarded }
            $0.fileOperationUndoManagerClient.moveScopes = { _ in .moved }
        }
        store.exhaustivity = .off

        // Both source folder streams start: moved tab is source-keyed, fallback is unrelated.
        await store.send(.windows(.element(
            id: sourceID,
            action: .window(.tabContent(
                tabID: movedTabID,
                action: .entryViewLayout(.entryOperations(.loading(.loadFolderItems(movedFolderRequest)))),
            )),
        )))
        await store.send(.windows(.element(
            id: sourceID,
            action: .window(.tabContent(
                tabID: fallbackTabID,
                action: .entryViewLayout(.entryOperations(.loading(.loadFolderItems(fallbackFolderRequest)))),
            )),
        )))
        await fulfillment(of: [movedLoadStarted, fallbackLoadStarted], timeout: 1)

        await store.send(.contentTabMoveRequest(request))
        XCTAssertEqual(store.state.contentTabMoveTerminalRecords[request.requestID]?.outcome, .succeeded)
        // Source-keyed moved folder stream must be cancelled by the explicit source-keyed cancel.
        await fulfillment(of: [movedLoadCancelled], timeout: 1)

        // Unrelated fallback stream (not moved) must NOT be cancelled.
        XCTAssertEqual(fallbackCancellationCount.value, 0)
        // Source stream loaded once (held), then target restart re-invokes the same moved URL a
        // second time (immediate empty result), so the moved URL is invoked exactly twice.
        XCTAssertEqual(movedLoadCount.value, 2)

        // Release the unrelated fallback stream so finish() can complete.
        fallbackGate.continuation.finish()
        await store.skipReceivedActions()
        await store.finish()

        XCTAssertEqual(targetContentContextsAtCancel.value, [true])

        XCTAssertEqual(events.value, [
            "folder-cancel",
            "window-rebind",
            "hierarchy-restart",
            "collection-restart",
            "rebind-complete",
        ])
        XCTAssertEqual(movedCancellationCount.value, 1)
        let movedLayout = try XCTUnwrap(store.state.windows[id: targetID]?.window.content.entryViewLayout)
        XCTAssertEqual(movedLayout.collectionReplaceEpoch, 5)
        XCTAssertEqual(movedLayout.nextCollectionAppendToken, 8)
    }

    /// CTM-001-move_content_tab_to_another_window: inactive move는 source active lifecycle을 rebind하지 않는다.
    /// source active tab이 유지되면 loading과 navigation observation을 그대로 두고 target outgoing owner만 teardown해야 한다.
    /// - 검증 내용: source active loading cancellation과 stop/start/apply action 0회, target outgoing cancellation과 moved
    /// rebind
    /// - 사전 조건: source moved tab은 inactive이고 별도 active tab과 target outgoing tab이 각 loading owner를 가진다.
    /// - 기대 결과: source active lifecycle은 유지되고 target outgoing probe는 취소되며 target moved apply가 전달된다.
    func testContentTabMoveInactiveTabSkipsSourceActiveLifecycleAndRebindsTarget() async throws {
        let sourceID = UUID(4532)
        let targetID = UUID(4533)
        let movedTabID = ContentTabID(rawValue: "inactive-lifecycle-moved")
        let sourceActiveTabID = ContentTabID(rawValue: "inactive-lifecycle-active")
        let targetOutgoingTabID = ContentTabID(rawValue: "inactive-lifecycle-target")
        let sourceActiveLoadingOwnerID = UUID(4534)
        let targetLoadingOwnerID = UUID(4535)
        let sourceProbeRequestID = UUID(4536)
        let targetProbeRequestID = UUID(4537)
        let cleanupRequestID = UUID(4538)
        let request = ContentTabMoveRequest(
            requestID: UUID(4539),
            sourceWindowID: sourceID,
            tabID: movedTabID,
            targetWindowID: targetID,
        )
        var source = try Self.makeContentTabMoveWindow(
            id: sourceID,
            tabs: [
                (movedTabID, "/inactive/moved"),
                (sourceActiveTabID, "/inactive/active"),
            ],
        )
        source.window.contentTabs.activeTabID = sourceActiveTabID
        source.window.content = try XCTUnwrap(source.window.tabContentStates[sourceActiveTabID])
        source.window.inspector = try XCTUnwrap(source.window.tabInspectorStates[sourceActiveTabID])
        source.window.content.entryViewLayout.entryOperations.windowID = sourceID
        source.window.content.entryViewLayout.entryOperations.loadingCancellationOwnerID = sourceActiveLoadingOwnerID
        source.window.tabContentStates[sourceActiveTabID] = source.window.content
        source.window.sidebar.pendingContentTabMoveRequest = request
        source.window.pendingContentTabMove = .init(request: request, lifecycle: .inFlight)

        var target = try Self.makeContentTabMoveWindow(
            id: targetID,
            tabs: [(targetOutgoingTabID, "/inactive/target")],
        )
        target.window.content.entryViewLayout.entryOperations.windowID = targetID
        target.window.content.entryViewLayout.entryOperations.loadingCancellationOwnerID = targetLoadingOwnerID
        target.window.tabContentStates[targetOutgoingTabID] = target.window.content

        var initialState = WindowManagerFeature.State()
        initialState.windows = [source, target]
        let sourceActiveCancellationCount = LockIsolated(0)
        let sourceActiveNavigationActionCount = LockIsolated(0)
        let targetCancellationCount = LockIsolated(0)
        let targetRebindActions = LockIsolated<[ContentTabObservationRebindEvent]>([])
        let probesStarted = expectation(description: "source active and target outgoing probes started")
        probesStarted.expectedFulfillmentCount = 2
        let targetCancelled = expectation(description: "target outgoing loading cancelled")
        let sourceCleanup = expectation(description: "source active loading cleanup")
        let targetRebindCompleted = expectation(description: "target moved observation rebound")

        func probe(
            id: EntryOperationsLoadingCancelID,
            onCancel: @escaping @Sendable () -> Void,
        ) -> Effect<WindowManagerAction> {
            .run { _ in
                probesStarted.fulfill()
                try await withTaskCancellationHandler {
                    try await Task.sleep(for: .seconds(60))
                } onCancel: {
                    onCancel()
                }
            }
            .cancellable(id: id)
        }

        let sourceCancelID = EntryOperationsLoadingCancelID.loadItems(
            windowID: sourceID,
            ownerID: sourceActiveLoadingOwnerID,
        )
        let targetCancelID = EntryOperationsLoadingCancelID.loadItems(
            windowID: targetID,
            ownerID: targetLoadingOwnerID,
        )
        let store = TestStore(initialState: initialState) {
            CombineReducers {
                WindowManagerFeature()
                Reduce { _, action in
                    if case let .windows(.element(
                        id: windowID,
                        action: .window(.view(.dismissContentTabMoveFailure(requestID: probeRequestID))),
                    )) = action {
                        if windowID == sourceID, probeRequestID == sourceProbeRequestID {
                            return probe(id: sourceCancelID) {
                                sourceActiveCancellationCount.withValue { $0 += 1 }
                                sourceCleanup.fulfill()
                            }
                        }
                        if windowID == targetID, probeRequestID == targetProbeRequestID {
                            return probe(id: targetCancelID) {
                                targetCancellationCount.withValue { $0 += 1 }
                                targetCancelled.fulfill()
                            }
                        }
                        if windowID == sourceID, probeRequestID == cleanupRequestID {
                            return .cancel(id: sourceCancelID)
                        }
                    }
                    guard case let .windows(.element(
                        id: windowID,
                        action: .window(.tabContent(tabID: tabID, action: contentAction)),
                    )) = action else { return .none }
                    guard let rebindEvent = contentTabObservationRebindEvent(contentAction) else {
                        return .none
                    }
                    if windowID == sourceID, tabID == sourceActiveTabID {
                        sourceActiveNavigationActionCount.withValue { $0 += 1 }
                    }
                    if windowID == targetID, tabID == movedTabID {
                        targetRebindActions.withValue { $0.append(rebindEvent) }
                        if rebindEvent == .apply { targetRebindCompleted.fulfill() }
                    }
                    return .none
                }
            }
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 450))
            $0.entryLoadingClient.loadItems = { _, _ in [] }
            $0.fileChangeGatewayClient.observeEvents = { AsyncStream { $0.finish() } }
            $0.notificationCenterClient.notifications = { _, _ in AsyncStream { $0.finish() } }
            $0.fileManagerWindowClient.activate = { _ in .discarded }
            $0.fileOperationUndoManagerClient.moveScopes = { _ in .moved }
        }
        // store.exhaustivity = .off: long-lived probe 내부 action보다 source lifecycle 무효과와 target teardown/rebind를 검증한다.
        store.exhaustivity = .off

        await store.send(.windows(.element(
            id: sourceID,
            action: .window(.view(.dismissContentTabMoveFailure(requestID: sourceProbeRequestID))),
        )))
        await store.send(.windows(.element(
            id: targetID,
            action: .window(.view(.dismissContentTabMoveFailure(requestID: targetProbeRequestID))),
        )))
        await fulfillment(of: [probesStarted], timeout: 1)

        await store.send(.contentTabMoveRequest(request))
        await fulfillment(of: [targetCancelled, targetRebindCompleted], timeout: 1)
        XCTAssertEqual(store.state.contentTabMoveTerminalRecords[request.requestID]?.outcome, .succeeded)
        XCTAssertEqual(sourceActiveCancellationCount.value, 0)
        XCTAssertEqual(sourceActiveNavigationActionCount.value, 0)
        XCTAssertEqual(targetCancellationCount.value, 1)
        XCTAssertEqual(targetRebindActions.value, [.stop, .start, .apply])

        await store.send(.windows(.element(
            id: sourceID,
            action: .window(.view(.dismissContentTabMoveFailure(requestID: cleanupRequestID))),
        )))
        await fulfillment(of: [sourceCleanup], timeout: 1)
        await store.finish()
    }

    func testContentTabMovePreservesSharedSiblingComposerEffects() async throws {
        let sourceID = UUID(4541)
        let targetID = UUID(4542)
        let movedTabID = ContentTabID(rawValue: "shared-effect-moved")
        let sourceActiveTabID = ContentTabID(rawValue: "shared-effect-source-active")
        let targetOutgoingTabID = ContentTabID(rawValue: "shared-effect-target-outgoing")
        let targetInactiveTabID = ContentTabID(rawValue: "shared-effect-target-inactive")
        let request = ContentTabMoveRequest(
            requestID: UUID(4546),
            sourceWindowID: sourceID,
            tabID: movedTabID,
            targetWindowID: targetID,
        )
        var source = try Self.makeContentTabMoveWindow(
            id: sourceID,
            tabs: [
                (movedTabID, "/shared-effect/source/moved"),
                (sourceActiveTabID, "/shared-effect/source/active"),
            ],
        )
        source.window.contentTabs.activeTabID = sourceActiveTabID
        source.window.content = try XCTUnwrap(source.window.tabContentStates[sourceActiveTabID])
        source.window.inspector = try XCTUnwrap(source.window.tabInspectorStates[sourceActiveTabID])
        source.window.content.composer.activeSearchRequestID = UUID(4547)
        source.window.content.composer.isLoadingSearch = true
        source.window.tabContentStates[sourceActiveTabID] = source.window.content
        source.window.sidebar.pendingContentTabMoveRequest = request
        source.window.pendingContentTabMove = .init(request: request, lifecycle: .inFlight)

        var target = try Self.makeContentTabMoveWindow(
            id: targetID,
            tabs: [
                (targetOutgoingTabID, "/shared-effect/target/outgoing"),
                (targetInactiveTabID, "/shared-effect/target/inactive"),
            ],
        )
        target.window.contentTabs.activeTabID = targetOutgoingTabID
        target.window.content = try XCTUnwrap(target.window.tabContentStates[targetOutgoingTabID])
        target.window.inspector = try XCTUnwrap(target.window.tabInspectorStates[targetOutgoingTabID])
        target.window.tabContentStates[targetInactiveTabID]?.composer.activeSearchRequestID = UUID(4548)
        target.window.tabContentStates[targetInactiveTabID]?.composer.isLoadingSearch = true

        var initialState = WindowManagerFeature.State()
        initialState.windows = [source, target]
        let cleanupActionCount = LockIsolated(0)
        let rebindCompleted = expectation(description: "shared sibling move rebind completed")

        let store = TestStore(initialState: initialState) {
            CombineReducers {
                WindowManagerFeature()
                Reduce { _, action in
                    if case let .windows(.element(
                        id: windowID,
                        action: .window(.tabContent(tabID: tabID, action: contentAction)),
                    )) = action {
                        if case .composer(.internal(.cleanupCollectionWork)) = contentAction {
                            cleanupActionCount.withValue { $0 += 1 }
                        }
                        if windowID == targetID,
                           tabID == movedTabID,
                           case .internal(.applyNavigationState) = contentAction
                        {
                            rebindCompleted.fulfill()
                        }
                    }
                    return .none
                }
            }
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 450))
            $0.entryLoadingClient.loadItems = { _, _ in [] }
            $0.fileChangeGatewayClient.observeEvents = { AsyncStream { $0.finish() } }
            $0.notificationCenterClient.notifications = { _, _ in AsyncStream { $0.finish() } }
            $0.fileManagerWindowClient.activate = { _ in .discarded }
            $0.fileOperationUndoManagerClient.moveScopes = { _ in .moved }
        }
        store.exhaustivity = .off

        await store.send(.contentTabMoveRequest(request))
        await fulfillment(of: [rebindCompleted], timeout: 1)
        XCTAssertEqual(store.state.contentTabMoveTerminalRecords[request.requestID]?.outcome, .succeeded)
        XCTAssertEqual(cleanupActionCount.value, 0)
        XCTAssertEqual(store.state.windows[id: sourceID]?.window.content.composer.activeSearchRequestID, UUID(4547))
        XCTAssertEqual(store.state.windows[id: targetID]?.window.tabContentStates[targetInactiveTabID]?
            .composer.activeSearchRequestID, UUID(4548))
        await store.skipReceivedActions()
        await store.finish()
    }

    /// CTM-001-move_content_tab_to_another_window: foreign request는 동일 request ID terminal 원장을 선점하지 못한다.
    /// source package/sidebar의 full request correlation 전에 idempotency ledger를 변경하지 않는 계약을 검증한다.
    /// - 검증 내용: foreign full identity no-op, ledger 미기록, 이후 exact request 성공과 exact terminal
    /// - 사전 조건: exact inFlight request와 requestID만 같고 operation/ordered identity가 다른 foreign request가 있다.
    /// - 기대 결과: foreign 요청 뒤 상태가 동일하고 exact 요청만 target commit 및 succeeded terminal을 남긴다.
    func testContentTabMoveForeignRequestCannotPoisonTerminalLedger() async throws {
        let sourceID = UUID(4591)
        let targetID = UUID(4592)
        let movedTabID = ContentTabID(rawValue: "ledger-correlation-moved")
        let requestID = UUID(4593)
        let exactRequest = ContentTabMoveRequest(
            operationID: UUID(4594),
            requestID: requestID,
            sourceWindowID: sourceID,
            initiatingTabID: movedTabID,
            orderedTabIDs: [movedTabID],
            targetWindowID: targetID,
        )
        let foreignRequest = ContentTabMoveRequest(
            operationID: UUID(4595),
            requestID: requestID,
            sourceWindowID: sourceID,
            initiatingTabID: movedTabID,
            orderedTabIDs: [ContentTabID(rawValue: "ledger-correlation-foreign")],
            targetWindowID: targetID,
        )
        var source = try Self.makeContentTabMoveWindow(
            id: sourceID,
            tabs: [
                (movedTabID, "/ledger/source/moved"),
                (ContentTabID(rawValue: "ledger-correlation-remainder"), "/ledger/source/remainder"),
            ],
        )
        source.window.sidebar.pendingContentTabMoveRequest = exactRequest
        source.window.pendingContentTabMove = .init(request: exactRequest, lifecycle: .inFlight)
        let target = try Self.makeContentTabMoveWindow(
            id: targetID,
            tabs: [(ContentTabID(rawValue: "ledger-correlation-target"), "/ledger/target")],
        )
        var initialState = WindowManagerFeature.State()
        initialState.windows = [source, target]
        let activationCalled = expectation(description: "exact correlated target activation")
        let store = TestStore(initialState: initialState) {
            WindowManagerFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 450))
            $0.fileManagerWindowClient.activate = { id in
                XCTAssertEqual(id, targetID)
                activationCalled.fulfill()
                return .discarded
            }
            $0.fileOperationUndoManagerClient.moveScopes = { _ in .moved }
            $0.notificationCenterClient.notifications = { _, _ in AsyncStream { $0.finish() } }
        }
        // store.exhaustivity = .off: post-commit lifecycle action보다 foreign no-op과 exact terminal identity를 검증한다.
        store.exhaustivity = .off

        let stateBeforeForeignRequest = store.state
        await store.send(.contentTabMoveRequest(foreignRequest))
        XCTAssertEqual(store.state, stateBeforeForeignRequest)
        XCTAssertNil(store.state.contentTabMoveTerminalRecords[requestID])

        await store.send(.contentTabMoveRequest(exactRequest))
        await fulfillment(of: [activationCalled], timeout: 1)
        await store.skipReceivedActions()

        XCTAssertEqual(
            store.state.contentTabMoveTerminalRecords[requestID],
            ContentTabMoveTerminalRecord(request: exactRequest, outcome: .succeeded),
        )
        XCTAssertEqual(
            store.state.windows[id: targetID]?.window.contentTabs.tabs.count(where: { $0.id == movedTabID }),
            1,
        )
    }

    /// CTM-001-move_content_tab_to_another_window: 동일 request ID 재전달은 모든 effect와 mutation을 차단한다.
    /// - 검증 내용: target copy, activation/close/undo/observation/persistence 호출 횟수
    /// - 사전 조건: source에는 이동 후에도 남을 두 번째 tab이 존재한다.
    /// - 기대 결과: 첫 commit만 실행되고 duplicate request는 완전한 no-op이다.
    func testContentTabMoveDuplicateRequestIsEffectFreeNoOp() async throws {
        let sourceID = UUID()
        let targetID = UUID()
        let movedTabID = ContentTabID(rawValue: "duplicate-moved")
        let sourceRemainderID = ContentTabID(rawValue: "duplicate-source-remainder")
        let targetTabID = ContentTabID(rawValue: "duplicate-target")
        let request = ContentTabMoveRequest(
            requestID: UUID(),
            sourceWindowID: sourceID,
            tabID: movedTabID,
            targetWindowID: targetID,
        )
        var source = try Self.makeContentTabMoveWindow(
            id: sourceID,
            tabs: [(movedTabID, "/duplicate/moved"), (sourceRemainderID, "/duplicate/remainder")],
        )
        source.window.sidebar.pendingContentTabMoveRequest = request
        source.window.pendingContentTabMove = .init(request: request, lifecycle: .inFlight)
        let target = try Self.makeContentTabMoveWindow(id: targetID, tabs: [(targetTabID, "/duplicate/target")])
        var initialState = WindowManagerFeature.State()
        initialState.windows = [source, target]
        let activatedIDs = LockIsolated<[UUID]>([])
        let closedIDs = LockIsolated<[UUID]>([])
        let movedUndoScopes = LockIsolated<[(UndoManagerScope, UndoManagerScope)]>([])
        let notificationStarts = LockIsolated(0)
        let pinnedStoreCalls = LockIsolated(0)
        let activationCalled = expectation(description: "target activation")
        let store = TestStore(initialState: initialState) {
            WindowManagerFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 450))
            $0.fileManagerWindowClient.activate = { id in
                activatedIDs.withValue { $0.append(id) }
                activationCalled.fulfill()
                return .discarded
            }
            $0.fileManagerWindowClient.close = { id in closedIDs.withValue { $0.append(id) } }
            $0.fileOperationUndoManagerClient.moveScopes = { descriptors in
                movedUndoScopes.withValue { scopes in
                    scopes.append(contentsOf: descriptors.map { ($0.source, $0.target) })
                }
                return .moved
            }
            $0.notificationCenterClient.notifications = { _, _ in
                notificationStarts.withValue { $0 += 1 }
                return AsyncStream { $0.finish() }
            }
            $0.contentTabPinnedRecordClient.loadStore = { _ in
                pinnedStoreCalls.withValue { $0 += 1 }
                return .init()
            }
            $0.contentTabPinnedRecordClient.saveStore = { _, _ in
                pinnedStoreCalls.withValue { $0 += 1 }
            }
        }
        // store.exhaustivity = .off: unordered post-commit effect의 호출 횟수와 최종 registry만 검증한다.
        store.exhaustivity = .off

        await store.send(.contentTabMoveRequest(request))
        await fulfillment(of: [activationCalled], timeout: 1)
        await store.skipReceivedActions()
        let stateAfterFirstCommit = store.state
        let notificationStartsAfterFirstCommit = notificationStarts.value

        await store.send(.contentTabMoveRequest(request))

        XCTAssertEqual(store.state, stateAfterFirstCommit)
        XCTAssertEqual(
            store.state.windows[id: targetID]?.window.contentTabs.tabs.count(where: { $0.id == movedTabID }),
            1,
        )
        XCTAssertEqual(activatedIDs.value, [targetID])
        XCTAssertTrue(closedIDs.value.isEmpty)
        XCTAssertEqual(movedUndoScopes.value.map(\.0), [
            UndoManagerScope(windowID: sourceID, contentTabID: movedTabID.rawValue),
        ])
        XCTAssertEqual(movedUndoScopes.value.map(\.1), [
            UndoManagerScope(windowID: targetID, contentTabID: movedTabID.rawValue),
        ])
        XCTAssertEqual(notificationStarts.value, notificationStartsAfterFirstCommit)
        XCTAssertEqual(pinnedStoreCalls.value, 0)
    }

    /// CTM-001-move_content_tab_to_another_window: 다른 request ID의 동일 tab 재요청은 missing으로 거절한다.
    /// - 검증 내용: source failure terminal과 target 단일 copy
    /// - 사전 조건: moved tab은 target에만 있고 source는 matching second pending을 보유한다.
    /// - 기대 결과: unavailable rejection이며 target 중복은 생성되지 않는다.
    func testContentTabMoveDifferentRequestAfterSuccessRejectsMissingSourceTab() async throws {
        let sourceID = UUID()
        let targetID = UUID()
        let movedTabID = ContentTabID(rawValue: "different-request-moved")
        let secondRequest = ContentTabMoveRequest(
            requestID: UUID(),
            sourceWindowID: sourceID,
            tabID: movedTabID,
            targetWindowID: targetID,
        )
        var source = try Self.makeContentTabMoveWindow(
            id: sourceID,
            tabs: [(ContentTabID(rawValue: "different-request-source"), "/different/source")],
        )
        source.window.sidebar.pendingContentTabMoveRequest = secondRequest
        source.window.pendingContentTabMove = .init(request: secondRequest, lifecycle: .inFlight)
        let target = try Self.makeContentTabMoveWindow(
            id: targetID,
            tabs: [
                (ContentTabID(rawValue: "different-request-target"), "/different/target"),
                (movedTabID, "/different/moved"),
            ],
        )
        var initialState = WindowManagerFeature.State()
        initialState.windows = [source, target]
        let store = TestStore(initialState: initialState) { WindowManagerFeature() }
        store.exhaustivity = .off

        await store.send(.contentTabMoveRequest(secondRequest))
        await store.receive {
            Self.isContentTabMoveRejection($0, request: secondRequest, category: .unavailable)
        }

        XCTAssertEqual(
            store.state.windows[id: targetID]?.window.contentTabs.tabs.count(where: { $0.id == movedTabID }),
            1,
        )
        XCTAssertEqual(
            store.state.windows[id: sourceID]?.window.contentTabMoveFailurePresentation?.category,
            .unavailable,
        )
        XCTAssertEqual(
            store.state.contentTabMoveTerminalRecords[secondRequest.requestID]?.outcome,
            .rejected(.unavailable),
        )
    }

    /// CTM-001-move_content_tab_to_another_window: terminal ledger는 256 FIFO 상한을 지킨다.
    /// - 검증 내용: 257번째 기록 후 oldest eviction과 newer outcome 보존
    /// - 사전 조건: 서로 다른 request ID 257개를 순서대로 기록한다.
    /// - 기대 결과: 첫 ID만 제거되고 마지막 256개가 순서대로 남는다.
    func testContentTabMoveTerminalLedgerEvictsOldestAtLimit() throws {
        let requestIDs = (0 ... WindowManagerState.contentTabMoveTerminalLimit).map { UUID($0 + 1) }
        var state = WindowManagerFeature.State()

        for (index, requestID) in requestIDs.enumerated() {
            state.recordContentTabMoveTerminal(.init(
                requestID: requestID,
                sourceWindowID: UUID(1000 + index),
                tabID: ContentTabID(rawValue: "ledger-\(index)"),
                targetWindowID: UUID(2000 + index),
                outcome: index.isMultiple(of: 2) ? .succeeded : .rejected(.busy),
            ))
        }

        XCTAssertEqual(state.contentTabMoveTerminalRequestIDs.count, 256)
        XCTAssertEqual(state.contentTabMoveTerminalRecords.count, 256)
        XCTAssertNil(state.contentTabMoveTerminalRecords[requestIDs[0]])
        XCTAssertEqual(state.contentTabMoveTerminalRequestIDs.first, requestIDs[1])
        XCTAssertEqual(try state.contentTabMoveTerminalRecords[XCTUnwrap(requestIDs.last)]?.outcome, .succeeded)
    }

    /// CTM-001-move_content_tab_to_another_window: full/closing/source를 projection에서 제외한다.
    /// - 검증 내용: MRU 우선, registry fallback, capacity와 closing exclusion
    /// - 사전 조건: source, live target, full target, closing target이 registry에 존재한다.
    /// - 기대 결과: source projection에는 live target 하나만 노출된다.
    func testContentTabMoveProjectionExcludesSourceClosingAndFullWindows() async throws {
        let sourceID = UUID()
        let liveID = UUID()
        let fullID = UUID()
        let closingID = UUID()
        let source = try Self.makeContentTabMoveWindow(
            id: sourceID,
            tabs: [(ContentTabID(rawValue: "projection-source"), "/projection/source")],
        )
        let live = try Self.makeContentTabMoveWindow(
            id: liveID,
            tabs: [(ContentTabID(rawValue: "projection-live"), "/projection/live")],
        )
        let fullTabs = (0 ..< ContentTabConstants.maxTabs).map { index in
            (ContentTabID(rawValue: "projection-full-\(index)"), "/projection/full/\(index)")
        }
        let full = try Self.makeContentTabMoveWindow(id: fullID, tabs: fullTabs)
        let closing = try Self.makeContentTabMoveWindow(
            id: closingID,
            tabs: [(ContentTabID(rawValue: "projection-closing"), "/projection/closing")],
        )
        var initialState = WindowManagerFeature.State()
        initialState.windows = [source, full, closing, live]
        initialState.lastUsedWindowIDs = [fullID, liveID]
        initialState.closingWindowIDs = [closingID]
        let store = TestStore(initialState: initialState) { WindowManagerFeature() }
        store.exhaustivity = .off

        await store.send(.refreshContentTabMoveTargets)

        XCTAssertEqual(
            store.state.windows[id: sourceID]?.window.sidebar.contentTabMoveTargets.map(\.windowID),
            [liveID],
        )
    }

    /// CTM-001-move_content_tab_to_another_window: full target은 passive same-ID pinned projection 교체에만 노출된다.
    /// capacity 증가 없는 pinned 이동은 메뉴·drag source route에서 도달 가능하고 다른 tab에는 숨겨지는지 검증한다.
    /// - 검증 내용: tab-aware full-target projection과 row별 acceptance
    /// - 사전 조건: source/target에 같은 passive pinned ID가 있고 target은 다른 tab을 포함해 maxTabs로 가득 참
    /// - 기대 결과: pinned source tab에는 target이 허용되고 unrelated source tab에는 허용되지 않음
    func testContentTabMoveProjectionAllowsFullTargetOnlyForPassivePinnedReplacement() throws {
        let sourceID = UUID()
        let targetID = UUID()
        let pinnedTabID = ContentTabID(rawValue: "projection-full-pinned")
        let unrelatedTabID = ContentTabID(rawValue: "projection-full-unrelated")
        let pinnedRecord = ContentTabPinnedRecord(
            id: pinnedTabID.rawValue,
            page: .directory,
            anchor: .directory(path: "/projection/pinned"),
            title: "Pinned",
            iconName: "folder",
            pinnedAt: Date(timeIntervalSince1970: 451),
        )
        let restored = ContentTabState.restoringPinnedRecords(
            from: ContentTabPinnedRecordStore(records: [pinnedRecord]),
            isRestorableAnchor: { _ in true },
        ).state
        var source = FileManagerWindowFeature.State.makeInitial(path: "/source", windowID: sourceID)
        source.applyPinnedContentTabs(restored)
        source.contentTabs.tabs.append(.init(
            id: unrelatedTabID,
            page: .directory,
            anchor: .directory(path: "/source/unrelated"),
            isPinned: false,
            title: "Unrelated",
            iconName: "folder",
        ))
        source.tabContentStates[unrelatedTabID] = FileManagerContentFeature.State.initialContent(
            for: .directory(path: "/source/unrelated"),
            inheritingWindowContextFrom: source.content,
        )
        source.tabInspectorStates[unrelatedTabID] = FileManagerInspectorFeature.State().tabSnapshot()

        var target = FileManagerWindowFeature.State.makeInitial(path: "/target", windowID: targetID)
        target.applyPinnedContentTabs(restored)
        let remainingCapacity = ContentTabConstants.maxTabs - target.contentTabs.tabs.count
        for index in 0 ..< remainingCapacity {
            let tabID = ContentTabID(rawValue: "projection-full-filler-\(index)")
            let anchor = ContentTabPageAnchor.directory(path: "/target/filler/\(index)")
            target.contentTabs.tabs.append(.init(
                id: tabID,
                page: .directory,
                anchor: anchor,
                isPinned: false,
                title: "Filler \(index)",
                iconName: "folder",
            ))
            target.tabContentStates[tabID] = FileManagerContentFeature.State.initialContent(
                for: anchor,
                inheritingWindowContextFrom: target.content,
            )
            target.tabInspectorStates[tabID] = FileManagerInspectorFeature.State().tabSnapshot()
        }
        var state = WindowManagerFeature.State()
        state.windows = [
            .init(id: sourceID, window: source),
            .init(id: targetID, window: target),
        ]

        state.refreshContentTabMoveTargets()

        let projectedTarget = try XCTUnwrap(
            state.windows[id: sourceID]?.window.sidebar.contentTabMoveTargets.first(where: {
                $0.windowID == targetID
            }),
        )
        XCTAssertFalse(projectedTarget.acceptsNewTabs)
        XCTAssertTrue(projectedTarget.accepts(tabID: pinnedTabID))
        XCTAssertFalse(projectedTarget.accepts(tabID: unrelatedTabID))
        let sourceTargets = try XCTUnwrap(
            state.windows[id: sourceID]?.window.sidebar.contentTabMoveTargets,
        )
        let pinnedTargetIDs = ContentTabMoveProjection.availableTargets(
            sourceTargets,
            currentWindowID: sourceID,
            tabID: pinnedTabID,
        )
        .map(\.windowID)
        XCTAssertEqual(pinnedTargetIDs, [targetID])
        let unrelatedTargets = ContentTabMoveProjection.availableTargets(
            sourceTargets,
            currentWindowID: sourceID,
            tabID: unrelatedTabID,
        )
        XCTAssertTrue(unrelatedTargets.isEmpty)
    }

    /// CTM-001-move_content_tab_to_another_window: last-tab commit은 source를 tombstone으로 전환한다.
    /// - 검증 내용: exact close/activate ID, logical commit, focus callback ownership, late close idempotency
    /// - 사전 조건: focused source에 tab 하나, target에 tab 하나가 존재한다.
    /// - 기대 결과: source는 closing tombstone으로 유지되고 native callback 전 focus는 해제된다.
    func testContentTabMoveLastTabUsesExactCloseAndCallbackOwnedFocus() async throws {
        let sourceID = UUID()
        let targetID = UUID()
        let movedTabID = ContentTabID(rawValue: "last-tab-moved")
        let request = ContentTabMoveRequest(
            requestID: UUID(),
            sourceWindowID: sourceID,
            tabID: movedTabID,
            targetWindowID: targetID,
        )
        var source = try Self.makeContentTabMoveWindow(id: sourceID, tabs: [(movedTabID, "/last/source")])
        source.window.sidebar.pendingContentTabMoveRequest = request
        source.window.pendingContentTabMove = .init(request: request, lifecycle: .inFlight)
        let target = try Self.makeContentTabMoveWindow(
            id: targetID,
            tabs: [(ContentTabID(rawValue: "last-target"), "/last/target")],
        )
        var initialState = WindowManagerFeature.State()
        initialState.windows = [source, target]
        initialState.focusedWindowID = sourceID
        initialState.lastUsedWindowIDs = [sourceID, targetID]
        let activatedIDs = LockIsolated<[UUID]>([])
        let closedIDs = LockIsolated<[UUID]>([])
        let notificationStarts = LockIsolated(0)
        let registry = FileOperationUndoManagerRegistry()
        let undoClient = FileOperationUndoManagerClient.live(registry: registry)
        let sourceScope = UndoManagerScope(windowID: sourceID, contentTabID: movedTabID.rawValue)
        let targetScope = UndoManagerScope(windowID: targetID, contentTabID: movedTabID.rawValue)
        let sourceUndoManager = try XCTUnwrap(undoClient.activate(sourceScope))
        let activationCalled = expectation(description: "last-tab target activation")
        let closeCalled = expectation(description: "last-tab source close")
        let store = TestStore(initialState: initialState) {
            WindowManagerFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 450))
            $0.fileManagerWindowClient.activate = { id in
                activatedIDs.withValue { $0.append(id) }
                activationCalled.fulfill()
                return .discarded
            }
            $0.fileManagerWindowClient.close = { id in
                closedIDs.withValue { $0.append(id) }
                closeCalled.fulfill()
            }
            $0.fileOperationUndoManagerClient = undoClient
            $0.notificationCenterClient.notifications = { _, _ in
                notificationStarts.withValue { $0 += 1 }
                return AsyncStream { $0.finish() }
            }
        }
        // store.exhaustivity = .off: native activate/close의 상대 완료 순서는 계약이 아니다.
        store.exhaustivity = .off

        await store.send(.contentTabMoveRequest(request))
        await fulfillment(of: [activationCalled, closeCalled], timeout: 1)
        await store.skipReceivedActions()

        XCTAssertEqual(store.state.windows[id: sourceID]?.window.contentTabs.tabs.count, 0)
        XCTAssertTrue(store.state.closingWindowIDs.contains(sourceID))
        XCTAssertNil(store.state.focusedWindowID)
        XCTAssertEqual(
            store.state.windows[id: targetID]?.window.contentTabs.tabs.count(where: { $0.id == movedTabID }),
            1,
        )
        XCTAssertEqual(activatedIDs.value, [targetID])
        XCTAssertEqual(closedIDs.value, [sourceID])
        XCTAssertEqual(notificationStarts.value, 1)
        let removedSourceUndoManager = await undoClient.undoManager(sourceScope)
        let movedTargetUndoManagerValue = await undoClient.undoManager(targetScope)
        let movedTargetUndoManager = try XCTUnwrap(movedTargetUndoManagerValue)
        XCTAssertNil(removedSourceUndoManager)
        XCTAssertIdentical(sourceUndoManager, movedTargetUndoManager)

        await store.send(.event(.windowClosed(sourceID)))
        await store.send(.event(.windowClosed(sourceID)))

        XCTAssertFalse(store.state.closingWindowIDs.contains(sourceID))
        XCTAssertNil(store.state.focusedWindowID)
        XCTAssertEqual(closedIDs.value, [sourceID])
    }

    /// CTM-001-move_content_tab_to_another_window: discarded와 late mismatched activation은 logical commit을 뒤집지 않는다.
    /// - 검증 내용: attempt equality cleanup과 target 단일 copy 보존
    /// - 사전 조건: logical success 뒤 matching attempt가 registry에 존재한다.
    /// - 기대 결과: mismatched callback은 no-op, matching discarded는 attempt만 제거한다.
    func testContentTabMoveActivationDiscardAndLateMismatchNeverRollback() async throws {
        let sourceID = UUID()
        let targetID = UUID()
        let movedTabID = ContentTabID(rawValue: "discarded-moved")
        let requestID = UUID()
        let request = ContentTabMoveRequest(
            operationID: UUID(),
            requestID: requestID,
            sourceWindowID: sourceID,
            initiatingTabID: movedTabID,
            orderedTabIDs: [movedTabID],
            targetWindowID: targetID,
        )
        let mismatchedRequest = ContentTabMoveRequest(
            operationID: UUID(),
            requestID: requestID,
            sourceWindowID: sourceID,
            initiatingTabID: movedTabID,
            orderedTabIDs: [movedTabID],
            targetWindowID: UUID(),
        )
        let attempt = ContentTabMoveActivationAttempt(request: request)
        let mismatched = ContentTabMoveActivationAttempt(request: mismatchedRequest)
        var initialState = WindowManagerFeature.State()
        initialState.windows = try [
            Self.makeContentTabMoveWindow(
                id: sourceID,
                tabs: [(ContentTabID(rawValue: "discarded-source"), "/discarded/source")],
            ),
            Self.makeContentTabMoveWindow(
                id: targetID,
                tabs: [(movedTabID, "/discarded/moved")],
            ),
        ]
        initialState.contentTabMoveActivationAttempts[requestID] = attempt
        initialState.recordContentTabMoveTerminal(.init(request: request, outcome: .succeeded))
        let store = TestStore(initialState: initialState) { WindowManagerFeature() }

        await store.send(.contentTabMoveActivationResult(attempt: mismatched, result: .becameKey))
        await store.send(.contentTabMoveActivationResult(attempt: attempt, result: .discarded)) {
            $0.contentTabMoveActivationAttempts[requestID] = nil
        }
        await store.send(.contentTabMoveActivationResult(attempt: attempt, result: .becameKey))

        XCTAssertEqual(
            store.state.windows[id: targetID]?.window.contentTabs.tabs.count(where: { $0.id == movedTabID }),
            1,
        )
        XCTAssertNil(store.state.windows[id: sourceID]?.window.contentTabs.tabs[id: movedTabID])
        XCTAssertEqual(store.state.contentTabMoveTerminalRecords[requestID]?.outcome, .succeeded)
    }

    /// CTM-001-move_content_tab_to_another_window: native activation 중에는 후속 move transaction을 시작하지 않는다.
    /// 이전 AppKit focus side effect가 끝나기 전 transaction ownership을 유지하는 직렬화 경계를 검증한다.
    /// - 검증 내용: 첫 activation 대기 중 후속 request no-op과 activation ledger를 비교한다.
    /// - 사전 조건: 성공 terminal/native plan을 가진 A가 activation gate에서 대기하고 B source/target이 준비된다.
    /// - 기대 결과: A target만 활성화되고 B는 semantic state를 변경하지 않은 채 A transaction 종료 뒤 허용된다.
    func testContentTabMoveActivationSerializesSubsequentMoveRequest() async throws {
        let firstRequest = ContentTabMoveRequest(
            operationID: UUID(51001),
            requestID: UUID(51002),
            sourceWindowID: UUID(51003),
            initiatingTabID: ContentTabID(rawValue: "activation-first"),
            orderedTabIDs: [ContentTabID(rawValue: "activation-first")],
            targetWindowID: UUID(51004),
        )
        let secondRequest = ContentTabMoveRequest(
            operationID: UUID(51005),
            requestID: UUID(51006),
            sourceWindowID: UUID(51007),
            initiatingTabID: ContentTabID(rawValue: "activation-second"),
            orderedTabIDs: [ContentTabID(rawValue: "activation-second")],
            targetWindowID: UUID(51008),
        )
        let firstGate = ContentTabMoveActivationGate()
        let nativeActivationTargets = LockIsolated<[UUID]>([])
        var initialState = WindowManagerFeature.State()
        var secondSource = try Self.makeContentTabMoveWindow(
            id: secondRequest.sourceWindowID,
            tabs: [(secondRequest.initiatingTabID, "/activation/second-source")],
        )
        Self.prepareContentTabMoveRequest(secondRequest, in: &secondSource)
        initialState.windows = [
            .init(
                id: firstRequest.targetWindowID,
                window: .makeInitial(path: "/activation/first"),
            ),
            .init(
                id: secondRequest.targetWindowID,
                window: .makeInitial(path: "/activation/second"),
            ),
            secondSource,
        ]
        initialState.recordContentTabMoveTerminal(.init(request: firstRequest, outcome: .succeeded))
        initialState.contentTabMoveTransactions[firstRequest.requestID] = .init(request: firstRequest)
        initialState.contentTabMoveNativeEffectsPlans[firstRequest.requestID] = .init(
            request: firstRequest,
            closesSourceWindow: false,
        )
        initialState.contentTabMoveActivationAttempts[firstRequest.requestID] = .init(request: firstRequest)
        let store = TestStore(initialState: initialState) { WindowManagerFeature() } withDependencies: {
            $0.fileManagerWindowClient.activate = { id in
                if id == firstRequest.targetWindowID {
                    await firstGate.wait()
                    guard !Task.isCancelled else { return .discarded }
                }
                nativeActivationTargets.withValue { $0.append(id) }
                return .discarded
            }
        }
        // store.exhaustivity = .off: concurrent activation result 정리는 최종 state와 native call ledger로 검증한다.
        store.exhaustivity = .off

        await store.send(.contentTabMoveNativeEffectsRequested(request: firstRequest))
        await firstGate.waitUntilWaiting()
        await store.send(.contentTabMoveRequest(secondRequest))
        XCTAssertEqual(
            store.state.contentTabMoveTerminalRecords[secondRequest.requestID]?.outcome,
            .rejected(.busy),
        )
        XCTAssertNotNil(store.state.windows[id: secondRequest.sourceWindowID]?.window.contentTabs.tabs[
            id: secondRequest.initiatingTabID,
        ])
        await firstGate.release()
        await store.skipReceivedActions()
        await store.finish()

        XCTAssertEqual(nativeActivationTargets.value, [firstRequest.targetWindowID])
        XCTAssertNil(store.state.contentTabMoveActivationAttempts[firstRequest.requestID])
        XCTAssertNil(store.state.contentTabMoveTransactions[firstRequest.requestID])
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
        let finalizedWindowIDs = LockIsolated<[UUID]>([])
        let store = TestStore(initialState: initialState) {
            WindowManagerFeature()
        } withDependencies: {
            $0.uuid = .constant(newWindowID)
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
            $0.onboardingWindowClient.showIfNeeded = { false }
            $0.fileManagerWindowClient.open = { _ in }
            $0.fileManagerWindowClient.registeredWindowIDs = { [newWindowID] }
            $0.fileManagerWindowClient.finalizeClose = { id in
                finalizedWindowIDs.withValue { $0.append(id) }
            }
            $0.undoManagerClient.invalidateWindow = { _ in
                .init(succeeded: true, availability: .init())
            }
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
            $0.closingWindowIDs.insert(secondID)
            $0.invalidatingWindowIDs.insert(secondID)
            $0.refreshContentTabMoveTargets()
        }
        await store.receive(\.windowInvalidationFinished) {
            $0.windows.remove(id: secondID)
            $0.closingWindowIDs.remove(secondID)
            $0.invalidatingWindowIDs.remove(secondID)
            $0.lastUsedWindowIDs = [firstID]
            $0.refreshContentTabMoveTargets()
        }
        await store.send(.file(.newWindow(path: "/new")))
        await store.skipReceivedActions()
        await store.finish()

        XCTAssertEqual(finalizedWindowIDs.value, [secondID])
        XCTAssertEqual(store.state.windows.map(\.id), [firstID, newWindowID])
        XCTAssertEqual(store.state.focusedWindowID, newWindowID)
        XCTAssertEqual(store.state.lastUsedWindowIDs, [newWindowID, firstID])
        XCTAssertTrue(store.state.pendingWindowOpenIDs.isEmpty)
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

    /// Existing-window external reservation은 batch coordinator 전체 lifetime에서 append 전에 거부된다.
    /// - 검증 내용: current item과 inter-item gap에서 application nil 및 기존 tab identity 불변
    /// - 사전 조건: existing Window에 selected-tab batch coordinator가 있고 external reservation 1개가 계획됨
    /// - 기대 결과: reservation tab이 추가되지 않으며 new-window placement 정책에는 영향을 주지 않음
    func testPlacementApplicationRejectsExistingWindowReservationForBatchCurrentAndGap() throws {
        let batchID = UUID()
        let windowID = UUID()
        let itemID = UUID()
        let reservedTabID = ContentTabID(rawValue: "batch-blocked-external")

        for hasCurrentItem in [true, false] {
            var window = FileManagerWindowFeature.State.makeInitial(path: "/existing")
            let originalTabIDs = window.contentTabs.tabs.map(\.id)
            let activeTabID = try XCTUnwrap(window.contentTabs.activeTabID)
            window.pendingSelectedContentTabClose = PendingSelectedContentTabClose(
                operationID: UUID(),
                orderedTargetIDs: [activeTabID, ContentTabID(rawValue: "queued-target")],
                cursor: hasCurrentItem ? 0 : 1,
                currentTabID: hasCurrentItem ? activeTabID : nil,
                originalActiveTabID: activeTabID,
                preferredFallbackIDs: [],
            )
            let plan = ExternalOpenPlacementPlan(
                batchID: batchID,
                windows: [.init(
                    windowID: windowID,
                    isNewWindow: false,
                    items: [.init(itemID: itemID, tabID: reservedTabID)],
                )],
            )
            let windows: IdentifiedArrayOf<WindowSessionState> = [
                .init(id: windowID, window: window),
            ]

            let application = ExternalOpenPlacementApplication.apply(
                plan,
                reservationsByItemID: [
                    itemID: .init(id: reservedTabID, anchor: .directory(path: "/blocked")),
                ],
                to: windows,
            )

            XCTAssertNil(application)
            XCTAssertEqual(windows[id: windowID]?.window.contentTabs.tabs.map(\.id), originalTabIDs)
            XCTAssertNil(windows[id: windowID]?.window.contentTabs.tabs[id: reservedTabID])
        }
    }

    /// 기존 mounted window의 external reservations은 state commit 후 모든 Undo scope와 canonical tab handoff가 활성화된다.
    /// Directory load가 장기 실행 중이어도 apply terminal은 load 완료를 기다리지 않는 경계를 검증한다.
    /// - 검증 내용: ordered append, 전체 reservation scope 활성화, old→new active 전환, suspended load 전 terminal 1회다.
    /// - 사전 조건: seed tab이 active인 기존 window와 Directory reservation 두 개다.
    /// - 기대 결과: 각 preallocated tab에 독립 manager가 생기고 마지막 tab이 active인 채 terminal이 load 전에 도착한다.
    func testPlacementApplicationActivatesExistingWindowWithoutAwaitingDirectoryLoad() async throws {
        let batchID = UUID()
        let windowID = UUID()
        let firstItemID = UUID()
        let secondItemID = UUID()
        let firstTabID = ContentTabID(rawValue: "existing-window-external-first")
        let secondTabID = ContentTabID(rawValue: "existing-window-external-second")
        var existingWindow = FileManagerWindowFeature.State.makeInitial(path: "/seed")
        existingWindow.content.entryViewLayout.entryOperations.windowID = windowID
        existingWindow.content.composer.cancellationOwnerID = windowID
        existingWindow.syncActiveTabContentState()
        let previousActiveID = try XCTUnwrap(existingWindow.contentTabs.activeTabID)
        let registry = FileOperationUndoManagerRegistry()
        let client = FileOperationUndoManagerClient.live(registry: registry)
        let seedScope = UndoManagerScope(windowID: windowID, contentTabID: previousActiveID.rawValue)
        let seedManager = client.activate(seedScope)
        let seedGeneration = try XCTUnwrap(client.generation(seedScope))
        var initialState = WindowManagerFeature.State()
        initialState.windows = [.init(id: windowID, window: existingWindow)]
        initialState.authorizedExternalOpenBatchID = batchID
        let plan = ExternalOpenPlacementPlan(
            batchID: batchID,
            windows: [
                .init(
                    windowID: windowID,
                    isNewWindow: false,
                    items: [
                        .init(itemID: firstItemID, tabID: firstTabID),
                        .init(itemID: secondItemID, tabID: secondTabID),
                    ],
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
            $0.fileOperationUndoManagerClient = client
            $0.entryLoadingClient.loadItems = { url, _ in
                XCTAssertEqual(url.path, "/external-second")
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
                firstItemID: .init(id: firstTabID, anchor: .directory(path: "/external-first")),
                secondItemID: .init(id: secondTabID, anchor: .directory(path: "/external-second")),
            ],
        )))
        await fulfillment(of: [loadStarted, terminalReceived], timeout: 1)
        await store.skipReceivedActions()

        let committedWindow = try XCTUnwrap(store.state.windows[id: windowID]?.window)
        XCTAssertEqual(
            committedWindow.contentTabs.tabs.map(\.id),
            [previousActiveID, firstTabID, secondTabID],
        )
        XCTAssertEqual(committedWindow.contentTabs.activeTabID, secondTabID)
        XCTAssertEqual(committedWindow.contentTabs.previousActiveTabID, previousActiveID)
        XCTAssertEqual(committedWindow.contentTabs.selectedTabIDs, [secondTabID])
        XCTAssertEqual(committedWindow.contentTabs.selectionAnchorID, secondTabID)
        XCTAssertEqual(committedWindow.menuCommandProjection.selectedContentTabCount, 1)
        XCTAssertFalse(committedWindow.menuCommandProjection.canDuplicateSelectedContentTabs)
        XCTAssertEqual(terminalCount.value, 1)

        let firstScope = UndoManagerScope(windowID: windowID, contentTabID: firstTabID.rawValue)
        let secondScope = UndoManagerScope(windowID: windowID, contentTabID: secondTabID.rawValue)
        let firstGeneration = try XCTUnwrap(client.generation(firstScope))
        let secondGeneration = try XCTUnwrap(client.generation(secondScope))
        let firstManagerValue = await client.undoManager(firstScope)
        let secondManagerValue = await client.undoManager(secondScope)
        let firstManager = try XCTUnwrap(firstManagerValue)
        let secondManager = try XCTUnwrap(secondManagerValue)
        XCTAssertNotEqual(firstGeneration, secondGeneration)
        XCTAssertNotIdentical(firstManager, secondManager)
        let currentSeedManager = await client.undoManager(seedScope)
        XCTAssertIdentical(currentSeedManager, seedManager)
        XCTAssertEqual(client.generation(seedScope), seedGeneration)

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
            $0.uuid = .incrementing
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
            result: .init(
                contentTabs: stalePinnedState,
                fixedLocationItems: [],
                topNavigationOrder: .init(),
                arrangementAvailability: .available,
            ),
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

    /// matching cancel은 batch가 만든 새 window만 rollback하고 기존 reservation과 unrelated state는 보존한다.
    /// 늦은 windowClosed callback과 stale cancel은 추가 native close나 state 변경을 만들지 않는다.
    func testPlacementCancellationRollsBackOnlyOwnedNewWindows() async {
        let batchID = UUID()
        let otherBatchID = UUID()
        let existingWindowID = UUID()
        let newWindowID = UUID()
        let unrelatedWindowID = UUID()
        let existingItemID = UUID()
        let newItemID = UUID()
        let unrelatedBootstrapRequestID = UUID()
        let existingTabID = ContentTabID(rawValue: "cancel-preserved-existing")
        let newTabID = ContentTabID(rawValue: "cancel-removed-new")
        let existingWindow = FileManagerWindowFeature.State.makeInitial(path: "/existing")
        let unrelatedWindow = FileManagerWindowFeature.State.makeInitial(path: "/unrelated")
        let originalExistingTabIDs = existingWindow.contentTabs.tabs.map(\.id)
        let plan = ExternalOpenPlacementPlan(
            batchID: batchID,
            windows: [
                .init(
                    windowID: existingWindowID,
                    isNewWindow: false,
                    items: [.init(itemID: existingItemID, tabID: existingTabID)],
                ),
                .init(
                    windowID: newWindowID,
                    isNewWindow: true,
                    items: [.init(itemID: newItemID, tabID: newTabID)],
                ),
            ],
        )
        var initialState = WindowManagerFeature.State()
        initialState.windows = [
            .init(id: existingWindowID, window: existingWindow),
            .init(id: unrelatedWindowID, window: unrelatedWindow),
        ]
        initialState.focusedWindowID = unrelatedWindowID
        initialState.lastUsedWindowIDs = [unrelatedWindowID, existingWindowID]
        initialState.defaultWindowBootstrapRequestID = unrelatedBootstrapRequestID
        initialState.defaultWindowBootstrapWindowIDs = [unrelatedWindowID]
        initialState.externalWindowBatchIDs[unrelatedWindowID] = otherBatchID
        initialState.authorizedExternalOpenBatchID = batchID

        let openStarted = expectation(description: "owned native open started")
        let openCancelled = expectation(description: "owned native open cancelled")
        let nativeCloseCalled = expectation(description: "owned native window closed")
        let openGate = AsyncStream<Void>.makeStream()
        let closedWindowIDs = LockIsolated<[UUID]>([])
        let store = TestStore(initialState: initialState) {
            WindowManagerFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 0))
            $0.fileManagerWindowClient.open = { id in
                XCTAssertEqual(id, newWindowID)
                openStarted.fulfill()
                await withTaskCancellationHandler {
                    for await _ in openGate.stream {
                        break
                    }
                } onCancel: {
                    openCancelled.fulfill()
                }
            }
            $0.fileManagerWindowClient.close = { id in
                closedWindowIDs.withValue { $0.append(id) }
                nativeCloseCalled.fulfill()
            }
        }
        // store.exhaustivity = .off: child navigation보다 batch-owned rollback 경계와 native close를 검증함.
        store.exhaustivity = .off

        await store.send(.placement(.apply(
            plan: plan,
            reservationsByItemID: [
                existingItemID: .init(id: existingTabID, anchor: .directory(path: "/existing/reserved")),
                newItemID: .init(id: newTabID, anchor: .directory(path: "/new")),
            ],
        )))
        await fulfillment(of: [openStarted], timeout: 1)
        XCTAssertEqual(
            store.state.retainedExternalOpenPlacementOwnership,
            .init(batchID: batchID, newWindowIDs: [newWindowID]),
        )
        await store.send(.event(.windowBecameKey(newWindowID)))

        await store.send(.placement(.cancel(batchID: batchID)))
        await fulfillment(of: [openCancelled, nativeCloseCalled], timeout: 1)

        XCTAssertEqual(store.state.windows.map(\.id), [existingWindowID, unrelatedWindowID])
        XCTAssertEqual(
            store.state.windows[id: existingWindowID]?.window.contentTabs.tabs.map(\.id),
            originalExistingTabIDs + [existingTabID],
        )
        var normalizedUnrelatedWindow = store.state.windows[id: unrelatedWindowID]?.window
        normalizedUnrelatedWindow?.sidebar.currentWindowID = nil
        normalizedUnrelatedWindow?.sidebar.contentTabMoveTargets = []
        XCTAssertEqual(normalizedUnrelatedWindow, unrelatedWindow)
        XCTAssertEqual(store.state.externalWindowBatchIDs, [unrelatedWindowID: otherBatchID])
        XCTAssertNil(store.state.retainedExternalOpenPlacementOwnership)
        XCTAssertEqual(store.state.defaultWindowBootstrapRequestID, unrelatedBootstrapRequestID)
        XCTAssertEqual(store.state.defaultWindowBootstrapWindowIDs, [unrelatedWindowID])
        XCTAssertEqual(store.state.focusedWindowID, unrelatedWindowID)
        XCTAssertEqual(store.state.lastUsedWindowIDs, [unrelatedWindowID, existingWindowID])
        XCTAssertNil(store.state.authorizedExternalOpenBatchID)
        XCTAssertNil(store.state.externalOpenActivationAttempt)
        XCTAssertEqual(closedWindowIDs.value, [newWindowID])

        await store.send(.event(.windowClosed(newWindowID)))
        await store.send(.placement(.cancel(batchID: batchID)))
        await store.finish()

        XCTAssertEqual(store.state.windows.map(\.id), [existingWindowID, unrelatedWindowID])
        XCTAssertEqual(store.state.externalWindowBatchIDs, [unrelatedWindowID: otherBatchID])
        XCTAssertEqual(closedWindowIDs.value, [newWindowID])
        openGate.continuation.finish()
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
        initialState.retainedExternalOpenPlacementOwnership = .init(
            batchID: batchID,
            newWindowIDs: [windowID],
        )
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

        XCTAssertEqual(
            store.state.retainedExternalOpenPlacementOwnership,
            .init(batchID: batchID, newWindowIDs: [windowID]),
        )
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
            $0.refreshContentTabMoveTargets()
        }
        await store.send(.event(.windowResignedKey(finalWindowID))) {
            $0.focusedWindowID = nil
        }
        await store.send(.event(.windowBecameKey(firstWindowID))) {
            $0.focusedWindowID = firstWindowID
            $0.lastUsedWindowIDs = [firstWindowID, finalWindowID]
            $0.refreshContentTabMoveTargets()
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

    /// B activation request 전에 B가 닫히면 비동기 invalidation 뒤 최신 state의 A를 재시도하고 terminal을 한 번 보낸다.
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
            $0.undoManagerClient.invalidateWindow = { _ in
                .init(succeeded: true, availability: .init())
            }
            $0.fileManagerWindowClient.finalizeClose = { _ in }
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
            $0.closingWindowIDs.insert(finalWindowID)
            $0.invalidatingWindowIDs.insert(finalWindowID)
            $0.refreshContentTabMoveTargets()
        }
        await store.receive(\.windowInvalidationFinished) {
            $0.windows.remove(id: finalWindowID)
            $0.closingWindowIDs.remove(finalWindowID)
            $0.invalidatingWindowIDs.remove(finalWindowID)
            $0.externalWindowBatchIDs[finalWindowID] = nil
            $0.externalOpenActivationAttempt = firstAttempt
            $0.refreshContentTabMoveTargets()
        }
        await fulfillment(of: [firstStarted], timeout: 1)
        tracker.discard(finalWindowID)
        await finalRequestGate.open()

        await store.receive { action in
            action.isActivationResult(finalAttempt, .discarded)
        }
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

    /// becameKey 결과 도착 전에 target이 사라지면 비동기 invalidation 뒤 missing window를 건너뛰고 이전 survivor를 재시도한다.
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
            $0.undoManagerClient.invalidateWindow = { _ in
                .init(succeeded: true, availability: .init())
            }
            $0.fileManagerWindowClient.finalizeClose = { _ in }
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
            $0.closingWindowIDs.insert(finalWindowID)
            $0.invalidatingWindowIDs.insert(finalWindowID)
            $0.refreshContentTabMoveTargets()
        }
        await store.receive(\.windowInvalidationFinished) {
            $0.windows.remove(id: finalWindowID)
            $0.closingWindowIDs.remove(finalWindowID)
            $0.invalidatingWindowIDs.remove(finalWindowID)
            $0.externalWindowBatchIDs[finalWindowID] = nil
            $0.externalOpenActivationAttempt = firstAttempt
            $0.refreshContentTabMoveTargets()
        }
        await store.receive { action in
            action.isActivationResult(firstAttempt, .becameKey)
        } assert: {
            $0.authorizedExternalOpenBatchID = nil
            $0.externalOpenActivationAttempt = nil
        }
        await store.receive(\.delegate.externalOpenActivationCompleted, batchID)
        finalGate.continuation.yield(.becameKey)
        finalGate.continuation.finish()
        await store.receive { action in
            action.isActivationResult(finalAttempt, .becameKey)
        }
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

    /// tracked folder command는 실제 native open이 반환된 뒤에만 terminal을 보낸다.
    func testTrackedFolderCompletesOnlyAfterNativeOpenReturns() async {
        await assertTrackedNativeOpenCompletion(
            command: .openWindow(requestID: UUID(900), path: "/tmp/folder", selectEntryID: nil),
            requestID: UUID(900),
        )
    }

    /// tracked fallback command는 default bootstrap과 무관하게 실제 native open 직후 terminal을 보낸다.
    func testTrackedFallbackCompletesOnlyAfterNativeOpenReturns() async {
        await assertTrackedNativeOpenCompletion(
            command: .openInitialWindow(requestID: UUID(901)),
            requestID: UUID(901),
        )
    }

    /// gate revocation 뒤 queue에 남은 tracked command는 window를 만들지 않고 stale terminal 하나로 종료한다.
    func testRevokedTrackedSingletonCommandIsNoOpAndTerminates() async {
        let requestID = UUID(902)
        let openedIDs = LockIsolated<[UUID]>([])
        let terminalCount = LockIsolated(0)
        let store = TestStore(initialState: WindowManagerFeature.State()) {
            CombineReducers {
                WindowManagerFeature()
                Reduce { _, action in
                    if case .delegate(.trackedSingletonCompleted(requestID: requestID)) = action {
                        terminalCount.withValue { $0 += 1 }
                    }
                    return .none
                }
            }
        } withDependencies: {
            $0.fileManagerWindowClient.open = { id in openedIDs.withValue { $0.append(id) } }
        }
        // store.exhaustivity = .off: revoked command의 no-mutation과 정확히 한 terminal만 검증함.
        store.exhaustivity = .off

        await store.send(.trackedSingleton(.openWindow(
            requestID: requestID,
            path: "/tmp/revoked",
            selectEntryID: nil,
        )))
        await store.receive(\.delegate.trackedSingletonCompleted, requestID)
        await store.finish()

        XCTAssertTrue(store.state.windows.isEmpty)
        XCTAssertTrue(openedIDs.value.isEmpty)
        XCTAssertEqual(terminalCount.value, 1)
    }

    /// onboarding block은 tracked command를 mutate하지 않고 terminal 하나로 종료한다.
    func testTrackedSingletonBlockedByOnboardingTerminatesWithoutWindow() async {
        let requestID = UUID(904)
        var initialState = WindowManagerFeature.State()
        initialState.authorizedTrackedSingletonRequestID = requestID
        let store = TestStore(initialState: initialState) {
            WindowManagerFeature()
        } withDependencies: {
            $0.onboardingWindowClient.showIfNeeded = { true }
        }

        await store.send(.trackedSingleton(.openWindow(
            requestID: requestID,
            path: "/tmp/onboarding-blocked",
            selectEntryID: nil,
        ))) {
            $0.authorizedTrackedSingletonRequestID = nil
        }
        await store.receive(\.delegate.trackedSingletonCompleted, requestID)
        XCTAssertTrue(store.state.windows.isEmpty)
    }

    /// existing fallback window는 새 창을 만들지 않고 tracked terminal 하나로 종료한다.
    func testTrackedFallbackWithExistingWindowTerminatesWithoutDuplicate() async {
        let requestID = UUID(905)
        let windowID = UUID(906)
        var initialState = WindowManagerFeature.State()
        initialState.windows = [.init(id: windowID, window: .makeInitial(path: "/existing"))]
        initialState.authorizedTrackedSingletonRequestID = requestID
        let store = TestStore(initialState: initialState) {
            WindowManagerFeature()
        }

        await store.send(.trackedSingleton(.openInitialWindow(requestID: requestID))) {
            $0.authorizedTrackedSingletonRequestID = nil
        }
        await store.receive(\.delegate.trackedSingletonCompleted, requestID)
        XCTAssertEqual(Array(store.state.windows.ids), [windowID])
    }

    // MARK: - VOY-470-cross_window_committed_order

    /// VOY-470: pending overlay가 없는 peer는 source의 committed mixed order에 수렴한다.
    /// - 검증 내용: committed snapshot의 confirmed/visible peer fan-out
    /// - 사전 조건: 두 live window와 overlay가 없는 receiving window
    /// - 기대 결과: receiving window의 confirmed/optimistic order가 commit과 동일함
    func testCommittedTopNavigationOrderConvergesPeerWithoutOverlay() async {
        let sourceID = UUID(47001)
        let peerID = UUID(47002)
        let pinnedTabID = ContentTabID(rawValue: "tab-b")
        let token = FileManagerTopNavigationOperationToken(value: UUID(47003))
        let oldOrder = FileManagerTopNavigationOrder(items: [
            .location("location-a"),
            .contentTab(ContentTabID(rawValue: "tab-a")),
        ])
        let committedOrder = FileManagerTopNavigationOrder(items: [
            .contentTab(ContentTabID(rawValue: "tab-a")),
            .location("location-a"),
            .contentTab(pinnedTabID),
        ])
        var source = FileManagerWindowFeature.State.makeInitial(path: "/source")
        source.lastConfirmedTopNavigationOrder = oldOrder
        source.optimisticTopNavigationOrder = oldOrder
        var peer = FileManagerWindowFeature.State.makeInitial(path: "/peer")
        peer.lastConfirmedTopNavigationOrder = oldOrder
        peer.optimisticTopNavigationOrder = oldOrder
        var initialState = WindowManagerFeature.State()
        initialState.windows = [
            .init(id: sourceID, window: source),
            .init(id: peerID, window: peer),
        ]
        let persistenceRequest = WindowManagerTopNavigationPersistenceRequest(
            sourceWindowID: sourceID,
            token: token,
            operation: .move(
                source: .contentTab(pinnedTabID),
                destination: .after(.location("location-a")),
                discoveredLocationIDs: [],
            ),
        )
        initialState.topNavigationPersistenceQueue = [persistenceRequest]
        initialState.isTopNavigationPersistenceInFlight = true
        let commit = FileManagerTopNavigationCommit(order: committedOrder, revision: 10)
        let store = TestStore(initialState: initialState) { WindowManagerFeature() }
        // store.exhaustivity = .off: lifecycle success의 pinned sync 내부 action보다 committed order fan-out만 검증한다.
        store.exhaustivity = .off

        await store.send(.topNavigationPersistenceCompleted(.init(
            request: persistenceRequest,
            terminal: .committed(commit),
            authoritativePinnedContentTabs: nil,
        )))
        await store.receive { action in
            guard case let .windows(.element(
                id: id,
                action: .window(.applyCommittedTopNavigationSnapshot(
                    order: order,
                    revision: revision,
                    authoritativePinnedContentTabs: nil,
                )),
            )) = action else { return false }
            return id == peerID && order == committedOrder && revision == commit.revision
        }

        XCTAssertEqual(store.state.windows[id: peerID]?.window.lastConfirmedTopNavigationOrder, committedOrder)
        XCTAssertEqual(store.state.windows[id: peerID]?.window.optimisticTopNavigationOrder, committedOrder)
    }

    /// VOY-470: peer의 dormant/pending overlay는 외부 committed baseline 위에 재생된다.
    /// - 검증 내용: external baseline 저장 후 dormant slot과 pending move replay
    /// - 사전 조건: receiving window에 dormant C와 B-before-A pending intent가 존재
    /// - 기대 결과: 외부 추가 D를 보존한 [L,C,B,A,D] runtime order
    func testCommittedTopNavigationOrderReplaysReceivingWindowOverlays() async {
        let sourceID = UUID(47011)
        let peerID = UUID(47012)
        let sourceToken = FileManagerTopNavigationOperationToken(value: UUID(47013))
        let peerToken = FileManagerTopNavigationOperationToken(value: UUID(47014))
        let tabA = ContentTabID(rawValue: "tab-a")
        let tabB = ContentTabID(rawValue: "tab-b")
        let dormantTab = ContentTabID(rawValue: "tab-c")
        let baseline = FileManagerTopNavigationOrder(items: [
            .location("location-l"),
            .contentTab(tabA),
            .contentTab(tabB),
        ])
        let committedOrder = FileManagerTopNavigationOrder(items: baseline.items + [
            .contentTab(ContentTabID(rawValue: "tab-d")),
        ])
        let expectedRuntime = FileManagerTopNavigationOrder(items: [
            .location("location-l"),
            .contentTab(dormantTab),
            .contentTab(tabB),
            .contentTab(tabA),
            .contentTab(ContentTabID(rawValue: "tab-d")),
        ])
        let expectedOptimistic = FileManagerTopNavigationOrder(items: [
            .location("location-l"),
            .contentTab(tabB),
            .contentTab(tabA),
            .contentTab(ContentTabID(rawValue: "tab-d")),
        ])
        var peer = FileManagerWindowFeature.State.makeInitial(path: "/peer")
        peer.lastConfirmedTopNavigationOrder = baseline
        peer.optimisticTopNavigationOrder = baseline
        peer.dormantContentTabSlots = [.init(
            id: dormantTab,
            before: .location("location-l"),
            after: .contentTab(tabA),
        )]
        peer.pendingTopNavigationIntents = [.init(
            token: peerToken,
            intent: .move(source: .contentTab(tabB), destination: .before(.contentTab(tabA))),
        )]
        peer.replayTopNavigationOverlays()
        var initialState = WindowManagerFeature.State()
        initialState.windows = [
            .init(id: sourceID, window: .makeInitial(path: "/source")),
            .init(id: peerID, window: peer),
        ]
        let persistenceRequest = WindowManagerTopNavigationPersistenceRequest(
            sourceWindowID: sourceID,
            token: sourceToken,
            operation: .move(
                source: .contentTab(tabA),
                destination: .after(.contentTab(tabB)),
                discoveredLocationIDs: ["location-l"],
            ),
        )
        initialState.topNavigationPersistenceQueue = [persistenceRequest]
        initialState.isTopNavigationPersistenceInFlight = true
        let commit = FileManagerTopNavigationCommit(order: committedOrder, revision: 11)
        let store = TestStore(initialState: initialState) { WindowManagerFeature() }
        // store.exhaustivity = .off: parent fan-out 뒤 receiver의 overlay replay 최종 상태를 검증한다.
        store.exhaustivity = .off

        await store.send(.topNavigationPersistenceCompleted(.init(
            request: persistenceRequest,
            terminal: .committed(commit),
            authoritativePinnedContentTabs: nil,
        )))
        await store.receive { action in
            guard case let .windows(.element(
                id: id,
                action: .window(.applyCommittedTopNavigationSnapshot(
                    order: order,
                    revision: revision,
                    authoritativePinnedContentTabs: nil,
                )),
            )) = action else { return false }
            return id == peerID && order == committedOrder && revision == commit.revision
        }

        XCTAssertEqual(store.state.windows[id: peerID]?.window.lastConfirmedTopNavigationOrder, committedOrder)
        XCTAssertEqual(store.state.windows[id: peerID]?.window.optimisticTopNavigationOrder, expectedOptimistic)
        XCTAssertEqual(
            FileManagerTopNavigationOrderPolicy.runtimeOrder(
                authoritativeOrder: expectedOptimistic,
                discoveredLocationIDs: ["location-l"],
                pinnedContentTabIDs: [tabB, tabA, ContentTabID(rawValue: "tab-d")],
                dormantContentTabSlots: peer.dormantContentTabSlots,
            ),
            expectedRuntime,
        )
        XCTAssertEqual(store.state.windows[id: peerID]?.window.dormantContentTabSlots.map(\.id), [dormantTab])
        XCTAssertEqual(store.state.windows[id: peerID]?.window.pendingTopNavigationIntents.map(\.token), [peerToken])
    }

    /// VOY-470: 역순 도착한 independent transaction completion은 최신 locked commit을 되돌리지 않는다.
    /// - 검증 내용: newer pin+reorder commit 뒤 stale reorder-only commit fan-out
    /// - 사전 조건: 두 window가 서로 다른 semantic transaction을 완료하고 terminal이 역순 도착
    /// - 기대 결과: 두 window 모두 두 변경을 포함한 높은 revision snapshot 유지
    func testConcurrentIndependentTopNavigationCommitsKeepLatestCombinedSnapshot() async {
        let firstID = UUID(47021)
        let secondID = UUID(47022)
        let firstToken = FileManagerTopNavigationOperationToken(value: UUID(47023))
        let secondToken = FileManagerTopNavigationOperationToken(value: UUID(47024))
        let tabA = ContentTabID(rawValue: "tab-a")
        let pinnedByPeer = ContentTabID(rawValue: "tab-peer-pin")
        let olderOrder = FileManagerTopNavigationOrder(items: [
            .contentTab(tabA),
            .location("location-l"),
        ])
        let newestCombinedOrder = FileManagerTopNavigationOrder(items: [
            .contentTab(pinnedByPeer),
            .contentTab(tabA),
            .location("location-l"),
        ])
        var initialState = WindowManagerFeature.State()
        initialState.windows = [
            .init(id: firstID, window: .makeInitial(path: "/first")),
            .init(id: secondID, window: .makeInitial(path: "/second")),
        ]
        let newestCommit = FileManagerTopNavigationCommit(order: newestCombinedOrder, revision: 22)
        let staleCommit = FileManagerTopNavigationCommit(order: olderOrder, revision: 21)
        let store = TestStore(initialState: initialState) { WindowManagerFeature() }
        // store.exhaustivity = .off: 두 child completion과 peer fan-out의 revision winner만 검증한다.
        store.exhaustivity = .off

        await store.send(Self.committedTopNavigationAction(
            sourceID: firstID,
            token: firstToken,
            commit: newestCommit,
        ))
        await store.receive { action in
            guard case let .windows(.element(
                id: id,
                action: .window(.applyCommittedTopNavigationSnapshot(
                    order: order,
                    revision: revision,
                    authoritativePinnedContentTabs: nil,
                )),
            )) = action else { return false }
            return id == secondID && order == newestCombinedOrder && revision == newestCommit.revision
        }
        await store.send(Self.committedTopNavigationAction(
            sourceID: secondID,
            token: secondToken,
            commit: staleCommit,
        ))
        await store.receive { action in
            guard case let .windows(.element(
                id: id,
                action: .window(.applyExternalCommittedTopNavigationOrder(order, revision)),
            )) = action else { return false }
            return id == firstID && order == olderOrder && revision == staleCommit.revision
        }

        XCTAssertEqual(store.state.windows[id: firstID]?.window.lastConfirmedTopNavigationOrder, newestCombinedOrder)
        XCTAssertEqual(store.state.windows[id: secondID]?.window.lastConfirmedTopNavigationOrder, newestCombinedOrder)
        XCTAssertEqual(store.state.windows[id: firstID]?.window.lastConfirmedTopNavigationCommitRevision, 22)
        XCTAssertEqual(store.state.windows[id: secondID]?.window.lastConfirmedTopNavigationCommitRevision, 22)
    }

    /// VOY-470: pinned group move는 app-owned FIFO에서 요청·client 호출·source terminal을 각각 한 번만 만든다.
    /// - 검증 내용: movePinnedGroup queue cardinality, committed client argument, correlated source terminal
    /// - 사전 조건: live source window와 gate로 정지한 단일 `[C, A]` group persistence 요청
    /// - 기대 결과: in-flight queue 1건과 client 1회 뒤 queue가 비고 source terminal이 정확히 1회 도착한다.
    func testPinnedGroupMovePersistenceEnqueuesOnceCallsClientOnceAndEmitsOneSourceTerminal() async {
        let sourceID = UUID(47021)
        let token = FileManagerTopNavigationOperationToken(value: UUID(47022))
        let tabA = ContentTabID(rawValue: "app-group-a")
        let tabC = ContentTabID(rawValue: "app-group-c")
        let orderedIDs = [tabC, tabA]
        let destination = FileManagerTopNavigationMoveDestination.before(.location("Downloads"))
        let discoveredLocationIDs = ["Home", "Downloads"]
        let commit = FileManagerTopNavigationCommit(
            order: .init(items: [
                .location("Home"), .contentTab(tabC), .contentTab(tabA), .location("Downloads"),
            ]),
            revision: 21,
        )
        let gate = PinnedRecordMutationGate()
        let clientCallCount = LockIsolated(0)
        let queuedRequestCount = LockIsolated(0)
        let sourceTerminalCount = LockIsolated(0)
        let persistGroup: PinnedGroupMovePersistence = { _, locations, ids, target in
            clientCallCount.withValue { $0 += 1 }
            XCTAssertEqual(locations, discoveredLocationIDs)
            XCTAssertEqual(ids, orderedIDs)
            XCTAssertEqual(target, destination)
            await gate.wait()
            return commit
        }
        var initialState = WindowManagerFeature.State()
        initialState.windows = [.init(id: sourceID, window: .makeInitial(path: "/source"))]
        let store = Store(initialState: initialState) {
            CombineReducers {
                WindowManagerFeature()
                Reduce<WindowManagerFeature.State, WindowManagerFeature.Action> { _, action in
                    if case let .topNavigationPersistenceRequested(request) = action,
                       request.sourceWindowID == sourceID,
                       request.token == token,
                       case let .movePinnedGroup(
                           receivedIDs,
                           receivedDestination,
                           receivedLocationIDs,
                       ) = request.operation,
                       receivedIDs == orderedIDs,
                       receivedDestination == destination,
                       receivedLocationIDs == discoveredLocationIDs
                    {
                        queuedRequestCount.withValue { $0 += 1 }
                    }
                    if case let .windows(.element(
                        id: receivedSourceID,
                        action: .window(.internal(.topNavigationIntentCompleted(
                            token: receivedToken,
                            terminal: .committed(receivedCommit),
                        ))),
                    )) = action,
                        receivedSourceID == sourceID,
                        receivedToken == token,
                        receivedCommit == commit
                    {
                        sourceTerminalCount.withValue { $0 += 1 }
                    }
                    return .none
                }
            }
        } withDependencies: {
            $0.contentTabPinnedRecordClient.moveTopNavigationPinnedGroupCommitted = persistGroup
        }

        let task = store.send(.windows(.element(
            id: sourceID,
            action: .window(.delegate(.persistTopNavigationPinnedGroupMove(
                token: token,
                orderedIDs: orderedIDs,
                destination: destination,
                discoveredLocationIDs: discoveredLocationIDs,
            ))),
        )))
        await gate.waitUntilWaiting()

        store.withState { state in
            XCTAssertEqual(state.topNavigationPersistenceQueue.count, 1)
            XCTAssertEqual(state.topNavigationPersistenceQueue.first?.sourceWindowID, sourceID)
            XCTAssertTrue(state.isTopNavigationPersistenceInFlight)
        }
        XCTAssertEqual(queuedRequestCount.value, 1)
        XCTAssertEqual(clientCallCount.value, 1)

        await gate.open()
        await task.finish()

        store.withState { state in
            XCTAssertTrue(state.topNavigationPersistenceQueue.isEmpty)
            XCTAssertFalse(state.isTopNavigationPersistenceInFlight)
        }
        XCTAssertEqual(queuedRequestCount.value, 1)
        XCTAssertEqual(clientCallCount.value, 1)
        XCTAssertEqual(sourceTerminalCount.value, 1)
    }

    /// VOY-470: source window가 persistence completion 전에 닫혀도 남은 window는 commit을 수신한다.
    /// - 검증 내용: 실제 child move 요청, parent-owned persistence effect, source close, live peer fan-out
    /// - 사전 조건: persistence client가 대기하는 동안 source window 종료
    /// - 기대 결과: source는 재생성되지 않고 peer만 durable committed order로 수렴
    func testCommittedTopNavigationOrderFansOutAfterSourceWindowCloses() async {
        let sourceID = UUID(47031)
        let peerID = UUID(47032)
        let token = FileManagerTopNavigationOperationToken(value: UUID(47033))
        let sourceItem = FileManagerTopNavigationItemID.location("location-source")
        let destination = FileManagerTopNavigationMoveDestination.before(.location("location-live"))
        let committedOrder = FileManagerTopNavigationOrder(items: [
            sourceItem,
            .location("location-live"),
            .contentTab(ContentTabID(rawValue: "tab-live")),
        ])
        var initialState = WindowManagerFeature.State()
        initialState.windows = [
            .init(id: sourceID, window: .makeInitial(path: "/source")),
            .init(id: peerID, window: .makeInitial(path: "/peer")),
        ]
        initialState.windows[id: sourceID]?.window.lastConfirmedTopNavigationOrder = .init(items: [
            .location("location-live"), sourceItem,
        ])
        initialState.windows[id: sourceID]?.window.optimisticTopNavigationOrder = .init(items: [
            .location("location-live"), sourceItem,
        ])
        let commit = FileManagerTopNavigationCommit(order: committedOrder, revision: 31)
        let persistenceGate = PinnedRecordMutationGate()
        let store = TestStore(initialState: initialState) { WindowManagerFeature() } withDependencies: {
            $0.contentTabPinnedRecordClient.reserveTopNavigationOperationToken = { token }
            $0.contentTabPinnedRecordClient
                .moveTopNavigationItemCommitted = { _, _, receivedSource, receivedDestination in
                    XCTAssertEqual(receivedSource, sourceItem)
                    XCTAssertEqual(receivedDestination, destination)
                    await persistenceGate.wait()
                    return commit
                }
            $0.undoManagerClient.invalidateWindow = { _ in
                .init(succeeded: true, availability: .init())
            }
            $0.fileManagerWindowClient.finalizeClose = { _ in }
        }
        // store.exhaustivity = .off: child optimistic 세부 state보다 parent effect의 source 수명 독립성을 검증한다.
        store.exhaustivity = .off

        await store.send(.windows(.element(
            id: sourceID,
            action: .window(.topNavigationMoveRequested(source: sourceItem, destination: destination)),
        )))
        await store.receive { action in
            guard case let .windows(.element(
                id: id,
                action: .window(.delegate(.persistTopNavigationMove(receivedToken, _, _, _))),
            )) = action else { return false }
            return id == sourceID && receivedToken == token
        }
        await store.receive { action in
            guard case let .topNavigationPersistenceRequested(request) = action,
                  case let .move(source, receivedDestination, discoveredLocationIDs) = request.operation
            else { return false }
            return request.sourceWindowID == sourceID
                && request.token == token
                && source == sourceItem
                && receivedDestination == destination
                && discoveredLocationIDs.isEmpty
        }
        await persistenceGate.waitUntilWaiting()
        XCTAssertEqual(store.state.topNavigationPersistenceQueue.count, 1)
        XCTAssertEqual(store.state.topNavigationPersistenceQueue.first?.sourceWindowID, sourceID)
        XCTAssertTrue(store.state.isTopNavigationPersistenceInFlight)
        await store.send(.event(.windowClosed(sourceID)))
        XCTAssertNotNil(store.state.windows[id: sourceID])
        XCTAssertTrue(store.state.closingWindowIDs.contains(sourceID))
        XCTAssertTrue(store.state.deferredClosedWindowIDs.contains(sourceID))
        await persistenceGate.open()
        await store.receive { action in
            guard case let .windows(.element(
                id: id,
                action: .window(.applyCommittedTopNavigationSnapshot(
                    order: order,
                    revision: revision,
                    authoritativePinnedContentTabs: nil,
                )),
            )) = action else { return false }
            return id == peerID && order == committedOrder && revision == commit.revision
        }
        await store.skipReceivedActions()

        XCTAssertNil(store.state.windows[id: sourceID])
        XCTAssertEqual(Array(store.state.windows.ids), [peerID])
        XCTAssertEqual(store.state.windows[id: peerID]?.window.lastConfirmedTopNavigationOrder, committedOrder)
    }

    /// VOY-470: order-only fan-out은 same-ID runtime cache와 active/selected identity를 보존한다.
    /// - 검증 내용: committed order 적용 전후 ContentTab runtime/navigation identity 비교
    /// - 사전 조건: receiving window에 active local tab과 selected pinned shared tab/cache 존재
    /// - 기대 결과: order만 변경되고 ContentTab state 및 per-tab runtime cache는 동일함
    func testCommittedTopNavigationOrderPreservesRuntimeAndSelectionIdentity() async {
        let sourceID = UUID(47041)
        let peerID = UUID(47042)
        let token = FileManagerTopNavigationOperationToken(value: UUID(47043))
        let sharedID = ContentTabID(rawValue: "shared-tab")
        let localID = ContentTabID(rawValue: "local-tab")
        var tabs = ContentTabState(
            tabs: .init(uniqueElements: [
                ContentTabItem(
                    id: sharedID,
                    page: .directory,
                    anchor: .directory(path: "/shared"),
                    isPinned: true,
                    title: "Shared",
                    iconName: "folder",
                ),
                ContentTabItem(
                    id: localID,
                    page: .directory,
                    anchor: .directory(path: "/local"),
                    isPinned: false,
                    title: "Local",
                    iconName: "folder",
                ),
            ]),
            activeTabID: localID,
        )
        tabs.selectedTabIDs = [sharedID]
        tabs.selectionAnchorID = sharedID
        var peer = FileManagerWindowFeature.State.makeInitial(path: nil, contentTabs: tabs)
        peer.contentTabs = tabs
        peer.syncContentTabSidebarItems()
        peer.tabContentStates[sharedID] = FileManagerContentFeature.State.initialContent(
            for: ContentTabPageAnchor.directory(path: "/runtime-cache"),
            inheritingWindowContextFrom: peer.content,
        )
        let contentTabsBefore = peer.contentTabs
        let runtimeCacheBefore = peer.tabContentStates
        let activeContentBefore = peer.content
        let committedOrder = FileManagerTopNavigationOrder(items: [
            .location("location-l"),
            .contentTab(sharedID),
        ])
        var initialState = WindowManagerFeature.State()
        initialState.windows = [
            .init(id: sourceID, window: .makeInitial(path: "/source")),
            .init(id: peerID, window: peer),
        ]
        let persistenceRequest = WindowManagerTopNavigationPersistenceRequest(
            sourceWindowID: sourceID,
            token: token,
            operation: .move(
                source: .contentTab(sharedID),
                destination: .after(.location("location-l")),
                discoveredLocationIDs: ["location-l"],
            ),
        )
        initialState.topNavigationPersistenceQueue = [persistenceRequest]
        initialState.isTopNavigationPersistenceInFlight = true
        let commit = FileManagerTopNavigationCommit(order: committedOrder, revision: 41)
        let store = TestStore(initialState: initialState) { WindowManagerFeature() }
        // store.exhaustivity = .off: order 외 runtime/selection 전체 snapshot 불변성을 검증한다.
        store.exhaustivity = .off

        await store.send(.topNavigationPersistenceCompleted(.init(
            request: persistenceRequest,
            terminal: .committed(commit),
            authoritativePinnedContentTabs: nil,
        )))
        await store.receive { action in
            guard case let .windows(.element(
                id: id,
                action: .window(.applyCommittedTopNavigationSnapshot(
                    order: order,
                    revision: revision,
                    authoritativePinnedContentTabs: nil,
                )),
            )) = action else { return false }
            return id == peerID && order == committedOrder && revision == commit.revision
        }

        XCTAssertEqual(store.state.windows[id: peerID]?.window.contentTabs, contentTabsBefore)
        XCTAssertEqual(store.state.windows[id: peerID]?.window.tabContentStates, runtimeCacheBefore)
        XCTAssertEqual(store.state.windows[id: peerID]?.window.content, activeContentBefore)
        XCTAssertEqual(store.state.windows[id: peerID]?.window.contentTabs.activeTabID, localID)
        XCTAssertEqual(store.state.windows[id: peerID]?.window.contentTabs.selectedTabIDs, [sharedID])
        XCTAssertEqual(store.state.windows[id: peerID]?.window.contentTabs.selectionAnchorID, sharedID)
    }

    /// VOY-470: valid external v2 commit은 unavailable receiver를 복구하되 local bytes를 쓰지 않는다.
    /// - 검증 내용: availability/presentation recovery와 receiver-side UserDefaults write 0회
    /// - 사전 조건: corrupt unavailable receiving state와 valid committed snapshot
    /// - 기대 결과: state는 available로 복구되고 invalid local byte rewrite는 없음
    func testCommittedTopNavigationOrderRecoversUnavailablePeerWithoutLocalRewrite() async {
        let sourceID = UUID(47051)
        let peerID = UUID(47052)
        let token = FileManagerTopNavigationOperationToken(value: UUID(47053))
        let writeCount = LockIsolated(0)
        let committedOrder = FileManagerTopNavigationOrder(items: [
            .location("location-recovered"),
            .contentTab(ContentTabID(rawValue: "tab-recovered")),
        ])
        var peer = FileManagerWindowFeature.State.makeInitial(path: "/peer")
        peer.topNavigationArrangementAvailability = .unavailable(.corrupt)
        peer.topNavigationArrangementPresentation = .loadUnavailable
        var initialState = WindowManagerFeature.State()
        initialState.windows = [
            .init(id: sourceID, window: .makeInitial(path: "/source")),
            .init(id: peerID, window: peer),
        ]
        let persistenceRequest = WindowManagerTopNavigationPersistenceRequest(
            sourceWindowID: sourceID,
            token: token,
            operation: .move(
                source: .location("location-recovered"),
                destination: .after(.contentTab(ContentTabID(rawValue: "tab-recovered"))),
                discoveredLocationIDs: ["location-recovered"],
            ),
        )
        initialState.topNavigationPersistenceQueue = [persistenceRequest]
        initialState.isTopNavigationPersistenceInFlight = true
        let commit = FileManagerTopNavigationCommit(order: committedOrder, revision: 51)
        let store = TestStore(initialState: initialState) { WindowManagerFeature() } withDependencies: {
            $0.userDefaultsClient.setObject = { _, _ in writeCount.withValue { $0 += 1 } }
        }
        // store.exhaustivity = .off: parent/receiver state 복구와 persistence write 부재만 검증한다.
        store.exhaustivity = .off

        await store.send(.topNavigationPersistenceCompleted(.init(
            request: persistenceRequest,
            terminal: .committed(commit),
            authoritativePinnedContentTabs: nil,
        )))
        await store.receive { action in
            guard case let .windows(.element(
                id: id,
                action: .window(.applyCommittedTopNavigationSnapshot(
                    order: order,
                    revision: revision,
                    authoritativePinnedContentTabs: nil,
                )),
            )) = action else { return false }
            return id == peerID && order == committedOrder && revision == commit.revision
        }

        XCTAssertEqual(store.state.windows[id: peerID]?.window.topNavigationArrangementAvailability, .available)
        XCTAssertNil(store.state.windows[id: peerID]?.window.topNavigationArrangementPresentation)
        XCTAssertEqual(store.state.windows[id: peerID]?.window.lastConfirmedTopNavigationOrder, committedOrder)
        XCTAssertEqual(writeCount.value, 0)
    }

    private static func committedTopNavigationAction(
        sourceID: UUID,
        token: FileManagerTopNavigationOperationToken,
        commit: FileManagerTopNavigationCommit,
    ) -> WindowManagerAction {
        .topNavigationMovePersistenceCompleted(
            sourceWindowID: sourceID,
            token: token,
            terminal: .committed(commit),
        )
    }

    private func assertTrackedNativeOpenCompletion(
        command: WindowManagerAction.TrackedSingletonCommand,
        requestID: UUID,
    ) async {
        let windowID = UUID(903)
        let openStarted = expectation(description: "native open started")
        let terminalReceived = expectation(description: "tracked terminal received")
        let openGate = AsyncStream<Void>.makeStream()
        let terminalCount = LockIsolated(0)
        var initialState = WindowManagerFeature.State()
        initialState.authorizedTrackedSingletonRequestID = requestID
        let store = TestStore(initialState: initialState) {
            CombineReducers {
                WindowManagerFeature()
                Reduce { _, action in
                    if case .delegate(.trackedSingletonCompleted(requestID: requestID)) = action {
                        terminalCount.withValue { $0 += 1 }
                        terminalReceived.fulfill()
                    }
                    return .none
                }
            }
        } withDependencies: {
            $0.uuid = .constant(windowID)
            $0.date = .constant(Date(timeIntervalSince1970: 0))
            $0.onboardingWindowClient.showIfNeeded = { false }
            $0.contentTabPinnedRecordClient.loadStore = { _ in ContentTabPinnedRecordStore() }
            $0.fileManagerWindowClient.open = { _ in
                openStarted.fulfill()
                for await _ in openGate.stream {
                    break
                }
            }
        }
        // store.exhaustivity = .off: child 초기화 action보다 native open/terminal 순서만 검증함.
        store.exhaustivity = .off

        await store.send(.trackedSingleton(command))
        await fulfillment(of: [openStarted], timeout: 1)
        XCTAssertEqual(terminalCount.value, 0)

        openGate.continuation.yield(())
        openGate.continuation.finish()
        await fulfillment(of: [terminalReceived], timeout: 1)
        await store.skipReceivedActions()
        await store.finish()

        XCTAssertEqual(terminalCount.value, 1)
    }

    private struct PlacementBoundaryScenario {
        let free: Int
        let valid: Int
        let expected: [Int]
    }

    private static func assertContentTabMoveTargetBusyRejection(
        variant: Int,
        mutateTarget: (inout FileManagerWindowFeature.State) -> Void,
    ) async throws {
        let sourceID = UUID(45830 + variant * 10)
        let targetID = UUID(45831 + variant * 10)
        let movedID = ContentTabID(rawValue: "target-busy-moved-\(variant)")
        let targetTabID = ContentTabID(rawValue: "target-busy-existing-\(variant)")
        let request = ContentTabMoveRequest(
            operationID: UUID(45832 + variant * 10),
            requestID: UUID(45833 + variant * 10),
            sourceWindowID: sourceID,
            initiatingTabID: movedID,
            orderedTabIDs: [movedID],
            targetWindowID: targetID,
        )
        var source = try makeContentTabMoveWindow(
            id: sourceID,
            tabs: [(movedID, "/target-busy/source/\(variant)")],
        )
        prepareContentTabMoveRequest(request, in: &source)
        var target = try makeContentTabMoveWindow(
            id: targetID,
            tabs: [(targetTabID, "/target-busy/target/\(variant)")],
        )
        mutateTarget(&target.window)
        let sourceBefore = source.window
        let targetBefore = target.window
        var initialState = WindowManagerFeature.State()
        initialState.windows = [source, target]
        let moveScopesCalls = LockIsolated(0)
        let lifecycleCalls = LockIsolated(0)
        let activationCalls = LockIsolated(0)
        let closeCalls = LockIsolated(0)
        let store = TestStore(initialState: initialState) { WindowManagerFeature() } withDependencies: {
            $0.fileOperationUndoManagerClient.moveScopes = { _ in
                moveScopesCalls.withValue { $0 += 1 }
                return .moved
            }
            $0.notificationCenterClient.notifications = { _, _ in
                lifecycleCalls.withValue { $0 += 1 }
                return AsyncStream { $0.finish() }
            }
            $0.fileManagerWindowClient.activate = { _ in
                activationCalls.withValue { $0 += 1 }
                return .discarded
            }
            $0.fileManagerWindowClient.close = { _ in closeCalls.withValue { $0 += 1 } }
        }
        // store.exhaustivity = .off: rejection terminal과 semantic/effect 원자성만 검증한다.
        store.exhaustivity = .off

        await store.send(.contentTabMoveRequest(request))
        await store.receive { isContentTabMoveRejection($0, request: request, category: .busy) }
        await store.finish()

        var expectedSource = sourceBefore
        expectedSource.sidebar.pendingContentTabMoveRequest = nil
        expectedSource.pendingContentTabMove = nil
        expectedSource.contentTabMoveFailurePresentation = .init(requestID: request.requestID, category: .busy)
        XCTAssertEqual(store.state.windows[id: sourceID]?.window, expectedSource)
        XCTAssertEqual(store.state.windows[id: targetID]?.window, targetBefore)
        XCTAssertEqual(store.state.contentTabMoveTerminalRecords[request.requestID]?.outcome, .rejected(.busy))
        XCTAssertEqual(moveScopesCalls.value, 0)
        XCTAssertTrue(store.state.contentTabMoveTransactions.isEmpty)
        XCTAssertTrue(store.state.contentTabMoveNativeEffectsPlans.isEmpty)
        XCTAssertTrue(store.state.contentTabMoveActivationAttempts.isEmpty)
        XCTAssertEqual(lifecycleCalls.value, 0)
        XCTAssertEqual(activationCalls.value, 0)
        XCTAssertEqual(closeCalls.value, 0)
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

    private static func prepareContentTabMoveRequest(
        _ request: ContentTabMoveRequest,
        in source: inout WindowSessionState,
    ) {
        source.window.sidebar.pendingContentTabMoveRequest = request
        source.window.pendingContentTabMove = .init(request: request, lifecycle: .inFlight)
    }

    private static func makeContentTabMoveWindow(
        id: UUID,
        tabs: [(ContentTabID, String)],
    ) throws -> WindowSessionState {
        let reservations = tabs.map { tabID, path in
            ExternalContentTabReservation(id: tabID, anchor: .directory(path: path))
        }
        let window = try XCTUnwrap(FileManagerWindowFeature.State.makeExternalInitial(
            reservations: reservations,
            windowID: id,
        ))
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
        resolvePropertyKey: { .canonical($0) },
        resolveCondition: { propertyKey, operatorCode, values, sourcePayload in
            let contract: Condition.ValueContract
            let type: SystemPropertyTypeKey
            switch propertyKey {
            case "tag_names":
                contract = .init(shape: .list, count: .multiple, input: .listText)
                type = .categorical
            case "last_used_date":
                contract = .init(shape: .single, count: .fixed(1), input: .singleDate)
                type = .date
            default:
                contract = .init(shape: .single, count: .fixed(1), input: .singleText)
                type = .string
            }
            return Condition(
                property: .init(
                    key: propertyKey,
                    label: propertyKey,
                    type: type,
                    unitContract: nil,
                    operatorOptions: ["any", "gt", "neq"].map {
                        .init(code: $0, label: $0)
                    },
                ),
                operation: operatorCode.map {
                    .init(code: $0, label: $0, valueContract: contract)
                },
                values: values,
                availability: .available,
                opaqueSource: sourcePayload,
            )
        },
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
