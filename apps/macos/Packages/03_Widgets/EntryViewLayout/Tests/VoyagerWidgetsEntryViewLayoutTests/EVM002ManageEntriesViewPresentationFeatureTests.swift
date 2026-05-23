import ComposableArchitecture
@testable import VoyagerWidgetsEntryViewLayout
import XCTest

@MainActor
final class EVM002ManageEntriesViewPresentationTests: XCTestCase {
    // MARK: - EVM-002-show_hide_hidden_entry

    func testToggleShowHiddenFilesFlipsState() async {
        let store = TestStore(initialState: EntryViewLayoutState()) {
            EntryViewLayoutFeature()
        }

        XCTAssertFalse(store.state.showHiddenFiles)

        await store.send(.view(.toggleShowHiddenFiles)) {
            $0.showHiddenFiles = true
        }
    }

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

    func testSetListVisibleColumnsUpdatesState() async {
        let store = TestStore(initialState: EntryViewLayoutState()) {
            EntryViewLayoutFeature()
        }

        let newColumns: [EntryListColumn] = [.name, .size, .dateModified, .kind, .application]

        await store.send(.internal(.setListVisibleColumns(newColumns))) {
            $0.listVisibleColumns = EntryListColumn.normalizeVisibleColumns(newColumns)
        }
    }

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

    func testNameColumnIsRequired() async {
        let store = TestStore(initialState: EntryViewLayoutState()) {
            EntryViewLayoutFeature()
        }

        // name 컬럼 숨기기 시도 → requiredColumns 에 포함되어 무시됨
        await store.send(.internal(.setListColumnVisibility(column: .name, isVisible: false)))

        // 상태 변경 없음 — name 은 필수 컬럼이므로 제거되지 않음
    }

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

    // MARK: - EVM-002-view_entry_counts_in_current_page

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

    // MARK: - EVM-002-show_selected_entry_counts

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

    // MARK: - EVM-002-update_entry_selection

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
}
