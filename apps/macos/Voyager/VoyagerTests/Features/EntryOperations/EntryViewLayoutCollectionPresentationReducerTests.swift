import ComposableArchitecture
@testable import Voyager
import VoyagerEntitiesEntry
import VoyagerFeaturesContentPageNavigation
import VoyagerFeaturesEntryArrangements
import VoyagerFeaturesEntryOperations
import XCTest

@MainActor
/// 컬렉션 모드 리듀서 — 토글/항목 업데이트/재적용/정리 전이를 검증.
final class EntryViewLayoutCollectionReducerTests: XCTestCase {
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

    /// testSetCollectionModeUpdatesStateAndReapplies 테스트 동작을 검증한다.
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

    /// testSetCollectionItemsUpdatesStateAndReapplies 테스트 동작을 검증한다.
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

    /// testSetCollectionItemsWithCollectionModeOn 테스트 동작을 검증한다.
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

    /// testClearCollectionPresentationFallsBackToRegularSource 테스트 동작을 검증한다.
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

    /// testReapplyUsesDisplayOrderItemsSnapshot 테스트 동작을 검증한다.
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

    /// testEntryOperationsItemsLoadedReusesSameHelperPath 테스트 동작을 검증한다.
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

    /// testRemoveCollectionPathsPrunesItemsAndSelection 테스트 동작을 검증한다.
    func testRemoveCollectionPathsPrunesItemsAndSelection() async {
        let store = makeTestStore()

        let removedItem = EntryModel.temporaryFolder(id: "/tmp/a.txt", name: "a.txt")
        let keptItem = EntryModel.temporaryFolder(id: "/tmp/b.txt", name: "b.txt")

        await store.send(.internal(.setCollectionMode(true))) {
            $0.isCollectionMode = true
            $0.entries = []
        }
        await receiveReapplySequence(
            from: store,
            applyItems: [],
            isCollectionMode: true,
        )

        await store.send(.internal(.setCollectionItems([removedItem, keptItem]))) {
            $0.collectionItems = [removedItem, keptItem]
            $0.entries = [removedItem, keptItem]
        }
        await receiveReapplySequence(
            from: store,
            applyItems: [removedItem, keptItem],
            isCollectionMode: true,
            resultingEntries: [removedItem, keptItem],
        )

        await store.send(.internal(.setSelectionState(
            ids: [removedItem.id, keptItem.id],
            lastSelectedId: removedItem.id,
            rangeAnchorId: removedItem.id,
            shouldScrollToSelection: true,
        ))) {
            $0.selectedIds = [removedItem.id, keptItem.id]
            $0.lastSelectedId = removedItem.id
            $0.rangeAnchorId = removedItem.id
            $0.shouldScrollToSelection = true
        }

        await store.send(.internal(.removeCollectionPaths(["/tmp/a.txt"]))) {
            $0.collectionItems = [keptItem]
            $0.selectedIds = [keptItem.id]
            $0.lastSelectedId = keptItem.id
            $0.rangeAnchorId = keptItem.id
            $0.shouldScrollToSelection = false
            $0.entries = [keptItem]
        }
        await receiveReapplySequence(
            from: store,
            applyItems: [keptItem],
            isCollectionMode: true,
            resultingEntries: [keptItem],
        )
    }

    /// testAddCollectionPathsRestoresItemsWithoutDuplicatingExistingOnes 테스트 동작을 검증한다.
    func testAddCollectionPathsRestoresItemsWithoutDuplicatingExistingOnes() async {
        let store = makeTestStore()

        let existingItem = EntryModel.temporaryFolder(id: "/tmp/existing.txt", name: "existing.txt")
        let restoredItem = EntryModel.temporaryFolder(id: "/tmp/restored.txt", name: "restored.txt")

        await store.send(.internal(.setCollectionMode(true))) {
            $0.isCollectionMode = true
            $0.entries = []
        }
        await receiveReapplySequence(
            from: store,
            applyItems: [],
            isCollectionMode: true,
        )

        await store.send(.internal(.setCollectionItems([existingItem]))) {
            $0.collectionItems = [existingItem]
            $0.entries = [existingItem]
        }
        await receiveReapplySequence(
            from: store,
            applyItems: [existingItem],
            isCollectionMode: true,
            resultingEntries: [existingItem],
        )

        await store.send(.internal(.addCollectionPaths(["/tmp/restored.txt", "/tmp/existing.txt"]))) {
            $0.collectionItems = [existingItem, restoredItem]
            $0.entries = [existingItem, restoredItem]
        }
        await receiveReapplySequence(
            from: store,
            applyItems: [existingItem, restoredItem],
            isCollectionMode: true,
            resultingEntries: [existingItem, restoredItem],
        )
    }
}
