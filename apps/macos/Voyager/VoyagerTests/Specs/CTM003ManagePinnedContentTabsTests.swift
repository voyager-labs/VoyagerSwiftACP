import ComposableArchitecture
import Foundation
@testable import Voyager
import VoyagerEntitiesCollection
@testable import VoyagerPagesFileManager
import VoyagerShared
import XCTest

private actor CTM003TerminalGate {
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

private actor CTM003TerminalSignal {
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

private struct CTM003ActionCounts: Equatable {
    var storeChanged = 0
    var batchCompleted = 0
    var applyByWindow: [UUID: Int] = [:]
}

@MainActor
final class CTM003ManagePinnedContentTabsTests: XCTestCase {
    private static let pinnedAt = Date(timeIntervalSince1970: 639)

    // MARK: - CTM-003-pin_selected_content_tabs

    /// CTM-003-pin_selected_content_tabs: File 메뉴가 active tab 상태로 selected target과 count를 투영한다.
    /// Sidebar context menu와 동일한 batch command를 macOS File 메뉴 및 Command-P에서도 실행하는지 검증한다.
    /// - 검증 내용: `Pin 2 Tabs`/`Unpin 2 Tabs` title, enablement, MenuCommands delegate, Window batch request
    /// - 사전 조건: focused Window에 선택 탭 2개가 있고 active tab의 pinned 상태가 각각 false/true이다.
    /// - 기대 결과: active 상태가 target을 결정하고 정확히 하나의 selected Pin/Unpin request가 전달된다.
    func testFileMenuShowsSelectedCountAndRoutesTargetFromActiveTab() async {
        for activePinned in [false, true] {
            let windowID = UUID()
            var window = FileManagerWindowFeature.State.makeInitial(path: "/Users/test/FileMenu")
            guard let activeTabID = window.contentTabs.activeTabID else {
                return XCTFail("Expected active content tab")
            }
            let secondTabID = ContentTabID(rawValue: "file-menu-second-\(activePinned)")
            window.contentTabs.tabs[id: activeTabID]?.isPinned = activePinned
            window.contentTabs.tabs.append(ContentTabItem(
                id: secondTabID,
                page: .directory,
                anchor: .directory(path: "/Users/test/FileMenu/Second"),
                isPinned: false,
                title: "Second",
                iconName: "folder",
            ))
            window.contentTabs.selectedTabIDs = [activeTabID, secondTabID]

            var appState = AppRootState()
            appState.windowManager.windows = [WindowSessionState(id: windowID, window: window)]
            appState.windowManager.focusedWindowID = windowID
            let menuState = MenuCommandsState(state: appState)
            let operation = activePinned ? "Unpin" : "Pin"
            let expectedTarget: SelectedContentTabPinMutationTargetState = activePinned ? .unpinned : .pinned

            XCTAssertEqual(menuState.pinTabTitle, "\(operation) 2 Tabs")
            XCTAssertTrue(menuState.canPinTab)

            let menuStore = TestStore(initialState: menuState) { MenuCommandsFeature() }
            await menuStore.send(.view(.app(.togglePinTab)))
            await menuStore.receive { action in
                guard case .delegate(.windowManager(.file(.togglePinTab))) = action else { return false }
                return true
            }

            let windowStore = TestStore(initialState: appState.windowManager) {
                Reduce { (state: inout WindowManagerFeature.State, action: WindowManagerFeature.Action) in
                    guard case .file(.togglePinTab) = action else { return .none }
                    return WindowManagerFeature().reduce(into: &state, action: action)
                }
            }
            await windowStore.send(.file(.togglePinTab))
            await windowStore.receive { action in
                guard case let .windows(.element(
                    id: routedWindowID,
                    action: .window(.requestSelectedContentTabPinMutation(target: target)),
                )) = action else { return false }
                return routedWindowID == windowID && target == expectedTarget
            }
        }
    }

    /// CTM-003-pin_selected_content_tabs: active가 선택 밖이면 첫 selected row가 File 메뉴 target을 결정한다.
    /// 선택 밖 active의 상태가 batch 메뉴 의미를 뒤집지 않는 fallback 규칙을 검증한다.
    /// - 검증 내용: pinned active와 unpinned selected 2개에서 `Pin 2 Tabs` 및 `.pinned` request
    /// - 사전 조건: active tab은 pinned이지만 explicit selection에는 포함되지 않는다.
    /// - 기대 결과: Sidebar 순서상 첫 selected tab 상태로 제목과 batch target이 결정된다.
    func testFileMenuUsesFirstSelectedTabWhenActiveIsOutsideSelection() async {
        let windowID = UUID()
        var window = FileManagerWindowFeature.State.makeInitial(path: "/Users/test/FileMenuFallback")
        guard let activeTabID = window.contentTabs.activeTabID else {
            return XCTFail("Expected active content tab")
        }
        window.contentTabs.tabs[id: activeTabID]?.isPinned = true
        let selectedIDs = [
            ContentTabID(rawValue: "file-menu-selected-1"),
            ContentTabID(rawValue: "file-menu-selected-2"),
        ]
        for (index, tabID) in selectedIDs.enumerated() {
            window.contentTabs.tabs.append(ContentTabItem(
                id: tabID,
                page: .directory,
                anchor: .directory(path: "/Users/test/FileMenuFallback/\(index)"),
                isPinned: false,
                title: "Selected \(index + 1)",
                iconName: "folder",
            ))
        }
        window.contentTabs.selectedTabIDs = Set(selectedIDs)

        var appState = AppRootState()
        appState.windowManager.windows = [WindowSessionState(id: windowID, window: window)]
        appState.windowManager.focusedWindowID = windowID
        let menuState = MenuCommandsState(state: appState)

        XCTAssertEqual(menuState.pinTabTitle, "Pin 2 Tabs")
        XCTAssertTrue(menuState.canPinTab)

        let store = TestStore(initialState: appState.windowManager) {
            Reduce { (state: inout WindowManagerFeature.State, action: WindowManagerFeature.Action) in
                guard case .file(.togglePinTab) = action else { return .none }
                return WindowManagerFeature().reduce(into: &state, action: action)
            }
        }
        await store.send(.file(.togglePinTab))
        await store.receive { action in
            guard case let .windows(.element(
                id: routedWindowID,
                action: .window(.requestSelectedContentTabPinMutation(target: target)),
            )) = action else { return false }
            return routedWindowID == windowID && target == .pinned
        }
    }

    /// CTM-003-pin_selected_content_tabs: 서로 다른 세 탭의 current success를 항목별로 전역 반영한다.
    /// 선택 Pin batch의 각 durable terminal이 독립적인 전역 동기화를 소유하는지 검증한다.
    /// - 검증 내용: success 3회당 storeChanged/load/fan-out 3회, aggregate completion 추가 sync 0회
    /// - 사전 조건: source의 selected Directory 세 탭, idle other window, deterministic applied store
    /// - 기대 결과: 두 window가 persisted records 세 개로 수렴하고 source selection/anchor가 보존된다.
    func testThreeCurrentSuccessesFanOutIndividuallyWithoutAggregateSync() async {
        let sourceWindowID = UUID()
        let otherWindowID = UUID()
        let operationID = UUID()
        let source = Self.makeThreeSelectedUnpinnedWindow(path: "/Users/test/Source")
        let selectedIDs = source.contentTabs.tabs.map(\.id)
        let originalSelection = source.contentTabs.selectedTabIDs
        let originalAnchor = source.contentTabs.selectionAnchorID
        let other = FileManagerWindowFeature.State.makeInitial(path: "/Users/test/Other")
        var initialState = WindowManagerFeature.State()
        initialState.windows = [
            WindowSessionState(id: sourceWindowID, window: source),
            WindowSessionState(id: otherWindowID, window: other),
        ]
        let persistedStore = LockIsolated(ContentTabPinnedRecordStore())
        let mutationCount = LockIsolated(0)
        let counts = LockIsolated(CTM003ActionCounts())
        let store = Store(initialState: initialState) {
            Self.trackedWindowManager(counts: counts)
        } withDependencies: {
            $0.uuid = .constant(operationID)
            $0.date = .constant(Self.pinnedAt)
            $0.contentTabPinnedRecordClient.applyPersistenceMutationCommitted = { _, _, mutation in
                let count = mutationCount.withValue { value in
                    value += 1
                    return value
                }
                let updated = persistedStore.withValue { store in
                    store = Self.applying(mutation, to: store)
                    return store
                }
                return .init(
                    store: updated,
                    topNavigation: .init(order: updated.topNavigationOrder, revision: UInt64(count)),
                )
            }
        }

        let batchTask = store.send(.windows(.element(
            id: sourceWindowID,
            action: .window(.requestSelectedContentTabPinMutation(target: .pinned)),
        )))
        await batchTask.finish()

        XCTAssertEqual(persistedStore.value.records.map(\.id), selectedIDs.map(\.rawValue))
        XCTAssertEqual(mutationCount.value, 3)
        XCTAssertEqual(counts.value.batchCompleted, 1)
        XCTAssertEqual(counts.value.applyByWindow[sourceWindowID], 3)
        XCTAssertEqual(counts.value.applyByWindow[otherWindowID], 3)
        store.withState { state in
            let sourceState = state.windows[id: sourceWindowID]?.window
            let otherState = state.windows[id: otherWindowID]?.window
            XCTAssertNil(sourceState?.pendingSelectedContentTabPinMutation)
            XCTAssertEqual(sourceState?.contentTabs.selectedTabIDs, originalSelection)
            XCTAssertEqual(sourceState?.contentTabs.selectionAnchorID, originalAnchor)
            XCTAssertEqual(Self.pinnedIDs(sourceState), selectedIDs)
            XCTAssertEqual(Self.pinnedIDs(otherState), selectedIDs)
        }
    }

    /// CTM-003-pin_selected_content_tabs: app-owned unavailable terminal은 batch를 중단하지 않는다.
    /// WindowManager FIFO가 corrupt store를 반환해도 각 항목을 failure로 완료하는지 검증한다.
    /// - 검증 내용: 세 persistence 요청, optimistic rollback, queue/coordinator cleanup
    /// - 사전 조건: 선택된 unpinned tab 3개와 항상 corrupt를 반환하는 app persistence owner
    /// - 기대 결과: 세 tab이 unpinned로 rollback되고 parent queue와 Selected Pin coordinator가 비어 있음
    func testAppOwnedUnavailableStoreCompletesSelectedPinBatchFailures() async {
        let windowID = UUID()
        let source = Self.makeThreeSelectedUnpinnedWindow(path: "/Users/test/Unavailable")
        let selectedIDs = source.contentTabs.tabs.map(\.id)
        var initialState = WindowManagerFeature.State()
        initialState.windows = [WindowSessionState(id: windowID, window: source)]
        let mutationCount = LockIsolated(0)
        let store = Store(initialState: initialState) { WindowManagerFeature() } withDependencies: {
            $0.uuid = .incrementing
            $0.date = .constant(Self.pinnedAt)
            $0.contentTabPinnedRecordClient.reserveMutationGeneration = {
                ContentTabPinnedRecordMutationGeneration(tabID: $0)
            }
            $0.contentTabPinnedRecordClient.applyPersistenceMutationCommitted = { _, _, _ in
                mutationCount.withValue { $0 += 1 }
                throw ContentTabPinnedRecordStoreLoadError.corruptUnavailable
            }
            $0.collectionAlertClient.showCollectionOpenErrorAlert = { _, _ in }
        }

        let task = store.send(.windows(.element(
            id: windowID,
            action: .window(.requestSelectedContentTabPinMutation(target: .pinned)),
        )))
        await task.finish()

        XCTAssertEqual(mutationCount.value, selectedIDs.count)
        store.withState { state in
            let window = state.windows[id: windowID]?.window
            XCTAssertTrue(selectedIDs.allSatisfy { window?.contentTabs.tabs[id: $0]?.isPinned == false })
            XCTAssertEqual(window?.contentTabs.pendingPinnedRecordIDs.isEmpty, true)
            XCTAssertNil(window?.pendingSelectedContentTabPinMutation)
            XCTAssertTrue(state.topNavigationPersistenceQueue.isEmpty)
            XCTAssertFalse(state.isTopNavigationPersistenceInFlight)
        }
    }

    /// CTM-003-pin_selected_content_tabs: globally stale success는 local cleanup만 수행한다.
    /// 같은 탭의 더 최신 generation이 존재할 때 stale applied terminal이 전역 fan-out을 만들지 않는지 검증한다.
    /// - 검증 내용: child pending cleanup, remaining 증가, storeChanged/load/fan-out 0회
    /// - 사전 조건: locally-current optimistic Pin과 globally-stale generation
    /// - 기대 결과: batch는 remaining=1로 끝나고 child pending만 제거된다.
    func testGlobalStaleSuccessCleansChildAndCountsRemainingWithoutFanOut() async {
        let windowID = UUID()
        let operationID = UUID()
        let tabID = ContentTabID(rawValue: "global-stale")
        let window = Self.makeOptimisticPinWindow(
            path: "/Users/test/GlobalStale",
            tabID: tabID,
            operationID: operationID,
        )
        let intentID = window.contentTabs.markLatestPinnedRecordPersistenceIntent(for: tabID)
        let context = ContentTabPinnedRecordTerminalContext(
            intentID: intentID,
            generation: ContentTabPinnedRecordMutationGeneration(tabID: tabID),
        )
        var initialState = WindowManagerFeature.State()
        initialState.windows = [WindowSessionState(id: windowID, window: window)]
        let counts = LockIsolated(CTM003ActionCounts())
        let loadCount = LockIsolated(0)
        let store = TestStore(initialState: initialState) {
            Self.trackedWindowManager(counts: counts)
        } withDependencies: {
            $0.contentTabPinnedRecordClient.isCurrentMutationGeneration = { _ in false }
            $0.contentTabPinnedRecordClient.loadStore = { _ in
                loadCount.withValue { $0 += 1 }
                return ContentTabPinnedRecordStore()
            }
            $0.collectionAlertClient.showCollectionOpenErrorAlert = { _, _ in }
        }
        // store.exhaustivity = .off: app parent와 package child의 terminal chain 최종 상태 및 호출 수를 함께 검증한다.
        store.exhaustivity = .off

        await store.send(.windows(.element(
            id: windowID,
            action: .window(.performSelectedContentTabPinMutation(
                operationID: operationID,
                tabID: tabID,
                action: .pinnedRecordSaveSucceeded(tabID: tabID, context: context),
            )),
        )))
        await store.skipReceivedActions()
        await store.finish()

        XCTAssertEqual(counts.value.storeChanged, 0)
        XCTAssertEqual(counts.value.applyByWindow[windowID, default: 0], 0)
        XCTAssertEqual(loadCount.value, 0)
        XCTAssertNil(store.state.windows[id: windowID]?.window.pendingSelectedContentTabPinMutation)
        XCTAssertEqual(store.state.windows[id: windowID]?.window.contentTabs.pendingPinnedRecordIDs.isEmpty, true)
    }

    /// CTM-003-pin_selected_content_tabs: failure와 notApplied는 rollback 뒤 authoritative reconciliation을 요청한다.
    /// reload 자체가 실패해도 item-local rollback과 batch 분류가 바뀌지 않는지 검증한다.
    /// - 검증 내용: failed/notApplied 각각 storeChanged 1회, load failure 뒤 failure/remaining 분류 유지
    /// - 사전 조건: locally-current optimistic Pin terminal과 항상 throw하는 loadStore
    /// CTM-003-pin_selected_content_tabs: app-owned terminal은 source closing/removal 뒤에도 reload를 완료한다.
    /// source-local coordinator를 부활시키지 않고 surviving windows만 authoritative snapshot을 받는지 검증한다.
    /// - 검증 내용: closing/removed source의 local delivery 0, load 1, S-window fan-out, duplicate finish no-op
    /// - 사전 조건: accepted applied mutation metadata와 surviving window 2개
    /// CTM-003-pin_selected_content_tabs: source close 뒤 latest 실패·취소·supersede도 durable winner를 재동기화한다.
    /// app-global completion이 source-local terminal 생존 여부와 무관하게 authoritative reload를 소유하는지 검증한다.
    /// - 검증 내용: G1 applied와 G2 failed/cancelled/superseded 각각 reload, survivor fan-out, duplicate completion no-op
    /// - 사전 조건: G1 durable record, closing source, 같은 tab의 G1/G2 in-flight metadata, idle survivor
    /// CTM-003-pin_selected_content_tabs: selected Pin busy source는 latest authoritative snapshot만 재생한다.
    /// source가 defer하는 동안 idle other window는 각 authoritative snapshot을 즉시 적용하는지 검증한다.
    /// - 검증 내용: A→B latest-wins defer, coordinator clear/cancel 뒤 B replay 1회, idle window immediate apply
    /// - 사전 조건: source selected Pin coordinator 완료 직전, 두 global snapshots A와 B
    /// - 기대 결과: source는 B만 replay하고 other는 A 다음 B를 적용하며 source selection/anchor가 유지된다.
    func testSelectedPinBusyDefersLatestSnapshotAndReplaysAfterCoordinatorClear() async {
        let sourceWindowID = UUID()
        let otherWindowID = UUID()
        let operationID = UUID()
        let targetID = ContentTabID(rawValue: "batch-target")
        var source = FileManagerWindowFeature.State.makeInitial(path: "/Users/test/Source")
        source.contentTabs.tabs.append(Self.unpinnedItem(id: targetID, path: "/Users/test/Target"))
        source.contentTabs.selectedTabIDs = [targetID]
        source.contentTabs.selectionAnchorID = targetID
        source.pendingSelectedContentTabPinMutation = PendingSelectedContentTabPinMutation(
            operationID: operationID,
            target: .pinned,
            orderedTargetIDs: [targetID],
            currentTabID: targetID,
        )
        source.syncContentTabSidebarItems()
        let originalSelection = source.contentTabs.selectedTabIDs
        let originalAnchor = source.contentTabs.selectionAnchorID
        let other = FileManagerWindowFeature.State.makeInitial(path: "/Users/test/Other")
        var initialState = WindowManagerFeature.State()
        initialState.windows = [
            WindowSessionState(id: sourceWindowID, window: source),
            WindowSessionState(id: otherWindowID, window: other),
        ]
        let snapshotA = Self.store(recordID: "snapshot-a", path: "/Users/test/A")
        let snapshotB = Self.store(recordID: "snapshot-b", path: "/Users/test/B")
        let persistedStore = LockIsolated(snapshotA)
        let counts = LockIsolated(CTM003ActionCounts())
        let store = TestStore(initialState: initialState) {
            Self.trackedWindowManager(counts: counts)
        } withDependencies: {
            $0.contentTabPinnedRecordClient.loadStore = { _ in persistedStore.value }
        }
        // store.exhaustivity = .off: 두 fan-out의 child handoff보다 latest deferred payload와 final projection을 검증한다.
        store.exhaustivity = .off

        await store.send(.pinnedContentTabsStoreChanged)
        await store.skipReceivedActions()
        XCTAssertEqual(
            Self.pinnedIDs(store.state.windows[id: otherWindowID]?.window),
            [ContentTabID(rawValue: "snapshot-a")],
        )
        XCTAssertEqual(Self.pinnedIDs(store.state.windows[id: sourceWindowID]?.window), [])
        XCTAssertEqual(
            Self.pinnedIDs(store.state.windows[id: sourceWindowID]?.window.deferredPinnedContentTabs),
            [ContentTabID(rawValue: "snapshot-a")],
        )

        persistedStore.withValue { $0 = snapshotB }
        await store.send(.pinnedContentTabsStoreChanged)
        await store.skipReceivedActions()
        XCTAssertEqual(
            Self.pinnedIDs(store.state.windows[id: otherWindowID]?.window),
            [ContentTabID(rawValue: "snapshot-b")],
        )
        XCTAssertEqual(
            Self.pinnedIDs(store.state.windows[id: sourceWindowID]?.window.deferredPinnedContentTabs),
            [ContentTabID(rawValue: "snapshot-b")],
        )
        XCTAssertEqual(store.state.windows[id: sourceWindowID]?.window.deferredPinnedContentTabsMode, .authoritative)

        await store.send(.windows(.element(
            id: sourceWindowID,
            action: .window(.selectedPinMutationItemCompleted(
                operationID: operationID,
                tabID: targetID,
                outcome: .success,
            )),
        )))
        await store.skipReceivedActions()
        await store.finish()

        XCTAssertNil(store.state.windows[id: sourceWindowID]?.window.pendingSelectedContentTabPinMutation)
        XCTAssertNil(store.state.windows[id: sourceWindowID]?.window.deferredPinnedContentTabs)
        XCTAssertEqual(
            Self.pinnedIDs(store.state.windows[id: sourceWindowID]?.window),
            [ContentTabID(rawValue: "snapshot-b")],
        )
        XCTAssertEqual(store.state.windows[id: sourceWindowID]?.window.contentTabs.selectedTabIDs, originalSelection)
        XCTAssertEqual(store.state.windows[id: sourceWindowID]?.window.contentTabs.selectionAnchorID, originalAnchor)
        XCTAssertEqual(counts.value.storeChanged, 2)
        XCTAssertEqual(counts.value.applyByWindow[sourceWindowID], 3)
        XCTAssertEqual(counts.value.applyByWindow[otherWindowID], 2)
    }

    /// CTM-003-pin_selected_content_tabs: selected-close busy도 기존 latest authoritative defer를 유지한다.
    /// selected Pin predicate 확장이 selected-close composition을 회귀시키지 않는지 검증한다.
    /// - 검증 내용: selected-close 중 A→B defer와 close coordinator clear 뒤 B replay
    /// - 사전 조건: 완료 직전 selected-close coordinator와 authoritative snapshots A/B
    /// - 기대 결과: source deferred payload는 B 하나이며 정상 close completion 뒤 B가 적용된다.
    func testSelectedCloseBusyStillDefersLatestAuthoritativeSnapshot() async {
        let windowID = UUID()
        let operationID = UUID()
        let tabID = ContentTabID(rawValue: "close-target")
        var window = FileManagerWindowFeature.State.makeInitial(path: "/Users/test/Close")
        window.pendingSelectedContentTabClose = PendingSelectedContentTabClose(
            operationID: operationID,
            orderedTargetIDs: [tabID],
            cursor: 1,
            currentTabID: nil,
            originalActiveTabID: window.contentTabs.activeTabID,
            preferredFallbackIDs: window.contentTabs.tabs.map(\.id),
        )
        var initialState = WindowManagerFeature.State()
        initialState.windows = [WindowSessionState(id: windowID, window: window)]
        let closeA = Self.store(recordID: "close-a", path: "/Users/test/CloseA")
        let closeB = Self.store(recordID: "close-b", path: "/Users/test/CloseB")
        let persistedStore = LockIsolated(closeA)
        let store = TestStore(initialState: initialState) { WindowManagerFeature() } withDependencies: {
            $0.contentTabPinnedRecordClient.loadStore = { _ in persistedStore.value }
        }
        // store.exhaustivity = .off: selected-close의 기존 deferred replay 최종 상태만 검증한다.
        store.exhaustivity = .off

        await store.send(.pinnedContentTabsStoreChanged)
        await store.skipReceivedActions()
        persistedStore.withValue { $0 = closeB }
        await store.send(.pinnedContentTabsStoreChanged)
        await store.skipReceivedActions()
        XCTAssertEqual(
            Self.pinnedIDs(store.state.windows[id: windowID]?.window.deferredPinnedContentTabs),
            [ContentTabID(rawValue: "close-b")],
        )

        await store.send(.windows(.element(
            id: windowID,
            action: .window(.processNextSelectedContentTabClose(operationID: operationID)),
        )))
        await store.skipReceivedActions()
        await store.finish()
        XCTAssertEqual(Self.pinnedIDs(store.state.windows[id: windowID]?.window), [ContentTabID(rawValue: "close-b")])
        XCTAssertNil(store.state.windows[id: windowID]?.window.deferredPinnedContentTabs)
    }

    /// CTM-003-pin_selected_content_tabs: onDisappear는 coordinator/current/deferred를 폐기한다.
    /// teardown 뒤 늦은 terminal이 child cleanup, count, progress, sync를 만들지 않는지 검증한다.
    /// - 검증 내용: selected Pin cancel/clear, deferred discard, late terminal exact no-op
    /// - 사전 조건: current optimistic Pin과 authoritative deferred snapshot
    /// - 기대 결과: late terminal 전후 window state와 action counts가 동일하다.
    func testOnDisappearDiscardsPinCoordinatorDeferredSnapshotAndLateTerminal() async {
        let windowID = UUID()
        let operationID = UUID()
        let tabID = ContentTabID(rawValue: "teardown-target")
        var window = Self.makeOptimisticPinWindow(
            path: "/Users/test/Teardown",
            tabID: tabID,
            operationID: operationID,
        )
        window.deferredPinnedContentTabs = ContentTabState.restoringPinnedRecords(
            from: Self.store(recordID: "discarded", path: "/Users/test/Discarded"),
        ).state
        window.deferredPinnedContentTabsMode = .authoritative
        let intentID = window.contentTabs.markLatestPinnedRecordPersistenceIntent(for: tabID)
        let context = ContentTabPinnedRecordTerminalContext(
            intentID: intentID,
            generation: ContentTabPinnedRecordMutationGeneration(tabID: tabID),
        )
        var initialState = WindowManagerFeature.State()
        initialState.windows = [WindowSessionState(id: windowID, window: window)]
        let counts = LockIsolated(CTM003ActionCounts())
        let store = TestStore(initialState: initialState) {
            Self.trackedWindowManager(counts: counts)
        } withDependencies: {
            $0.contentTabPinnedRecordClient.isCurrentMutationGeneration = { _ in true }
        }
        // store.exhaustivity = .off: cancellation effect보다 teardown 후 late action의 zero mutation을 검증한다.
        store.exhaustivity = .off

        await store.send(.windows(.element(id: windowID, action: .window(.onDisappear))))
        await store.finish()
        let disappearedState = store.state
        let disappearedCounts = counts.value
        await store.send(.windows(.element(
            id: windowID,
            action: .window(.performSelectedContentTabPinMutation(
                operationID: operationID,
                tabID: tabID,
                action: .pinnedRecordSaveSucceeded(tabID: tabID, context: context),
            )),
        )))
        XCTAssertEqual(store.state, disappearedState)
        XCTAssertEqual(counts.value, disappearedCounts)
        XCTAssertNil(store.state.windows[id: windowID]?.window.pendingSelectedContentTabPinMutation)
        XCTAssertNil(store.state.windows[id: windowID]?.window.deferredPinnedContentTabs)
    }

    // MARK: - CTM-003-unpin_selected_content_tabs

    /// CTM-003-unpin_selected_content_tabs: same-tab generation 경쟁과 다른 탭 mutation은 persisted winner로 수렴한다.
    /// stale applied selected terminal과 current ordinary terminal의 interleaving이 window별 projection을 갈라놓지 않는지 검증한다.
    /// - 검증 내용: G1 selected Unpin stale success fan-out 0, G2 same-tab Pin fan-out 1, 별도 탭 Pin fan-out 1
    /// - 사전 조건: G1 durable commit 뒤 terminal gate, G2 same-tab winner와 independent tab mutation
    private static func trackedWindowManager(
        counts: LockIsolated<CTM003ActionCounts>,
    ) -> some ReducerOf<WindowManagerFeature> {
        CombineReducers {
            WindowManagerFeature()
            Reduce<WindowManagerFeature.State, WindowManagerFeature.Action> { _, action in
                counts.withValue { value in
                    if case .pinnedContentTabsStoreChanged = action {
                        value.storeChanged += 1
                    }
                    if case .windows(.element(id: _, action: .window(.selectedPinMutationBatchCompleted))) = action {
                        value.batchCompleted += 1
                    }
                    if case let .windows(.element(
                        id: windowID,
                        action: .window(.applyCommittedTopNavigationSnapshot),
                    )) = action {
                        value.applyByWindow[windowID, default: 0] += 1
                    }
                }
                return .none
            }
        }
    }

    private static func makeThreeSelectedUnpinnedWindow(path: String) -> FileManagerWindowFeature.State {
        var state = FileManagerWindowFeature.State.makeInitial(path: path)
        state.contentTabs.tabs.append(unpinnedItem(id: "selected-two", path: "/Users/test/Two"))
        state.contentTabs.tabs.append(unpinnedItem(id: "selected-three", path: "/Users/test/Three"))
        let ids = state.contentTabs.tabs.map(\.id)
        state.contentTabs.selectedTabIDs = Set(ids)
        state.contentTabs.selectionAnchorID = ids.last
        state.syncContentTabSidebarItems()
        return state
    }

    private static func makeOptimisticPinWindow(
        path: String,
        tabID: ContentTabID,
        operationID: UUID,
    ) -> FileManagerWindowFeature.State {
        var state = FileManagerWindowFeature.State.makeInitial(path: path)
        state.contentTabs.tabs.append(unpinnedItem(id: tabID, path: "/Users/test/Optimistic"))
        let tabIndex = state.contentTabs.tabs.index(id: tabID)
        state.contentTabs.tabs[id: tabID]?.isPinned = true
        if let tabIndex {
            state.contentTabs.tabs.move(fromOffsets: IndexSet(integer: tabIndex), toOffset: 0)
        }
        state.contentTabs.selectedTabIDs = [tabID]
        state.contentTabs.selectionAnchorID = tabID
        state.pendingSelectedContentTabPinMutation = PendingSelectedContentTabPinMutation(
            operationID: operationID,
            target: .pinned,
            orderedTargetIDs: [tabID],
            currentTabID: tabID,
        )
        _ = state.contentTabs.markLatestPinnedRecordPersistenceIntent(for: tabID)
        state.contentTabs.pendingPinnedRecordIDs.insert(tabID)
        state.syncContentTabSidebarItems()
        return state
    }

    private static func unpinnedItem(id: ContentTabID, path: String) -> ContentTabItem {
        ContentTabItem(
            id: id,
            page: .directory,
            anchor: .directory(path: path),
            isPinned: false,
            title: URL(fileURLWithPath: path).lastPathComponent,
            iconName: "folder",
        )
    }

    private static func unpinnedItem(id: String, path: String) -> ContentTabItem {
        unpinnedItem(id: ContentTabID(rawValue: id), path: path)
    }

    private static func pinnedItem(record: ContentTabPinnedRecord) -> ContentTabItem {
        ContentTabItem(
            id: ContentTabID(rawValue: record.id),
            page: record.page,
            anchor: record.anchor,
            isPinned: true,
            title: record.title,
            iconName: record.iconName,
        )
    }

    private static func record(id: String, path: String) -> ContentTabPinnedRecord {
        ContentTabPinnedRecord(
            id: id,
            page: .directory,
            anchor: .directory(path: path),
            title: URL(fileURLWithPath: path).lastPathComponent,
            iconName: "folder",
            pinnedAt: pinnedAt,
        )
    }

    private static func store(recordID: String, path: String) -> ContentTabPinnedRecordStore {
        ContentTabPinnedRecordStore(records: [record(id: recordID, path: path)])
    }

    nonisolated private static func applying(
        _ mutation: ContentTabPinnedRecordPersistenceMutation,
        to store: ContentTabPinnedRecordStore,
    ) -> ContentTabPinnedRecordStore {
        var updated = store
        switch mutation {
        case let .upsert(record, _):
            updated.records.removeAll { $0.id == record.id }
            updated.records.append(record)
            updated.topNavigationOrder.items.removeAll { $0 == .contentTab(ContentTabID(rawValue: record.id)) }
            updated.topNavigationOrder.items.append(.contentTab(ContentTabID(rawValue: record.id)))
        case let .remove(recordID):
            updated.records.removeAll { $0.id == recordID }
            updated.topNavigationOrder.items.removeAll {
                $0 == .contentTab(ContentTabID(rawValue: recordID))
            }
        }
        return updated
    }

    private static func pinnedIDs(_ window: FileManagerWindowFeature.State?) -> [ContentTabID] {
        window?.contentTabs.tabs.filter(\.isPinned).map(\.id) ?? []
    }

    private static func pinnedIDs(_ contentTabs: ContentTabState?) -> [ContentTabID] {
        contentTabs?.tabs.filter(\.isPinned).map(\.id) ?? []
    }
}

private struct CTM003TestFailure: Error {}
