import ComposableArchitecture
import Foundation
@testable import Voyager
import XCTest

/// Tests for EntryContextMenuCoordinator rename routing behavior.
///
/// These tests verify that the context menu correctly follows the rename lifecycle policy:
/// 1. When `rowEntry` is provided, it's used for rename regardless of selection state
/// 2. When no `rowEntry`, falls back to single selected item
/// 3. Multi-selection without `rowEntry` does nothing
/// 4. `sendWithSelection` reseats selection before executing the action
@MainActor
final class EntryContextMenuRenameRoutingTests: XCTestCase {
    // MARK: - contextMenuStartRename Tests

    /// When rowEntry is provided, it should be used for rename even if selection is different.
    /// This is the primary path for right-click on unselected item -> rename.
    func testContextMenuStartRenameUsesRowEntryWhenPresent() async {
        let rowEntry = makeEntry(name: "rowItem", fullPath: "/tmp/rowItem.txt")
        let selectedItem = makeEntry(name: "selectedItem", fullPath: "/tmp/selectedItem.txt")

        var initialState = EntryViewLayoutState()
        initialState.entries = [rowEntry, selectedItem]
        initialState.selectedIds = [selectedItem.id]
        initialState.entryOperations.loadingContext.items = IdentifiedArray(uniqueElements: [rowEntry, selectedItem])

        let testStore = TestStore(initialState: initialState) {
            EntryViewLayoutFeature()
        }
        testStore.exhaustivity = .off

        let coordinator = EntryContextMenuCoordinator(
            store: testStore.store,
            rowEntry: rowEntry,
        )

        coordinator.contextMenuStartRename()

        await testStore.receive(.delegate(.startRename(id: rowEntry.id, text: rowEntry.name)))

        await testStore.finish()
    }

    /// When no rowEntry is provided and there's exactly one selected item, use that item for rename.
    /// This is the path for right-click on already-selected item -> rename.
    func testContextMenuStartRenameUsesSingleSelectedItemWhenNoRowEntry() async {
        let selectedItem = makeEntry(name: "selectedItem", fullPath: "/tmp/selectedItem.txt")
        let unselectedItem = makeEntry(name: "unselectedItem", fullPath: "/tmp/unselectedItem.txt")

        var initialState = EntryViewLayoutState()
        initialState.entries = [selectedItem, unselectedItem]
        initialState.selectedIds = [selectedItem.id]
        initialState.entryOperations.loadingContext.items = IdentifiedArray(uniqueElements: [
            selectedItem,
            unselectedItem,
        ])

        let testStore = TestStore(initialState: initialState) {
            EntryViewLayoutFeature()
        }
        testStore.exhaustivity = .off

        // No rowEntry provided
        let coordinator = EntryContextMenuCoordinator(
            store: testStore.store,
            rowEntry: nil,
        )

        coordinator.contextMenuStartRename()

        await testStore.receive(.delegate(.startRename(id: selectedItem.id, text: selectedItem.name)))

        await testStore.finish()
    }

    /// When no rowEntry and multi-selection, rename should not be triggered.
    /// This is the expected behavior: rename requires a single target.
    func testContextMenuStartRenameDoesNothingForMultiSelectionWithoutRowEntry() async {
        let item1 = makeEntry(name: "item1", fullPath: "/tmp/item1.txt")
        let item2 = makeEntry(name: "item2", fullPath: "/tmp/item2.txt")

        var initialState = EntryViewLayoutState()
        initialState.entries = [item1, item2]
        initialState.selectedIds = [item1.id, item2.id]
        initialState.entryOperations.loadingContext.items = IdentifiedArray(uniqueElements: [item1, item2])

        let testStore = TestStore(initialState: initialState) {
            EntryViewLayoutFeature()
        }
        testStore.exhaustivity = .off

        // No rowEntry provided, multi-selection active
        let coordinator = EntryContextMenuCoordinator(
            store: testStore.store,
            rowEntry: nil,
        )

        coordinator.contextMenuStartRename()

        // No action should be received - multi-selection without rowEntry does nothing
        await testStore.finish()
    }

    // MARK: - sendWithSelection Tests

    /// When the item is not in the current selection, sendWithSelection should reseat selection
    /// to only that item before executing the action.
    func testSendWithSelectionReseatsSelectionBeforeRenameAction() async {
        let clickedItem = makeEntry(name: "clickedItem", fullPath: "/tmp/clickedItem.txt")
        let otherItem = makeEntry(name: "otherItem", fullPath: "/tmp/otherItem.txt")

        var initialState = EntryViewLayoutState()
        initialState.entries = [clickedItem, otherItem]
        initialState.selectedIds = [otherItem.id]
        initialState.entryOperations.loadingContext.items = IdentifiedArray(uniqueElements: [clickedItem, otherItem])

        let testStore = TestStore(initialState: initialState) {
            EntryViewLayoutFeature()
        }
        testStore.exhaustivity = .off

        var renameActionCalled = false

        EntryContextMenuCoordinator.sendWithSelection(
            clickedItem,
            selectedIds: testStore.state.selectedIds,
            entryViewLayoutStore: testStore.store,
        ) {
            renameActionCalled = true
        }

        // Should first reseat selection
        await testStore.receive(.internal(.setSelectionState(
            ids: [clickedItem.id],
            lastSelectedId: clickedItem.id,
            rangeAnchorId: clickedItem.id,
            shouldScrollToSelection: false,
        )))

        await testStore.finish()

        // Verify the action was called after reseat
        XCTAssertTrue(renameActionCalled, "Rename action should be called after selection reseat")
    }

    /// When the item is already in selection, no reseat should occur.
    func testSendWithSelectionDoesNotReseatWhenItemAlreadySelected() async {
        let clickedItem = makeEntry(name: "clickedItem", fullPath: "/tmp/clickedItem.txt")
        let otherItem = makeEntry(name: "otherItem", fullPath: "/tmp/otherItem.txt")

        var initialState = EntryViewLayoutState()
        initialState.entries = [clickedItem, otherItem]
        initialState.selectedIds = [clickedItem.id] // clickedItem is already selected
        initialState.entryOperations.loadingContext.items = IdentifiedArray(uniqueElements: [clickedItem, otherItem])

        let testStore = TestStore(initialState: initialState) {
            EntryViewLayoutFeature()
        }

        var renameActionCalled = false

        EntryContextMenuCoordinator.sendWithSelection(
            clickedItem,
            selectedIds: testStore.state.selectedIds,
            entryViewLayoutStore: testStore.store,
        ) {
            renameActionCalled = true
        }

        // No selection reseat should occur - no actions expected
        await testStore.finish()

        // Verify the action was called immediately
        XCTAssertTrue(renameActionCalled, "Rename action should be called without reseat")
    }

    // MARK: - Helper Methods

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
