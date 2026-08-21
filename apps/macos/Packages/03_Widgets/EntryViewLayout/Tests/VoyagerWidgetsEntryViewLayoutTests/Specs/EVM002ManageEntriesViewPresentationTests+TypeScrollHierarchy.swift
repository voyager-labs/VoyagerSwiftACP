import AppKit
import ComposableArchitecture
import VoyagerEntitiesEntry
import VoyagerFeaturesEntryOperations
import VoyagerShared
@testable import VoyagerWidgetsEntryViewLayout
import XCTest

extension EVM002ManageEntriesViewPresentationTests {
    /// EVM-002-manage_entries_view_type_scroll: visible hierarchy child target은 root load 성공 동기화를 통과한다.
    ///
    /// - 검증 내용: target 설정과 첫 list render 사이의 itemsLoaded가 visible child pending을 보존하고 첫 render가 소비한다.
    /// - 사전 조건: list hierarchy에서 expanded root의 child가 visible하고 render observation은 수동 제어된다.
    /// - 기대 결과: itemsLoaded 직후 pending이 유지되고 첫 canonical render 후 nil이며 재렌더에도 stale target이 없다.
    func testHierarchyChildPendingTypeScrollSurvivesRootLoadSuccessUntilListRender() {
        let fixture = makeHierarchyTypeScrollFixture()
        let store = Store(initialState: fixture.state) { EntryViewLayoutFeature() }
        let coordinator = EntryListCoordinator(store: store)
        coordinator.bind(to: EntryListView(frame: NSRect(x: 0, y: 0, width: 400, height: 40)))
        coordinator.isRenderObservationEnabled = false
        let before = EntryListCoordinatorRenderSnapshot(state: store.state)

        store.send(.view(.setTypeScrollTarget(fixture.child.id)))
        store.send(.entryOperations(.loading(.itemsLoaded([fixture.root]))))

        XCTAssertEqual(store.state.pendingTypeScrollTargetId, fixture.child.id)
        let synchronized = EntryListCoordinatorRenderSnapshot(state: store.state)
        coordinator.handleSnapshotChanges(previous: before, snapshot: synchronized)
        XCTAssertNil(store.state.pendingTypeScrollTargetId)

        coordinator.handleSnapshotChanges(
            previous: synchronized,
            snapshot: EntryListCoordinatorRenderSnapshot(state: store.state),
        )
        XCTAssertNil(store.state.pendingTypeScrollTargetId)
    }

    /// EVM-002-manage_entries_view_type_scroll: visible hierarchy child target은 parent를 유지한 root 실패 동기화를 통과한다.
    ///
    /// - 검증 내용: partial root를 유지한 실패 snapshot 동기화가 visible child pending을 보존한다.
    /// - 사전 조건: 실패 snapshot의 incoming roots에 expanded child의 parent root가 남아 있다.
    /// - 기대 결과: 동기화 직후 pending이 유지되고 첫 canonical render가 한 번 reset한다.
    func testHierarchyChildPendingTypeScrollSurvivesFailedRootSnapshotRetainingParentUntilListRender() {
        let fixture = makeHierarchyTypeScrollFixture()
        let store = Store(initialState: fixture.state) { EntryViewLayoutFeature() }
        let coordinator = EntryListCoordinator(store: store)
        coordinator.bind(to: EntryListView(frame: NSRect(x: 0, y: 0, width: 400, height: 40)))
        coordinator.isRenderObservationEnabled = false
        let before = EntryListCoordinatorRenderSnapshot(state: store.state)

        store.send(.view(.setTypeScrollTarget(fixture.child.id)))
        var synchronizedState = store.state
        synchronizedState.synchronizeEntries([fixture.root])

        XCTAssertEqual(synchronizedState.pendingTypeScrollTargetId, fixture.child.id)
        let synchronized = EntryListCoordinatorRenderSnapshot(state: synchronizedState)
        coordinator.handleSnapshotChanges(previous: before, snapshot: synchronized)
        XCTAssertNil(store.state.pendingTypeScrollTargetId)
    }

    /// EVM-002-manage_entries_view_type_scroll: incoming roots에서 parent가 제거되면 stale hierarchy child target을 제거한다.
    ///
    /// - 검증 내용: old hierarchy cache가 expanded child를 유지해도 prospective incoming-root projection만 survivor로 인정한다.
    /// - 사전 조건: 기존 root와 child가 visible하고 pending이지만 incoming roots는 parent root를 누락한다.
    /// - 기대 결과: synchronizeEntries([]) 직후 pending은 nil이고 old hierarchy cache 존재 여부와 무관하다.
    func testHierarchyChildPendingTypeScrollClearsWhenIncomingRootsRemoveParent() {
        let fixture = makeHierarchyTypeScrollFixture()
        var state = fixture.state
        state.pendingTypeScrollTargetId = fixture.child.id

        state.synchronizeEntries([])

        XCTAssertNotNil(state.hierarchy.nodesByID[fixture.root.id])
        XCTAssertNil(state.pendingTypeScrollTargetId)
    }

    /// EVM-002-manage_entries_view_type_scroll: hierarchy child가 visible projection을 떠나면 pending target을 제거한다.
    ///
    /// - 검증 내용: collapsed, hidden, removed child를 root 동기화 survivor로 인정하지 않는다.
    /// - 사전 조건: hierarchy projection은 활성이고 각 child id가 pending target이다.
    /// - 기대 결과: 세 topology 모두 synchronizeEntries 후 pending이 nil이다.
    func testHierarchyPendingTypeScrollClearsWhenChildLeavesVisibleProjection() {
        let fixture = makeHierarchyTypeScrollFixture()

        var collapsed = fixture.state
        collapsed.hierarchy.setExpandedIDs([])
        collapsed.pendingTypeScrollTargetId = fixture.child.id
        collapsed.synchronizeEntries([fixture.root])

        let hiddenDescendant = EntryModel.temporaryFolder(
            id: "/root/folder/child/descendant",
            name: "descendant",
        )
        var hidden = fixture.state
        hidden.hierarchy.nodesByID[fixture.child.id] = FolderNodeState(
            children: [hiddenDescendant],
            loadPhase: .loaded,
            generation: 1,
            coreFinished: true,
        )
        hidden.pendingTypeScrollTargetId = hiddenDescendant.id
        hidden.synchronizeEntries([fixture.root])

        var removed = fixture.state
        removed.hierarchy.nodesByID[fixture.root.id]?.folder.children = []
        removed.pendingTypeScrollTargetId = fixture.child.id
        removed.synchronizeEntries([fixture.root])

        XCTAssertNil(collapsed.pendingTypeScrollTargetId)
        XCTAssertNil(hidden.pendingTypeScrollTargetId)
        XCTAssertNil(removed.pendingTypeScrollTargetId)
    }

    /// EVM-002-manage_entries_view_type_scroll: hierarchy 비활성 mode는 missing child target을 보존하지 않는다.
    ///
    /// - 검증 내용: flat, grid, grouped, collection mode가 hierarchy nodes의 missing target을 survivor로 사용하지 않는다.
    /// - 사전 조건: hierarchy node에는 child가 남아 있지만 실제 hierarchy projection mode는 비활성이다.
    /// - 기대 결과: 모든 mode에서 root synchronize 후 pending이 nil이다.
    func testMissingPendingTypeScrollTargetClearsOutsideActiveHierarchyProjection() {
        let fixture = makeHierarchyTypeScrollFixture()
        var states: [EntryViewLayoutState] = []

        var flat = fixture.state
        flat.hierarchy = .init(rootPath: "", nodesByID: flat.hierarchy.nodesByID)
        states.append(flat)

        var grid = fixture.state
        grid.mode = .grid
        states.append(grid)

        var grouped = fixture.state
        grouped.entryArrangements.groupKey = .name
        states.append(grouped)

        var collection = fixture.state
        collection.isCollectionMode = true
        states.append(collection)

        for index in states.indices {
            states[index].pendingTypeScrollTargetId = fixture.child.id
            states[index].synchronizeEntries([fixture.root])
            XCTAssertNil(states[index].pendingTypeScrollTargetId)
        }
    }

    private func makeHierarchyTypeScrollFixture(
        child: EntryModel = .temporaryFolder(id: "/root/folder/child", name: "child"),
    ) -> HierarchyTypeScrollFixture {
        let root = EntryModel.temporaryFolder(id: "/root/folder", name: "folder")
        var state = EntryViewLayoutState()
        state.mode = .list
        state.entries = [root]
        state.entryOperations.items = [root]
        state.hierarchy = .init(
            rootPath: "/root",
            nodesByID: [
                root.id: FolderNodeState(
                    children: [child],
                    loadPhase: .loaded,
                    generation: 1,
                    coreFinished: true,
                ),
            ],
        )
        state.hierarchy.setExpandedIDs([root.id])
        return HierarchyTypeScrollFixture(state: state, root: root, child: child)
    }
}

private struct HierarchyTypeScrollFixture {
    let state: EntryViewLayoutState
    let root: EntryModel
    let child: EntryModel
}
