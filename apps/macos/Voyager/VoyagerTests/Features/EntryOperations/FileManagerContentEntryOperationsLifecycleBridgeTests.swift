import ComposableArchitecture
import Foundation
@testable import Voyager
import VoyagerEntitiesEntry
import VoyagerFeaturesEntryOperations
import XCTest

@MainActor
final class FileManagerContentEntryOpsBridgeTests: XCTestCase {
    private let reducer = FileManagerContentFeature()

    // MARK: - Harness

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
                    FileManagerContentFeature().handleEntryOperationsAction(entryAction, state: &state.content)
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
            guard case .forwarded(.entryViewLayout(.entryOperations(.loading(.loadRecentItems(showHidden: false))))) =
                action else { return false }
            return true
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
                tagName,
                showHidden,
            ))))) =
                action else { return false }
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
        await store.receive(.forwarded(.entryViewLayout(.internal(.removeCollectionPaths(["/tmp/a.txt"]))))) {
            $0.content.entryViewLayout.collectionItems = [retainedItem]
            $0.content.entryViewLayout.selectedIds = []
            $0.content.entryViewLayout.lastSelectedId = nil
            $0.content.entryViewLayout.rangeAnchorId = nil
            $0.content.entryViewLayout.shouldScrollToSelection = false
            $0.content.entryViewLayout.entries = [retainedItem]
        }
        await store.receive(.forwarded(.entryViewLayout(.entryArrangements(.reapply))))
        await store.finish()
    }
}
