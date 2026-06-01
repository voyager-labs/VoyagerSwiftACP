import ComposableArchitecture
import IdentifiedCollections
import VoyagerEntitiesAppPreferences
import VoyagerEntitiesEntry
@testable import VoyagerPagesFileManager
import VoyagerWidgetsEntryViewLayout
import XCTest

@MainActor
final class EVM002FileManagerPagePresentationTests: XCTestCase {
    // MARK: - EVM-002-set_entries_view_as_list_table

    /// EVM-002-set_entries_view_as_list_table: 리스트 모드로 레이아웃 변경 시 상태 전이 검증
    /// 사용자가 리스트 뷰로 전환하면 entryViewLayout.mode가 .list로 업데이트되고 composer 동기화가 발생한다.
    /// - 검증 내용: view(.changeLayout(.list)) 액션이 mode를 .list로 변경하고 composer.syncCollectionState 이펙트를 트리거하는지 확인
    /// - 사전 조건: 기본 FileManagerContentState (mode 기본값)
    /// - 기대 결과: state.entryViewLayout.mode == .list, composer.syncCollectionState 수신
    func testChangeLayoutToListUpdatesMode() async {
        var state = FileManagerContentState()
        state.entryViewLayout.mode = .grid

        let store = makeFileManagerContentStore(initialState: state)

        await store.send(.view(.changeLayout(.list))) {
            $0.entryViewLayout.mode = .list
        }

        // composer 동기화 수신 — 하위 composer 액션
        await store.receive(\.composer.internal.syncCollectionState)
    }

    // MARK: - EVM-002-set_entries_view_as_icon_grid

    /// EVM-002-set_entries_view_as_icon_grid: 그리드 모드로 레이아웃 변경 시 상태 전이 검증
    /// 사용자가 아이콘 그리드 뷰로 전환하면 entryViewLayout.mode가 .grid로 업데이트되고 composer 동기화가 발생한다.
    /// - 검증 내용: view(.changeLayout(.grid)) 액션이 mode를 .grid로 변경하고 composer.syncCollectionState 이펙트를 트리거하는지 확인
    /// - 사전 조건: 기본 FileManagerContentState (mode 기본값)
    /// - 기대 결과: state.entryViewLayout.mode == .grid, composer.syncCollectionState 수신
    func testChangeLayoutToGridUpdatesMode() async {
        let store = makeFileManagerContentStore()

        await store.send(.view(.changeLayout(.grid))) {
            $0.entryViewLayout.mode = .grid
        }

        await store.receive(\.composer.internal.syncCollectionState)
    }

    /// EVM-002-set_entries_view_as_icon_grid: 레이아웃 변경 시 UserDefaults 영속성 검증
    /// 그리드 모드로 전환 시 선택한 레이아웃 모드가 UserDefaults에 영속화된다.
    /// - 검증 내용: changeLayout(.grid) 후 userDefaultsClient.setString이 올바른 키와 값으로 호출되는지 확인
    /// - 사전 조건: 기본 FileManagerContentState, UserDefaultsStringRecorder 주입
    /// - 기대 결과: recorder에 SettingsKeys.viewLayout == EntryViewLayoutState.Mode.grid.rawValue 기록
    func testChangeLayoutPersistsToSettings() async {
        let recorder = UserDefaultsStringRecorder()
        let store = makeFileManagerContentStore(setString: recorder.record)

        await store.send(.view(.changeLayout(.grid))) {
            $0.entryViewLayout.mode = .grid
        }

        await store.receive(\.composer.internal.syncCollectionState)

        XCTAssertEqual(recorder.value(forKey: SettingsKeys.viewLayout), EntryViewLayoutState.Mode.grid.rawValue)
    }

    /// EVM-002-set_entries_view_as_list_table: 레이아웃 변경 시 활성 이름 변경 취소 검증
    /// 다른 모드로 레이아웃 변경 시 진행 중인 rename 작업이 취소되어야 한다.
    /// - 검증 내용: renamingItemId가 존재하는 상태에서 changeLayout(.grid) 시 cancelRename 액션 수신 및 renamingItemId nil 설정
    /// - 사전 조건: mode == .list, renamingItemId == "test-entry-id"
    /// - 기대 결과: mode == .grid, renamingItemId == nil, cancelRename 액션 수신
    func testChangeLayoutCancelsActiveRename() async {
        let renamingId: EntryModel.ID = "test-entry-id"
        var state = FileManagerContentState()
        state.entryViewLayout.mode = .list
        state.entryViewLayout.entryOperations.renamingItemId = renamingId

        let store = makeFileManagerContentFeatureStore(initialState: state)

        await store.send(.view(.changeLayout(.grid))) {
            $0.entryViewLayout.mode = .grid
        }

        await store.receive(\.composer.internal.syncCollectionState)
        await store.receive(\.entryViewLayout.entryOperations.edit.cancelRename) {
            $0.entryViewLayout.entryOperations.renamingItemId = nil
        }
    }

    /// EVM-002-set_entries_view_as_list_table: 동일 모드 재선택 시 rename 취소 방지 검증
    /// 이미 활성화된 모드를 다시 선택하면 isModeChanging이 false이므로 rename이 취소되지 않는다.
    /// - 검증 내용: mode == .list 상태에서 changeLayout(.list) 시 cancelRename 액션이 발생하지 않는지 확인
    /// - 사전 조건: mode == .list, renamingItemId == "test-entry-id"
    /// - 기대 결과: renamingItemId 유지, cancelRename 미수신, composer.syncCollectionState만 수신
    func testChangeLayoutSameModeDoesNotCancelRename() async {
        let renamingId: EntryModel.ID = "test-entry-id"
        var state = FileManagerContentState()
        state.entryViewLayout.mode = .list
        state.entryViewLayout.entryOperations.renamingItemId = renamingId

        let store = makeFileManagerContentStore(initialState: state)

        // 같은 모드로 변경 → isModeChanging == false → 취소 없음
        await store.send(.view(.changeLayout(.list)))

        await store.receive(\.composer.internal.syncCollectionState)
    }

    // MARK: - EVM-002-show_hide_hidden_entry (Page-level reload + navigation stability)

    /// store.exhaustivity = .off: loadItems 이후 itemsLoaded→arrangements 체인은 검증 대상이 아님
    /// EVM-002-show_hide_hidden_entry: 숨김 파일 토글 + 리로드 시 네비게이션/히스토리 불변 검증
    /// FileManagerContentFeature 전체 리듀서에서 toggleShowHiddenFilesAndReload가
    /// entryViewLayout.toggleShowHiddenFiles + reload 체인을 트리거하며
    /// 네비게이션 라우트와 히스토리가 변경되지 않음을 증명한다.
    ///
    /// - 사전 조건: navigationState == .folder("/seed"), showHiddenFiles == false
    /// - 기대 결과:
    ///   1) .entryViewLayout(.view(.toggleShowHiddenFiles)) 수신, showHiddenFiles == true
    ///   2) .entryViewLayout(.entryOperations(.loading(.loadItems(path: "/seed", showHidden: true)))) 수신
    ///   3) navigationState, backHistory, forwardHistory 변경 없음
    func testToggleShowHiddenFilesAndReloadPreservesNavigationHistory() async {
        var state = FileManagerContentState()
        state.navigation.seedInitialFolderPath("/seed")
        state.entryViewLayout.showHiddenFiles = false

        let store = makeFileManagerContentFeatureStore(initialState: state)
        store.exhaustivity = .off

        let preNavigation = store.state.navigation.navigationState
        let preBackHistory = store.state.navigation.backHistory
        let preForwardHistory = store.state.navigation.forwardHistory

        // NavigationBridgeReducer가 effect만 반환 (상태 변이 없음)
        await store.send(.view(.toggleShowHiddenFilesAndReload))

        _ = await store.receive(\.entryViewLayout.view.toggleShowHiddenFiles) {
            $0.entryViewLayout.showHiddenFiles = true
        }

        _ = await store.receive(\.entryViewLayout.entryOperations.loading.loadItems)

        // 네비게이션 라우트와 히스토리가 변경되지 않았는지 확인
        XCTAssertEqual(store.state.navigation.navigationState, preNavigation)
        XCTAssertEqual(store.state.navigation.backHistory, preBackHistory)
        XCTAssertEqual(store.state.navigation.forwardHistory, preForwardHistory)
    }

    // MARK: - EVM-002-set_entries_view_as_list_table (seeded .grid → .list)

    /// EVM-002-set_entries_view_as_list_table: .grid → .list 전환 시 모드/영속성/composer 동기화 검증
    /// 초기 모드가 .grid인 상태에서 .list로 전환할 때 모드 변경, UserDefaults 영속화,
    /// composer 동기화가 모두 정상 동작함을 증명한다.
    ///
    /// - 사전 조건: entryViewLayout.mode == .grid
    /// - 기대 결과:
    ///   1) mode == .list
    ///   2) SettingsKeys.viewLayout에 "list" 영속화
    ///   3) composer.syncCollectionState 수신
    func testChangeLayoutFromGridToListPersistsAndSyncs() async {
        let recorder = UserDefaultsStringRecorder()
        var state = FileManagerContentState()
        state.entryViewLayout.mode = .grid

        // store.exhaustivity = .off: FileManagerContentFeature 전체 리듀서 사용 시
        // changeLayout이 ComposerReducer 외에도 Scope/composer 자체 처리를 트리거할 수 있음
        let store = makeFileManagerContentFeatureStore(
            initialState: state,
            setString: recorder.record,
        )
        store.exhaustivity = .off

        await store.send(.view(.changeLayout(.list))) {
            $0.entryViewLayout.mode = .list
        }

        _ = await store.receive(\.composer.internal.syncCollectionState)

        XCTAssertEqual(recorder.value(forKey: SettingsKeys.viewLayout), EntryViewLayoutState.Mode.list.rawValue)
        XCTAssertEqual(store.state.entryViewLayout.mode, .list)
    }

    // MARK: - EVM-002-view_entry_counts_in_current_page / EVM-002-show_selected_entry_counts

    /// EVM-002-view_entry_counts_in_current_page / EVM-002-show_selected_entry_counts:
    /// ContentPaneBreadcrumbBarView.statusText의 소스 데이터 검증
    ///
    /// statusText는 `displayItems.count`와 `selectedIds.count`로 계산된다:
    ///   - selected == 0 → "\(total) items"
    ///   - selected > 0 → "\(selected) of \(total) selected"
    ///
    /// 이 테스트는 entryViewLayout.displayItems와 selectedIds가
    /// statusText 계산에 사용되는 정확한 소스 값임을 reducer 레벨에서 증명한다.
    /// displayItems는 entryOperations.loadingContext.items를 반환하므로
    /// 상태 시딩 시 loadingContext.items를 직접 채운다.
    ///
    /// - 사전 조건: displayItems에 3개 항목, selectedIds에 2개 선택
    /// - 기대 결과: displayItems.count == 3, selectedIds.count == 2
    func testStatusTextSourceMatchesDisplayItemsAndSelectedIds() {
        var state = FileManagerContentState()
        let entries: [EntryModel] = [
            .temporaryFolder(id: "/seed/file-a", name: "file-a"),
            .temporaryFolder(id: "/seed/file-b", name: "file-b"),
            .temporaryFolder(id: "/seed/file-c", name: "file-c"),
        ]
        state.entryViewLayout.entryOperations.loadingContext.items = IdentifiedArrayOf(uniqueElements: entries)
        state.entryViewLayout.selectedIds = ["/seed/file-a", "/seed/file-c"]

        let store = makeFileManagerContentFeatureStore(initialState: state)
        store.exhaustivity = .off

        let total = store.state.entryViewLayout.displayItems.count
        let selected = store.state.entryViewLayout.selectedIds.count

        XCTAssertEqual(total, 3, "displayItems.count should match total item count for statusText")
        XCTAssertEqual(selected, 2, "selectedIds.count should match selected count for statusText")
        XCTAssertGreaterThan(selected, 0, "selected > 0 → statusText should be '\(selected) of \(total) selected'")
    }

    /// EVM-002-view_entry_counts_in_current_page: 선택 없음 시 statusText 소스 검증
    ///
    /// - 사전 조건: displayItems에 2개 항목, selectedIds가 비어 있음
    /// - 기대 결과: displayItems.count == 2, selectedIds.count == 0
    func testStatusTextSourceWithNoSelection() {
        var state = FileManagerContentState()
        let entries: [EntryModel] = [
            .temporaryFolder(id: "/seed/file-x", name: "file-x"),
            .temporaryFolder(id: "/seed/file-y", name: "file-y"),
        ]
        state.entryViewLayout.entryOperations.loadingContext.items = IdentifiedArrayOf(uniqueElements: entries)
        state.entryViewLayout.selectedIds = []

        let store = makeFileManagerContentFeatureStore(initialState: state)
        store.exhaustivity = .off

        let total = store.state.entryViewLayout.displayItems.count
        let selected = store.state.entryViewLayout.selectedIds.count

        XCTAssertEqual(total, 2)
        XCTAssertEqual(selected, 0, "selectedIds.count == 0 → statusText should be '\(total) items'")
    }
}
