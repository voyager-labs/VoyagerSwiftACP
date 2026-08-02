import VoyagerEntitiesEntry
import VoyagerShared
@testable import VoyagerWidgetsEntryViewLayout
import XCTest

extension EVM002ManageEntriesViewPresentationTests {
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
