import AppKit
import ComposableArchitecture
import VoyagerEntitiesEntry
import VoyagerEntitiesTag
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

    /// EVM-002-update_entry_selection: 컨텍스트 메뉴 대상이 표시 중인 유효 selection만 보존한다.
    /// stale selection이 남아 있어도 선택된 row를 우클릭하면 현재 화면의 유효한 다중 선택만 메뉴와 실행 대상으로 사용해야 한다.
    /// - 검증 내용: context menu target이 display entries와 selected IDs의 교집합을 selection 및 entries로 반환한다.
    /// - 사전 조건: 두 display entry와 하나의 stale ID가 선택되어 있고 두 번째 entry를 우클릭한다.
    /// - 기대 결과: target은 두 유효 entry와 두 유효 ID만 포함하며 stale ID는 제거된다.
    func testContextMenuTargetPrunesStaleSelectionForSelectedRow() {
        let first = EntryModel.temporaryFolder(id: "/tmp/first", name: "first")
        let second = EntryModel.temporaryFolder(id: "/tmp/second", name: "second")

        let target = EntryContextMenuTarget.resolve(
            displayEntries: [first, second],
            selectedIds: [first.id, second.id, "/stale"],
            rowEntry: second,
        )

        XCTAssertEqual(target.selectedIds, [first.id, second.id])
        XCTAssertEqual(target.entries.map(\.id), [first.id, second.id])
    }

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
        state.renamingItemId = renamingId

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

        await store.receive(\.delegate.renameCanceled)
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
        state.renamingItemId = renamingId

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
        state.entries = []

        _ = EntryViewLayoutFeature.updateEntriesAndReapply(&state)

        XCTAssertEqual(state.entries, [])
        XCTAssertEqual(state.selectedIds, [])
        XCTAssertNil(state.lastSelectedId)
        XCTAssertNil(state.rangeAnchorId)
        XCTAssertTrue(state.shouldScrollToSelection)
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
        state.entries = [keptEntry, otherEntry]

        _ = EntryViewLayoutFeature.updateEntriesAndReapply(&state)

        XCTAssertEqual(state.entries, [keptEntry, otherEntry])
        XCTAssertEqual(state.selectedIds, [keptEntry.id])
        XCTAssertEqual(state.lastSelectedId, keptEntry.id)
        XCTAssertEqual(state.rangeAnchorId, keptEntry.id)
        XCTAssertTrue(state.shouldScrollToSelection)
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
    /// - 기대 결과: kind 컬럼을 표시하는 view intent가 1회 전달됨
    func testHeaderMenuToggleClickSendsSetListColumnVisibility() {
        let model = EntryViewLayoutColumnsMenuModel(visibleColumns: [.name])
        let headerView = EntryListHeaderView()
        var sentActions: [EntryViewLayoutAction.View] = []
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
        guard case let .updateListColumnVisibility(column, isVisible) = first else {
            XCTFail("Expected updateListColumnVisibility")
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
        var sentActions: [EntryViewLayoutAction.View] = []
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
    /// - 기대 결과: 컬럼 초기화 view intent가 1회 전달됨
    func testHeaderMenuResetClickSendsResetListVisibleColumns() {
        let model = EntryViewLayoutColumnsMenuModel(visibleColumns: [.name])
        let headerView = EntryListHeaderView()
        var sentActions: [EntryViewLayoutAction.View] = []
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
        guard case .resetListVisibleColumns = first else {
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

    // MARK: - EVM-002-set_entries_view_as_icon_grid

    /// EVM-002-set_entries_view_as_icon_grid: collection item 기본값은 빈 목록으로 시작함
    /// EntryViewLayout의 collection presentation state가 기본 상태에서 일반 entries와 분리되어 있는지 검증한다.
    /// - 검증 내용: `collectionItems` 기본값 확인
    /// - 사전 조건: 기본 `EntryViewLayoutState`
    /// - 기대 결과: collection items가 비어 있음
    func testCollectionItemsDefaultEmpty() {
        let state = EntryViewLayoutState()
        XCTAssertTrue(state.collectionItems.isEmpty)
    }

    /// EVM-002-set_entries_view_as_icon_grid: collection mode 기본값은 비활성임
    /// EntryViewLayout이 일반 page presentation을 기본 표시 소스로 사용하는지 검증한다.
    /// - 검증 내용: `isCollectionMode` 기본값 확인
    /// - 사전 조건: 기본 `EntryViewLayoutState`
    /// - 기대 결과: collection mode가 false임
    func testIsCollectionModeDefaultFalse() {
        let state = EntryViewLayoutState()
        XCTAssertFalse(state.isCollectionMode)
    }

    /// EVM-002-set_entries_view_as_icon_grid: collection mode가 아니면 일반 entry operations items를 표시함
    /// collection presentation이 꺼진 상태에서 기존 entry operations 결과가 display source로 유지되는지 검증한다.
    /// - 검증 내용: 일반 items가 `displayItems`에 반영되는지 확인
    /// - 사전 조건: collection mode가 false이고 entry operations items가 존재함
    /// - 기대 결과: display items가 일반 items를 반환함
    func testDisplayItemsReturnsEntryOperationsItemsWhenNotCollectionMode() {
        var state = EntryViewLayoutState()
        let item = EntryModel.temporaryFolder(id: "/tmp/regular.txt", name: "regular.txt")
        state.entries = [item]

        XCTAssertFalse(state.isCollectionMode)
        XCTAssertEqual(state.displayItems.count, 1)
        XCTAssertEqual(state.displayItems.first?.id, item.id)
    }

    /// EVM-002-set_entries_view_as_icon_grid: collection mode에서는 collection items를 표시함
    /// collection presentation이 켜진 상태에서 일반 items 대신 collection items가 display source가 되는지 검증한다.
    /// - 검증 내용: collection mode의 `displayItems` source 확인
    /// - 사전 조건: 일반 items와 collection items가 모두 있고 collection mode가 true임
    /// - 기대 결과: display items가 collection items만 반환함
    func testDisplayItemsReturnsCollectionItemsWhenCollectionMode() {
        var state = EntryViewLayoutState()
        let regularItem = EntryModel.temporaryFolder(id: "/tmp/regular.txt", name: "regular.txt")
        let collectionItem = EntryModel.temporaryFolder(id: "/tmp/col.txt", name: "col.txt")

        state.entries = [regularItem]
        state.collectionItems = [collectionItem]
        state.isCollectionMode = true

        XCTAssertEqual(state.displayItems.count, 1)
        XCTAssertEqual(state.displayItems.first?.id, collectionItem.id)
    }

    /// EVM-002-set_entries_view_as_icon_grid: collection mode에서는 일반 items를 표시하지 않음
    /// collection presentation이 켜진 상태에서 collection item이 없으면 regular item이 누수되지 않는지 검증한다.
    /// - 검증 내용: collection mode의 empty display source 확인
    /// - 사전 조건: 일반 items만 있고 collection mode가 true임
    /// - 기대 결과: display items가 비어 있음
    func testDisplayItemsIgnoresRegularItemsInCollectionMode() {
        var state = EntryViewLayoutState()
        let regularItem = EntryModel.temporaryFolder(id: "/tmp/regular.txt", name: "regular.txt")
        state.entries = [regularItem]
        state.isCollectionMode = true

        XCTAssertTrue(state.displayItems.isEmpty)
    }

    /// EVM-002-set_entries_view_as_icon_grid: display order items는 현재 display source 배열을 반환함
    /// EntryViewLayout의 정렬 입력이 일반 display source와 동일한 순서를 쓰는지 검증한다.
    /// - 검증 내용: `displayOrderItems`가 일반 items 순서를 보존하는지 확인
    /// - 사전 조건: 일반 items가 두 개 존재하고 collection mode가 false임
    /// - 기대 결과: display order items가 일반 items 순서를 반환함
    func testDisplayOrderItemsReturnsArrayOfDisplayItems() {
        var state = EntryViewLayoutState()
        let item1 = EntryModel.temporaryFolder(id: "/tmp/a.txt", name: "a.txt")
        let item2 = EntryModel.temporaryFolder(id: "/tmp/b.txt", name: "b.txt")
        state.entries = [item1, item2]

        XCTAssertEqual(state.displayOrderItems.count, 2)
        XCTAssertEqual(state.displayOrderItems[0].id, item1.id)
        XCTAssertEqual(state.displayOrderItems[1].id, item2.id)
    }

    /// EVM-002-set_entries_view_as_icon_grid: collection mode의 display order items는 collection items 순서를 반환함
    /// collection presentation 정렬 입력이 collection item source를 기준으로 만들어지는지 검증한다.
    /// - 검증 내용: collection mode의 `displayOrderItems` source 확인
    /// - 사전 조건: collection items가 두 개 있고 collection mode가 true임
    /// - 기대 결과: display order items가 collection items 순서를 반환함
    func testDisplayOrderItemsWithCollectionMode() {
        var state = EntryViewLayoutState()
        let colItem1 = EntryModel.temporaryFolder(id: "/tmp/col1.txt", name: "col1.txt")
        let colItem2 = EntryModel.temporaryFolder(id: "/tmp/col2.txt", name: "col2.txt")
        state.collectionItems = [colItem1, colItem2]
        state.isCollectionMode = true

        XCTAssertEqual(state.displayOrderItems.count, 2)
        XCTAssertEqual(state.displayOrderItems[0].id, colItem1.id)
        XCTAssertEqual(state.displayOrderItems[1].id, colItem2.id)
    }

    /// EVM-002-set_entries_view_as_icon_grid: display order items 기본값은 빈 목록임
    /// EntryViewLayout이 항목 없는 초기 상태에서 정렬 입력을 만들지 않는지 검증한다.
    /// - 검증 내용: 기본 `displayOrderItems` 확인
    /// - 사전 조건: 기본 `EntryViewLayoutState`
    /// - 기대 결과: display order items가 비어 있음
    func testDisplayOrderItemsEmptyByDefault() {
        let state = EntryViewLayoutState()
        XCTAssertTrue(state.displayOrderItems.isEmpty)
    }

    /// EVM-002-set_entries_view_as_icon_grid: collection items를 상태에 저장할 수 있음
    /// collection presentation source가 reducer와 view state에서 유지되는지 검증한다.
    /// - 검증 내용: `collectionItems` 저장 결과 확인
    /// - 사전 조건: collection item 한 개를 상태에 설정함
    /// - 기대 결과: collection items에 동일한 id가 보존됨
    func testSettingCollectionItems() {
        var state = EntryViewLayoutState()
        let item = EntryModel.temporaryFolder(id: "/tmp/col.txt", name: "col.txt")
        state.collectionItems = [item]

        XCTAssertEqual(state.collectionItems.count, 1)
        XCTAssertEqual(state.collectionItems.first?.id, item.id)
    }

    /// EVM-002-set_entries_view_as_icon_grid: collection mode toggle은 display source를 전환함
    /// 일반 탐색과 collection presentation 간 표시 source가 mode에 맞게 전환되는지 검증한다.
    /// - 검증 내용: toggle 전후 `displayItems` source 확인
    /// - 사전 조건: 일반 item과 collection item이 모두 존재함
    /// - 기대 결과: mode false에서는 일반 item, true에서는 collection item, 다시 false에서는 일반 item을 반환함
    func testTogglingCollectionModeSwitchesDisplaySource() {
        var state = EntryViewLayoutState()
        let regularItem = EntryModel.temporaryFolder(id: "/tmp/regular.txt", name: "regular.txt")
        let collectionItem = EntryModel.temporaryFolder(id: "/tmp/col.txt", name: "col.txt")

        state.entries = [regularItem]
        state.collectionItems = [collectionItem]

        XCTAssertEqual(state.displayItems.first?.id, regularItem.id)

        state.isCollectionMode = true
        XCTAssertEqual(state.displayItems.first?.id, collectionItem.id)

        state.isCollectionMode = false
        XCTAssertEqual(state.displayItems.first?.id, regularItem.id)
    }

    /// EVM-002-set_entries_view_as_icon_grid: collection mode 전환은 현재 source를 재적용함
    /// reducer가 collection presentation mode 변경 후 arrangement reapply sequence를 실행하는지 검증한다.
    /// - 검증 내용: 일반 items load 후 collection mode 전환과 collection items 설정 sequence 확인
    /// - 사전 조건: 일반 item과 collection item이 순차적으로 주어짐
    /// - 기대 결과: mode에 맞는 apply/reapply delegate sequence와 entries가 반영됨
    func testSetCollectionModeUpdatesStateAndReapplies() async {
        let store = makeCollectionPresentationTestStore()

        let regularItem = EntryModel.temporaryFolder(id: "/tmp/regular.txt", name: "regular.txt")
        let collectionItem = EntryModel.temporaryFolder(id: "/tmp/col.txt", name: "col.txt")

        await store.send(.internal(.setCollectionItems([regularItem]))) {
            $0.collectionItems = [regularItem]
            $0.outlineProjectionRevision = 1
            $0.lastVisibleSelectableEntryIDs = Set([])
        }

        await store.send(.internal(.setCollectionMode(true))) {
            $0.isCollectionMode = true
            $0.outlineProjectionRevision = 2
            $0.lastVisibleSelectableEntryIDs = Set([regularItem.id])
            $0.entries = [regularItem]
        }

        await store.send(.internal(.setCollectionItems([collectionItem]))) {
            $0.collectionItems = [collectionItem]
            $0.entries = [collectionItem]
        }
    }

    /// EVM-002-set_entries_view_as_icon_grid: collection items 갱신은 reapply sequence를 실행함
    /// collection item source 변경이 current presentation mode 기준으로 arrangement apply를 재요청하는지 검증한다.
    /// - 검증 내용: collection items 설정 후 reapply sequence 확인
    /// - 사전 조건: collection mode가 false인 상태에서 collection items를 설정함
    /// - 기대 결과: 일반 mode 기준 empty source가 reapply됨
    func testSetCollectionItemsUpdatesStateAndReapplies() async {
        let store = makeCollectionPresentationTestStore()

        let item1 = EntryModel.temporaryFolder(id: "/tmp/a.txt", name: "a.txt")
        let item2 = EntryModel.temporaryFolder(id: "/tmp/b.txt", name: "b.txt")

        await store.send(.internal(.setCollectionItems([item1, item2]))) {
            $0.collectionItems = [item1, item2]
            $0.entries = []
        }
    }

    /// EVM-002-set_entries_view_as_icon_grid: 기본 collection materialization은 metadata probe를 요청하지 않는다.
    /// 이름 정렬과 grouping 없음인 기본 화면은 staged core loading만 수행해야 한다.
    /// - 검증 내용: collection metadata priority의 probe 목록
    /// - 사전 조건: name sort와 group none인 기본 EntryViewLayout state
    /// - 기대 결과: priority는 `.none`이고 probe 목록이 비어 있음
    func testDefaultCollectionMetadataPrioritySkipsProbes() {
        let state = EntryViewLayoutState()

        XCTAssertEqual(EntryViewLayoutFeature.collectionMetadataPriority(for: state), .none)
    }

    /// EVM-002-set_entries_view_as_icon_grid: collection mode 중 collection items 갱신은 entries를 collection source로 맞춤
    /// collection mode가 켜진 상태의 collection items 설정이 entries와 arrangement source를 동기화하는지 검증한다.
    /// - 검증 내용: collection mode 상태의 items 설정과 reapply sequence 확인
    /// - 사전 조건: collection mode를 먼저 켠 뒤 collection item을 설정함
    /// - 기대 결과: collection item이 entries와 arrangement apply source로 반영됨
    func testSetCollectionItemsWithCollectionModeOn() async {
        let store = makeCollectionPresentationTestStore()

        let item = EntryModel.temporaryFolder(id: "/tmp/col.txt", name: "col.txt")

        await store.send(.internal(.setCollectionMode(true))) {
            $0.isCollectionMode = true
            $0.entries = []
        }

        await store.send(.internal(.setCollectionItems([item]))) {
            $0.collectionItems = [item]
            $0.entries = [item]
        }
    }

    /// EVM-002-set_entries_view_as_icon_grid: collection presentation clear는 일반 source로 복귀함
    /// collection mode에서 빠져나올 때 collection items를 비우고 일반 items를 다시 표시하는지 검증한다.
    /// - 검증 내용: clearCollectionPresentation 후 mode, collectionItems, entries, reapply sequence 확인
    /// - 사전 조건: 일반 item load 후 collection mode와 collection item이 설정됨
    /// - 기대 결과: 일반 mode로 복귀하고 entries가 일반 item source로 복원됨
    func testClearCollectionPresentationFallsBackToRegularSource() async {
        let store = makeCollectionPresentationTestStore()

        let regularItem = EntryModel.temporaryFolder(id: "/tmp/regular.txt", name: "regular.txt")
        let collectionItem = EntryModel.temporaryFolder(id: "/tmp/col.txt", name: "col.txt")

        await store.send(.internal(.setCollectionItems([regularItem]))) {
            $0.collectionItems = [regularItem]
            $0.outlineProjectionRevision = 1
            $0.lastVisibleSelectableEntryIDs = Set([])
        }

        await store.send(.internal(.setCollectionMode(true))) {
            $0.isCollectionMode = true
            $0.outlineProjectionRevision = 2
            $0.lastVisibleSelectableEntryIDs = Set([regularItem.id])
            $0.entries = [regularItem]
        }

        await store.send(.internal(.setCollectionItems([collectionItem]))) {
            $0.collectionItems = [collectionItem]
            $0.entries = [collectionItem]
        }

        await store.send(.internal(.clearCollectionPresentation)) {
            $0.isCollectionMode = false
            $0.collectionItems = []
            $0.collectionReplaceEpoch = 1
            $0.entries = [collectionItem]
        }
    }

    /// EVM-002-set_entries_view_as_icon_grid: reapply는 현재 display order snapshot을 사용함
    /// collection presentation reapply가 현재 표시 source를 arrangement input으로 전달하는지 검증한다.
    /// - 검증 내용: collection mode/items 설정 후 entries와 mode 확인
    /// - 사전 조건: collection mode를 켜고 collection item을 설정함
    /// - 기대 결과: entries가 collection item source로 유지됨
    func testReapplyUsesDisplayOrderItemsSnapshot() async {
        let store = makeCollectionPresentationTestStore()

        let item = EntryModel.temporaryFolder(id: "/tmp/a.txt", name: "a.txt")

        await store.send(.internal(.setCollectionMode(true))) {
            $0.isCollectionMode = true
            $0.entries = []
        }

        await store.send(.internal(.setCollectionItems([item]))) {
            $0.collectionItems = [item]
            $0.entries = [item]
        }

        let state = store.state
        XCTAssertTrue(state.isCollectionMode)
        XCTAssertEqual(state.entries.map(\.id), [item.id])
    }

    /// EVM-002-set_entries_view_as_icon_grid: regular itemsLoaded도 동일한 reapply helper path를 사용함
    /// collection presentation reducer가 일반 entry operations load와 collection presentation load를 동일한 arrangement 경로로
    /// 처리하는지 검증한다.
    /// - 검증 내용: itemsLoaded 후 entries와 reapply sequence 확인
    /// - 사전 조건: 일반 item load action 수신
    /// - 기대 결과: 일반 mode 기준 entries와 arrangement apply가 반영됨
    func testEntryOperationsItemsLoadedReusesSameHelperPath() async {
        let store = makeCollectionPresentationTestStore()

        let item = EntryModel.temporaryFolder(id: "/tmp/test.txt", name: "test.txt")

        await store.send(.internal(.setCollectionItems([item]))) {
            $0.collectionItems = [item]
            $0.outlineProjectionRevision = 1
            $0.lastVisibleSelectableEntryIDs = Set([])
        }

        let state = store.state
        XCTAssertFalse(state.isCollectionMode)
        XCTAssertEqual(state.entries.map(\.id), [])
    }

    /// EVM-002-progressive_entry_loading: 같은 window의 collection stream은 tab owner별 cancellation ID를 사용한다.
    /// - 사전 조건: 같은 windowID와 서로 다른 loadingCancellationOwnerID를 가진 두 layout state
    /// - 기대 결과: replace와 append cancellation ID가 모두 서로 다름
    func testCollectionCancellationIDsAreScopedByLoadingOwner() throws {
        let windowID = try XCTUnwrap(UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA"))
        var firstState = EntryViewLayoutState()
        firstState.collectionWindowID = windowID
        firstState.collectionLoadingCancellationOwnerID = try XCTUnwrap(
            UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB"),
        )
        var secondState = EntryViewLayoutState()
        secondState.collectionWindowID = windowID
        secondState.collectionLoadingCancellationOwnerID = try XCTUnwrap(
            UUID(uuidString: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC"),
        )

        XCTAssertNotEqual(
            EntryViewLayoutFeature.collectionCancelID(for: .replace, state: firstState),
            EntryViewLayoutFeature.collectionCancelID(for: .replace, state: secondState),
        )
        XCTAssertNotEqual(
            EntryViewLayoutFeature.collectionCancelID(for: .append(1), state: firstState),
            EntryViewLayoutFeature.collectionCancelID(for: .append(1), state: secondState),
        )
    }

    /// EVM-002-set_entries_view_as_icon_grid: collection paths 제거는 items와 selection을 함께 정리함
    /// collection presentation에서 제거된 path가 display source와 selection state에서 빠지는지 검증한다.
    /// - 검증 내용: removeCollectionPaths 후 collectionItems, selectedIds, anchors, entries 확인
    /// - 사전 조건: collection mode에서 두 collection item과 selection state가 설정됨
    /// - 기대 결과: 제거 대상 item은 빠지고 남은 item 기준 selection과 entries가 유지됨
    func testRemoveCollectionPathsPrunesItemsAndSelection() async {
        let store = makeCollectionPresentationTestStore()

        let removedItem = EntryModel.temporaryFolder(id: "/tmp/a.txt", name: "a.txt")
        let keptItem = EntryModel.temporaryFolder(id: "/tmp/b.txt", name: "b.txt")

        await store.send(.internal(.setCollectionMode(true))) {
            $0.isCollectionMode = true
            $0.entries = []
        }

        await store.send(.internal(.setCollectionItems([removedItem, keptItem]))) {
            $0.collectionItems = [removedItem, keptItem]
            $0.entries = [removedItem, keptItem]
        }

        await store.send(.internal(.setSelectionState(
            ids: [removedItem.id, keptItem.id],
            lastSelectedId: removedItem.id,
            rangeAnchorId: removedItem.id,
            shouldScrollToSelection: true,
        ))) {
            $0.selectedIds = [removedItem.id, keptItem.id]
            $0.lastSelectedId = removedItem.id
            $0.rangeAnchorId = removedItem.id
            $0.shouldScrollToSelection = true
        }
        await store.receive(\.delegate.selectionChanged)

        await store.send(.internal(.removeCollectionPaths(["/tmp/a.txt"]))) {
            $0.collectionItems = [keptItem]
            $0.selectedIds = [keptItem.id]
            $0.lastSelectedId = keptItem.id
            $0.rangeAnchorId = keptItem.id
            $0.shouldScrollToSelection = true
            $0.entries = [keptItem]
        }
    }

    /// EVM-002-set_entries_view_as_icon_grid: collection replacement는 첫 core batch 또는 empty finish 전까지 차단 상태를 유지한다.
    /// - 검증 내용: search path replacement 시작이 동기 변환 완료가 아닌 staged stream 시작을 나타내는 loading state를 남긴다.
    /// - 사전 조건: collection mode가 활성화되어 있고 materialization할 path가 하나 있다.
    /// - 기대 결과: 첫 core event 전에는 isCollectionContentLoading이 true다.
    func testCollectionReplacementRemainsBlockingUntilFirstCoreEvent() {
        var state = EntryViewLayoutState()
        state.isCollectionMode = true

        _ = EntryViewLayoutFeature().reduce(into: &state, action: .internal(.applyCollectionSearchPaths(
            paths: ["/tmp/collection-entry.txt"],
            showHidden: false,
            priority: .none,
        )))

        XCTAssertTrue(state.isCollectionContentLoading)
        XCTAssertEqual(state.collectionReplaceEpoch, 1)
        XCTAssertEqual(state.expectedCollectionReplaceBatchIndex, 0)
        XCTAssertFalse(state.collectionCoreFinished)
        XCTAssertFalse(state.collectionStreamCompleted)
    }

    /// EVM-002-set_entries_view_as_icon_grid: replacement core batch는 순서대로 누적되고 empty finish가 차단을 해제한다.
    /// - 검증 내용: 첫 batch 이후 partial rows를 유지하며 malformed/post-finish event를 무시한다.
    /// - 사전 조건: 현재 collection epoch의 loading replacement stream이 시작됐다.
    /// - 기대 결과: batch 0과 coreFinished(1)만 수용되고 rows는 유지된다.
    func testCollectionReplacementAcceptsOrderedBatchesAndEmptyFinish() {
        let item = EntryModel.temporaryFolder(id: "/tmp/replace.txt", name: "replace.txt")
        var state = EntryViewLayoutState()
        state.isCollectionMode = true
        state.collectionReplaceEpoch = 2
        state.isCollectionContentLoading = true

        let reducer = EntryViewLayoutFeature()
        _ = reducer.reduce(into: &state, action: .internal(.collectionReplaceEvent(
            epoch: 2,
            event: .coreBatch(items: [item], batchIndex: 0),
        )))
        XCTAssertEqual(state.collectionItems.map(\.id), [item.id])
        XCTAssertEqual(state.expectedCollectionReplaceBatchIndex, 1)
        XCTAssertFalse(state.isCollectionContentLoading)

        _ = reducer.reduce(into: &state, action: .internal(.collectionReplaceEvent(
            epoch: 1,
            event: .coreBatch(items: [EntryModel.temporaryFolder(id: "/tmp/stale", name: "stale")], batchIndex: 1),
        )))
        XCTAssertEqual(state.collectionItems.map(\.id), [item.id])

        _ = reducer.reduce(into: &state, action: .internal(.collectionReplaceEvent(
            epoch: 2,
            event: .coreBatch(items: [item], batchIndex: 0),
        )))
        XCTAssertEqual(state.collectionItems.map(\.id), [item.id])

        _ = reducer.reduce(into: &state, action: .internal(.collectionReplaceEvent(
            epoch: 2,
            event: .coreFinished(batchCount: 1),
        )))
        XCTAssertTrue(state.collectionCoreFinished)

        _ = reducer.reduce(into: &state, action: .internal(.collectionReplaceEvent(
            epoch: 2,
            event: .coreBatch(
                items: [EntryModel.temporaryFolder(id: "/tmp/late.txt", name: "late.txt")],
                batchIndex: 1,
            ),
        )))
        XCTAssertEqual(state.collectionItems.map(\.id), [item.id])

        var emptyState = EntryViewLayoutState()
        emptyState.isCollectionMode = true
        emptyState.collectionReplaceEpoch = 3
        emptyState.isCollectionContentLoading = true
        _ = reducer.reduce(into: &emptyState, action: .internal(.collectionReplaceEvent(
            epoch: 3,
            event: .coreFinished(batchCount: 0),
        )))
        XCTAssertFalse(emptyState.isCollectionContentLoading)
        XCTAssertTrue(emptyState.collectionCoreFinished)
        XCTAssertTrue(emptyState.collectionItems.isEmpty)
    }

    /// EVM-002-set_entries_view_as_icon_grid: concurrent append token은 current replacement epoch 안에서 독립적으로 dedupe된다.
    /// - 검증 내용: token별 ordered batch acceptance와 first-occurrence ID preservation을 확인한다.
    /// - 사전 조건: 같은 replace epoch에서 append token 두 개가 활성 상태다.
    /// - 기대 결과: 각 token의 batch 0만 수용하고 duplicate ID와 completed token의 late batch는 무시된다.
    func testCollectionAppendTokensRemainIndependentWithinReplacementEpoch() {
        let a = EntryModel.temporaryFolder(id: "/tmp/a", name: "a")
        let b = EntryModel.temporaryFolder(id: "/tmp/b", name: "b")
        var state = EntryViewLayoutState()
        state.isCollectionMode = true
        state.collectionReplaceEpoch = 4
        state.activeCollectionAppendExpectedBatchIndices = [10: 0, 20: 0]
        let reducer = EntryViewLayoutFeature()

        _ = reducer.reduce(into: &state, action: .internal(.collectionAppendEvent(
            epoch: 4,
            token: 10,
            event: .coreBatch(items: [a, a], batchIndex: 0),
        )))
        _ = reducer.reduce(into: &state, action: .internal(.collectionAppendEvent(
            epoch: 4,
            token: 20,
            event: .coreBatch(items: [a, b], batchIndex: 0),
        )))
        XCTAssertEqual(state.collectionItems.map(\.id), [a.id, b.id])
        XCTAssertEqual(state.activeCollectionAppendExpectedBatchIndices, [10: 1, 20: 1])

        _ = reducer.reduce(into: &state, action: .internal(.collectionAppendEvent(
            epoch: 4,
            token: 10,
            event: .coreFinished(batchCount: 1),
        )))
        _ = reducer.reduce(into: &state, action: .internal(.collectionAppendEvent(
            epoch: 4,
            token: 10,
            event: .coreBatch(items: [EntryModel.temporaryFolder(id: "/tmp/late", name: "late")], batchIndex: 1),
        )))
        _ = reducer.reduce(into: &state, action: .internal(.collectionAppendEvent(
            epoch: 3,
            token: 20,
            event: .coreBatch(items: [EntryModel.temporaryFolder(id: "/tmp/stale", name: "stale")], batchIndex: 1),
        )))
        XCTAssertEqual(state.collectionItems.map(\.id), [a.id, b.id])
    }

    /// EVM-002-set_entries_view_as_icon_grid: removed collection path는 active append의 late batch보다 우선한다.
    /// - 검증 내용: removal tombstone이 current token의 materialized event도 거부하는지 확인한다.
    /// - 사전 조건: collection에 target row가 있고 append token이 batch 0을 기다린다.
    /// - 기대 결과: target은 제거 후 다시 나타나지 않고 unrelated path만 추가된다.
    func testCollectionRemovalWinsOverActiveAppendEvent() {
        let removed = EntryModel.temporaryFolder(id: "/tmp/removed", name: "removed")
        let kept = EntryModel.temporaryFolder(id: "/tmp/kept", name: "kept")
        var state = EntryViewLayoutState()
        state.isCollectionMode = true
        state.collectionReplaceEpoch = 5
        state.collectionItems = [removed]
        state.activeCollectionAppendExpectedBatchIndices = [30: 0]
        let reducer = EntryViewLayoutFeature()

        _ = reducer.reduce(into: &state, action: .internal(.removeCollectionPaths([removed.fullPath])))
        _ = reducer.reduce(into: &state, action: .internal(.collectionAppendEvent(
            epoch: 5,
            token: 30,
            event: .coreBatch(items: [removed, kept], batchIndex: 0),
        )))

        XCTAssertEqual(state.collectionItems.map(\.id), [kept.id])
    }

    /// EVM-002-set_entries_view_as_icon_grid: explicit add는 같은 session의 matching removal tombstone을 해제한다.
    /// - 검증 내용: 표준화된 동등 path의 explicit add 뒤 append event가 restored item을 수용하고 unrelated tombstone은 보존한다.
    /// - 사전 조건: current collection session에서 restored path와 unrelated path가 모두 제거되어 있다.
    /// - 기대 결과: restored item만 materialize되고 unrelated late stream protection은 유지된다.
    func testExplicitCollectionAddClearsMatchingNormalizedRemovalTombstoneBeforeAppend() {
        let restored = EntryModel.temporaryFolder(id: "/tmp/collection/restored", name: "restored")
        let unrelatedPath = "/tmp/collection/unrelated"
        var state = EntryViewLayoutState()
        state.isCollectionMode = true
        let reducer = EntryViewLayoutFeature()

        _ = reducer.reduce(into: &state, action: .internal(.removeCollectionPaths([
            restored.fullPath,
            unrelatedPath,
        ])))
        _ = reducer.reduce(into: &state, action: .internal(.addCollectionPaths([
            "/tmp/collection/./restored",
        ])))
        _ = reducer.reduce(into: &state, action: .internal(.collectionAppendEvent(
            epoch: 0,
            token: 1,
            event: .coreBatch(items: [restored], batchIndex: 0),
        )))

        XCTAssertEqual(state.collectionItems.map(\.id), [restored.id])
        XCTAssertEqual(state.removedCollectionPaths, [unrelatedPath])
    }

    /// EVM-002-set_entries_view_as_icon_grid: collection clear는 epoch를 전진시켜 모든 active stream을 retire한다.
    /// - 검증 내용: clear 뒤 old epoch/token bookkeeping이 남지 않는지 확인한다.
    /// - 사전 조건: replace와 append request가 모두 in-flight다.
    /// - 기대 결과: collection mode/items/loading이 초기화되고 active token은 제거된다.
    func testClearCollectionPresentationRetiresCurrentStreamEpoch() {
        var state = EntryViewLayoutState()
        state.isCollectionMode = true
        state.collectionReplaceEpoch = 7
        state.collectionItems = [EntryModel.temporaryFolder(id: "/tmp/clear", name: "clear")]
        state.activeCollectionAppendExpectedBatchIndices = [40: 0]
        state.isCollectionContentLoading = true

        _ = EntryViewLayoutFeature().reduce(into: &state, action: .internal(.clearCollectionPresentation))

        XCTAssertEqual(state.collectionReplaceEpoch, 8)
        XCTAssertFalse(state.isCollectionMode)
        XCTAssertTrue(state.collectionItems.isEmpty)
        XCTAssertTrue(state.activeCollectionAppendExpectedBatchIndices.isEmpty)
        XCTAssertFalse(state.isCollectionContentLoading)
    }

    /// EVM-002-set_entries_view_as_icon_grid: replacement partial failure는 emitted rows를 보존하고 incomplete state를 남긴다.
    /// - 검증 내용: failure가 first core batch 이후 collection source를 비우지 않는지 확인한다.
    /// - 사전 조건: replacement stream이 row 하나를 materialize한 뒤 terminal failure를 보낸다.
    /// - 기대 결과: row는 남고 loading은 해제되며 incomplete failure가 기록된다.
    func testCollectionReplacementPartialFailureRetainsRows() {
        let item = EntryModel.temporaryFolder(id: "/tmp/partial", name: "partial")
        var state = EntryViewLayoutState()
        state.isCollectionMode = true
        state.collectionReplaceEpoch = 6
        state.collectionItems = [item]
        state.expectedCollectionReplaceBatchIndex = 1
        state.isCollectionContentLoading = false
        let reducer = EntryViewLayoutFeature()

        _ = reducer.reduce(into: &state, action: .internal(.collectionReplaceFailed(
            epoch: 6,
            message: "materialization failed",
        )))

        XCTAssertEqual(state.collectionItems.map(\.id), [item.id])
        XCTAssertFalse(state.isCollectionContentLoading)
        XCTAssertEqual(state.collectionIncompleteFailure, "materialization failed")
        XCTAssertTrue(state.collectionStreamCompleted)
    }

    /// EVM-002-set_entries_view_as_icon_grid: active deferred sort patch는 collection arrangement를 다시 적용한다.
    /// - 검증 내용: active kind sort의 spotlight patch가 updated model과 reapply action chain을 만든다.
    /// - 사전 조건: collection core가 완료됐고 kind sort가 활성화되어 있다.
    /// - 기대 결과: patched kind가 collection/entries에 반영되고 arrangement reapply가 요청된다.
    func testActiveCollectionMetadataPatchReappliesArrangement() async {
        let item = EntryModel.temporaryFolder(id: "/tmp/patch", name: "patch")
        let patched = item.applying(.spotlight(
            id: item.id,
            kind: "Patched Folder",
            creatorApplication: nil,
            lastOpenedDate: nil,
        ))
        var initialState = EntryViewLayoutState()
        initialState.isCollectionMode = true
        initialState.collectionCoreFinished = true
        initialState.collectionItems = [item]
        initialState.entries = [item]
        initialState.sortKey = .kind
        let store = TestStore(initialState: initialState) {
            EntryViewLayoutFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
        }
        // store.exhaustivity = .off: arrangement child의 내부 grouping 파생 상태는 이 spec owner의 검증 범위가 아니다.
        store.exhaustivity = .off

        await store.send(.internal(.collectionReplaceEvent(
            epoch: 0,
            event: .metadataPatches([.spotlight(
                id: item.id,
                kind: "Patched Folder",
                creatorApplication: nil,
                lastOpenedDate: nil,
            )]),
        ))) {
            $0.collectionItems = [patched]
            $0.entries = [patched]
        }
    }

    /// EVM-002-set_entries_view_as_icon_grid: inactive deferred patch는 collection ID order를 바꾸지 않는다.
    /// - 검증 내용: name sort에서 spotlight kind patch가 cell data만 갱신하는지 확인한다.
    /// - 사전 조건: collection core가 완료됐고 name sort가 활성화되어 있다.
    /// - 기대 결과: entries의 ID 순서는 유지되며 patched kind만 반영된다.
    func testInactiveCollectionMetadataPatchPreservesEntryOrder() {
        let first = EntryModel.temporaryFolder(id: "/tmp/first", name: "first")
        let second = EntryModel.temporaryFolder(id: "/tmp/second", name: "second")
        var state = EntryViewLayoutState()
        state.isCollectionMode = true
        state.collectionCoreFinished = true
        state.collectionItems = [first, second]
        state.entries = [first, second]
        state.sortKey = .name

        _ = EntryViewLayoutFeature().reduce(into: &state, action: .internal(.collectionReplaceEvent(
            epoch: 0,
            event: .metadataPatches([.spotlight(
                id: second.id,
                kind: "Patched Folder",
                creatorApplication: nil,
                lastOpenedDate: nil,
            )]),
        )))

        XCTAssertEqual(state.entries.map(\.id), [first.id, second.id])
        XCTAssertEqual(state.entries.last?.facets.kind, "Patched Folder")
    }

    private func makeCollectionPresentationTestStore() -> TestStore<EntryViewLayoutState, EntryViewLayoutAction> {
        let store = TestStore(initialState: EntryViewLayoutState()) {
            EntryViewLayoutFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
        }
        // collection presentation 테스트는 reapply routing과 display source 동기화만 검증하며,
        // EntryArrangements 내부 grouping 파생 상태는 해당 패키지 owner suite에서 별도로 검증한다.
        store.exhaustivity = .off
        return store
    }
}

extension EVM002ManageEntriesViewPresentationTests {
    // MARK: - EVM-002-toggle_directory_expansion_in_list

    /// EVM-002-toggle_directory_expansion_in_list: expanded folder는 immediate child를 parent 바로 아래에 projection한다.
    /// 사용자가 list directory에서 folder disclosure를 열었을 때 child entry가 same page outline에 나타나는지 검증한다.
    /// - 검증 내용: root와 expanded folder의 child state가 preorder visible rows로 변환된다.
    /// - 사전 조건: /root/a folder가 expanded이고 /root/a/file child가 loaded 상태다.
    /// - 기대 결과: visible entry IDs는 /root/a, /root/a/file, /root/b 순서다.
    func testDirectoryExpansionProjectsImmediateChildren() {
        let folder = EntryModel.temporaryFolder(id: "/root/a", name: "a")
        let file = makeHierarchyEntry(id: "/root/a/file", name: "file")
        let sibling = EntryModel.temporaryFolder(id: "/root/b", name: "b")
        let projection = makeHierarchyProjection(
            roots: [folder, sibling],
            expandedFolderIDs: [folder.id],
            childrenByFolderID: [folder.id: [file]],
        )

        XCTAssertEqual(projection.visibleSelectableEntryIDs, [folder.id, file.id, sibling.id])
        XCTAssertEqual(projection.visibleRows, [.entry(folder.id), .entry(file.id), .entry(sibling.id)])
    }

    /// EVM-002-toggle_directory_expansion_in_list: expanded child folder는 repeated immediate projection으로 arbitrary
    /// depth를 만든다.
    /// 사용자가 root folder와 그 child folder를 차례로 열었을 때 eager subtree load 없이 preorder가 구성되는지 검증한다.
    /// - 검증 내용: expanded ancestor chain만 visible rows에 포함하고 collapsed ancestor 아래 descendant는 제외한다.
    /// - 사전 조건: /root/a와 /root/a/b가 expanded이고 각각 immediate children이 loaded 상태다.
    /// - 기대 결과: visible entry IDs는 /root/a, /root/a/file, /root/a/b, /root/a/b/deep 순서다.
    func testNestedExpansionProjectsArbitraryDepthOneLevelAtATime() {
        let folder = EntryModel.temporaryFolder(id: "/root/a", name: "a")
        let file = makeHierarchyEntry(id: "/root/a/file", name: "file")
        let nestedFolder = EntryModel.temporaryFolder(id: "/root/a/b", name: "z")
        let deepFile = makeHierarchyEntry(id: "/root/a/b/deep", name: "deep")
        let projection = makeHierarchyProjection(
            roots: [folder],
            expandedFolderIDs: [folder.id, nestedFolder.id],
            childrenByFolderID: [folder.id: [file, nestedFolder], nestedFolder.id: [deepFile]],
        )

        XCTAssertEqual(projection.visibleSelectableEntryIDs, [folder.id, file.id, nestedFolder.id, deepFile.id])
        XCTAssertEqual(
            projection.visibleRows,
            [.entry(folder.id), .entry(file.id), .entry(nestedFolder.id), .entry(deepFile.id)],
        )
    }

    /// EVM-002-toggle_directory_expansion_in_list: expanded loaded-empty folder는 nonselectable empty feedback row를
    /// projection한다.
    /// 사용자가 child가 없는 folder를 열어도 synthetic feedback이 selection 대상이 되지 않는지 검증한다.
    /// - 검증 내용: loaded empty folder는 stable empty synthetic ID를 child row로 가진다.
    /// - 사전 조건: /root/empty folder가 expanded이고 loaded children가 빈 배열이다.
    /// - 기대 결과: empty row는 visibleRows에 있으나 visibleSelectableEntryIDs에는 없다.
    func testExpandedEmptyFolderProjectsNonselectableEmptyRow() {
        let folder = EntryModel.temporaryFolder(id: "/root/empty", name: "empty")
        let projection = makeHierarchyProjection(
            roots: [folder],
            expandedFolderIDs: [folder.id],
            childrenByFolderID: [folder.id: []],
        )

        XCTAssertEqual(projection.visibleRows, [.entry(folder.id), .empty(parent: folder.id)])
        XCTAssertEqual(projection.visibleSelectableEntryIDs, [folder.id])
        XCTAssertFalse(projection.itemPayloads[.empty(parent: folder.id)]?.isSelectable ?? true)
        XCTAssertFalse(projection.itemPayloads[.empty(parent: folder.id)]?.isRetryable ?? true)
    }

    /// EVM-002-toggle_directory_expansion_in_list: root와 every expanded parent는 독립 sibling set으로 arrangement된다.
    /// 서로 다른 folder의 children가 하나의 global sorted list로 섞이지 않고 각 parent 아래에 남는지 검증한다.
    /// - 검증 내용: projection은 root와 parent-local child arrays에 같은 sorter를 적용한 뒤 preorder로 flatten한다.
    /// - 사전 조건: root와 /root/a의 child input order가 name sort와 반대이고 /root/b는 collapsed다.
    /// - 기대 결과: /root/a children은 /root/a 아래에서만 정렬되고 /root/b와 섞이지 않는다.
    func testEachParentReceivesIndependentSiblingArrangement() {
        let folderA = EntryModel.temporaryFolder(id: "/root/a", name: "a")
        let folderB = EntryModel.temporaryFolder(id: "/root/b", name: "b")
        let childZ = makeHierarchyEntry(id: "/root/a/z", name: "z")
        let childY = makeHierarchyEntry(id: "/root/a/y", name: "y")
        let projection = makeHierarchyProjection(
            roots: [folderB, folderA],
            expandedFolderIDs: [folderA.id],
            childrenByFolderID: [folderA.id: [childZ, childY]],
        )

        XCTAssertEqual(projection.visibleSelectableEntryIDs, [folderA.id, childY.id, childZ.id, folderB.id])
    }

    private func makeHierarchyProjection(
        roots: [EntryModel],
        expandedFolderIDs: Set<EntryModel.ID>,
        childrenByFolderID: [EntryModel.ID: [EntryModel]],
    ) -> EntryListOutlineProjection {
        var hierarchyState = EntryListHierarchyState(
            rootPath: "/root",
            nodesByID: childrenByFolderID.mapValues { children in
                FolderNodeState(
                    folder: FolderSnapshot(children: children),
                    generation: 0,
                    loadPhase: .loaded,
                )
            },
        )
        hierarchyState.setExpandedIDs(expandedFolderIDs)
        return EntryListOutlineProjection(
            revision: 1,
            rootEntries: roots,
            hierarchyState: hierarchyState,
            context: .init(mode: .list, isNormalDirectoryPage: true, hasActiveGrouping: false),
            sortKey: .name,
            sortOrder: .ascending,
        )
    }

    private func makeHierarchyEntry(id: String, name: String) -> EntryModel {
        EntryModel(
            name: name,
            fullPath: id,
            isFolder: false,
            isHidden: false,
            size: 0,
            modifiedDate: Date(timeIntervalSince1970: 1_700_000_000),
            fileExtension: "txt",
            facets: EntryFacets(
                createdDate: Date(timeIntervalSince1970: 1_700_000_000),
                addedDate: Date(timeIntervalSince1970: 1_700_000_000),
                lastOpenedDate: nil,
                kind: "Text",
                creatorApplication: nil,
                tags: nil,
                supplementaryMetadata: nil,
            ),
        )
    }
}

extension EVM002ManageEntriesViewPresentationTests {
    /// EVM-002-toggle_directory_expansion_in_list: 동일 folder의 loading expansion은 중복 요청을 만들지 않는다.
    /// - 검증 내용: loading phase에서 다시 expand해도 generation이 유지된다.
    /// - 사전 조건: /root/a가 root entry이고 첫 expansion이 loading 상태다.
    /// - 기대 결과: 두 번째 expansion 뒤에도 generation은 1이다.
    func testFirstExpandLoadsOnlyImmediateChildrenOnce() {
        let folder = EntryModel.temporaryFolder(id: "/root/a", name: "a")
        var state = hierarchyLoadingState(roots: [folder])
        let reducer = EntryListHierarchyReducer()
        _ = reducer.reduce(into: &state, action: .hierarchy(.folderExpansionRequested(id: folder.id)))
        _ = reducer.reduce(into: &state, action: .hierarchy(.folderExpansionRequested(id: folder.id)))
        XCTAssertEqual(state.hierarchy.nodesByID[folder.id as String]?.generation, 1)
        XCTAssertEqual(state.hierarchy.nodesByID[folder.id as String]?.loadPhase, .loadingCore)
    }

    /// EVM-002-toggle_directory_expansion_in_list: sibling folder loads는 서로 독립이다.
    /// - 검증 내용: 각 folder가 자체 generation/loading phase를 가진다.
    /// - 사전 조건: /root/a와 /root/b가 root folders다.
    /// - 기대 결과: 두 folder 모두 loading이며 generation 1이다.
    func testConcurrentFolderLoadsRemainIndependent() {
        let a = EntryModel.temporaryFolder(id: "/root/a", name: "a")
        let b = EntryModel.temporaryFolder(id: "/root/b", name: "b")
        var state = hierarchyLoadingState(roots: [a, b])
        let reducer = EntryListHierarchyReducer()
        _ = reducer.reduce(into: &state, action: .hierarchy(.folderExpansionRequested(id: a.id)))
        _ = reducer.reduce(into: &state, action: .hierarchy(.folderExpansionRequested(id: b.id)))
        XCTAssertEqual(state.hierarchy.nodesByID[a.id as String]?.loadPhase, .loadingCore)
        XCTAssertEqual(state.hierarchy.nodesByID[b.id as String]?.loadPhase, .loadingCore)
    }

    /// EVM-002-toggle_directory_expansion_in_list: loaded folder 재확장은 session cache를 재사용한다.
    /// - 검증 내용: collapse 뒤 expand가 loaded children/generation을 유지한다.
    /// - 사전 조건: /root/a의 immediate child가 loaded다.
    /// - 기대 결과: 재확장 후 child cache와 generation이 변하지 않는다.
    func testReexpandUsesSessionCache() {
        let folder = EntryModel.temporaryFolder(id: "/root/a", name: "a")
        let child = makeHierarchyEntry(id: "/root/a/file", name: "file")
        var state = hierarchyLoadingState(roots: [folder])
        state.hierarchy.nodesByID[folder.id as String] = .init(children: [child], loadPhase: .loaded, generation: 4)
        let reducer = EntryListHierarchyReducer()
        _ = reducer.reduce(into: &state, action: .hierarchy(.folderCollapseRequested(id: folder.id)))
        _ = reducer.reduce(into: &state, action: .hierarchy(.folderExpansionRequested(id: folder.id)))
        XCTAssertEqual(state.hierarchy.nodesByID[folder.id as String]?.folder.children, [child])
        XCTAssertEqual(state.hierarchy.nodesByID[folder.id as String]?.generation, 4)
    }

    /// EVM-002-toggle_directory_expansion_in_list: retry는 failed folder만 새 generation으로 교체한다.
    /// - 검증 내용: sibling loaded state가 retry에 의해 변경되지 않는다.
    /// - 사전 조건: a는 failed, b는 loaded다.
    /// - 기대 결과: a만 loading generation 2가 되고 b cache는 유지된다.
    func testFolderRetryPreservesSiblingState() {
        let a = EntryModel.temporaryFolder(id: "/root/a", name: "a")
        let b = EntryModel.temporaryFolder(id: "/root/b", name: "b")
        let child = makeHierarchyEntry(id: "/root/b/file", name: "file")
        var state = hierarchyLoadingState(roots: [a, b])
        state.hierarchy.nodesByID[a.id as String] = .init(generation: 1, loadPhase: .failed(.permissionDenied))
        state.hierarchy.nodesByID[b.id as String] = .init(children: [child], loadPhase: .loaded, generation: 3)
        let reducer = EntryListHierarchyReducer()
        _ = reducer.reduce(into: &state, action: .hierarchy(.folderRetryRequested(id: a.id)))
        XCTAssertEqual(state.hierarchy.nodesByID[a.id as String]?.loadPhase, .loadingCore)
        XCTAssertEqual(state.hierarchy.nodesByID[a.id as String]?.generation, 2)
        XCTAssertEqual(state.hierarchy.nodesByID[b.id as String]?.folder.children, [child])
    }

    /// EVM-002-toggle_directory_expansion_in_list: 이전 generation response는 현재 request를 바꾸지 않는다.
    /// - 검증 내용: generation guard가 stale success를 무시한다.
    /// - 사전 조건: /root/a generation 2가 loading 중이다.
    /// - 기대 결과: generation 1 success 뒤에도 phase는 loading이며 cache는 비어 있다.
    func testOlderFolderGenerationResponseIsIgnored() {
        let folder = EntryModel.temporaryFolder(id: "/root/a", name: "a")
        let staleChild = makeHierarchyEntry(id: "/root/a/stale", name: "stale")
        var state = hierarchyLoadingState(roots: [folder])
        state.hierarchy.nodesByID[folder.id as String] = .init(generation: 2, loadPhase: .loadingCore)
        let reducer = EntryListHierarchyReducer()
        _ = reducer.reduce(into: &state, action: .hierarchy(.folderChildrenResponse(
            rootContextGeneration: 0,
            folderID: folder.id,
            folderGeneration: 1,
            .event(.coreBatch(items: [staleChild], batchIndex: 0)),
        )))
        XCTAssertEqual(state.hierarchy.nodesByID[folder.id as String]?.loadPhase, .loadingCore)
        XCTAssertEqual(state.hierarchy.nodesByID[folder.id as String]?.folder.children, [])
    }

    /// EVM-002-toggle_directory_expansion_in_list: collapse는 해당 folder request만 무효화한다.
    /// - 검증 내용: collapse가 folder generation을 올리고 sibling loading을 보존한다.
    /// - 사전 조건: a와 b가 loading/expanded 상태다.
    /// - 기대 결과: a만 collapsed generation 2가 되고 b는 loading generation 1이다.
    func testCollapseCancelsOnlyCollapsedFolderLoad() {
        let a = EntryModel.temporaryFolder(id: "/root/a", name: "a")
        let b = EntryModel.temporaryFolder(id: "/root/b", name: "b")
        var state = hierarchyLoadingState(roots: [a, b])
        state.hierarchy.nodesByID[a.id as String] = .init(expansionIntent: true, generation: 1, loadPhase: .loadingCore)
        state.hierarchy.nodesByID[b.id as String] = .init(expansionIntent: true, generation: 1, loadPhase: .loadingCore)
        _ = EntryListHierarchyReducer().reduce(into: &state, action: .hierarchy(.folderCollapseRequested(id: a.id)))
        XCTAssertFalse(state.hierarchy.expandedFolderIDs.contains(a.id))
        XCTAssertTrue(state.hierarchy.expandedFolderIDs.contains(b.id))
        XCTAssertEqual(state.hierarchy.nodesByID[a.id as String]?.generation, 2)
        XCTAssertEqual(state.hierarchy.nodesByID[b.id as String]?.generation, 1)
    }

    private func hierarchyLoadingState(roots: [EntryModel]) -> EntryViewLayoutState {
        var state = EntryViewLayoutState()
        state.entries = roots
        state.hierarchy = .init(rootPath: "/root")
        return state
    }
}
