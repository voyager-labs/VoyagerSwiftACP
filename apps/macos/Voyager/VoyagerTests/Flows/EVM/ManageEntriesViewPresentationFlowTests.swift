// FLOW-ID: evm.manage_entries_view_presentation
import ComposableArchitecture
import Foundation
import VoyagerEntitiesEntry
import VoyagerFeaturesContentPageNavigation
import VoyagerFeaturesEntryOperations
@testable import VoyagerPagesFileManager
import VoyagerShared
import VoyagerWidgetsEntryViewLayout
import XCTest

@MainActor
final class ManageEntriesViewPresentationFlowTests: XCTestCase {
    // FLOW-PATH: happy_path.list_icon_projection_preserves_selection

    /// EVM-002-set_entries_view_as_icon_grid: list/icon projection 전환은 current page와 selection을 보존한다.
    /// - 검증 내용: list에서 grid로 전환한 뒤 route/history와 selected entry identity가 유지된다.
    /// - 사전 조건: `/flow/current` directory page에서 하나의 entry가 선택되어 있다.
    /// - 기대 결과: mode만 grid로 바뀌고 page identity와 selection은 같다.
    func testListIconProjectionPreservesSelectionAndPageIdentity() async {
        let selectedID: EntryModel.ID = "/flow/current/selected.txt"
        let selectedEntry = EntryModel.temporaryFolder(id: selectedID, name: "selected.txt")
        var state = FileManagerContentFeature.State()
        state.navigation.seedInitialFolderPath("/flow/current")
        state.entryViewLayout.mode = .list
        state.entryViewLayout.entries = [selectedEntry]
        state.entryViewLayout.entryOperations.items = [selectedEntry]
        state.entryViewLayout.selectedIds = [selectedID]
        let store = TestStore(initialState: state) {
            FileManagerContentFeature()
        } withDependencies: {
            $0.userDefaultsClient.setString = { _, _ in }
        }
        // flow는 projection의 내부 arrangement/action sequence가 아닌 visible mode와 selection 결과를 검증한다.
        store.exhaustivity = .off

        let initialRoute = store.state.navigation.navigationState
        let initialHistory = store.state.navigation.backHistory
        await store.send(.view(.changeLayout(.grid)))
        await store.receive(\.entryViewLayout.internal.setMode) {
            $0.entryViewLayout.mode = .grid
        }

        XCTAssertEqual(store.state.entryViewLayout.mode, .grid)
        XCTAssertEqual(store.state.entryViewLayout.selectedIds, [selectedID])
        XCTAssertEqual(store.state.navigation.navigationState, initialRoute)
        XCTAssertEqual(store.state.navigation.backHistory, initialHistory)
    }

    // FLOW-PATH: happy_path.list_directory_expansion_preserves_page_identity

    /// EVM-002-toggle_directory_expansion_in_list: list directory disclosure는 staged child stream을 projection에 반영한다.
    /// - 검증 내용: composed FileManager reducer가 parent loading, 첫 child batch, core finish를 순서대로 투영한다.
    /// - 사전 조건: `/flow/current` directory page의 root folder 하나가 list layout으로 표시된다.
    /// - 기대 결과: route/history는 유지되고 parent spinner는 core finish에서만 꺼진다.
    func testNestedDirectoryExpansionProjectsStagedChildrenWithoutNavigation() async {
        let folder = EntryModel.temporaryFolder(id: "/flow/current/folder", name: "folder")
        let child = EntryModel.temporaryFolder(id: "/flow/current/folder/child", name: "child")
        var state = FileManagerContentFeature.State()
        state.navigation.seedInitialFolderPath("/flow/current")
        state.entryViewLayout.entries = [folder]
        state.entryViewLayout.entryOperations.items = [folder]
        state.entryViewLayout.hierarchy = .init(rootPath: "/flow/current")
        let store = TestStore(initialState: state) {
            FileManagerContentFeature()
        } withDependencies: {
            $0.entryLoadingClient.stagedLoadItems = { url, _, _ in
                XCTAssertEqual(url.path, folder.fullPath)
                return AsyncThrowingStream { continuation in
                    continuation.yield(.coreBatch(items: [child], batchIndex: 0))
                    continuation.yield(.coreFinished(batchCount: 1))
                    continuation.finish()
                }
            }
            $0.userDefaultsClient.setString = { _, _ in }
        }
        // store.exhaustivity = .off: flow는 composed route/history와 visible projection만 소유한다.
        store.exhaustivity = .off

        let initialRoute = store.state.navigation.navigationState
        let initialHistory = store.state.navigation.backHistory
        await store.send(.entryViewLayout(.hierarchy(.folderExpansionRequested(id: folder.id))))
        await store.receive { action in
            guard case let .entryViewLayout(.hierarchy(.folderChildrenResponse(
                rootContextGeneration,
                folderID,
                folderGeneration,
                result,
            ))) = action
            else {
                return false
            }
            return rootContextGeneration == 0
                && folderID == folder.id
                && folderGeneration == 1
                && result == .event(.coreBatch(items: [child], batchIndex: 0))
        }

        XCTAssertEqual(store.state.entryViewLayout.hierarchy.nodesByID[folder.id]?.loadPhase, .loadingCore)
        XCTAssertFalse(store.state.entryViewLayout.hierarchy.nodesByID[folder.id]?.folder.coreFinished ?? true)
        XCTAssertEqual(
            store.state.entryViewLayout.visibleSelectableEntryIDs(isNormalDirectoryPage: true),
            [folder.id, child.id],
        )

        await store.receive { action in
            guard case let .entryViewLayout(.hierarchy(.folderChildrenResponse(
                rootContextGeneration,
                folderID,
                folderGeneration,
                result,
            ))) = action
            else {
                return false
            }
            return rootContextGeneration == 0
                && folderID == folder.id
                && folderGeneration == 1
                && result == .event(.coreFinished(batchCount: 1))
        }
        XCTAssertTrue(store.state.entryViewLayout.hierarchy.nodesByID[folder.id]?.folder.coreFinished ?? false)

        await store.receive { action in
            guard case let .entryViewLayout(.hierarchy(.folderChildrenResponse(
                rootContextGeneration,
                folderID,
                folderGeneration,
                result,
            ))) = action
            else {
                return false
            }
            return rootContextGeneration == 0
                && folderID == folder.id
                && folderGeneration == 1
                && result == .streamCompleted
        }
        XCTAssertEqual(store.state.entryViewLayout.hierarchy.nodesByID[folder.id]?.loadPhase, .loaded)

        XCTAssertEqual(store.state.navigation.navigationState, initialRoute)
        XCTAssertEqual(store.state.navigation.backHistory, initialHistory)
        XCTAssertEqual(
            store.state.entryViewLayout.visibleSelectableEntryIDs(isNormalDirectoryPage: true),
            [folder.id, child.id],
        )
    }
}
