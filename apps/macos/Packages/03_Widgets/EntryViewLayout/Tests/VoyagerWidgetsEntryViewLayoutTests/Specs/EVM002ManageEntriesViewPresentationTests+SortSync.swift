import VoyagerShared
@testable import VoyagerWidgetsEntryViewLayout
import XCTest

extension EVM002ManageEntriesViewPresentationTests {
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
