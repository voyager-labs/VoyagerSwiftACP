// FLOW-ID: evm.navigate_pages
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
final class NavigatePagesFlowTests: XCTestCase {
    // FLOW-PATH: happy_path.navigate_and_preserve_history

    /// EVM-001-navigate_pages: directory page 이동은 새 route를 표시하고 이전 page를 history에 남긴다.
    /// - 검증 내용: navigation flow가 destination route와 되돌아갈 수 있는 history를 함께 만든다.
    /// - 사전 조건: 현재 content page는 `/flow/source` directory다.
    /// - 기대 결과: destination은 `/flow/destination`이고 back history에는 source page가 남는다.
    func testNavigateToDirectoryPreservesReturnHistory() async {
        var state = ContentPageNavigationFeature.State()
        state.seedInitialFolderPath("/flow/source")
        let store = TestStore(initialState: state) {
            ContentPageNavigationFeature()
        }
        // flow는 delegate 내부 순서가 아닌 page route와 history의 사용자 관찰 결과를 검증한다.
        store.exhaustivity = .off

        await store.send(.internal(.performNavigateToPath("/flow/destination")))

        XCTAssertEqual(store.state.navigationState, .folder("/flow/destination"))
        XCTAssertEqual(store.state.backHistory.count, 1)
        XCTAssertTrue(store.state.canGoBack)
    }

    // FLOW-PATH: happy_path.external_reload_preserves_page_identity

    /// EVM-001-reload_directory_page_on_external_change: external reload은 현재 page identity와 history를 바꾸지 않는다.
    /// - 검증 내용: directory child change를 전달해도 current route와 history snapshot이 유지된다.
    /// - 사전 조건: `/flow/current` directory page에 existing back history가 있다.
    /// - 기대 결과: reload boundary 뒤에도 같은 route와 history가 표시된다.
    func testExternalReloadPreservesCurrentPageIdentity() async {
        var state = FileManagerContentFeature.State()
        state.navigation.seedInitialFolderPath("/flow/current")
        state.navigation.appendBackHistory(.init(navigationState: .folder("/flow/previous")))
        let store = TestStore(initialState: state) {
            FileManagerContentFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_700_000_000))
        }
        // flow는 background reload의 package-local load detail 대신 page identity 보존만 검증한다.
        store.exhaustivity = .off

        let initialRoute = store.state.navigation.navigationState
        let initialHistory = store.state.navigation.backHistory
        await store.send(.externalFileSystemChanged([FileChangeGatewayEvent(
            path: "/flow/current/changed.txt",
            flags: 0,
        )]))

        XCTAssertEqual(store.state.navigation.navigationState, initialRoute)
        XCTAssertEqual(store.state.navigation.backHistory, initialHistory)
    }

    // FLOW-PATH: happy_path.directory_route_reaches_staged_first_batch

    /// EVM-001-navigate_pages: directory route는 staged root request의 첫 batch를 entries presentation까지 전달한다.
    /// - 검증 내용: composed route reload가 directory staged client와 first-batch entries를 연결한다.
    /// - 사전 조건: `/flow/current` directory route에서 child filesystem change가 발생한다.
    /// - 기대 결과: 첫 batch 뒤 entries가 표시되고 blocking loading이 해제된다.
    func testDirectoryRouteReachesStagedFirstBatchPresentation() async {
        let entry = EntryModel.temporaryFolder(id: "/flow/current/entry", name: "entry")
        var state = FileManagerContentFeature.State()
        state.navigation.seedInitialFolderPath("/flow/current")
        let store = TestStore(initialState: state) {
            FileManagerContentFeature()
        } withDependencies: {
            $0.entryLoadingClient.stagedLoadItems = { url, _, _ in
                XCTAssertEqual(url.path, "/flow/current")
                return Self.stagedStream(with: entry)
            }
            $0.userDefaultsClient.setString = { _, _ in }
            $0.date = .constant(Date(timeIntervalSince1970: 1_700_000_000))
        }
        // flow는 root reducer의 event validation이 아닌 route-to-presentation handoff만 검증한다.
        store.exhaustivity = .off

        await store.send(.externalFileSystemChanged([FileChangeGatewayEvent(
            path: "/flow/current/changed.txt",
            flags: 0,
        )]))
        await store.receive(\.entryOperations.loading.loadItems)
        await store.receive { action in
            guard case let .entryOperations(.loading(.streamEvent(event))) = action else {
                return false
            }
            return event.event == .coreBatch(items: [entry], batchIndex: 0)
        }
        await store.receive { action in
            guard case .entryViewLayout(.view(.applyContentProjection)) = action else { return false }
            return true
        }

        XCTAssertEqual(store.state.entryViewLayout.entries, [entry])
        XCTAssertFalse(store.state.entryOperations.isLoading)
    }

    // FLOW-PATH: happy_path.recents_route_reaches_staged_first_batch

    /// EVM-001-navigate_pages: Recents route는 staged root request의 첫 batch를 entries presentation까지 전달한다.
    /// - 검증 내용: composed route reload가 Recents staged client와 first-batch entries를 연결한다.
    /// - 사전 조건: Recents route에서 filesystem change가 발생한다.
    /// - 기대 결과: 첫 batch 뒤 entries가 표시되고 blocking loading이 해제된다.
    func testRecentsRouteReachesStagedFirstBatchPresentation() async {
        let entry = EntryModel.temporaryFolder(id: "/flow/recents/entry", name: "entry")
        var state = FileManagerContentFeature.State()
        state.navigation.navigationState = .recents
        let store = TestStore(initialState: state) {
            FileManagerContentFeature()
        } withDependencies: {
            $0.entryLoadingClient.stagedLoadRecentItems = { _, _ in
                Self.stagedStream(with: entry)
            }
            $0.userDefaultsClient.setString = { _, _ in }
            $0.date = .constant(Date(timeIntervalSince1970: 1_700_000_000))
        }
        // flow는 root reducer의 payload batching을 재검증하지 않고 production route handoff만 검증한다.
        store.exhaustivity = .off

        await store.send(.externalFileSystemChanged([FileChangeGatewayEvent(
            path: "/flow/recents/changed.txt",
            flags: 0,
        )]))
        await store.receive(\.entryOperations.loading.loadRecentItems)
        await store.receive { action in
            guard case let .entryOperations(.loading(.streamEvent(event))) = action else {
                return false
            }
            return event.event == .coreBatch(items: [entry], batchIndex: 0)
        }
        await store.receive { action in
            guard case .entryViewLayout(.view(.applyContentProjection)) = action else { return false }
            return true
        }

        XCTAssertEqual(store.state.entryViewLayout.entries, [entry])
        XCTAssertFalse(store.state.entryOperations.isLoading)
    }

    // FLOW-PATH: happy_path.tags_route_reaches_staged_first_batch

    /// EVM-001-navigate_pages: Tags route는 staged root request의 첫 batch를 entries presentation까지 전달한다.
    /// - 검증 내용: composed route reload가 Tags staged client와 first-batch entries를 연결한다.
    /// - 사전 조건: `Work` Tags route에서 filesystem change가 발생한다.
    /// - 기대 결과: 첫 batch 뒤 entries가 표시되고 blocking loading이 해제된다.
    func testTagsRouteReachesStagedFirstBatchPresentation() async {
        let entry = EntryModel.temporaryFolder(id: "/flow/tags/entry", name: "entry")
        var state = FileManagerContentFeature.State()
        state.navigation.navigationState = .tags("Work")
        let store = TestStore(initialState: state) {
            FileManagerContentFeature()
        } withDependencies: {
            $0.entryLoadingClient.stagedLoadFilesWithTag = { tag, _, _ in
                XCTAssertEqual(tag, "Work")
                return Self.stagedStream(with: entry)
            }
            $0.userDefaultsClient.setString = { _, _ in }
            $0.date = .constant(Date(timeIntervalSince1970: 1_700_000_000))
        }
        // flow는 root reducer의 stale-generation guards가 아닌 production route handoff만 검증한다.
        store.exhaustivity = .off

        await store.send(.externalFileSystemChanged([FileChangeGatewayEvent(path: "/flow/tags/changed.txt", flags: 0)]))
        await store.receive(\.entryOperations.loading.loadTagItems)
        await store.receive { action in
            guard case let .entryOperations(.loading(.streamEvent(event))) = action else {
                return false
            }
            return event.event == .coreBatch(items: [entry], batchIndex: 0)
        }
        await store.receive { action in
            guard case .entryViewLayout(.view(.applyContentProjection)) = action else { return false }
            return true
        }

        XCTAssertEqual(store.state.entryViewLayout.entries, [entry])
        XCTAssertFalse(store.state.entryOperations.isLoading)
    }

    nonisolated private static func stagedStream(
        with entry: EntryModel,
    ) -> AsyncThrowingStream<EntryLoadEvent, Error> {
        AsyncThrowingStream { continuation in
            continuation.yield(.coreBatch(items: [entry], batchIndex: 0))
            continuation.yield(.coreFinished(batchCount: 1))
            continuation.finish()
        }
    }
}
