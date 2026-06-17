import AppKit
import ComposableArchitecture
import VoyagerEntitiesEntry
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
        await store.receive(\.delegate.selectionChanged)
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
        await store.receive(\.delegate.selectionChanged)
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

        let ids: Set = ["id-1", "id-2", "id-3"]

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
        await store.receive(\.delegate.selectionChanged)
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

        let newSelection: Set = ["other-item"]

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
        await store.receive(\.delegate.selectionChanged)
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
        await store.receive(\.delegate.selectionChanged)
    }

    // MARK: - EVM-002-show_selected_entry_counts

    /// EVM-002-show_selected_entry_counts: 새 항목 목록이 비면 이전 folder selection을 제거하는지 검증
    ///
    /// - 검증 내용: itemsLoaded([]) 후 selectedIds와 selection anchor가 새 entries 기준으로 정리됨
    /// - 사전 조건: 이전 folder에서 더블클릭으로 선택된 ID가 남아 있는 상태
    /// - 기대 결과: 빈 folder에서는 선택 수가 0이 되도록 selection 상태가 초기화됨
    func testItemsLoadedEmptyEntriesClearsStaleSelection() {
        var state = EntryViewLayoutState()
        state.selectedIds = ["/previous/selected"]
        state.lastSelectedId = "/previous/selected"
        state.rangeAnchorId = "/previous/selected"
        state.shouldScrollToSelection = true
        state.entryOperations.loadingContext.items = []

        _ = EntryViewLayoutFeature.updateEntriesAndReapply(&state)

        XCTAssertEqual(state.entries, [])
        XCTAssertEqual(state.selectedIds, [])
        XCTAssertNil(state.lastSelectedId)
        XCTAssertNil(state.rangeAnchorId)
        XCTAssertFalse(state.shouldScrollToSelection)
    }

    /// EVM-002-show_selected_entry_counts: 새 항목 목록에 남아 있는 selection만 유지하는지 검증
    ///
    /// - 검증 내용: itemsLoaded 후 selectedIds가 새 entries ID와 교집합으로 정리됨
    /// - 사전 조건: 유지 가능한 ID와 이전 folder stale ID가 함께 선택된 상태
    /// - 기대 결과: 유지 가능한 선택만 남고 stale anchor는 남은 선택으로 보정됨
    func testItemsLoadedEntriesPreservesOnlyVisibleSelection() {
        let keptEntry = EntryModel.temporaryFolder(id: "/next/kept", name: "kept")
        let otherEntry = EntryModel.temporaryFolder(id: "/next/other", name: "other")
        var state = EntryViewLayoutState()
        state.selectedIds = [keptEntry.id, "/previous/stale"]
        state.lastSelectedId = "/previous/stale"
        state.rangeAnchorId = "/previous/stale"
        state.shouldScrollToSelection = true
        state.entryOperations.loadingContext.items = [keptEntry, otherEntry]

        _ = EntryViewLayoutFeature.updateEntriesAndReapply(&state)

        XCTAssertEqual(state.entries, [keptEntry, otherEntry])
        XCTAssertEqual(state.selectedIds, [keptEntry.id])
        XCTAssertEqual(state.lastSelectedId, keptEntry.id)
        XCTAssertEqual(state.rangeAnchorId, keptEntry.id)
        XCTAssertFalse(state.shouldScrollToSelection)
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

        let newIds: Set = ["id-a", "id-b", "id-c", "id-d"]

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
        await store.receive(\.delegate.selectionChanged)

        XCTAssertEqual(store.state.selectedIds.count, 4)
    }

    // MARK: - EVM-002-customize_list_view_column

    /// EVM-002-customize_list_view_column: 헤더 메뉴가 컬럼 모델을 그대로 렌더링하는지 검증
    ///
    /// - 검증 내용: 메뉴 항목의 제목, 체크 상태, 활성화 상태가 `EntryViewLayoutColumnsMenuModel`과 일치
    /// - 사전 조건: name과 size 컬럼만 표시되는 리스트 헤더 상태
    /// - 기대 결과: 토글 항목 뒤에 구분선과 reset 항목이 같은 순서로 노출됨
    func testHeaderMenuMatchesModelToggleItemsAndResetItem() {
        let model = EntryViewLayoutColumnsMenuModel(visibleColumns: [.name, .size])
        let headerView = EntryListHeaderView()
        let menu = headerView.makeMenu(model: model)

        XCTAssertEqual(menu.items.count, model.toggleItems.count + 2)
        XCTAssertTrue(menu.items[model.toggleItems.count].isSeparatorItem)

        for (index, toggle) in model.toggleItems.enumerated() {
            let menuItem = menu.items[index]
            XCTAssertEqual(menuItem.title, toggle.title)
            XCTAssertEqual(
                menuItem.state,
                toggle.isChecked ? NSControl.StateValue.on : NSControl.StateValue.off,
            )
            XCTAssertEqual(menuItem.isEnabled, toggle.isEnabled)
        }

        let resetItem = menu.items[model.toggleItems.count + 1]
        XCTAssertEqual(resetItem.title, model.resetItem.title)
        XCTAssertEqual(resetItem.isEnabled, model.resetItem.isEnabled)
    }

    /// EVM-002-customize_list_view_column: 필수 name 컬럼 메뉴 항목이 숨김 불가 상태인지 검증
    ///
    /// - 검증 내용: name 컬럼이 표시 목록에 없어도 메뉴에서는 checked + disabled로 렌더링
    /// - 사전 조건: dateModified만 visibleColumns로 전달된 헤더 메뉴
    /// - 기대 결과: name 항목은 체크되어 있고 비활성화됨
    func testRequiredNameColumnMenuItemIsDisabledAndChecked() {
        let model = EntryViewLayoutColumnsMenuModel(visibleColumns: [.dateModified])
        let headerView = EntryListHeaderView()
        let menu = headerView.makeMenu(model: model)

        let nameItem = menu.items.first { $0.title == EntryListColumn.name.title }
        XCTAssertNotNil(nameItem)
        guard let nameItem else { return }
        XCTAssertEqual(nameItem.state, NSControl.StateValue.on)
        XCTAssertFalse(nameItem.isEnabled)
    }

    /// EVM-002-customize_list_view_column: 헤더 메뉴 토글 클릭이 컬럼 가시성 액션으로 이어지는지 검증
    ///
    /// - 검증 내용: 비표시 kind 컬럼 메뉴 클릭 시 `setListColumnVisibility` 액션이 발행
    /// - 사전 조건: name 컬럼만 표시되는 헤더 메뉴와 action recorder
    /// - 기대 결과: kind 컬럼을 표시하는 내부 액션이 1회 전달됨
    func testHeaderMenuToggleClickSendsSetListColumnVisibility() {
        let model = EntryViewLayoutColumnsMenuModel(visibleColumns: [.name])
        let headerView = EntryListHeaderView()
        var sentActions: [EntryViewLayoutAction] = []
        headerView.send = { sentActions.append($0) }

        let menu = headerView.makeMenu(model: model)
        guard let kindItem = menu.items.first(where: { $0.title == EntryListColumn.kind.title }) else {
            XCTFail("Expected Kind menu item")
            return
        }
        XCTAssertEqual(kindItem.state, NSControl.StateValue.off)
        XCTAssertTrue(kindItem.isEnabled)

        guard let target = kindItem.target as AnyObject? else {
            XCTFail("Expected Kind item target")
            return
        }
        guard let action = kindItem.action else {
            XCTFail("Expected Kind item action")
            return
        }
        _ = target.perform(action, with: kindItem)

        XCTAssertEqual(sentActions.count, 1)
        guard let first = sentActions.first else { return }
        guard case let .internal(.setListColumnVisibility(column, isVisible)) = first else {
            XCTFail("Expected setListColumnVisibility")
            return
        }
        XCTAssertEqual(column, .kind)
        XCTAssertTrue(isVisible)
    }

    /// EVM-002-customize_list_view_column: 필수 name 컬럼은 강제 호출되어도 숨김 액션을 내지 않는지 검증
    ///
    /// - 검증 내용: disabled name menu item을 강제로 실행해도 `setListColumnVisibility`가 발행되지 않음
    /// - 사전 조건: name 항목이 비활성화된 헤더 메뉴와 action recorder
    /// - 기대 결과: 전송된 액션이 없음
    func testRequiredNameColumnCannotBeHiddenEvenIfHandlerIsInvoked() {
        let model = EntryViewLayoutColumnsMenuModel(visibleColumns: [.dateModified])
        let headerView = EntryListHeaderView()
        var sentActions: [EntryViewLayoutAction] = []
        headerView.send = { sentActions.append($0) }

        let menu = headerView.makeMenu(model: model)
        guard let nameItem = menu.items.first(where: { $0.title == EntryListColumn.name.title }) else {
            XCTFail("Expected Name menu item")
            return
        }
        XCTAssertEqual(nameItem.state, NSControl.StateValue.on)
        XCTAssertFalse(nameItem.isEnabled)

        nameItem.isEnabled = true
        guard let target = nameItem.target as AnyObject? else {
            XCTFail("Expected Name item target")
            return
        }
        guard let action = nameItem.action else {
            XCTFail("Expected Name item action")
            return
        }
        _ = target.perform(action, with: nameItem)
        XCTAssertTrue(sentActions.isEmpty)
    }

    /// EVM-002-customize_list_view_column: reset 메뉴 클릭이 기본 컬럼 복원 액션으로 이어지는지 검증
    ///
    /// - 검증 내용: 헤더 메뉴 reset item 실행 시 `resetListVisibleColumns` 액션 발행
    /// - 사전 조건: name 컬럼만 표시되는 헤더 메뉴와 action recorder
    /// - 기대 결과: 컬럼 초기화 내부 액션이 1회 전달됨
    func testHeaderMenuResetClickSendsResetListVisibleColumns() {
        let model = EntryViewLayoutColumnsMenuModel(visibleColumns: [.name])
        let headerView = EntryListHeaderView()
        var sentActions: [EntryViewLayoutAction] = []
        headerView.send = { sentActions.append($0) }

        let menu = headerView.makeMenu(model: model)
        guard let resetItem = menu.items.first(where: { $0.title == model.resetItem.title }) else {
            XCTFail("Expected Reset menu item")
            return
        }
        XCTAssertEqual(resetItem.title, model.resetItem.title)
        XCTAssertTrue(resetItem.isEnabled)

        guard let target = resetItem.target as AnyObject? else {
            XCTFail("Expected Reset item target")
            return
        }
        guard let action = resetItem.action else {
            XCTFail("Expected Reset item action")
            return
        }
        _ = target.perform(action, with: resetItem)

        XCTAssertEqual(sentActions.count, 1)
        guard let first = sentActions.first else { return }
        guard case .internal(.resetListVisibleColumns) = first else {
            XCTFail("Expected resetListVisibleColumns")
            return
        }
    }

    /// EVM-002-customize_list_view_column: 컬럼 메뉴 모델이 모든 컬럼 토글을 제공하는지 검증
    ///
    /// - 검증 내용: toggle item의 컬럼 집합이 `EntryListColumn.allCases`와 일치
    /// - 사전 조건: 기본 visibleColumns 기반 컬럼 메뉴 모델
    /// - 기대 결과: 사용자가 모든 컬럼의 표시 여부를 조작할 수 있음
    func testColumnsMenuModelToggleItemsCoverAllEntryListColumns() {
        let model = EntryViewLayoutColumnsMenuModel(visibleColumns: EntryListColumn.defaultVisibleColumns)

        XCTAssertEqual(model.toggleItems.count, EntryListColumn.allCases.count)
        XCTAssertEqual(Set(model.toggleItems.map(\.column)), Set(EntryListColumn.allCases))
    }

    /// EVM-002-customize_list_view_column: 컬럼 메뉴 모델에서 name 컬럼이 숨김 불가인지 검증
    ///
    /// - 검증 내용: name toggle item이 checked 상태이며 disabled로 모델링됨
    /// - 사전 조건: dateModified만 visibleColumns로 전달된 컬럼 메뉴 모델
    /// - 기대 결과: name 컬럼은 필수 컬럼으로 유지됨
    func testColumnsMenuModelRequiredNameColumnIsNotHideable() {
        let model = EntryViewLayoutColumnsMenuModel(visibleColumns: [.dateModified])

        let nameItem = model.toggleItems.first(where: { $0.column == .name })
        XCTAssertNotNil(nameItem)
        XCTAssertEqual(nameItem?.isEnabled, false)
        XCTAssertEqual(nameItem?.isChecked, true)
    }

    /// EVM-002-customize_list_view_column: 일반 컬럼 체크 상태가 visibleColumns를 반영하는지 검증
    ///
    /// - 검증 내용: 표시 컬럼과 비표시 컬럼의 checked/enabled 값이 모델에 반영
    /// - 사전 조건: name과 size만 visibleColumns로 설정
    /// - 기대 결과: size는 checked, kind는 unchecked이며 둘 다 조작 가능함
    func testColumnsMenuModelCheckedStateReflectsVisibilityForNonRequiredColumns() {
        let visibleColumns: [EntryListColumn] = [.name, .size]
        let model = EntryViewLayoutColumnsMenuModel(visibleColumns: visibleColumns)

        let sizeItem = model.toggleItems.first(where: { $0.column == .size })
        XCTAssertNotNil(sizeItem)
        XCTAssertEqual(sizeItem?.isChecked, true)
        XCTAssertEqual(sizeItem?.isEnabled, true)

        let kindItem = model.toggleItems.first(where: { $0.column == .kind })
        XCTAssertNotNil(kindItem)
        XCTAssertEqual(kindItem?.isChecked, false)
        XCTAssertEqual(kindItem?.isEnabled, true)
    }

    /// EVM-002-customize_list_view_column: 컬럼 메뉴 모델이 reset 항목을 제공하는지 검증
    ///
    /// - 검증 내용: reset item 제목이 컬럼 초기화 동작으로 노출됨
    /// - 사전 조건: 기본 visibleColumns 기반 컬럼 메뉴 모델
    /// - 기대 결과: 메뉴 하단에 `Reset Columns` 항목을 렌더링할 수 있음
    func testColumnsMenuModelResetItemExists() {
        let model = EntryViewLayoutColumnsMenuModel(visibleColumns: EntryListColumn.defaultVisibleColumns)
        XCTAssertEqual(model.resetItem.title, "Reset Columns")
    }

    // MARK: - EVM-002-set_entries_view_as_icon_grid

    /// EVM-002-set_entries_view_as_icon_grid: grid 최초 bind 시 store selection이 collection view에 반영되는지 검증
    ///
    /// - 검증 내용: `EntryGridCoordinator.bind`가 `selectedIds`를 `NSCollectionView.selectionIndexPaths`에 동기화
    /// - 사전 조건: 두 entry 중 첫 번째 entry가 선택된 grid 상태
    /// - 기대 결과: collection view의 선택 index path가 첫 번째 item으로 설정됨
    func testInitialGridBindAppliesStoreSelectionToCollectionView() {
        let selectedEntry = EntryModel.temporaryFolder(id: "/seed/selected", name: "selected")
        let otherEntry = EntryModel.temporaryFolder(id: "/seed/other", name: "other")
        var state = EntryViewLayoutState()
        state.entries = [selectedEntry, otherEntry]
        state.selectedIds = [selectedEntry.id]

        let store = Store(initialState: state) {
            EntryViewLayoutFeature()
        }
        let view = EntryGridView(frame: NSRect(x: 0, y: 0, width: 320, height: 240))
        let coordinator = EntryGridCoordinator(store: store)

        coordinator.bind(to: view)

        XCTAssertEqual(
            view.collectionView.selectionIndexPaths,
            [IndexPath(item: 0, section: 0)],
            "Grid가 처음 bind될 때 store.selectedIds를 NSCollectionView selection으로 반영해야 함",
        )
    }

    /// EVM-002-set_entries_view_as_icon_grid: 선택 이후 생성된 grid item이 선택 시각 상태를 반영하는지 검증
    ///
    /// - 검증 내용: coordinator가 item 생성 시 현재 collection selection을 `isSelected`에 반영
    /// - 사전 조건: 선택된 entry 하나가 있는 grid 상태
    /// - 기대 결과: 생성된 grid item의 `isSelected`가 true
    func testGridItemCreatedAfterSelectionReflectsSelectedAppearanceState() {
        let selectedEntry = EntryModel.temporaryFolder(id: "/seed/selected", name: "selected")
        var state = EntryViewLayoutState()
        state.entries = [selectedEntry]
        state.selectedIds = [selectedEntry.id]

        let store = Store(initialState: state) {
            EntryViewLayoutFeature()
        }
        let view = EntryGridView(frame: NSRect(x: 0, y: 0, width: 320, height: 240))
        let coordinator = EntryGridCoordinator(store: store)
        let indexPath = IndexPath(item: 0, section: 0)

        coordinator.bind(to: view)
        let item = coordinator.collectionView(
            view.collectionView,
            itemForRepresentedObjectAt: indexPath,
        )

        XCTAssertTrue(
            item.isSelected,
            "Grid item이 selection 적용 뒤 생성되어도 현재 collection selection을 시각 상태로 반영해야 함",
        )
    }

    // MARK: - EVM-002-update_entry_selection

    /// EVM-002-update_entry_selection: list row가 focus 전환에도 강조 선택 상태를 유지하는지 검증
    ///
    /// - 검증 내용: row view의 `isEmphasized`를 false로 설정해도 accent 선택 강조가 유지됨
    /// - 사전 조건: `EntryListSelectionRowView` 인스턴스
    /// - 기대 결과: `isEmphasized`가 true로 보정됨
    func testSelectionRowViewKeepsEmphasizedSelection() {
        let rowView = EntryListSelectionRowView()

        rowView.isEmphasized = false

        XCTAssertTrue(rowView.isEmphasized)
    }

    /// EVM-002-update_entry_selection: list row가 regular highlight style을 유지하는지 검증
    ///
    /// - 검증 내용: AppKit 기본 inactive gray 대신 직접 그릴 수 있는 regular style 설정을 허용
    /// - 사전 조건: `EntryListSelectionRowView` 인스턴스
    /// - 기대 결과: `selectionHighlightStyle`이 `.regular`로 유지됨
    func testSelectionRowViewUsesRegularHighlightStyle() {
        let rowView = EntryListSelectionRowView()

        rowView.selectionHighlightStyle = .regular

        XCTAssertEqual(rowView.selectionHighlightStyle, .regular)
    }
}
