import ComposableArchitecture
import Foundation
@testable import Voyager
import VoyagerEntitiesEntry
import VoyagerFeaturesEntryOperations
import XCTest

@MainActor
final class FileManagerContentEntryOpsLifecycleBridgeTests: XCTestCase {
    private let reducer = FileManagerContentFeature()

    // MARK: - Harness

    @MainActor
    struct LifecycleBridgeHarness: Reducer {
        // swiftlint:disable:next nesting
        struct State: Equatable {
            var content: FileManagerContentState

            static func == (lhs: Self, rhs: Self) -> Bool {
                _ = lhs
                _ = rhs
                return true
            }
        }

        // swiftlint:disable:next nesting
        enum Action: Sendable, Equatable {
            case bridge(EntryOperationsAction)
            case forwarded(FileManagerContentAction)

            static func == (lhs: Self, rhs: Self) -> Bool {
                switch (lhs, rhs) {
                case (.bridge, .bridge), (.forwarded, .forwarded):
                    true
                default:
                    false
                }
            }
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

    // MARK: - Helpers

    private func makeInitialState() -> LifecycleBridgeHarness.State {
        LifecycleBridgeHarness.State(content: FileManagerContentState())
    }

    private func makeInitialState(folderPath: String) -> LifecycleBridgeHarness.State {
        var state = makeInitialState()
        state.content.navigation.seedInitialFolderPath(folderPath)
        state.content.navigation.navigationState = .folder(folderPath)
        return state
    }

    // MARK: - .lifecycle(.operationFinished) triggers content reload

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
            guard case let .forwarded(
                .entryViewLayout(.entryOperations(.loading(.loadRecentItems(showHidden: showHidden)))),
            ) = action else {
                return false
            }
            return showHidden == false
        }
        await store.finish()
    }

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
                tagName: tagName,
                showHidden: showHidden,
            ))))) = action else { return false }
            return tagName == "Work" && showHidden == false
        }
        await store.finish()
    }

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

    // MARK: - .lifecycle(.emptyTrashCompleted) triggers closeWindow delegate

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

    // MARK: - .lifecycle(.entryActionCompleted) returns none (metric logging only)

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
            guard case .forwarded(.entryViewLayout(.internal(.addCollectionPaths(["/tmp/a.txt"])))) = action else {
                return false
            }
            return true
        }
        await store.finish()
    }

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
            guard case .forwarded(.entryViewLayout(.internal(.addCollectionPaths(["/tmp/a.txt"])))) = action else {
                return false
            }
            return true
        }
        await store.finish()
    }

    // MARK: - Non-lifecycle entry operations do not trigger bridge side effects

    func testLoadingItemsLoadedReturnsNone() async {
        let store = TestStore(initialState: makeInitialState()) {
            LifecycleBridgeHarness()
        }
        store.exhaustivity = .off

        await store.send(.bridge(.loading(.itemsLoaded([]))))
        await store.finish()
    }

    func testWindowIDChangedDoesNotTriggerReloadOrCloseWindow() async {
        let store = TestStore(initialState: makeInitialState()) {
            LifecycleBridgeHarness()
        }
        store.exhaustivity = .off

        await store.send(.bridge(.lifecycle(.windowIDChanged(UUID()))))
        await store.finish()
    }

    func testPathsMutatedDoesNotTriggerReloadOrCloseWindow() async {
        let folderPath = "/tmp/voyager"
        let store = TestStore(initialState: makeInitialState(folderPath: folderPath)) {
            LifecycleBridgeHarness()
        }
        store.exhaustivity = .off

        await store.send(.bridge(.lifecycle(.pathsMutated(["/tmp/a.txt", "/tmp/b.txt"]))))
        await store.finish()
    }

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
        await store.receive(
            { action in
                guard case .forwarded(.entryViewLayout(.internal(.removeCollectionPaths(["/tmp/a.txt"])))) = action
                else {
                    return false
                }
                return true
            },
            assert: { state in
                state.content.entryViewLayout.collectionItems = [retainedItem]
                state.content.entryViewLayout.selectedIds = []
                state.content.entryViewLayout.lastSelectedId = nil
                state.content.entryViewLayout.rangeAnchorId = nil
                state.content.entryViewLayout.shouldScrollToSelection = false
                state.content.entryViewLayout.entries = [retainedItem]
            },
        )
        await store.receive { action in
            guard case .forwarded(.entryViewLayout(.entryArrangements(.reapply))) = action else {
                return false
            }
            return true
        }
        await store.finish()
    }
}
