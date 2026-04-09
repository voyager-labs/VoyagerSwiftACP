import ComposableArchitecture
@testable import Voyager
import VoyagerEntitiesEntry
import VoyagerFeaturesEntryOperations
import XCTest

@MainActor
final class EntryViewLayoutCollectionPresentationReducerTests: XCTestCase {
    private func makeTestStore() -> TestStore<EntryViewLayoutState, EntryViewLayoutAction> {
        TestStore(initialState: EntryViewLayoutState()) {
            EntryViewLayoutFeature()
        }
    }

    func testSetCollectionModeUpdatesStateAndReapplies() async {
        let store = makeTestStore()

        let regularItem = EntryModel.temporaryFolder(id: "/tmp/regular.txt", name: "regular.txt")
        let collectionItem = EntryModel.temporaryFolder(id: "/tmp/col.txt", name: "col.txt")

        await store.send(.entryOperations(.loading(.itemsLoaded([regularItem])))) {
            $0.entryOperations.items = [regularItem]
            $0.entries = [regularItem]
        }
        await store.receive(.entryArrangements(.reapply))
        await store.receive(.entryArrangements(.delegate(.requestApply)))
        await store.receive(.entryArrangements(.apply(items: [regularItem], isCollectionMode: false)))
        await store.receive(.entryArrangements(.delegate(.applied(
            sortedItems: [regularItem],
            isCollectionMode: false,
        )))) {
            $0.entries = [regularItem]
        }

        await store.send(.internal(.setCollectionMode(true))) {
            $0.isCollectionMode = true
            $0.entries = []
        }
        await store.receive(.entryArrangements(.reapply))
        await store.receive(.entryArrangements(.delegate(.requestApply)))
        await store.receive(.entryArrangements(.apply(items: [], isCollectionMode: true)))
        await store.receive(.entryArrangements(.delegate(.applied(sortedItems: [], isCollectionMode: true))))

        await store.send(.internal(.setCollectionItems([collectionItem]))) {
            $0.collectionItems = [collectionItem]
            $0.entries = [collectionItem]
        }
        await store.receive(.entryArrangements(.reapply))
        await store.receive(.entryArrangements(.delegate(.requestApply)))
        await store.receive(.entryArrangements(.apply(items: [collectionItem], isCollectionMode: true)))
        await store.receive(.entryArrangements(.delegate(.applied(
            sortedItems: [collectionItem],
            isCollectionMode: true,
        )))) {
            $0.entries = [collectionItem]
        }
    }

    func testSetCollectionItemsUpdatesStateAndReapplies() async {
        let store = makeTestStore()

        let item1 = EntryModel.temporaryFolder(id: "/tmp/a.txt", name: "a.txt")
        let item2 = EntryModel.temporaryFolder(id: "/tmp/b.txt", name: "b.txt")

        await store.send(.internal(.setCollectionItems([item1, item2]))) {
            $0.collectionItems = [item1, item2]
            $0.entries = []
        }
        await store.receive(.entryArrangements(.reapply))
        await store.receive(.entryArrangements(.delegate(.requestApply)))
        await store.receive(.entryArrangements(.apply(items: [], isCollectionMode: false)))
        await store.receive(.entryArrangements(.delegate(.applied(sortedItems: [], isCollectionMode: false))))
    }

    func testSetCollectionItemsWithCollectionModeOn() async {
        let store = makeTestStore()

        let item = EntryModel.temporaryFolder(id: "/tmp/col.txt", name: "col.txt")

        await store.send(.internal(.setCollectionMode(true))) {
            $0.isCollectionMode = true
            $0.entries = []
        }
        await store.receive(.entryArrangements(.reapply))
        await store.receive(.entryArrangements(.delegate(.requestApply)))
        await store.receive(.entryArrangements(.apply(items: [], isCollectionMode: true)))
        await store.receive(.entryArrangements(.delegate(.applied(sortedItems: [], isCollectionMode: true))))

        await store.send(.internal(.setCollectionItems([item]))) {
            $0.collectionItems = [item]
            $0.entries = [item]
        }
        await store.receive(.entryArrangements(.reapply))
        await store.receive(.entryArrangements(.delegate(.requestApply)))
        await store.receive(.entryArrangements(.apply(items: [item], isCollectionMode: true)))
        await store.receive(.entryArrangements(.delegate(.applied(sortedItems: [item], isCollectionMode: true)))) {
            $0.entries = [item]
        }
    }

    func testClearCollectionPresentationFallsBackToRegularSource() async {
        let store = makeTestStore()

        let regularItem = EntryModel.temporaryFolder(id: "/tmp/regular.txt", name: "regular.txt")
        let collectionItem = EntryModel.temporaryFolder(id: "/tmp/col.txt", name: "col.txt")

        await store.send(.entryOperations(.loading(.itemsLoaded([regularItem])))) {
            $0.entryOperations.items = [regularItem]
            $0.entries = [regularItem]
        }
        await store.receive(.entryArrangements(.reapply))
        await store.receive(.entryArrangements(.delegate(.requestApply)))
        await store.receive(.entryArrangements(.apply(items: [regularItem], isCollectionMode: false)))
        await store.receive(.entryArrangements(.delegate(.applied(
            sortedItems: [regularItem],
            isCollectionMode: false,
        )))) {
            $0.entries = [regularItem]
        }

        await store.send(.internal(.setCollectionMode(true))) {
            $0.isCollectionMode = true
            $0.entries = []
        }
        await store.receive(.entryArrangements(.reapply))
        await store.receive(.entryArrangements(.delegate(.requestApply)))
        await store.receive(.entryArrangements(.apply(items: [], isCollectionMode: true)))
        await store.receive(.entryArrangements(.delegate(.applied(sortedItems: [], isCollectionMode: true))))

        await store.send(.internal(.setCollectionItems([collectionItem]))) {
            $0.collectionItems = [collectionItem]
            $0.entries = [collectionItem]
        }
        await store.receive(.entryArrangements(.reapply))
        await store.receive(.entryArrangements(.delegate(.requestApply)))
        await store.receive(.entryArrangements(.apply(items: [collectionItem], isCollectionMode: true)))
        await store.receive(.entryArrangements(.delegate(.applied(
            sortedItems: [collectionItem],
            isCollectionMode: true,
        )))) {
            $0.entries = [collectionItem]
        }

        await store.send(.internal(.clearCollectionPresentation)) {
            $0.isCollectionMode = false
            $0.collectionItems = []
            $0.entries = [regularItem]
        }
        await store.receive(.entryArrangements(.reapply))
        await store.receive(.entryArrangements(.delegate(.requestApply)))
        await store.receive(.entryArrangements(.apply(items: [regularItem], isCollectionMode: false)))
        await store.receive(.entryArrangements(.delegate(.applied(
            sortedItems: [regularItem],
            isCollectionMode: false,
        )))) {
            $0.entries = [regularItem]
        }
    }

    func testReapplyUsesDisplayOrderItemsSnapshot() async {
        let store = makeTestStore()

        let item = EntryModel.temporaryFolder(id: "/tmp/a.txt", name: "a.txt")

        await store.send(.internal(.setCollectionMode(true))) {
            $0.isCollectionMode = true
            $0.entries = []
        }
        await store.receive(.entryArrangements(.reapply))
        await store.receive(.entryArrangements(.delegate(.requestApply)))
        await store.receive(.entryArrangements(.apply(items: [], isCollectionMode: true)))
        await store.receive(.entryArrangements(.delegate(.applied(sortedItems: [], isCollectionMode: true))))

        await store.send(.internal(.setCollectionItems([item]))) {
            $0.collectionItems = [item]
            $0.entries = [item]
        }
        await store.receive(.entryArrangements(.reapply))
        await store.receive(.entryArrangements(.delegate(.requestApply)))
        await store.receive(.entryArrangements(.apply(items: [item], isCollectionMode: true)))
        await store.receive(.entryArrangements(.delegate(.applied(sortedItems: [item], isCollectionMode: true)))) {
            $0.entries = [item]
        }

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
        await store.receive(.entryArrangements(.reapply))
        await store.receive(.entryArrangements(.delegate(.requestApply)))
        await store.receive(.entryArrangements(.apply(items: [item], isCollectionMode: false)))
        await store.receive(.entryArrangements(.delegate(.applied(sortedItems: [item], isCollectionMode: false)))) {
            $0.entries = [item]
        }

        let state = store.state
        XCTAssertFalse(state.isCollectionMode)
        XCTAssertEqual(state.entries.map(\.id), [item.id])
    }
}
