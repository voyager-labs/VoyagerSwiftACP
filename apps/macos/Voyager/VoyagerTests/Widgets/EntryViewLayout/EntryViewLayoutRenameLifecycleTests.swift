import ComposableArchitecture
import Foundation
@testable import Voyager
import XCTest

@MainActor
final class EntryViewLayoutRenameLifecycleTests: XCTestCase {
    func testSelectionChangeCancelsRenameWhenSelectedItemChanges() async {
        let renamingItem = makeEntry(name: "renaming", fullPath: "/tmp/renaming.txt")
        let otherItem = makeEntry(name: "other", fullPath: "/tmp/other.txt")

        var initialState = EntryViewLayoutState()
        initialState.entries = [renamingItem, otherItem]
        initialState.selectedIds = [renamingItem.id]
        initialState.entryOperations.loadingContext.items = IdentifiedArray(uniqueElements: [renamingItem, otherItem])
        initialState.entryOperations.renamingItemId = renamingItem.id
        initialState.entryOperations.renamingText = "renaming"

        let store = TestStore(initialState: initialState) {
            EntryViewLayoutFeature()
        }
        store.exhaustivity = .off

        await store.send(.internal(.setSelectionState(
            ids: [otherItem.id],
            lastSelectedId: otherItem.id,
            rangeAnchorId: otherItem.id,
            shouldScrollToSelection: true,
        )))

        await store.receive(.entryOperations(.edit(.cancelRename)))

        await store.finish()
    }

    func testSelectionChangeCancelsRenameWhenSelectionBecomesEmpty() async {
        let renamingItem = makeEntry(name: "renaming", fullPath: "/tmp/renaming.txt")

        var initialState = EntryViewLayoutState()
        initialState.entries = [renamingItem]
        initialState.selectedIds = [renamingItem.id]
        initialState.entryOperations.loadingContext.items = IdentifiedArray(uniqueElements: [renamingItem])
        initialState.entryOperations.renamingItemId = renamingItem.id
        initialState.entryOperations.renamingText = "renaming"

        let store = TestStore(initialState: initialState) {
            EntryViewLayoutFeature()
        }
        store.exhaustivity = .off

        await store.send(.internal(.setSelectionState(
            ids: [],
            lastSelectedId: nil,
            rangeAnchorId: nil,
            shouldScrollToSelection: false,
        )))

        await store.receive(.entryOperations(.edit(.cancelRename)))

        await store.finish()
    }

    func testSelectionChangeCancelsRenameWhenSelectionBecomesMultiSelect() async {
        let renamingItem = makeEntry(name: "renaming", fullPath: "/tmp/renaming.txt")
        let otherItem = makeEntry(name: "other", fullPath: "/tmp/other.txt")

        var initialState = EntryViewLayoutState()
        initialState.entries = [renamingItem, otherItem]
        initialState.selectedIds = [renamingItem.id]
        initialState.entryOperations.loadingContext.items = IdentifiedArray(uniqueElements: [renamingItem, otherItem])
        initialState.entryOperations.renamingItemId = renamingItem.id
        initialState.entryOperations.renamingText = "renaming"

        let store = TestStore(initialState: initialState) {
            EntryViewLayoutFeature()
        }
        store.exhaustivity = .off

        await store.send(.internal(.setSelectionState(
            ids: [renamingItem.id, otherItem.id],
            lastSelectedId: otherItem.id,
            rangeAnchorId: renamingItem.id,
            shouldScrollToSelection: true,
        )))

        await store.receive(.entryOperations(.edit(.cancelRename)))

        await store.finish()
    }

    func testSelectionChangePreservesRenameWhenSameSingleItemRemainsSelected() async {
        let renamingItem = makeEntry(name: "renaming", fullPath: "/tmp/renaming.txt")
        let otherItem = makeEntry(name: "other", fullPath: "/tmp/other.txt")

        var initialState = EntryViewLayoutState()
        initialState.entries = [renamingItem, otherItem]
        initialState.selectedIds = [renamingItem.id]
        initialState.entryOperations.loadingContext.items = IdentifiedArray(uniqueElements: [renamingItem, otherItem])
        initialState.entryOperations.renamingItemId = renamingItem.id
        initialState.entryOperations.renamingText = "renaming"

        let store = TestStore(initialState: initialState) {
            EntryViewLayoutFeature()
        }

        await store.send(.internal(.setSelectionState(
            ids: [renamingItem.id],
            lastSelectedId: renamingItem.id,
            rangeAnchorId: renamingItem.id,
            shouldScrollToSelection: false,
        ))) { state in
            XCTAssertEqual(state.selectedIds, [renamingItem.id])
            XCTAssertEqual(state.entryOperations.renamingItemId, renamingItem.id)
            XCTAssertEqual(state.entryOperations.renamingText, "renaming")
        }

        await store.finish()
    }

    func testSelectionChangeDoesNothingWhenNoRenameActive() async {
        let item1 = makeEntry(name: "item1", fullPath: "/tmp/item1.txt")
        let item2 = makeEntry(name: "item2", fullPath: "/tmp/item2.txt")

        var initialState = EntryViewLayoutState()
        initialState.entries = [item1, item2]
        initialState.selectedIds = [item1.id]
        initialState.entryOperations.loadingContext.items = IdentifiedArray(uniqueElements: [item1, item2])

        let store = TestStore(initialState: initialState) {
            EntryViewLayoutFeature()
        }

        await store.send(.internal(.setSelectionState(
            ids: [item2.id],
            lastSelectedId: item2.id,
            rangeAnchorId: item2.id,
            shouldScrollToSelection: true,
        ))) { state in
            XCTAssertEqual(state.selectedIds, [item2.id])
            XCTAssertNil(state.entryOperations.renamingItemId)
        }

        await store.finish()
    }

    private func makeEntry(
        name: String,
        fullPath: String,
        isFolder: Bool = false,
        fileExtension: String = "txt",
    ) -> EntryModel {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        return EntryModel(
            name: name,
            fullPath: fullPath,
            isFolder: isFolder,
            isHidden: false,
            size: 1,
            modifiedDate: date,
            fileExtension: fileExtension,
            facets: EntryFacets(
                createdDate: date,
                addedDate: date,
                lastOpenedDate: nil,
                kind: isFolder ? "Folder" : "Text",
                creatorApplication: nil,
                tags: nil,
                supplementaryMetadata: nil,
            ),
        )
    }
}
