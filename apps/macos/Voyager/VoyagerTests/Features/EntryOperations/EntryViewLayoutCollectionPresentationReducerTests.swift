import ComposableArchitecture
@testable import Voyager
import VoyagerEntitiesEntry
import VoyagerFeaturesEntryOperations
@testable import VoyagerWidgetsEntryViewLayout
import XCTest

@MainActor
final class EntryViewLayoutCollectionPresentationReducerTests: XCTestCase {
    private func makeTestStore() -> TestStore<EntryViewLayoutState, EntryViewLayoutAction> {
        TestStore(initialState: EntryViewLayoutState()) {
            EntryViewLayoutFeature()
        }
    }

    private func receiveReapplySequence(
        from store: TestStore<EntryViewLayoutState, EntryViewLayoutAction>,
        applyItems: [EntryModel],
        isCollectionMode: Bool,
        resultingEntries: [EntryModel]? = nil,
    ) async {
        await store.receive { action in
            guard case .entryArrangements(.reapply) = action else { return false }
            return true
        }
        await store.receive { action in
            guard case .entryArrangements(.delegate(.requestApply)) = action else { return false }
            return true
        }
        await store.receive { action in
            guard case let .entryArrangements(.apply(items, mode)) = action else { return false }
            return items == applyItems && mode == isCollectionMode
        }
        await store.receive(
            { action in
                guard case let .entryArrangements(.delegate(.applied(sortedItems, mode))) = action else { return false }
                return sortedItems == applyItems && mode == isCollectionMode
            },
            assert: { state in
                if let resultingEntries {
                    state.entries = resultingEntries
                }
            },
        )
    }

    func testSetCollectionModeUpdatesStateAndReapplies() async {
        let store = makeTestStore()

        let regularItem = EntryModel.temporaryFolder(id: "/tmp/regular.txt", name: "regular.txt")
        let collectionItem = EntryModel.temporaryFolder(id: "/tmp/col.txt", name: "col.txt")

        await store.send(.entryOperations(.loading(.itemsLoaded([regularItem])))) {
            $0.entryOperations.items = [regularItem]
            $0.entries = [regularItem]
        }
        await receiveReapplySequence(
            from: store,
            applyItems: [regularItem],
            isCollectionMode: false,
            resultingEntries: [regularItem],
        )

        await store.send(.internal(.setCollectionMode(true))) {
            $0.isCollectionMode = true
            $0.entries = []
        }
        await receiveReapplySequence(
            from: store,
            applyItems: [],
            isCollectionMode: true,
        )

        await store.send(.internal(.setCollectionItems([collectionItem]))) {
            $0.collectionItems = [collectionItem]
            $0.entries = [collectionItem]
        }
        await receiveReapplySequence(
            from: store,
            applyItems: [collectionItem],
            isCollectionMode: true,
            resultingEntries: [collectionItem],
        )
    }

    func testSetCollectionItemsUpdatesStateAndReapplies() async {
        let store = makeTestStore()

        let item1 = EntryModel.temporaryFolder(id: "/tmp/a.txt", name: "a.txt")
        let item2 = EntryModel.temporaryFolder(id: "/tmp/b.txt", name: "b.txt")

        await store.send(.internal(.setCollectionItems([item1, item2]))) {
            $0.collectionItems = [item1, item2]
            $0.entries = []
        }
        await receiveReapplySequence(
            from: store,
            applyItems: [],
            isCollectionMode: false,
        )
    }

    func testSetCollectionItemsWithCollectionModeOn() async {
        let store = makeTestStore()

        let item = EntryModel.temporaryFolder(id: "/tmp/col.txt", name: "col.txt")

        await store.send(.internal(.setCollectionMode(true))) {
            $0.isCollectionMode = true
            $0.entries = []
        }
        await receiveReapplySequence(
            from: store,
            applyItems: [],
            isCollectionMode: true,
        )

        await store.send(.internal(.setCollectionItems([item]))) {
            $0.collectionItems = [item]
            $0.entries = [item]
        }
        await receiveReapplySequence(
            from: store,
            applyItems: [item],
            isCollectionMode: true,
            resultingEntries: [item],
        )
    }

    func testClearCollectionPresentationFallsBackToRegularSource() async {
        let store = makeTestStore()

        let regularItem = EntryModel.temporaryFolder(id: "/tmp/regular.txt", name: "regular.txt")
        let collectionItem = EntryModel.temporaryFolder(id: "/tmp/col.txt", name: "col.txt")

        await store.send(.entryOperations(.loading(.itemsLoaded([regularItem])))) {
            $0.entryOperations.items = [regularItem]
            $0.entries = [regularItem]
        }
        await receiveReapplySequence(
            from: store,
            applyItems: [regularItem],
            isCollectionMode: false,
            resultingEntries: [regularItem],
        )

        await store.send(.internal(.setCollectionMode(true))) {
            $0.isCollectionMode = true
            $0.entries = []
        }
        await receiveReapplySequence(
            from: store,
            applyItems: [],
            isCollectionMode: true,
        )

        await store.send(.internal(.setCollectionItems([collectionItem]))) {
            $0.collectionItems = [collectionItem]
            $0.entries = [collectionItem]
        }
        await receiveReapplySequence(
            from: store,
            applyItems: [collectionItem],
            isCollectionMode: true,
            resultingEntries: [collectionItem],
        )

        await store.send(.internal(.clearCollectionPresentation)) {
            $0.isCollectionMode = false
            $0.collectionItems = []
            $0.entries = [regularItem]
        }
        await receiveReapplySequence(
            from: store,
            applyItems: [regularItem],
            isCollectionMode: false,
            resultingEntries: [regularItem],
        )
    }

    func testReapplyUsesDisplayOrderItemsSnapshot() async {
        let store = makeTestStore()

        let item = EntryModel.temporaryFolder(id: "/tmp/a.txt", name: "a.txt")

        await store.send(.internal(.setCollectionMode(true))) {
            $0.isCollectionMode = true
            $0.entries = []
        }
        await receiveReapplySequence(
            from: store,
            applyItems: [],
            isCollectionMode: true,
        )

        await store.send(.internal(.setCollectionItems([item]))) {
            $0.collectionItems = [item]
            $0.entries = [item]
        }
        await receiveReapplySequence(
            from: store,
            applyItems: [item],
            isCollectionMode: true,
            resultingEntries: [item],
        )

        let state = store.state
        XCTAssertTrue(state.isCollectionMode)
        XCTAssertEqual(state.entries.map(\.id), [item.id])
    }

    func testEntryOperationsItemsLoadedReusesSameHelperPath() async {
        let store = makeTestStore()

        let item = EntryModel.temporaryFolder(id: "/tmp/test.txt", name: "test.txt")

        await store.send(.entryOperations(.loading(.itemsLoaded([item])))) {
            $0.entryOperations.items = [item]
            $0.entries = [item]
        }
        await receiveReapplySequence(
            from: store,
            applyItems: [item],
            isCollectionMode: false,
            resultingEntries: [item],
        )

        let state = store.state
        XCTAssertFalse(state.isCollectionMode)
        XCTAssertEqual(state.entries.map(\.id), [item.id])
    }
}
