import AppKit
import ComposableArchitecture
import Foundation
import VoyagerEntitiesEntry
@testable import VoyagerFeaturesEntryOperations
@testable import VoyagerPagesFileManager
@testable import VoyagerWidgetsEntryViewLayout
import XCTest

@MainActor
extension EVM002FileManagerPagePresentationTests {
    // MARK: - EVM-002-update_entry_selection

    /// EVM-002-update_entry_selection: Quick Look open은 active content의 canonical selection을 바꾸지 않는다.
    /// 선택된 A에서 Quick Look command를 실행해도 FileManager composition이 selected IDs와 두 cursor를 유지하는지 검증한다.
    /// - 검증 내용: navigation.quickLookSelectedItem command가 A를 Quick Look client에 전달한 뒤 selection tuple이 유지되는지 확인
    /// - 사전 조건: /root의 A, B 중 A가 선택된 FileManagerContentFeature와 mocked Quick Look client
    /// - 기대 결과: Quick Look open은 A 한 번만 호출하고 selectedIds, focus, anchor는 모두 A로 유지된다.
    func testQuickLookOpenPreservesActiveContentSelectionTuple() async {
        let first = selectionLifetimeEntry(id: "/root/a.txt", name: "a.txt")
        let second = selectionLifetimeEntry(id: "/root/b.txt", name: "b.txt")
        let quickLookCalls = LockIsolated<[[String]]>([])
        let quickLookOpened = expectation(description: "Quick Look opened for selected entry")
        let initialTuple = SelectionLifetimeTuple(
            selectedIds: [first.id],
            lastSelectedId: first.id,
            rangeAnchorId: first.id,
        )
        let store = makeSelectionLifetimeStore(
            entries: [first, second],
            selectedID: first.id,
            quickLook: { urls, _ in
                quickLookCalls.withValue { $0.append(urls.map(\.path)) }
                quickLookOpened.fulfill()
            },
        )
        store.exhaustivity = .off

        await store.send(.entryViewLayout(.delegate(.executeCommand("navigation.quickLookSelectedItem"))))
        await fulfillment(of: [quickLookOpened], timeout: 2)

        XCTAssertEqual(quickLookCalls.value, [[first.fullPath]])
        XCTAssertEqual(
            SelectionLifetimeTuple(state: store.state.entryViewLayout),
            initialTuple,
        )
        await store.skipReceivedActions()
    }

    /// EVM-002-update_entry_selection: Quick Look open 이후의 정상 selection 이동은 새 항목을 정확히 한 번 sync한다.
    /// A를 미리 본 뒤 normal view selection action으로 B로 이동할 때 composition bridge가 B만 한 번 동기화하는지 검증한다.
    /// - 검증 내용: A Quick Look open 후 `.view(.updateSelection)`이 B의 Quick Look sync와 canonical tuple을 만드는지 확인
    /// - 사전 조건: A가 선택된 FileManagerContentFeature, mocked Quick Look client, A open 완료
    /// - 기대 결과: B path sync가 정확히 한 번 발생하고 tuple은 B로 이동하며 추가 sync는 없다.
    func testSelectionMoveAfterQuickLookSyncsNewEntryOnce() async {
        let first = selectionLifetimeEntry(id: "/root/a.txt", name: "a.txt")
        let second = selectionLifetimeEntry(id: "/root/b.txt", name: "b.txt")
        let quickLookCalls = LockIsolated<[[String]]>([])
        let syncCalls = LockIsolated<[(paths: [String], selectedIndex: Int)]>([])
        let quickLookOpened = expectation(description: "Quick Look opened for selected entry")
        let selectionSynced = expectation(description: "new selection synchronized to Quick Look")
        let store = makeSelectionLifetimeStore(
            entries: [first, second],
            selectedID: first.id,
            quickLook: { urls, _ in
                quickLookCalls.withValue { $0.append(urls.map(\.path)) }
                quickLookOpened.fulfill()
            },
            syncQuickLookSelection: { urls, selectedIndex in
                syncCalls.withValue { $0.append((urls.map(\.path), selectedIndex)) }
                selectionSynced.fulfill()
            },
        )
        store.exhaustivity = .off

        await store.send(.entryViewLayout(.delegate(.executeCommand("navigation.quickLookSelectedItem"))))
        await fulfillment(of: [quickLookOpened], timeout: 2)
        await store.skipReceivedActions()

        await store.send(.entryViewLayout(.view(.updateSelection(
            ids: [second.id],
            lastSelectedId: second.id,
            rangeAnchorId: second.id,
            shouldScrollToSelection: false,
        ))))
        await store.receive(\.entryViewLayout.internal.setSelectionState)
        await fulfillment(of: [selectionSynced], timeout: 2)

        XCTAssertEqual(quickLookCalls.value, [[first.fullPath]])
        XCTAssertEqual(syncCalls.value.map(\.paths), [[second.fullPath]])
        XCTAssertEqual(syncCalls.value.map(\.selectedIndex), [0])
        XCTAssertEqual(
            SelectionLifetimeTuple(state: store.state.entryViewLayout),
            SelectionLifetimeTuple(
                selectedIds: [second.id],
                lastSelectedId: second.id,
                rangeAnchorId: second.id,
            ),
        )
        await store.skipReceivedActions()
    }

    /// EVM-002-update_entry_selection: List/Grid root 행의 Return rename 성공은 새 identity로 선택을 유지한다.
    /// - 검증 내용: startRename → commitRename → 실제 rename effect → buffered root reload의 전체 reducer 경로
    /// - 사전 조건: 각 layout에서 현재 폴더의 선택된 root 파일을 서로 다른 이름으로 변경한다.
    /// - 기대 결과: selectedIds, lastSelectedId, rangeAnchorId가 새 path를 가리키고 replacement가 정산된다.
    func testListAndGridRootRowReturnRenameLifecycleRetainsSelection() async throws {
        for mode in [EntryViewLayoutState.Mode.list, .grid] {
            try await assertRootRowReturnRenameLifecycleRetainsSelection(mode: mode)
        }
    }

    private func assertRootRowReturnRenameLifecycleRetainsSelection(
        mode: EntryViewLayoutState.Mode,
    ) async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("voy-790-rename-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let beforeURL = rootURL.appendingPathComponent("before.txt")
        let afterURL = rootURL.appendingPathComponent("after.txt")
        try Data().write(to: beforeURL)
        let before = selectionLifetimeEntry(id: beforeURL.path, name: beforeURL.lastPathComponent)
        let after = selectionLifetimeEntry(id: afterURL.path, name: afterURL.lastPathComponent)

        let state = selectionLifetimeDirectoryState(rootURL: rootURL, selected: before, mode: mode)

        let loadStarted = expectation(description: "rename reload started")
        let loadGate = AsyncStream<Void>.makeStream()
        let store = makeRenameLifecycleStore(
            state: state,
            after: after,
            loadStarted: loadStarted,
            loadGate: loadGate,
        )
        let nativeProjection = SelectionLifetimeNativeProjection(
            mode: mode,
            store: store.scope(state: \.entryViewLayout, action: \.entryViewLayout),
        )
        try nativeProjection.assertSelection(entry: before)

        store.send(.entryViewLayout(.entryOperations(.edit(.startRename(item: before, text: after.name)))))
        store.send(.entryViewLayout(.entryOperations(.edit(.commitRename))))
        await fulfillment(of: [loadStarted], timeout: 2)

        XCTAssertEqual(store.withState { $0.entryViewLayout.selectedIds }, [before.id])
        XCTAssertNotNil(store.withState { $0.pendingIdentityTransition })
        XCTAssertTrue(store.withState { $0.entryViewLayout.isIdentityReplacementActive })
        loadGate.continuation.yield()
        loadGate.continuation.finish()

        try await waitForIdentityTransitionToSettle(store: store, expectedEntry: after)
        try await waitForNativeSelection(nativeProjection, expectedEntry: after)
        assertSelectionLifetimeTuple(store: store, expectedEntry: after)
        try nativeProjection.assertSelection(entry: after)
    }

    /// EVM-002-update_entry_selection: rename undo/redo reload도 실행 방향 identity로 선택을 이동한다.
    /// - 검증 내용: replaySucceeded(.undo/.redo) → hierarchy invalidation → root reload → replacement settle
    /// - 사전 조건: 원래 before→after rename record와 현재 실행 결과 파일이 root에 있다.
    /// - 기대 결과: undo는 before path, redo는 after path로 전체 selection tuple을 왕복시킨다.
    func testListRootRenameUndoRedoLifecycleMigratesSelectionBothDirections() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("voy-790-replay-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let beforeURL = rootURL.appendingPathComponent("before.txt")
        let afterURL = rootURL.appendingPathComponent("after.txt")
        try Data().write(to: afterURL)
        let before = selectionLifetimeEntry(id: beforeURL.path, name: beforeURL.lastPathComponent)
        let after = selectionLifetimeEntry(id: afterURL.path, name: afterURL.lastPathComponent)
        let record = EntryActionRecord(
            operationKind: .rename,
            targets: [.init(beforePath: before.id, afterPath: after.id)],
        )

        let state = selectionLifetimeDirectoryState(rootURL: rootURL, selected: after, mode: .list)

        let store = makeRenameReplayStore(state: state, before: before, after: after)

        try FileManager.default.moveItem(at: afterURL, to: beforeURL)
        store.send(.entryViewLayout(.entryOperations(.undoRedo(.replaySucceeded(
            direction: .undo,
            sourceRecordID: record.id,
            updatedRecord: record,
        )))))
        try await waitForIdentityTransitionToSettle(store: store, expectedEntry: before)
        assertSelectionLifetimeTuple(store: store, expectedEntry: before)

        try FileManager.default.moveItem(at: beforeURL, to: afterURL)
        store.send(.entryViewLayout(.entryOperations(.undoRedo(.replaySucceeded(
            direction: .redo,
            sourceRecordID: record.id,
            updatedRecord: record,
        )))))
        try await waitForIdentityTransitionToSettle(store: store, expectedEntry: after)
        assertSelectionLifetimeTuple(store: store, expectedEntry: after)
    }

    private func selectionLifetimeDirectoryState(
        rootURL: URL,
        selected: EntryModel,
        mode: EntryViewLayoutState.Mode,
    ) -> FileManagerContentState {
        var state = FileManagerContentState()
        state.navigation.seedInitialFolderPath(rootURL.path)
        state.entryViewLayout.mode = mode
        state.entryViewLayout.entries = [selected]
        state.entryViewLayout.entryOperations.items = [selected]
        state.entryViewLayout.entryOperations.loadingContext.sourceKind = .directory
        state.entryViewLayout.entryOperations.loadingContext.directoryPath = rootURL.path
        state.entryViewLayout.entryOperations.loadingContext.coreFinished = true
        state.entryViewLayout.entryOperations.loadingContext.streamTerminal = true
        state.entryViewLayout.hierarchy.replaceRoot(path: rootURL.path)
        state.entryViewLayout.selectedIds = [selected.id]
        state.entryViewLayout.lastSelectedId = selected.id
        state.entryViewLayout.rangeAnchorId = selected.id
        return state
    }

    private func makeRenameLifecycleStore(
        state: FileManagerContentState,
        after: EntryModel,
        loadStarted: XCTestExpectation,
        loadGate: (stream: AsyncStream<Void>, continuation: AsyncStream<Void>.Continuation),
    ) -> Store<FileManagerContentState, FileManagerContentAction> {
        var fileOpsClient = EntryFileOpsClient.previewValue
        fileOpsClient.renameFile = { source, destination in
            try FileManager.default.moveItem(at: source, to: destination)
        }
        return Store(initialState: state) {
            FileManagerContentFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 0))
            $0.entryFileOpsClient = fileOpsClient
            $0.entryLoadingClient.stagedLoadItems = { _, _, _ in
                loadStarted.fulfill()
                return AsyncThrowingStream { continuation in
                    Task {
                        for await _ in loadGate.stream {
                            break
                        }
                        continuation.yield(.coreBatch(items: [after], batchIndex: 0))
                        continuation.yield(.coreFinished(batchCount: 1))
                        continuation.finish()
                    }
                }
            }
            $0.entryQuickLookClient = .previewValue
        }
    }

    private func makeRenameReplayStore(
        state: FileManagerContentState,
        before: EntryModel,
        after: EntryModel,
    ) -> Store<FileManagerContentState, FileManagerContentAction> {
        Store(initialState: state) {
            FileManagerContentFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 0))
            $0.entryLoadingClient.stagedLoadItems = { _, _, _ in
                let entry = FileManager.default.fileExists(atPath: before.id) ? before : after
                return AsyncThrowingStream { continuation in
                    continuation.yield(.coreBatch(items: [entry], batchIndex: 0))
                    continuation.yield(.coreFinished(batchCount: 1))
                    continuation.finish()
                }
            }
            $0.entryQuickLookClient = .previewValue
        }
    }

    private func waitForNativeSelection(
        _ projection: SelectionLifetimeNativeProjection,
        expectedEntry: EntryModel,
    ) async throws {
        for _ in 0 ..< 200 {
            if projection.selectionMatches(entry: expectedEntry) { return }
            try await Task.sleep(for: .milliseconds(5))
        }
    }

    private func waitForIdentityTransitionToSettle(
        store: Store<FileManagerContentState, FileManagerContentAction>,
        expectedEntry: EntryModel,
    ) async throws {
        for _ in 0 ..< 200 {
            let didSettle = store.withState { state in
                !state.entryViewLayout.entryOperations.isLoading
                    && state.entryViewLayout.selectedIds == [expectedEntry.id]
                    && state.entryViewLayout.entries == [expectedEntry]
                    && state.pendingIdentityTransition == nil
                    && !state.entryViewLayout.isIdentityReplacementActive
            }
            if didSettle { return }
            try await Task.sleep(for: .milliseconds(5))
        }
    }

    private func assertSelectionLifetimeTuple(
        store: Store<FileManagerContentState, FileManagerContentAction>,
        expectedEntry: EntryModel,
    ) {
        XCTAssertEqual(
            store.withState { SelectionLifetimeTuple(state: $0.entryViewLayout) },
            SelectionLifetimeTuple(
                selectedIds: [expectedEntry.id],
                lastSelectedId: expectedEntry.id,
                rangeAnchorId: expectedEntry.id,
            ),
        )
        XCTAssertEqual(store.withState { $0.entryViewLayout.entries }, [expectedEntry])
        XCTAssertNil(store.withState { $0.pendingIdentityTransition })
        XCTAssertFalse(store.withState { $0.entryViewLayout.isIdentityReplacementActive })
    }

    private func makeSelectionLifetimeStore(
        entries: [EntryModel],
        selectedID: EntryModel.ID,
        quickLook: @escaping @Sendable ([URL], Int) async throws -> Void,
        syncQuickLookSelection: @escaping @Sendable ([URL], Int) async -> Void = { _, _ in },
    ) -> TestStore<FileManagerContentState, FileManagerContentAction> {
        var state = FileManagerContentState()
        state.navigation.seedInitialFolderPath("/root")
        state.entryViewLayout.entries = entries
        state.entryViewLayout.entryOperations.items = .init(uniqueElements: entries)
        state.entryViewLayout.entryOperations.loadingContext.sourceKind = .directory
        state.entryViewLayout.entryOperations.loadingContext.directoryPath = "/root"
        state.entryViewLayout.entryOperations.loadingContext.coreFinished = true
        state.entryViewLayout.entryOperations.loadingContext.streamTerminal = true
        state.entryViewLayout.entryOperations.loadingContext.acceptedCoreFinishedGeneration = 1
        state.entryViewLayout.selectedIds = [selectedID]
        state.entryViewLayout.lastSelectedId = selectedID
        state.entryViewLayout.rangeAnchorId = selectedID

        return TestStore(initialState: state) {
            FileManagerContentFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 0))
            $0.entryLoadingClient.stagedLoadItems = { _, _, _ in
                AsyncThrowingStream { continuation in
                    continuation.yield(.coreBatch(items: entries, batchIndex: 0))
                    continuation.yield(.coreFinished(batchCount: 1))
                    continuation.finish()
                }
            }
            $0.entryQuickLookClient = .init(
                quickLook: quickLook,
                syncQuickLookSelection: syncQuickLookSelection,
            )
        }
    }

    private func selectionLifetimeEntry(id: String, name: String) -> EntryModel {
        EntryModel(
            name: name,
            fullPath: id,
            isFolder: false,
            isHidden: false,
            size: 1,
            modifiedDate: Date(timeIntervalSince1970: 0),
            fileExtension: "txt",
            facets: .init(
                createdDate: Date(timeIntervalSince1970: 0),
                addedDate: Date(timeIntervalSince1970: 0),
                lastOpenedDate: nil,
                kind: "Text",
                creatorApplication: nil,
                tags: nil,
                supplementaryMetadata: nil,
            ),
        )
    }
}

@MainActor
private enum SelectionLifetimeNativeProjection {
    case list(coordinator: EntryListCoordinator, view: EntryListView)
    case grid(coordinator: EntryGridCoordinator, view: EntryGridView)

    init(mode: EntryViewLayoutState.Mode, store: StoreOf<EntryViewLayoutFeature>) {
        switch mode {
        case .list:
            let view = EntryListView(frame: NSRect(x: 0, y: 0, width: 480, height: 320))
            let coordinator = EntryListCoordinator(store: store)
            coordinator.bind(to: view)
            self = .list(coordinator: coordinator, view: view)
        case .grid:
            let view = EntryGridView(frame: NSRect(x: 0, y: 0, width: 320, height: 240))
            let coordinator = EntryGridCoordinator(store: store)
            coordinator.bind(to: view)
            self = .grid(coordinator: coordinator, view: view)
        }
    }

    func selectionMatches(entry: EntryModel) -> Bool {
        switch self {
        case let .list(coordinator, view):
            guard let item = coordinator.entryItemById[entry.id] else { return false }
            return view.tableView.selectedRow == view.tableView.row(forItem: item)
        case let .grid(coordinator, view):
            guard let indexPath = coordinator.indexPathByEntryId[entry.id] else { return false }
            return view.collectionView.selectionIndexPaths == [indexPath]
        }
    }

    func assertSelection(entry: EntryModel) throws {
        switch self {
        case let .list(coordinator, view):
            let item = try XCTUnwrap(coordinator.entryItemById[entry.id])
            XCTAssertEqual(view.tableView.selectedRow, view.tableView.row(forItem: item))
        case let .grid(coordinator, view):
            let indexPath = try XCTUnwrap(coordinator.indexPathByEntryId[entry.id])
            XCTAssertEqual(view.collectionView.selectionIndexPaths, [indexPath])
        }
    }
}

private struct SelectionLifetimeTuple: Equatable {
    let selectedIds: [EntryModel.ID]
    let lastSelectedId: EntryModel.ID?
    let rangeAnchorId: EntryModel.ID?

    init(
        selectedIds: [EntryModel.ID],
        lastSelectedId: EntryModel.ID?,
        rangeAnchorId: EntryModel.ID?,
    ) {
        self.selectedIds = selectedIds
        self.lastSelectedId = lastSelectedId
        self.rangeAnchorId = rangeAnchorId
    }

    init(state: EntryViewLayoutState) {
        self.init(
            selectedIds: Array(state.selectedIds),
            lastSelectedId: state.lastSelectedId,
            rangeAnchorId: state.rangeAnchorId,
        )
    }
}
