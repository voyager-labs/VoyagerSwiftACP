import ComposableArchitecture
import Foundation
@testable import Voyager
import VoyagerEntitiesEntry
import VoyagerFeaturesEntryOperations
import XCTest

@MainActor
final class FileManagerContentCollectionNavigationBridgeTests: XCTestCase {
    private let reducer = FileManagerContentFeature()

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

        await store.receive(.entryViewLayout(.internal(.clearCollectionPresentation)))
        await store.receive(.entryViewLayout(.entryOperations(.loading(.loadItems(
            path: "/tmp/voyager",
            showHidden: false,
        ))))
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

        await store.receive(.entryViewLayout(.internal(.clearCollectionPresentation)))
        await store.receive(.entryViewLayout(.entryOperations(.loading(.loadRecentItems(
            showHidden: false,
        ))))
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

        await store.receive(.entryViewLayout(.internal(.clearCollectionPresentation)))
        await store.receive(.entryViewLayout(.entryOperations(.loading(.loadTagItems(
            tagName: "Work",
            showHidden: false,
        ))))
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

        await store.receive(.entryViewLayout(.internal(.clearCollectionPresentation)))
        await store.receive(.entryViewLayout(.entryOperations(.loading(.loadComputerItems))))
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

        await store.receive(.entryViewLayout(.internal(.setCollectionMode(true))))
    }

    // MARK: - handleEntryOperationsAction: Returns None for Loading Actions

    func testItemsLoadedReturnsNoneFromPageLevelHandler() async {
        var state = makeInitialState()
        let effect = reducer.handleEntryOperationsAction(
            .loading(.itemsLoaded),
            state: &state,
        )

        var hasActions = false
        for await _ in effect.actions {
            hasActions = true
        }
        XCTAssertFalse(hasActions,
                       "handleEntryOperationsAction(.loading(.itemsLoaded)) must return .none")
    }

    // MARK: - operationFinished: Reload Only, No Reapply

    func testOperationFinishedTriggersReloadWithoutReapply() async {
        var state = makeInitialState()
        state.navigation.navigationState = .folder("/tmp/voyager")

        let effect = reducer.handleEntryOperationsAction(
            .lifecycle(.operationFinished),
            state: &state,
        )

        var receivedActions: [FileManagerContentAction] = []
        for await action in effect.actions {
            receivedActions.append(action)
        }

        let hasReapply = receivedActions.contains {
            if case .entryViewLayout(.entryArrangements(.reapply)) = $0 { return true }
            return false
        }
        XCTAssertFalse(hasReapply,
                       "operationFinished must not send page-level reapply")

        let hasLoadItems = receivedActions.contains {
            if case .entryViewLayout(.entryOperations(.loading(.loadItems))) = $0 { return true }
            return false
        }
        XCTAssertTrue(hasLoadItems,
                      "operationFinished must trigger reload via loadItems")
    }

    // MARK: - makeEntryOperationsCommandContext: Uses entryViewLayout.entries

    func testCommandContextUsesEntryViewLayoutEntries() {
        let entry = EntryModel.temporaryFolder(id: "/tmp/file.txt", name: "file.txt")
        var state = makeInitialState()
        state.entryViewLayout.entries = [entry]
        state.entryViewLayout.selectedIds = [entry.id]

        let context = reducer.makeEntryOperationsCommandContext(state: state)

        XCTAssertEqual(context.displayItems.map(\.id), [entry.id],
                       "makeEntryOperationsCommandContext must read displayItems from entryViewLayout.entries")
        XCTAssertEqual(context.selectedIds, [entry.id])
    }

    // MARK: - Helpers

    private func makeInitialState() -> FileManagerContentState {
        var state = FileManagerContentState()
        state.navigation.seedInitialFolderPath("/tmp/voyager")
        return state
    }
}
