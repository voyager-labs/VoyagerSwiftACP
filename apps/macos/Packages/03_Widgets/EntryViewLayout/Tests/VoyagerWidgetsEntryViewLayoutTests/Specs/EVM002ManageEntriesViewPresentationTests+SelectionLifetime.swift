import AppKit
import ComposableArchitecture
import VoyagerEntitiesEntry
@testable import VoyagerWidgetsEntryViewLayout
import XCTest

extension EVM002ManageEntriesViewPresentationTests {
    // MARK: - EVM-002-update_entry_selection

    /// EVM-002-update_entry_selection: 출처 없는 List selection-did-change empty callback은 visible selection을 유지한다.
    /// window/focus 전환 등으로 AppKit이 native selection을 비운 뒤 도착한 context 없는 empty callback이
    /// canonical selection을 지우면 안 된다.
    /// - 검증 내용: delegate 분리 후 비운 native selection에 이어진 context 없는 `outlineViewSelectionDidChange`가
    ///   canonical tuple과 물리 row selection을 유지·복원하는지 확인한다.
    /// - 사전 조건: 첫 번째 Entry가 선택된 List coordinator와 비워진 native selection이 있다.
    /// - 기대 결과: store selection은 그대로이고 native row는 store 선택으로 복원된다.
    func testLifecycleEmptyListCallbackPreservesVisibleSelection() {
        let selectedEntry = EntryModel.temporaryFolder(id: "/root/a.txt", name: "a.txt")
        let otherEntry = EntryModel.temporaryFolder(id: "/root/b.txt", name: "b.txt")
        var state = EntryViewLayoutState()
        state.entries = [selectedEntry, otherEntry]
        state.selectedIds = [selectedEntry.id]
        state.lastSelectedId = selectedEntry.id
        state.rangeAnchorId = selectedEntry.id

        let store = Store(initialState: state) { EntryViewLayoutFeature() }
        let view = EntryListView(frame: NSRect(x: 0, y: 0, width: 480, height: 320))
        let coordinator = EntryListCoordinator(store: store)
        coordinator.bind(to: view)
        XCTAssertEqual(view.tableView.selectedRowIndexes, IndexSet(integer: 0))

        let delegate = view.tableView.delegate
        view.tableView.delegate = nil
        view.tableView.deselectAll(nil)
        view.tableView.delegate = delegate
        coordinator.outlineViewSelectionDidChange(Notification(name: .init("selection-lifecycle-empty")))

        XCTAssertEqual(store.state.selectedIds, [selectedEntry.id])
        XCTAssertEqual(store.state.lastSelectedId, selectedEntry.id)
        XCTAssertEqual(store.state.rangeAnchorId, selectedEntry.id)
        XCTAssertEqual(view.tableView.selectedRowIndexes, IndexSet(integer: 0))
    }

    /// EVM-002-update_entry_selection: View clear intent는 authoritative internal clear로 라우팅된다.
    /// UI adapter가 empty tuple을 직접 만들지 않고 명시적 clear intent를 보낼 때도 기존 reducer clear 계약을 재사용한다.
    /// - 검증 내용: `.view(.clearSelection)`이 selected IDs와 두 cursor를 초기화하고 selection delegate를 한 번 발행하는지 확인한다.
    /// - 사전 조건: 하나의 Entry와 focus/anchor가 선택된 `EntryViewLayoutFeature` 상태가 있다.
    /// - 기대 결과: 세 selection 필드가 비고 `selectionChanged`가 한 번 수신된다.
    func testViewClearSelectionRoutesToAuthoritativeClear() async {
        let selectedID = "/root/a.txt"
        var state = EntryViewLayoutState()
        state.selectedIds = [selectedID]
        state.lastSelectedId = selectedID
        state.rangeAnchorId = selectedID

        let store = TestStore(initialState: state) {
            EntryViewLayoutFeature()
        }

        await store.send(.view(.clearSelection))
        await store.receive(\.internal.applyClearSelection) {
            $0.selectedIds = []
            $0.lastSelectedId = nil
            $0.rangeAnchorId = nil
            $0.shouldScrollToSelection = false
        }
        await store.receive(\.delegate.selectionChanged)
    }

    /// EVM-002-update_entry_selection: 출처 없는 Grid selection callback은 visible selection을 유지한다.
    /// lifecycle 이벤트가 만든 empty `NSCollectionViewDelegate` callback이 canonical selection을 지우면 안 된다.
    /// - 검증 내용: delegate 분리 후 비운 collection selection에 이어진 `updateSelectionFromCollectionView`가
    ///   canonical tuple과 `selectionIndexPaths`를 유지·복원하는지 확인한다.
    /// - 사전 조건: 첫 번째 Entry가 선택된 Grid coordinator와 비워진 native selection이 있다.
    /// - 기대 결과: store selection은 그대로이고 native index path는 store 선택으로 복원된다.
    func testLifecycleEmptyGridCallbackPreservesVisibleSelection() {
        let selectedEntry = EntryModel.temporaryFolder(id: "/root/a.txt", name: "a.txt")
        let otherEntry = EntryModel.temporaryFolder(id: "/root/b.txt", name: "b.txt")
        var state = EntryViewLayoutState()
        state.entries = [selectedEntry, otherEntry]
        state.selectedIds = [selectedEntry.id]
        state.lastSelectedId = selectedEntry.id
        state.rangeAnchorId = selectedEntry.id

        let store = Store(initialState: state) { EntryViewLayoutFeature() }
        let view = EntryGridView(frame: NSRect(x: 0, y: 0, width: 320, height: 240))
        let coordinator = EntryGridCoordinator(store: store)
        coordinator.bind(to: view)
        XCTAssertEqual(view.collectionView.selectionIndexPaths, [IndexPath(item: 0, section: 0)])

        let delegate = view.collectionView.delegate
        view.collectionView.delegate = nil
        view.collectionView.deselectAll(nil)
        view.collectionView.delegate = delegate
        coordinator.updateSelectionFromCollectionView(view.collectionView)

        XCTAssertEqual(store.state.selectedIds, [selectedEntry.id])
        XCTAssertEqual(store.state.lastSelectedId, selectedEntry.id)
        XCTAssertEqual(store.state.rangeAnchorId, selectedEntry.id)
        XCTAssertEqual(view.collectionView.selectionIndexPaths, [IndexPath(item: 0, section: 0)])
    }

    /// EVM-002-update_entry_selection: retained Grid selection은 incremental insertion 뒤 새 index path로 이동한다.
    /// selectedIds가 동일해도 Entry ID를 기준으로 native index path를 재투영해야 한다.
    /// - 검증 내용: 첫 번째 항목 앞에 새 항목을 삽입한 뒤 기존 선택 ID가 index 1에 선택되는지 확인한다.
    /// - 사전 조건: index 0의 Entry A가 선택된 두 항목 Grid와 A를 유지하는 단일 삽입 snapshot이 있다.
    /// - 기대 결과: canonical tuple은 유지되고 native selection은 A의 새 index path를 가리킨다.
    func testRetainedGridSelectionRemapsAfterIncrementalInsertion() {
        let selectedEntry = EntryModel.temporaryFolder(id: "/root/a.txt", name: "a.txt")
        let otherEntry = EntryModel.temporaryFolder(id: "/root/b.txt", name: "b.txt")
        let insertedEntry = EntryModel.temporaryFolder(id: "/root/0.txt", name: "0.txt")
        var previousState = EntryViewLayoutState()
        previousState.entries = [selectedEntry, otherEntry]
        previousState.selectedIds = [selectedEntry.id]
        previousState.lastSelectedId = selectedEntry.id
        previousState.rangeAnchorId = selectedEntry.id
        var snapshotState = previousState
        snapshotState.entries = [insertedEntry, selectedEntry, otherEntry]

        let store = Store(initialState: previousState) { EntryViewLayoutFeature() }
        let view = EntryGridView(frame: NSRect(x: 0, y: 0, width: 320, height: 240))
        let coordinator = EntryGridCoordinator(store: store)
        coordinator.bind(to: view)
        coordinator.isRenderObservationEnabled = false

        coordinator.handleSnapshotChanges(
            previous: EntryGridRenderSnapshot(state: previousState),
            snapshot: EntryGridRenderSnapshot(state: snapshotState),
        )

        XCTAssertEqual(store.state.selectedIds, [selectedEntry.id])
        XCTAssertEqual(view.collectionView.selectionIndexPaths, [IndexPath(item: 1, section: 0)])
    }

    /// EVM-002-update_entry_selection: List↔Grid coordinator remount는 same-ID selection을 재투영한다.
    /// - 검증 내용: 동일 store를 List→Grid→List coordinator가 bind할 때 tuple/native selection parity를 확인한다.
    /// - 사전 조건: 두 root Entry 중 첫 번째 Entry가 선택된 상태와 새 adapter view가 있다.
    /// - 기대 결과: 각 adapter가 선택 ID를 현재 row/index path로 재투영하고 cursor tuple을 보존한다.
    func testSelectionSurvivesListGridListCoordinatorRemount() {
        let selectedEntry = EntryModel.temporaryFolder(id: "/root/a.txt", name: "a.txt")
        let otherEntry = EntryModel.temporaryFolder(id: "/root/b.txt", name: "b.txt")
        var state = EntryViewLayoutState()
        state.entries = [selectedEntry, otherEntry]
        state.selectedIds = [selectedEntry.id]
        state.lastSelectedId = selectedEntry.id
        state.rangeAnchorId = selectedEntry.id

        let store = Store(initialState: state) { EntryViewLayoutFeature() }
        let firstListView = EntryListView(frame: NSRect(x: 0, y: 0, width: 480, height: 320))
        let firstListCoordinator = EntryListCoordinator(store: store)
        firstListCoordinator.bind(to: firstListView)
        XCTAssertEqual(firstListView.tableView.selectedRowIndexes, IndexSet(integer: 0))

        let gridView = EntryGridView(frame: NSRect(x: 0, y: 0, width: 320, height: 240))
        let gridCoordinator = EntryGridCoordinator(store: store)
        gridCoordinator.bind(to: gridView)
        XCTAssertEqual(gridView.collectionView.selectionIndexPaths, [IndexPath(item: 0, section: 0)])

        let remountedListView = EntryListView(frame: NSRect(x: 0, y: 0, width: 480, height: 320))
        let remountedListCoordinator = EntryListCoordinator(store: store)
        remountedListCoordinator.bind(to: remountedListView)

        XCTAssertEqual(store.state.selectedIds, [selectedEntry.id])
        XCTAssertEqual(store.state.lastSelectedId, selectedEntry.id)
        XCTAssertEqual(store.state.rangeAnchorId, selectedEntry.id)
        XCTAssertEqual(remountedListView.tableView.selectedRowIndexes, IndexSet(integer: 0))
    }

    /// EVM-002-update_entry_selection: List의 명시적 blank clear는 empty tuple setter가 아닌 clear intent를 사용한다.
    /// - 검증 내용: blank provenance가 붙은 empty native callback이 한 번의 clear action만 발행하는지 확인한다.
    /// - 사전 조건: 선택된 Entry 하나와 비워진 native row selection이 있다.
    /// - 기대 결과: canonical tuple/native selection이 비고 `clearSelection`만 한 번 기록된다.
    func testExplicitListBlankClearUsesClearIntentOnce() {
        let entry = EntryModel.temporaryFolder(id: "/root/a.txt", name: "a.txt")
        let fixture = SelectionLifetimeListFixture(entries: [entry], selectedID: entry.id)
        fixture.tableView.noteExplicitUserClearGesture()
        fixture.clearNativeSelectionAndNotify()

        XCTAssertTrue(fixture.store.state.selectedIds.isEmpty)
        XCTAssertNil(fixture.store.state.lastSelectedId)
        XCTAssertNil(fixture.store.state.rangeAnchorId)
        XCTAssertTrue(fixture.tableView.selectedRowIndexes.isEmpty)
        XCTAssertEqual(fixture.recorder.clearCount, 1)
        XCTAssertEqual(fixture.recorder.updateCount, 0)
    }

    /// EVM-002-update_entry_selection: List의 Command-last-deselect도 명시적 clear intent를 사용한다.
    /// - 검증 내용: Command context가 마지막 Entry를 제거할 때 clear action을 한 번 발행하는지 확인한다.
    /// - 사전 조건: 한 Entry가 선택되고 해당 row에 Command native selection context가 설정돼 있다.
    /// - 기대 결과: canonical tuple/native selection이 비고 updateSelection은 발행되지 않는다.
    func testCommandLastListDeselectUsesClearIntentOnce() throws {
        let entry = EntryModel.temporaryFolder(id: "/root/a.txt", name: "a.txt")
        let fixture = SelectionLifetimeListFixture(entries: [entry], selectedID: entry.id)
        let row = try fixture.entryRow(id: entry.id)
        let occurrence = try XCTUnwrap(fixture.tableView.item(atRow: row) as AnyObject?)
        fixture.tableView.deselectAll(nil)

        fixture.coordinator.normalizeNativeSelection(
            physicalRows: [],
            context: EntryListNativeSelectionContext(
                destinationOccurrence: occurrence,
                modifierFlags: .command,
            ),
        )

        XCTAssertTrue(fixture.store.state.selectedIds.isEmpty)
        XCTAssertNil(fixture.store.state.lastSelectedId)
        XCTAssertNil(fixture.store.state.rangeAnchorId)
        XCTAssertEqual(fixture.recorder.clearCount, 1)
        XCTAssertEqual(fixture.recorder.updateCount, 0)
    }

    /// EVM-002-update_entry_selection: Grid의 명시적 blank clear는 empty callback을 clear intent로 귀속한다.
    /// - 검증 내용: coordinator가 연결한 blank-space hook 뒤 empty collection callback이 한 번의 clear를 발행하는지 확인한다.
    /// - 사전 조건: 선택된 Entry 하나와 비워진 native collection selection이 있다.
    /// - 기대 결과: canonical tuple/native selection이 비고 clear action만 한 번 기록된다.
    func testExplicitGridBlankClearUsesClearIntentOnce() {
        let entry = EntryModel.temporaryFolder(id: "/root/a.txt", name: "a.txt")
        let fixture = SelectionLifetimeGridFixture(entries: [entry], selectedID: entry.id)
        fixture.view.collectionView.onBlankSpaceSelectionClear?()
        fixture.clearNativeSelectionAndNotify()
        fixture.coordinator.handleLassoSelection(indexPaths: [], isFinal: true)

        XCTAssertTrue(fixture.store.state.selectedIds.isEmpty)
        XCTAssertNil(fixture.store.state.lastSelectedId)
        XCTAssertNil(fixture.store.state.rangeAnchorId)
        XCTAssertTrue(fixture.view.collectionView.selectionIndexPaths.isEmpty)
        XCTAssertEqual(fixture.recorder.clearCount, 1)
        XCTAssertEqual(fixture.recorder.updateCount, 0)
    }

    /// EVM-002-update_entry_selection: Grid의 Command-last-deselect는 non-empty command selection과 분리돼 clear된다.
    /// - 검증 내용: command item hook 뒤 마지막 native selection 해제가 clear intent를 한 번 발행하는지 확인한다.
    /// - 사전 조건: 한 Entry가 선택되고 Command toggle provenance가 설정돼 있다.
    /// - 기대 결과: canonical tuple/native selection이 비고 updateSelection은 발행되지 않는다.
    func testCommandLastGridDeselectUsesClearIntentOnce() {
        let entry = EntryModel.temporaryFolder(id: "/root/a.txt", name: "a.txt")
        let fixture = SelectionLifetimeGridFixture(entries: [entry], selectedID: entry.id)
        fixture.view.collectionView.onCommandItemClick?()
        fixture.clearNativeSelectionAndNotify()

        XCTAssertTrue(fixture.store.state.selectedIds.isEmpty)
        XCTAssertNil(fixture.store.state.lastSelectedId)
        XCTAssertNil(fixture.store.state.rangeAnchorId)
        XCTAssertEqual(fixture.recorder.clearCount, 1)
        XCTAssertEqual(fixture.recorder.updateCount, 0)
    }

    /// EVM-002-update_entry_selection: Grid empty final lasso는 명시적 clear로 종료된다.
    /// - 검증 내용: lasso가 빈 index path로 끝날 때 native empty callback과 별도로 clear intent를 발행하는지 확인한다.
    /// - 사전 조건: 선택된 Entry 하나가 있고 빈 lasso final 결과가 전달된다.
    /// - 기대 결과: canonical tuple/native selection이 비고 clear action은 한 번 기록된다.
    func testEmptyFinalGridLassoUsesClearIntentOnce() {
        let entry = EntryModel.temporaryFolder(id: "/root/a.txt", name: "a.txt")
        let fixture = SelectionLifetimeGridFixture(entries: [entry], selectedID: entry.id)
        fixture.coordinator.handleLassoSelection(indexPaths: [], isFinal: true)

        XCTAssertTrue(fixture.store.state.selectedIds.isEmpty)
        XCTAssertNil(fixture.store.state.lastSelectedId)
        XCTAssertNil(fixture.store.state.rangeAnchorId)
        XCTAssertTrue(fixture.view.collectionView.selectionIndexPaths.isEmpty)
        XCTAssertEqual(fixture.recorder.clearCount, 1)
        XCTAssertEqual(fixture.recorder.updateCount, 0)
    }

    /// EVM-002-update_entry_selection: Grid non-empty lasso는 기존 updateSelection 경로를 유지한다.
    /// - 검증 내용: 빈 결과 전용 clear 분기가 additive/non-empty lasso의 canonical update를 바꾸지 않는지 확인한다.
    /// - 사전 조건: 두 Entry Grid에 첫 번째 Entry가 선택되고 두 번째 index path가 final lasso 결과로 전달된다.
    /// - 기대 결과: 두 번째 Entry만 updateSelection으로 선택되고 clear action은 없다.
    func testNonEmptyFinalGridLassoKeepsUpdateSelection() {
        let first = EntryModel.temporaryFolder(id: "/root/a.txt", name: "a.txt")
        let second = EntryModel.temporaryFolder(id: "/root/b.txt", name: "b.txt")
        let fixture = SelectionLifetimeGridFixture(entries: [first, second], selectedID: first.id)
        fixture.coordinator.handleLassoSelection(indexPaths: [IndexPath(item: 1, section: 0)], isFinal: true)

        XCTAssertEqual(fixture.store.state.selectedIds, [second.id])
        XCTAssertEqual(fixture.store.state.lastSelectedId, second.id)
        XCTAssertEqual(fixture.view.collectionView.selectionIndexPaths, [IndexPath(item: 1, section: 0)])
        XCTAssertEqual(fixture.recorder.clearCount, 0)
        XCTAssertEqual(fixture.recorder.updateCount, 1)
    }
}

@MainActor
private final class SelectionLifetimeRecorder: @unchecked Sendable {
    var updateCount = 0
    var clearCount = 0
}

@MainActor
private final class SelectionLifetimeListFixture {
    let store: StoreOf<EntryViewLayoutFeature>
    let coordinator: EntryListCoordinator
    let view: EntryListView
    let recorder: SelectionLifetimeRecorder

    var tableView: EntryListView.EntryListTableView {
        view.tableView
    }

    init(entries: [EntryModel], selectedID: EntryModel.ID?) {
        var state = EntryViewLayoutState()
        state.entries = entries
        if let selectedID {
            state.selectedIds = [selectedID]
            state.lastSelectedId = selectedID
            state.rangeAnchorId = selectedID
        }
        let recorder = SelectionLifetimeRecorder()
        self.recorder = recorder
        let store = Store(initialState: state) {
            Reduce<EntryViewLayoutState, EntryViewLayoutAction> { state, action in
                switch action {
                case let .view(.updateSelection(ids, focus, anchor, shouldScroll)):
                    state.selectedIds = ids
                    state.lastSelectedId = focus
                    state.rangeAnchorId = anchor
                    state.shouldScrollToSelection = shouldScroll
                    recorder.updateCount += 1
                case .view(.clearSelection):
                    state.selectedIds = []
                    state.lastSelectedId = nil
                    state.rangeAnchorId = nil
                    state.shouldScrollToSelection = false
                    recorder.clearCount += 1
                default:
                    break
                }
                return .none
            }
        }
        self.store = store
        coordinator = EntryListCoordinator(store: store)
        view = EntryListView(frame: NSRect(x: 0, y: 0, width: 480, height: 320))
        coordinator.bind(to: view)
        view.layoutSubtreeIfNeeded()
        tableView.layoutSubtreeIfNeeded()
    }

    func entryRow(id: EntryModel.ID) throws -> Int {
        let item = try XCTUnwrap(coordinator.entryItemsByID[id]?.first(where: { tableView.row(forItem: $0) >= 0 }))
        return tableView.row(forItem: item)
    }

    func clearNativeSelectionAndNotify() {
        let delegate = tableView.delegate
        tableView.delegate = nil
        tableView.deselectAll(nil)
        tableView.delegate = delegate
        coordinator.outlineViewSelectionDidChange(Notification(name: .init("selection-lifetime-empty")))
    }
}

@MainActor
private final class SelectionLifetimeGridFixture {
    let store: StoreOf<EntryViewLayoutFeature>
    let coordinator: EntryGridCoordinator
    let view: EntryGridView
    let recorder: SelectionLifetimeRecorder

    init(entries: [EntryModel], selectedID: EntryModel.ID?) {
        var state = EntryViewLayoutState()
        state.entries = entries
        if let selectedID {
            state.selectedIds = [selectedID]
            state.lastSelectedId = selectedID
            state.rangeAnchorId = selectedID
        }
        let recorder = SelectionLifetimeRecorder()
        self.recorder = recorder
        let store = Store(initialState: state) {
            Reduce<EntryViewLayoutState, EntryViewLayoutAction> { state, action in
                switch action {
                case let .view(.updateSelection(ids, focus, anchor, shouldScroll)):
                    state.selectedIds = ids
                    state.lastSelectedId = focus
                    state.rangeAnchorId = anchor
                    state.shouldScrollToSelection = shouldScroll
                    recorder.updateCount += 1
                case .view(.clearSelection):
                    state.selectedIds = []
                    state.lastSelectedId = nil
                    state.rangeAnchorId = nil
                    state.shouldScrollToSelection = false
                    recorder.clearCount += 1
                default:
                    break
                }
                return .none
            }
        }
        self.store = store
        coordinator = EntryGridCoordinator(store: store)
        view = EntryGridView(frame: NSRect(x: 0, y: 0, width: 320, height: 240))
        coordinator.bind(to: view)
    }

    func clearNativeSelectionAndNotify() {
        let delegate = view.collectionView.delegate
        view.collectionView.delegate = nil
        view.collectionView.deselectAll(nil)
        view.collectionView.delegate = delegate
        coordinator.updateSelectionFromCollectionView(view.collectionView)
    }
}
