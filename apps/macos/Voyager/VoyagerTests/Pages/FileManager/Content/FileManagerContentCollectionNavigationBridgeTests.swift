// swiftlint:disable type_name nesting
import ComposableArchitecture
import Foundation
@testable import Voyager
import VoyagerEntitiesCollection
import VoyagerEntitiesEntry
import VoyagerFeaturesContentPageNavigation
import VoyagerFeaturesEntryArrangements
import VoyagerFeaturesEntryOperations
import VoyagerShared
import XCTest

@MainActor
final class FileManagerContentCollectionNavigationBridgeTests: XCTestCase {
    private let reducer = FileManagerContentFeature()

    @MainActor
    struct EntryOperationsBridgeHarness: Reducer {
        @MainActor
        struct State: Equatable {
            var content: FileManagerContentState
        }

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

    // MARK: - Non-Collection Navigation: clearCollectionPresentation + Load

    func testFolderNavigationSendsClearCollectionPresentationThenLoadItems() async {
        let store = TestStore(initialState: makeInitialState()) {
            reducer
        }

        store.exhaustivity = .off

        await store.send(.internal(.applyNavigationState(.folder("/tmp/voyager")))) {
            $0.entryViewLayout.currentPath = "/tmp/voyager"
            $0.entryViewLayout.savedScrollOffset = nil
        }

        await store.receive { action in
            guard case .entryViewLayout(.internal(.clearCollectionPresentation)) = action else { return false }
            return true
        }
        await store.receive { action in
            switch action {
            case let .entryViewLayout(entryViewLayoutAction):
                switch entryViewLayoutAction {
                case let .entryOperations(entryOperationsAction):
                    switch entryOperationsAction {
                    case let .loading(loadingAction):
                        switch loadingAction {
                        case let .loadItems(path, showHidden):
                            path == "/tmp/voyager" && showHidden == false
                        default:
                            false
                        }
                    default:
                        false
                    }
                default:
                    false
                }
            default:
                false
            }
        }
    }

    func testRecentsNavigationSendsClearCollectionPresentationThenLoadRecents() async {
        let store = TestStore(initialState: makeInitialState()) {
            reducer
        }

        store.exhaustivity = .off

        await store.send(.internal(.applyNavigationState(.recents))) {
            $0.entryViewLayout.currentPath = "Recents"
            $0.entryViewLayout.savedScrollOffset = nil
        }

        await store.receive { action in
            guard case .entryViewLayout(.internal(.clearCollectionPresentation)) = action else { return false }
            return true
        }
        await store.receive { action in
            switch action {
            case let .entryViewLayout(entryViewLayoutAction):
                switch entryViewLayoutAction {
                case let .entryOperations(entryOperationsAction):
                    switch entryOperationsAction {
                    case let .loading(loadingAction):
                        switch loadingAction {
                        case let .loadRecentItems(showHidden):
                            showHidden == false
                        default:
                            false
                        }
                    default:
                        false
                    }
                default:
                    false
                }
            default:
                false
            }
        }
    }

    func testTagsNavigationSendsClearCollectionPresentationThenLoadTagItems() async {
        let store = TestStore(initialState: makeInitialState()) {
            reducer
        }

        store.exhaustivity = .off

        await store.send(.internal(.applyNavigationState(.tags("Work")))) {
            $0.entryViewLayout.currentPath = "Work"
            $0.entryViewLayout.savedScrollOffset = nil
        }

        await store.receive { action in
            guard case .entryViewLayout(.internal(.clearCollectionPresentation)) = action else { return false }
            return true
        }
        await store.receive { action in
            switch action {
            case let .entryViewLayout(entryViewLayoutAction):
                switch entryViewLayoutAction {
                case let .entryOperations(entryOperationsAction):
                    switch entryOperationsAction {
                    case let .loading(loadingAction):
                        switch loadingAction {
                        case let .loadTagItems(tagName: tagName, showHidden: showHidden):
                            tagName == "Work" && showHidden == false
                        default:
                            false
                        }
                    default:
                        false
                    }
                default:
                    false
                }
            default:
                false
            }
        }
    }

    func testComputerNavigationSendsClearCollectionPresentationThenLoadComputerItems() async {
        let store = TestStore(initialState: makeInitialState()) {
            reducer
        }

        store.exhaustivity = .off

        await store.send(.internal(.applyNavigationState(.computer))) {
            $0.entryViewLayout.currentPath = ""
            $0.entryViewLayout.savedScrollOffset = nil
        }

        await store.receive { action in
            guard case .entryViewLayout(.internal(.clearCollectionPresentation)) = action else { return false }
            return true
        }
        await store.receive { action in
            guard case .entryViewLayout(.entryOperations(.loading(.loadComputerItems))) = action else { return false }
            return true
        }
    }

    // MARK: - Collection Navigation: setCollectionMode Only

    func testCollectionNavigationSendsSetCollectionModeTrueOnly() async {
        let store = TestStore(initialState: makeInitialState()) {
            reducer
        }

        store.exhaustivity = .off

        let collectionNavigation = ContentPageCollectionNavigation(
            kind: .temporary,
            context: CollectionContext(query: "test", scopes: [], conditions: []),
            sortKey: .name,
            sortOrder: .ascending,
            viewLayout: .list,
        )

        await store.send(.internal(.applyNavigationState(.collection(collectionNavigation)))) {
            $0.entryViewLayout.currentPath = "New Collection"
            $0.entryViewLayout.savedScrollOffset = nil
        }

        await store.receive { action in
            guard case .entryViewLayout(.internal(.setCollectionMode(true))) = action else { return false }
            return true
        }
    }

    // MARK: - handleEntryOperationsAction: Returns None for Loading Actions

    func testItemsLoadedReturnsNoneFromPageLevelHandler() async {
        let store = TestStore(initialState: EntryOperationsBridgeHarness.State(content: .init())) {
            EntryOperationsBridgeHarness()
        }
        store.exhaustivity = .off

        await store.send(EntryOperationsBridgeHarness.Action.bridge(.loading(.itemsLoaded([]))))
        await store.finish()
    }

    // MARK: - operationFinished: Reload Only, No Reapply

    func testOperationFinishedTriggersReloadWithoutReapply() async {
        var initialState = EntryOperationsBridgeHarness.State(content: .init())
        initialState.content.navigation.seedInitialFolderPath("/tmp/voyager")
        initialState.content.navigation.navigationState = .folder("/tmp/voyager")

        let store = TestStore(initialState: initialState) {
            EntryOperationsBridgeHarness()
        }
        store.exhaustivity = .off

        await store.send(EntryOperationsBridgeHarness.Action.bridge(.lifecycle(.operationFinished(
            "/tmp/voyager",
            OperationKind.rename,
            Result<Void, FileOpError>.success(()),
        ))))
        await store.receive { action in
            switch action {
            case let .forwarded(forwardedAction):
                switch forwardedAction {
                case let .entryViewLayout(entryViewLayoutAction):
                    switch entryViewLayoutAction {
                    case let .entryOperations(entryOperationsAction):
                        switch entryOperationsAction {
                        case let .loading(loadingAction):
                            switch loadingAction {
                            case let .loadItems(path, showHidden):
                                path == "/tmp/voyager" && showHidden == false
                            default:
                                false
                            }
                        default:
                            false
                        }
                    default:
                        false
                    }
                default:
                    false
                }
            default:
                false
            }
        }
        await store.finish()
    }

    // MARK: - makeEntryOperationsCommandContext: Uses entryViewLayout.entries

    func testCommandContextUsesEntryViewLayoutEntries() {
        let entry = EntryModel.temporaryFolder(id: "/tmp/file.txt", name: "file.txt")
        var state = makeInitialState()
        state.entryViewLayout.entries = [entry]
        state.entryViewLayout.selectedIds = [entry.id]

        let context = reducer.makeEntryOperationsCommandContext(state: state)

        XCTAssertEqual(
            context.displayItems.map(\.id),
            [entry.id],
            "makeEntryOperationsCommandContext must read displayItems from entryViewLayout.entries",
        )
        XCTAssertEqual(context.selectedIds, [entry.id])
    }

    // MARK: - Helpers

    private func makeInitialState() -> FileManagerContentState {
        var state = FileManagerContentState()
        state.navigation.seedInitialFolderPath("/tmp/voyager")
        return state
    }
}

// swiftlint:enable type_name nesting
