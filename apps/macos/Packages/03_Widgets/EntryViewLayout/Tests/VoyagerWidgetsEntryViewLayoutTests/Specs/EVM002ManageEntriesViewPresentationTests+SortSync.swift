import VoyagerEntitiesEntry
import VoyagerShared
@testable import VoyagerWidgetsEntryViewLayout
import XCTest

extension EVM002ManageEntriesViewPresentationTests {
    // MARK: - EVM-002-update_entry_selection

    /// EVM-002-update_entry_selection: data synchronization preserves collapsed child selection and scroll intent.
    /// authoritative entries에 남아 있는 child가 visible projection에서 일시적으로 숨겨져도 선택 상태를 보존하는지 검증한다.
    /// - 검증 내용: synchronizeEntries가 entries membership으로 selection을 정리하고 scroll intent를 유지한다.
    /// - 사전 조건: collapsed folder의 child가 entries에 존재하고 child가 선택되어 있으며 scroll intent가 true다.
    /// - 기대 결과: reconcile 후 selectedIds와 shouldScrollToSelection이 모두 유지된다.
    func testSynchronizeEntriesPreservesCollapsedChildSelectionAndScrollIntent() {
        let folder = EntryModel.temporaryFolder(id: "/root/a", name: "a")
        let child = EntryModel.temporaryFolder(id: "/root/a/child", name: "child")
        var state = EntryViewLayoutState()
        state.entries = [folder]
        state.hierarchy = .init(rootPath: "/root")
        state.hierarchy.nodesByID[folder.id] = FolderNodeState(
            children: [child],
            loadPhase: .loaded,
            generation: 0,
        )
        state.selectedIds = [child.id]
        state.lastSelectedId = child.id
        state.rangeAnchorId = child.id
        state.shouldScrollToSelection = true

        state.synchronizeEntries([folder, child])

        XCTAssertEqual(state.selectedIds, [child.id])
        XCTAssertEqual(state.lastSelectedId, child.id)
        XCTAssertEqual(state.rangeAnchorId, child.id)
        XCTAssertTrue(state.shouldScrollToSelection)
    }

    /// EVM-002-update_entry_selection: data synchronization deselects entries removed from authoritative data.
    /// authoritative entries에서 실제로 제거된 항목만 selection에서 제거되는지 검증한다.
    /// - 검증 내용: synchronizePresentation이 제거된 entry의 selection과 focus/anchor를 정리한다.
    /// - 사전 조건: a와 b가 entries에 있고 b가 선택되어 있으며 scroll intent가 true다.
    /// - 기대 결과: b 제거 후 selection, focus, anchor가 비고 scroll intent는 data sync가 지우지 않는다.
    func testSynchronizePresentationDeselectsRemovedEntriesWithoutClearingScrollIntent() {
        let first = EntryModel.temporaryFolder(id: "/root/a", name: "a")
        let removed = EntryModel.temporaryFolder(id: "/root/b", name: "b")
        var state = EntryViewLayoutState()
        state.entries = [first, removed]
        state.selectedIds = [removed.id]
        state.lastSelectedId = removed.id
        state.rangeAnchorId = removed.id
        state.shouldScrollToSelection = true

        state.synchronizePresentation(
            entries: [first],
            sections: [],
            openWithApplications: [],
        )

        XCTAssertTrue(state.selectedIds.isEmpty)
        XCTAssertNil(state.lastSelectedId)
        XCTAssertNil(state.rangeAnchorId)
        XCTAssertTrue(state.shouldScrollToSelection)
    }

    /// EVM-002-sort_entries_by_property: hierarchy 정렬 순서 변경은 outline revision을 갱신한다.
    /// - 검증 내용: 같은 visible ID 집합의 ascending→descending 순서 변화가 revision을 증가시키는지 확인한다.
    /// - 사전 조건: hierarchy가 활성화되고 a, b root entry의 첫 projection이 reconcile돼 있다.
    /// - 기대 결과: ID 집합은 같아도 ordered projection 변화로 revision이 1 증가한다.
    func testHierarchySortOrderChangeAdvancesOutlineRevision() {
        let first = EntryModel.temporaryFolder(id: "/root/a", name: "a")
        let second = EntryModel.temporaryFolder(id: "/root/b", name: "b")
        var state = EntryViewLayoutState()
        state.entries = [first, second]
        state.hierarchy = .init(rootPath: "/root")
        state.reconcileSelectionWithVisibleEntries()
        let initialRevision = state.outlineProjectionRevision

        state.sortOrder = .descending
        state.reconcileSelectionWithVisibleEntries()

        XCTAssertEqual(state.outlineProjectionRevision, initialRevision + 1)
        XCTAssertEqual(
            state.visibleSelectableEntryIDs(isNormalDirectoryPage: true),
            [second.id, first.id],
        )
    }

    /// EVM-002-set_entries_view_as_list_table: header sort key와 order 변경을 하나의 final change로 만든다.
    /// - 검증 내용: Kind descending에서 Name ascending으로 바뀔 때 stale key가 포함되지 않는다.
    /// - 사전 조건: 현재 key/order와 header descriptor의 key/order가 모두 다르다.
    /// - 기대 결과: 단일 change가 Name ascending을 보존한다.
    func testListHeaderSortChangeCombinesFinalKeyAndOrder() {
        let change = EntryListCoordinatorSortDescriptorChange(
            sortKey: .name,
            sortOrder: .ascending,
        )

        let action = EntryListCoordinatorSortDescriptorMapper.actionNeeded(
            currentSortKey: .kind,
            currentSortOrder: .descending,
            change: change,
        )

        XCTAssertEqual(action, change)
    }
}
