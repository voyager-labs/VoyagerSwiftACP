import ComposableArchitecture
import Dependencies
@testable import VoyagerPagesFileManager
import XCTest

// MARK: - EVM-002-set_entries_view_as_list_table

@MainActor
final class EVM002LayoutPageContractTests: XCTestCase {
    // MARK: - EVM-002-set_entries_view_as_list_table

    func testChangeLayoutToListUpdatesMode() async {
        let store = TestStore(initialState: FileManagerContentState()) {
            FileManagerContentComposerReducer()
        } withDependencies: {
            $0.userDefaultsClient.setString = { _, _ in }
        }

        await store.send(.view(.changeLayout(.list))) {
            $0.entryViewLayout.mode = .list
        }

        // composer 동기화 수신 — 하위 composer 액션
        await store.receive(\.composer.syncCollectionState)
    }

    // MARK: - EVM-002-set_entries_view_as_icon_grid

    func testChangeLayoutToGridUpdatesMode() async {
        let store = TestStore(initialState: FileManagerContentState()) {
            FileManagerContentComposerReducer()
        } withDependencies: {
            $0.userDefaultsClient.setString = { _, _ in }
        }

        await store.send(.view(.changeLayout(.grid))) {
            $0.entryViewLayout.mode = .grid
        }

        await store.receive(\.composer.syncCollectionState)
    }

    func testChangeLayoutPersistsToSettings() async {
        var persistedValue: String?
        let store = TestStore(initialState: FileManagerContentState()) {
            FileManagerContentComposerReducer()
        } withDependencies: {
            $0.userDefaultsClient.setString = { value, key in
                if key == SettingsKeys.viewLayout {
                    persistedValue = value
                }
            }
        }

        await store.send(.view(.changeLayout(.grid))) {
            $0.entryViewLayout.mode = .grid
        }

        await store.receive(\.composer.syncCollectionState)

        XCTAssertEqual(persistedValue, EntryViewLayoutState.Mode.grid.rawValue)
    }

    func testChangeLayoutCancelsActiveRename() async {
        let renamingId: EntryModel.ID = "test-entry-id"
        var state = FileManagerContentState()
        state.entryViewLayout.mode = .list
        state.entryViewLayout.entryOperations.renamingItemId = renamingId

        let store = TestStore(initialState: state) {
            FileManagerContentComposerReducer()
        } withDependencies: {
            $0.userDefaultsClient.setString = { _, _ in }
        }

        await store.send(.view(.changeLayout(.grid))) {
            $0.entryViewLayout.mode = .grid
        }

        await store.receive(\.composer.syncCollectionState)
        await store.receive(\.entryViewLayout.entryOperations.edit.cancelRename) {
            $0.entryViewLayout.entryOperations.renamingItemId = nil
        }
    }

    func testChangeLayoutSameModeDoesNotCancelRename() async {
        let renamingId: EntryModel.ID = "test-entry-id"
        var state = FileManagerContentState()
        state.entryViewLayout.mode = .list
        state.entryViewLayout.entryOperations.renamingItemId = renamingId

        let store = TestStore(initialState: state) {
            FileManagerContentComposerReducer()
        } withDependencies: {
            $0.userDefaultsClient.setString = { _, _ in }
        }

        // 같은 모드로 변경 → isModeChanging == false → 취소 없음
        await store.send(.view(.changeLayout(.list)))

        await store.receive(\.composer.syncCollectionState)
    }
}
