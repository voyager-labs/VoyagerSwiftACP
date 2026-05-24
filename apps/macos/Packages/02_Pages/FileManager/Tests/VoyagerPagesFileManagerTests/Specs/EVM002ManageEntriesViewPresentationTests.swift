import ComposableArchitecture
@testable import VoyagerPagesFileManager
import XCTest

@MainActor
final class EVM002ManageEntriesViewPresentationTests: XCTestCase {
    // MARK: - EVM-002-set_entries_view_as_list_table

    /// EVM-002-set_entries_view_as_list_table: 리스트 모드로 레이아웃 변경 시 상태 전이 검증
    /// 사용자가 리스트 뷰로 전환하면 entryViewLayout.mode가 .list로 업데이트되고 composer 동기화가 발생한다.
    /// - 검증 내용: view(.changeLayout(.list)) 액션이 mode를 .list로 변경하고 composer.syncCollectionState 이펙트를 트리거하는지 확인
    /// - 사전 조건: 기본 FileManagerContentState (mode 기본값)
    /// - 기대 결과: state.entryViewLayout.mode == .list, composer.syncCollectionState 수신
    func testChangeLayoutToListUpdatesMode() async {
        let store = makeFileManagerContentStore()

        await store.send(.view(.changeLayout(.list))) {
            $0.entryViewLayout.mode = .list
        }

        // composer 동기화 수신 — 하위 composer 액션
        await store.receive(\.composer.syncCollectionState)
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

        await store.receive(\.composer.syncCollectionState)
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

        await store.receive(\.composer.syncCollectionState)

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

        let store = makeFileManagerContentStore(initialState: state)

        await store.send(.view(.changeLayout(.grid))) {
            $0.entryViewLayout.mode = .grid
        }

        await store.receive(\.composer.syncCollectionState)
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

        await store.receive(\.composer.syncCollectionState)
    }
}
