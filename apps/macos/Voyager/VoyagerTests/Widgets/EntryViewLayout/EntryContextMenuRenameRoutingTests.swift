import ComposableArchitecture
import Foundation
@testable import Voyager
import VoyagerEntitiesEntry
import VoyagerFeaturesEntryOperations
import XCTest

@MainActor
final class EntryContextMenuRenameRoutingTests: XCTestCase {
    // MARK: - Helpers

    private final class ActionRecorder {
        var actions: [EntryViewLayoutAction] = []
    }

    private func makeStore(
        initialState: EntryViewLayoutState,
        recorder: ActionRecorder,
    ) -> StoreOf<EntryViewLayoutFeature> {
        Store(initialState: initialState) {
            Reduce { _, action in
                recorder.actions.append(action)
                return .none
            }
        }
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

    // MARK: - contextMenuStartRename Tests

    func testContextMenuStartRenameUsesRowEntryWhenPresent() {
        let rowEntry = makeEntry(name: "rowItem", fullPath: "/tmp/rowItem.txt")
        let selectedItem = makeEntry(name: "selectedItem", fullPath: "/tmp/selectedItem.txt")

        var initialState = EntryViewLayoutState()
        initialState.entries = [rowEntry, selectedItem]
        initialState.selectedIds = [selectedItem.id]
        initialState.entryOperations.loadingContext.items = IdentifiedArray(uniqueElements: [rowEntry, selectedItem])

        let recorder = ActionRecorder()
        let store = makeStore(initialState: initialState, recorder: recorder)

        let coordinator = EntryContextMenuCoordinator(
            store: store,
            rowEntry: rowEntry,
        )

        coordinator.contextMenuStartRename()

        XCTAssertEqual(recorder.actions.count, 1)
        guard recorder.actions.count == 1 else { return }
        if case let .delegate(.startRename(id, text)) = recorder.actions[0] {
            XCTAssertEqual(id, rowEntry.id)
            XCTAssertEqual(text, rowEntry.name)
        } else {
            XCTFail("Expected .delegate(.startRename) but got \(recorder.actions[0])")
        }
    }

    func testContextMenuStartRenameUsesSingleSelectedItemWhenNoRowEntry() {
        let selectedItem = makeEntry(name: "selectedItem", fullPath: "/tmp/selectedItem.txt")
        let unselectedItem = makeEntry(name: "unselectedItem", fullPath: "/tmp/unselectedItem.txt")

        var initialState = EntryViewLayoutState()
        initialState.entries = [selectedItem, unselectedItem]
        initialState.selectedIds = [selectedItem.id]
        initialState.entryOperations.loadingContext.items = IdentifiedArray(uniqueElements: [
            selectedItem,
            unselectedItem,
        ])

        let recorder = ActionRecorder()
        let store = makeStore(initialState: initialState, recorder: recorder)

        let coordinator = EntryContextMenuCoordinator(
            store: store,
            rowEntry: nil,
        )

        coordinator.contextMenuStartRename()

        XCTAssertEqual(recorder.actions.count, 1)
        guard recorder.actions.count == 1 else { return }
        if case let .delegate(.startRename(id, text)) = recorder.actions[0] {
            XCTAssertEqual(id, selectedItem.id)
            XCTAssertEqual(text, selectedItem.name)
        } else {
            XCTFail("Expected .delegate(.startRename) but got \(recorder.actions[0])")
        }
    }

    func testContextMenuStartRenameDoesNothingForMultiSelectionWithoutRowEntry() {
        let item1 = makeEntry(name: "item1", fullPath: "/tmp/item1.txt")
        let item2 = makeEntry(name: "item2", fullPath: "/tmp/item2.txt")

        var initialState = EntryViewLayoutState()
        initialState.entries = [item1, item2]
        initialState.selectedIds = [item1.id, item2.id]
        initialState.entryOperations.loadingContext.items = IdentifiedArray(uniqueElements: [item1, item2])

        let recorder = ActionRecorder()
        let store = makeStore(initialState: initialState, recorder: recorder)

        let coordinator = EntryContextMenuCoordinator(
            store: store,
            rowEntry: nil,
        )

        coordinator.contextMenuStartRename()

        XCTAssertTrue(recorder.actions.isEmpty, "No actions should be sent for multi-selection without rowEntry")
    }

    // MARK: - sendWithSelection Tests

    func testSendWithSelectionReseatsSelectionBeforeRenameAction() {
        let clickedItem = makeEntry(name: "clickedItem", fullPath: "/tmp/clickedItem.txt")
        let otherItem = makeEntry(name: "otherItem", fullPath: "/tmp/otherItem.txt")

        var initialState = EntryViewLayoutState()
        initialState.entries = [clickedItem, otherItem]
        initialState.selectedIds = [otherItem.id]
        initialState.entryOperations.loadingContext.items = IdentifiedArray(uniqueElements: [clickedItem, otherItem])

        let recorder = ActionRecorder()
        let store = makeStore(initialState: initialState, recorder: recorder)

        var renameActionCalled = false

        EntryContextMenuCoordinator.sendWithSelection(
            clickedItem,
            selectedIds: store.state.selectedIds,
            entryViewLayoutStore: store,
        ) {
            renameActionCalled = true
        }

        guard recorder.actions.count == 1 else {
            XCTFail("Expected 1 action (selection reseat), got \(recorder.actions.count)")
            return
        }
        if case let .internal(.setSelectionState(ids, lastSelectedId, rangeAnchorId, shouldScrollToSelection)) =
            recorder.actions[0]
        {
            XCTAssertEqual(ids, [clickedItem.id])
            XCTAssertEqual(lastSelectedId, clickedItem.id)
            XCTAssertEqual(rangeAnchorId, clickedItem.id)
            XCTAssertFalse(shouldScrollToSelection)
        } else {
            XCTFail("Expected .internal(.setSelectionState) but got \(recorder.actions[0])")
        }

        XCTAssertTrue(renameActionCalled, "Rename action should be called after selection reseat")
    }

    func testSendWithSelectionDoesNotReseatWhenItemAlreadySelected() {
        let clickedItem = makeEntry(name: "clickedItem", fullPath: "/tmp/clickedItem.txt")
        let otherItem = makeEntry(name: "otherItem", fullPath: "/tmp/otherItem.txt")

        var initialState = EntryViewLayoutState()
        initialState.entries = [clickedItem, otherItem]
        initialState.selectedIds = [clickedItem.id]
        initialState.entryOperations.loadingContext.items = IdentifiedArray(uniqueElements: [clickedItem, otherItem])

        let recorder = ActionRecorder()
        let store = makeStore(initialState: initialState, recorder: recorder)

        var renameActionCalled = false

        EntryContextMenuCoordinator.sendWithSelection(
            clickedItem,
            selectedIds: store.state.selectedIds,
            entryViewLayoutStore: store,
        ) {
            renameActionCalled = true
        }

        XCTAssertTrue(recorder.actions.isEmpty, "No selection reseat should occur when item is already selected")
        XCTAssertTrue(renameActionCalled, "Rename action should be called without reseat")
    }
}
