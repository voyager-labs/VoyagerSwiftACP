import ComposableArchitecture
import Foundation
@testable import Voyager
import VoyagerEntitiesCollection
import VoyagerEntitiesEntry
import VoyagerFeaturesContentPageNavigation
import VoyagerFeaturesEntryArrangements
import VoyagerFeaturesEntryOperations
@testable import VoyagerPagesFileManager
import VoyagerShared
import XCTest

@MainActor
final class ContentEntryOpsLifecycleTests: XCTestCase {
    private let reducer = FileManagerContentFeature()

    // MARK: - 하네스

    @MainActor
    struct LifecycleBridgeHarness: Reducer {
        // swiftlint:disable:next nesting
        struct State: Equatable {
            var content: FileManagerContentState
        }

        // swiftlint:disable:next nesting
        enum Action: Sendable {
            case bridge(EntryOperationsAction)
            case forwarded(FileManagerContentAction)
        }

        var body: some Reducer<State, Action> {
            Reduce { state, action in
                switch action {
                case let .bridge(entryAction):
                    FileManagerContentEntryOpsCoordinator.handleEntryOperationsAction(
                        entryAction,
                        state: &state.content,
                    )
                    .map(Action.forwarded)
                case .forwarded:
                    .none
                }
            }
        }
    }

    // MARK: - 도우미

    private func makeInitialState() -> LifecycleBridgeHarness.State {
        LifecycleBridgeHarness.State(content: FileManagerContentState())
    }

    private func makeInitialState(folderPath: String) -> LifecycleBridgeHarness.State {
        var state = makeInitialState()
        state.content.navigation.seedInitialFolderPath(folderPath)
        state.content.navigation.navigationState = .folder(folderPath)
        return state
    }

    // MARK: - .lifecycle(.operationFinished)가 콘텐츠 리로드를 트리거

    /// testOperationFinishedTriggersContentReload 테스트 동작을 검증한다.
    func testOperationFinishedTriggersContentReload() async {
        let folderPath = "/tmp/voyager"
        let store = TestStore(initialState: makeInitialState(folderPath: folderPath)) {
            LifecycleBridgeHarness()
        }
        store.exhaustivity = .off

        await store.send(.bridge(.lifecycle(.operationFinished(
            "/tmp/voyager/file.txt",
            .rename,
            .success(()),
        ))))

        await store.receive { action in
            guard case let .forwarded(.entryViewLayout(.entryOperations(.loading(.loadItems(path, showHidden))))) =
                action else { return false }
            return path == folderPath && showHidden == false
        }
        await store.finish()
    }

    /// testOperationFinishedTriggersContentReloadForRecents 테스트 동작을 검증한다.
    func testOperationFinishedTriggersContentReloadForRecents() async {
        var initialState = makeInitialState()
        initialState.content.navigation.navigationState = .recents

        let store = TestStore(initialState: initialState) {
            LifecycleBridgeHarness()
        }
        store.exhaustivity = .off

        await store.send(.bridge(.lifecycle(.operationFinished(
            "/tmp/voyager/file.txt",
            .moveToTrash,
            .success(()),
        ))))

        await store.receive { action in
            guard case .forwarded(.entryViewLayout(.entryOperations(.loading(.loadRecentItems(showHidden: false))))) =
                action else { return false }
            return true
        }
        await store.finish()
    }

    /// testOperationFinishedTriggersContentReloadForTags 테스트 동작을 검증한다.
    func testOperationFinishedTriggersContentReloadForTags() async {
        var initialState = makeInitialState()
        initialState.content.navigation.navigationState = .tags("Work")

        let store = TestStore(initialState: initialState) {
            LifecycleBridgeHarness()
        }
        store.exhaustivity = .off

        await store.send(.bridge(.lifecycle(.operationFinished(
            "/tmp/voyager/file.txt",
            .setTags,
            .success(()),
        ))))

        await store.receive { action in
            guard case let .forwarded(.entryViewLayout(.entryOperations(.loading(.loadTagItems(
                tagName,
                showHidden,
            ))))) =
                action else { return false }
            return tagName == "Work" && showHidden == false
        }
        await store.finish()
    }

    /// testOperationFinishedOnCollectionNavigationReturnsNone 테스트 동작을 검증한다.
    func testOperationFinishedOnCollectionNavigationReturnsNone() async {
        var initialState = makeInitialState()
        initialState.content.navigation.navigationState = .collection(
            ContentPageCollectionNavigation(
                kind: .temporary,
                context: CollectionContext(query: "test", scopes: [], conditions: []),
                sortKey: .name,
                sortOrder: .ascending,
                viewLayout: .list,
            ),
        )

        let store = TestStore(initialState: initialState) {
            LifecycleBridgeHarness()
        }
        store.exhaustivity = .off

        await store.send(.bridge(.lifecycle(.operationFinished(
            "/tmp/voyager/file.txt",
            .rename,
            .success(()),
        ))))
        await store.finish()
    }

    // MARK: - .lifecycle(.emptyTrashCompleted)가 closeWindow 델리게이트를 트리거

    /// testEmptyTrashCompletedTriggersCloseWindow 테스트 동작을 검증한다.
    func testEmptyTrashCompletedTriggersCloseWindow() async {
        let store = TestStore(initialState: makeInitialState()) {
            LifecycleBridgeHarness()
        }
        store.exhaustivity = .off

        await store.send(.bridge(.lifecycle(.emptyTrashCompleted)))

        await store.receive { action in
            guard case .forwarded(.delegate(.closeWindow)) = action else { return false }
            return true
        }
        await store.finish()
    }

    // MARK: - .lifecycle(.entryActionCompleted)는 none 반환 (메트릭 로깅만)

    /// testEntryActionCompletedReturnsNoneWithoutReload 테스트 동작을 검증한다.
    func testEntryActionCompletedReturnsNoneWithoutReload() async {
        let folderPath = "/tmp/voyager"
        let store = TestStore(initialState: makeInitialState(folderPath: folderPath)) {
            LifecycleBridgeHarness()
        }
        store.exhaustivity = .off

        let record = EntryActionRecord(
            operationKind: .rename,
            targets: [EntryActionRecord.Target(beforePath: "/tmp/a.txt", afterPath: "/tmp/b.txt")],
        )

        await store.send(.bridge(.lifecycle(.entryActionCompleted(record))))
        await store.finish()
    }

    /// testPutBackEntryActionCompletedOnCollectionNavigationRestoresCollectionPresentation 테스트 동작을 검증한다.
    func testPutBackEntryActionCompletedOnCollectionNavigationRestoresCollectionPresentation() async {
        var initialState = makeInitialState()
        initialState.content.navigation.navigationState = .collection(
            ContentPageCollectionNavigation(
                kind: .temporary,
                context: CollectionContext(query: "test", scopes: [], conditions: []),
                sortKey: .name,
                sortOrder: .ascending,
                viewLayout: .list,
            ),
        )
        initialState.content.entryViewLayout.isCollectionMode = true

        let restoredRecord = EntryActionRecord(
            operationKind: .putBack,
            targets: [EntryActionRecord.Target(beforePath: "/Users/me/.Trash/a.txt", afterPath: "/tmp/a.txt")],
        )

        let store = TestStore(initialState: initialState) {
            LifecycleBridgeHarness()
        }
        store.exhaustivity = .off

        await store.send(.bridge(.lifecycle(.entryActionCompleted(restoredRecord))))
        await store.receive { action in
            guard case .forwarded = action else { return false }
            return true
        }
        await store.finish()
    }

    /// testUndoAppliedMoveToTrashOnCollectionNavigationRestoresCollectionPresentation 테스트 동작을 검증한다.
    func testUndoAppliedMoveToTrashOnCollectionNavigationRestoresCollectionPresentation() async {
        var initialState = makeInitialState()
        initialState.content.navigation.navigationState = .collection(
            ContentPageCollectionNavigation(
                kind: .temporary,
                context: CollectionContext(query: "test", scopes: [], conditions: []),
                sortKey: .name,
                sortOrder: .ascending,
                viewLayout: .list,
            ),
        )
        initialState.content.entryViewLayout.isCollectionMode = true

        let trashedRecord = EntryActionRecord(
            operationKind: .moveToTrash,
            targets: [EntryActionRecord.Target(beforePath: "/tmp/a.txt", afterPath: "/Users/me/.Trash/a.txt")],
        )

        let store = TestStore(initialState: initialState) {
            LifecycleBridgeHarness()
        }
        store.exhaustivity = .off

        await store.send(.bridge(.undoRedo(.entryActionApplied(direction: .undo, record: trashedRecord))))
        await store.receive { action in
            guard case .forwarded = action else { return false }
            return true
        }
        await store.finish()
    }

    // MARK: - 비수명주기 항목 연산은 브릿지 부수효과를 트리거하지 않음

    /// testLoadingItemsLoadedReturnsNone 테스트 동작을 검증한다.
    func testLoadingItemsLoadedReturnsNone() async {
        let store = TestStore(initialState: makeInitialState()) {
            LifecycleBridgeHarness()
        }
        store.exhaustivity = .off

        await store.send(.bridge(.loading(.itemsLoaded([]))))
        await store.finish()
    }

    /// testWindowIDChangedDoesNotTriggerReloadOrCloseWindow 테스트 동작을 검증한다.
    func testWindowIDChangedDoesNotTriggerReloadOrCloseWindow() async {
        let store = TestStore(initialState: makeInitialState()) {
            LifecycleBridgeHarness()
        }
        store.exhaustivity = .off

        await store.send(.bridge(.lifecycle(.windowIDChanged(UUID()))))
        await store.finish()
    }

    /// testPathsMutatedDoesNotTriggerReloadOrCloseWindow 테스트 동작을 검증한다.
    func testPathsMutatedDoesNotTriggerReloadOrCloseWindow() async {
        let folderPath = "/tmp/voyager"
        let store = TestStore(initialState: makeInitialState(folderPath: folderPath)) {
            LifecycleBridgeHarness()
        }
        store.exhaustivity = .off

        await store.send(.bridge(.lifecycle(.pathsMutated(["/tmp/a.txt", "/tmp/b.txt"]))))
        await store.finish()
    }

    /// testPathsMutatedOnCollectionNavigationPrunesCollectionPresentation 테스트 동작을 검증한다.
    func testPathsMutatedOnCollectionNavigationPrunesCollectionPresentation() async {
        var initialState = makeInitialState()
        let collectionItem = EntryModel.temporaryFolder(id: "/tmp/a.txt", name: "a.txt")
        let retainedItem = EntryModel.temporaryFolder(id: "/tmp/keep.txt", name: "keep.txt")
        initialState.content.navigation.navigationState = .collection(
            ContentPageCollectionNavigation(
                kind: .temporary,
                context: CollectionContext(query: "test", scopes: [], conditions: []),
                sortKey: .name,
                sortOrder: .ascending,
                viewLayout: .list,
            ),
        )
        initialState.content.entryViewLayout.isCollectionMode = true
        initialState.content.entryViewLayout.collectionItems = [collectionItem, retainedItem]
        initialState.content.entryViewLayout.entries = [collectionItem, retainedItem]
        initialState.content.entryViewLayout.selectedIds = [collectionItem.id]
        initialState.content.entryViewLayout.lastSelectedId = collectionItem.id
        initialState.content.entryViewLayout.rangeAnchorId = collectionItem.id

        let store = TestStore(initialState: initialState) {
            LifecycleBridgeHarness()
        }
        store.exhaustivity = .off

        await store.send(.bridge(.lifecycle(.pathsMutated(["/tmp/a.txt"]))))
        await store.receive { action in
            guard case .forwarded = action else { return false }
            return true
        }
        await store.receive { action in
            guard case .forwarded = action else { return false }
            return true
        }
        await store.finish()
    }
}
