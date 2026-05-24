import ComposableArchitecture
@testable import VoyagerWidgetsEntryViewLayout
import XCTest

@MainActor
final class EVM002ManageEntriesViewPresentationTests: XCTestCase {
    // MARK: - EVM-002-show_hide_hidden_entry

    /// EVM-002-show_hide_hidden_entry: 숨김 파일 토글이 상태를 반전시키는지 검증
    ///
    /// - 검증 내용: toggleShowHiddenFiles 액션이 showHiddenFiles를 false에서 true로 변경
    /// - 사전 조건: 초기 상태 showHiddenFiles == false
    /// - 기대 결과: 상태가 true로 전환됨
    func testToggleShowHiddenFilesFlipsState() async {
        let store = TestStore(initialState: EntryViewLayoutState()) {
            EntryViewLayoutFeature()
        }

        XCTAssertFalse(store.state.showHiddenFiles)

        await store.send(.view(.toggleShowHiddenFiles)) {
            $0.showHiddenFiles = true
        }
    }

    /// EVM-002-show_hide_hidden_entry: true→false 토글이 정상 동작하는지 검증
    ///
    /// - 검증 내용: 이미 showHiddenFiles가 true일 때 토글하면 false로 복원
    /// - 사전 조건: showHiddenFiles == true
    /// - 기대 결과: 상태가 false로 전환됨
    func testToggleShowHiddenFilesOffThenOn() async {
        var state = EntryViewLayoutState()
        state.showHiddenFiles = true

        let store = TestStore(initialState: state) {
            EntryViewLayoutFeature()
        }

        await store.send(.view(.toggleShowHiddenFiles)) {
            $0.showHiddenFiles = false
        }
    }

    /// EVM-002-show_hide_hidden_entry: 직접 설정 액션이 상태를 업데이트하는지 검증
    ///
    /// - 검증 내용: setShowHiddenFiles 내부 액션으로 true/false 직접 설정
    /// - 사전 조건: 초기 상태 showHiddenFiles == false
    /// - 기대 결과: true 설정 후 false로 복원 가능
    func testSetShowHiddenFilesDirectly() async {
        let store = TestStore(initialState: EntryViewLayoutState()) {
            EntryViewLayoutFeature()
        }

        await store.send(.internal(.setShowHiddenFiles(true))) {
            $0.showHiddenFiles = true
        }

        await store.send(.internal(.setShowHiddenFiles(false))) {
            $0.showHiddenFiles = false
        }
    }

    /// EVM-002-show_hide_hidden_entry: 환경설정 적용 시 showHiddenFiles가 반영되는지 검증
    ///
    /// - 검증 내용: applyPreferences 액션이 showHiddenFiles를 포함한 모든 설정을 업데이트
    /// - 사전 조건: 초기 상태 (기본값)
    /// - 기대 결과: preferences에 지정한 값들이 상태에 반영됨
    func testApplyPreferencesSetsShowHiddenFiles() async {
        let store = TestStore(initialState: EntryViewLayoutState()) {
            EntryViewLayoutFeature()
        }

        let preferences = EntryViewLayoutAction.EntryViewLayoutPreferences(
            listIconSize: 16,
            listTextSize: 12,
            gridIconSize: 64,
            gridTextSize: 12,
            showHiddenFiles: true,
        )

        await store.send(.internal(.applyPreferences(preferences))) {
            $0.listIconSize = 16
            $0.listTextSize = 12
            $0.gridIconSize = 64
            $0.gridTextSize = 12
            $0.showHiddenFiles = true
        }
    }

    // MARK: - EVM-002-customize_list_view_column

    /// EVM-002-customize_list_view_column: 컬럼 목록 설정이 상태에 반영되는지 검증
    ///
    /// - 검증 내용: setListVisibleColumns 액션이 normalizeVisibleColumns를 통해 상태 업데이트
    /// - 사전 조건: 초기 상태 (기본 컬럼)
    /// - 기대 결과: 새 컬럼 목록이 normalize되어 상태에 반영됨
    func testSetListVisibleColumnsUpdatesState() async {
        let store = TestStore(initialState: EntryViewLayoutState()) {
            EntryViewLayoutFeature()
        }

        let newColumns: [EntryListColumn] = [.name, .size, .dateModified, .kind, .application]

        await store.send(.internal(.setListVisibleColumns(newColumns))) {
            $0.listVisibleColumns = EntryListColumn.normalizeVisibleColumns(newColumns)
        }
    }

    /// EVM-002-customize_list_view_column: 빈 컬럼 목록 설정 시 기본값으로 폴백되는지 검증
    ///
    /// - 검증 내용: 빈 배열을 전달하면 defaultVisibleColumns로 복원
    /// - 사전 조건: listVisibleColumns가 기본값과 다른 상태
    /// - 기대 결과: defaultVisibleColumns로 복원됨
    func testNormalizeEmptyColumnsFallsBackToDefaults() async {
        var state = EntryViewLayoutState()
        state.listVisibleColumns = [.name, .size, .kind]

        let store = TestStore(initialState: state) {
            EntryViewLayoutFeature()
        }

        await store.send(.internal(.setListVisibleColumns([]))) {
            $0.listVisibleColumns = EntryListColumn.defaultVisibleColumns
        }
    }

    /// EVM-002-customize_list_view_column: name 컬럼이 필수여서 제거 불가능한지 검증
    ///
    /// - 검증 내용: name 컬럼을 숨기려 해도 상태 변경이 발생하지 않음
    /// - 사전 조건: 초기 상태
    /// - 기대 결과: 상태 변화 없음 (name은 requiredColumns에 포함)
    func testNameColumnIsRequired() async {
        let store = TestStore(initialState: EntryViewLayoutState()) {
            EntryViewLayoutFeature()
        }

        // name 컬럼 숨기기 시도 → requiredColumns 에 포함되어 무시됨
        await store.send(.internal(.setListColumnVisibility(column: .name, isVisible: false)))

        // 상태 변경 없음 — name 은 필수 컬럼이므로 제거되지 않음
    }

    /// EVM-002-customize_list_view_column: 비표시 컬럼을 추가할 수 있는지 검증
    ///
    /// - 검증 내용: application 컬럼을 추가하면 normalizeVisibleColumns에 포함됨
    /// - 사전 조건: 초기 상태 (application 컬럼 미표시)
    /// - 기대 결과: application 컬럼이 추가된 normalized 목록이 상태에 반영됨
    func testSetListColumnVisibilityAddsColumn() async {
        let store = TestStore(initialState: EntryViewLayoutState()) {
            EntryViewLayoutFeature()
        }

        // application 컬럼 추가 (기본 visible 에는 포함되지 않음)
        await store.send(.internal(.setListColumnVisibility(column: .application, isVisible: true))) {
            $0.listVisibleColumns = EntryListColumn.normalizeVisibleColumns(
                EntryListColumn.defaultVisibleColumns + [.application],
            )
        }
    }

    /// EVM-002-customize_list_view_column: 필수가 아닌 컬럼을 제거할 수 있는지 검증
    ///
    /// - 검증 내용: kind 컬럼을 숨기면 visible 목록에서 제거됨
    /// - 사전 조건: 초기 상태 (kind 컬럼 표시 중)
    /// - 기대 결과: kind가 제외된 normalized 목록이 상태에 반영됨
    func testSetListColumnVisibilityRemovesNonRequiredColumn() async {
        let store = TestStore(initialState: EntryViewLayoutState()) {
            EntryViewLayoutFeature()
        }

        // kind 컬럼 제거 (필수가 아님)
        let withoutKind = EntryListColumn.defaultVisibleColumns.filter { $0 != .kind }
        await store.send(.internal(.setListColumnVisibility(column: .kind, isVisible: false))) {
            $0.listVisibleColumns = EntryListColumn.normalizeVisibleColumns(withoutKind)
        }
    }

    /// EVM-002-customize_list_view_column: 컬럼 리셋이 기본값으로 복원하는지 검증
    ///
    /// - 검증 내용: resetListVisibleColumns 액션이 기본 컬럼으로 복원
    /// - 사전 조건: listVisibleColumns가 기본값과 다른 상태
    /// - 기대 결과: defaultVisibleColumns로 복원됨
    func testResetListVisibleColumns() async {
        var state = EntryViewLayoutState()
        state.listVisibleColumns = [.name, .size]

        let store = TestStore(initialState: state) {
            EntryViewLayoutFeature()
        }

        await store.send(.internal(.resetListVisibleColumns)) {
            $0.listVisibleColumns = EntryListColumn.defaultVisibleColumns
        }
    }

    // MARK: - EVM-002-update_entry_selection

    /// EVM-002-update_entry_selection: 전체 선택 액션이 모든 ID를 selectedIds에 설정하는지 검증
    ///
    /// - 검증 내용: applySelectAll 액션이 orderedItemIds를 selectedIds에 설정
    /// - 사전 조건: 초기 상태 (빈 selectedIds)
    /// - 기대 결과: 모든 ID가 selectedIds에 포함되고 lastSelectedId, rangeAnchorId가 마지막 ID로 설정됨
    func testApplySelectAllSetsAllIds() async {
        let orderedIds: [String] = ["a", "b", "c"]

        let store = TestStore(initialState: EntryViewLayoutState()) {
            EntryViewLayoutFeature()
        }

        await store.send(.internal(.applySelectAll(orderedItemIds: orderedIds))) {
            $0.selectedIds = Set(orderedIds)
            $0.lastSelectedId = "c"
            $0.rangeAnchorId = "c"
            $0.shouldScrollToSelection = false
        }
    }

    /// EVM-002-update_entry_selection: 선택 해제 액션이 IDs를 초기화하는지 검증
    ///
    /// - 검증 내용: applyClearSelection 액션이 selectedIds, lastSelectedId, rangeAnchorId를 초기화
    /// - 사전 조건: selectedIds에 값이 있고 lastSelectedId, rangeAnchorId가 설정된 상태
    /// - 기대 결과: 모든 선택 관련 필드가 초기값으로 복원됨
    func testClearSelectionResetsIds() async {
        var state = EntryViewLayoutState()
        state.selectedIds = ["id-1", "id-2"]
        state.lastSelectedId = "id-2"
        state.rangeAnchorId = "id-1"

        let store = TestStore(initialState: state) {
            EntryViewLayoutFeature()
        }

        await store.send(.internal(.applyClearSelection)) {
            $0.selectedIds = []
            $0.lastSelectedId = nil
            $0.rangeAnchorId = nil
            $0.shouldScrollToSelection = false
        }
    }

    /// EVM-002-update_entry_selection: setSelectionState 액션이 IDs를 업데이트하는지 검증
    ///
    /// - 검증 내용: setSelectionState 액션이 selectedIds, lastSelectedId, rangeAnchorId, shouldScrollToSelection을 설정
    /// - 사전 조건: 초기 상태
    /// - 기대 결과: 전달한 값들이 상태에 반영됨
    func testSetSelectionUpdatesSelectedIds() async {
        let store = TestStore(initialState: EntryViewLayoutState()) {
            EntryViewLayoutFeature()
        }

        let ids: Set<String> = ["id-1", "id-2", "id-3"]

        await store.send(.internal(.setSelectionState(
            ids: ids,
            lastSelectedId: "id-3",
            rangeAnchorId: "id-1",
            shouldScrollToSelection: true,
        ))) {
            $0.selectedIds = ids
            $0.lastSelectedId = "id-3"
            $0.rangeAnchorId = "id-1"
            $0.shouldScrollToSelection = true
        }
    }

    /// EVM-002-update_entry_selection: 선택 변경 시 renamingItem이 선택에 없으면 rename이 취소되는지 검증
    ///
    /// - 검증 내용: setSelectionState에서 renamingItemId가 새 선택에 포함되지 않으면 cancelRename 수신
    /// - 사전 조건: renamingItemId가 설정되어 있고 새 선택에 해당 ID가 없음
    /// - 기대 결과: cancelRename 액션이 수신되고 renamingItemId가 nil로 초기화됨
    func testSetSelectionCancelsRenameWhenRenamingItemNotInSelection() async {
        let renamingId = "renaming-item"
        var state = EntryViewLayoutState()
        state.entryOperations.renamingItemId = renamingId

        let store = TestStore(initialState: state) {
            EntryViewLayoutFeature()
        }

        let newSelection: Set<String> = ["other-item"]

        await store.send(.internal(.setSelectionState(
            ids: newSelection,
            lastSelectedId: "other-item",
            rangeAnchorId: nil,
            shouldScrollToSelection: false,
        ))) {
            $0.selectedIds = newSelection
            $0.lastSelectedId = "other-item"
            $0.rangeAnchorId = nil
            $0.shouldScrollToSelection = false
        }

        await store.receive(\.entryOperations.edit.cancelRename) {
            $0.entryOperations.renamingItemId = nil
        }
    }

    /// EVM-002-update_entry_selection: 선택 변경 시 renamingItem이 선택에 포함되면 rename이 유지되는지 검증
    ///
    /// - 검증 내용: setSelectionState에서 renamingItemId가 새 선택에 포함되면 cancelRename 수신 없음
    /// - 사전 조건: renamingItemId가 설정되어 있고 새 선택에 해당 ID가 포함됨
    /// - 기대 결과: 추가 수신 액션 없이 선택 상태만 업데이트됨
    func testSetSelectionKeepsRenameWhenRenamingItemIsSelected() async {
        let renamingId = "renaming-item"
        var state = EntryViewLayoutState()
        state.entryOperations.renamingItemId = renamingId

        let store = TestStore(initialState: state) {
            EntryViewLayoutFeature()
        }

        let selection: Set<String> = [renamingId]

        await store.send(.internal(.setSelectionState(
            ids: selection,
            lastSelectedId: renamingId,
            rangeAnchorId: nil,
            shouldScrollToSelection: false,
        ))) {
            $0.selectedIds = selection
            $0.lastSelectedId = renamingId
            $0.rangeAnchorId = nil
            $0.shouldScrollToSelection = false
        }
    }

    // MARK: - EVM-002-view_entry_counts_in_current_page

    /// EVM-002-view_entry_counts_in_current_page: 선택 수가 상태에 정확히 반영되는지 검증
    ///
    /// - 검증 내용: selectedIds.count가 실제 선택 수와 일치하며 setSelectionState 후에도 정확
    /// - 사전 조건: selectedIds에 2개 ID가 설정된 상태
    /// - 기대 결과: 초기 2개, setSelectionState 후 4개로 카운트 업데이트됨
    func testSelectionCountReflectsState() async {
        var state = EntryViewLayoutState()
        state.selectedIds = ["id-a", "id-b"]

        let store = TestStore(initialState: state) {
            EntryViewLayoutFeature()
        }

        XCTAssertEqual(store.state.selectedIds.count, 2)

        let newIds: Set<String> = ["id-a", "id-b", "id-c", "id-d"]

        await store.send(.internal(.setSelectionState(
            ids: newIds,
            lastSelectedId: "id-d",
            rangeAnchorId: "id-a",
            shouldScrollToSelection: false,
        ))) {
            $0.selectedIds = newIds
            $0.lastSelectedId = "id-d"
            $0.rangeAnchorId = "id-a"
            $0.shouldScrollToSelection = false
        }

        XCTAssertEqual(store.state.selectedIds.count, 4)
    }
}
