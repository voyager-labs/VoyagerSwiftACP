@preconcurrency import AppKit
import ComposableArchitecture
import CoreGraphics
import VoyagerEntitiesEntry
import VoyagerFeaturesEntryOperations

final class EntryContextMenuCoordinator: NSObject {
    private let store: StoreOf<EntryViewLayoutFeature>
    private let rowEntry: EntryModel?

    init(store: StoreOf<EntryViewLayoutFeature>, rowEntry: EntryModel? = nil) {
        self.store = store
        self.rowEntry = rowEntry
    }

    private func selectRowEntryIfNeeded() {
        guard let rowEntry, !store.state.selectedIds.contains(rowEntry.id) else { return }
        store.send(.internal(.setSelectionState(
            ids: [rowEntry.id],
            lastSelectedId: rowEntry.id,
            rangeAnchorId: rowEntry.id,
            shouldScrollToSelection: false,
        )))
    }

    private func executeCommand(_ command: EntryOperationsCommand) {
        selectRowEntryIfNeeded()
        store.send(.delegate(.executeCommand(command)))
    }

    private func startRename(_ item: EntryModel) {
        selectRowEntryIfNeeded()
        store.send(.delegate(.startRename(item: item, text: item.name)))
    }

    @objc
    func contextMenuOpenSelectedItem() {
        store.send(.delegate(.saveScrollOffset(.zero, forPath: store.state.currentPath)))
        executeCommand(.navigation(.openSelectedItem))
    }

    @objc
    func contextMenuOpenSelectedItemInNewTab(_ sender: NSMenuItem) {
        guard let path = sender.representedObject as? String else { return }
        store.send(.delegate(.openPathInNewTab(path)))
    }

    @objc
    func contextMenuQuickLookSelectedItem() {
        executeCommand(.navigation(.quickLookSelectedItem))
    }

    @objc
    func contextMenuGetInfoForSelectedItems() {
        executeCommand(.navigation(.getInfoForSelectedItems))
    }

    @objc
    func contextMenuShareSelectedItems() {
        executeCommand(.navigation(.shareSelectedItems(anchor: nil)))
    }

    @objc
    func contextMenuRevealSelectedItemsInFinder() {
        executeCommand(.navigation(.revealSelectedItemsInFinder))
    }

    @objc
    func contextMenuCopySelectedItems() {
        executeCommand(.clipboard(.copySelectedItems))
    }

    @objc
    func contextMenuCopySelectedAbsolutePaths() {
        executeCommand(.clipboard(.copySelectedAbsolutePaths))
    }

    @objc
    func contextMenuCopySelectedURLs() {
        executeCommand(.clipboard(.copySelectedURLs))
    }

    @objc
    func contextMenuCutSelectedItems() {
        executeCommand(.clipboard(.cutSelectedItems))
    }

    @objc
    func contextMenuPasteItems() {
        store.send(.delegate(.executeCommand(.clipboard(.pasteItems(destinationPath: store.state.currentPath)))))
    }

    @objc
    func contextMenuStartRename() {
        if let rowEntry {
            startRename(rowEntry)
            return
        }

        let selectedEntries = store.state.entries.filter { store.state.selectedIds.contains($0.id) }
        guard selectedEntries.count == 1, let item = selectedEntries.first else { return }
        store.send(.delegate(.startRename(item: item, text: item.name)))
    }

    @objc
    func contextMenuDuplicateSelectedItems() {
        executeCommand(.clipboard(.duplicateSelectedItems))
    }

    @objc
    func contextMenuCreateAliasForSelectedItems() {
        executeCommand(.mutation(.createAliasForSelectedItems))
    }

    @objc
    func contextMenuCompressSelectedItems() {
        executeCommand(.mutation(.compressSelectedItems))
    }

    @objc
    func contextMenuExtractSelectedItem() {
        executeCommand(.mutation(.extractSelectedItem))
    }

    @objc
    func contextMenuMoveSelectedItemsToTrash() {
        executeCommand(.mutation(.moveSelectedItemsToTrash))
    }

    @objc
    func contextMenuDeleteSelectedItemsImmediately() {
        executeCommand(.mutation(.deleteSelectedItemsImmediately))
    }

    @objc
    func contextMenuPutBackSelectedItems() {
        executeCommand(.mutation(.putBackSelectedItems))
    }

    @objc
    func contextMenuEmptyTrash() {
        store.send(.delegate(.executeCommand(.mutation(.emptyTrash))))
    }

    @objc
    func contextMenuOpenWithOther() {
        executeCommand(.navigation(.openWithSelectedItem(
            bundleID: nil,
            shouldSetAsDefault: false,
        )))
    }

    @objc
    func contextMenuOpenWithApp(_ sender: NSMenuItem) {
        let bundleID = sender.representedObject as? String
        executeCommand(.navigation(.openWithSelectedItem(
            bundleID: bundleID,
            shouldSetAsDefault: false,
        )))
    }

    @objc
    func contextMenuToggleTag(_ sender: NSMenuItem) {
        guard let tagName = sender.representedObject as? String else { return }
        executeCommand(.mutation(.toggleTagForSelectedItem(tag: tagName)))
    }
}

extension EntryContextMenuCoordinator {
    static func sendWithSelection(
        _ item: EntryModel,
        selectedIds: Set<EntryModel.ID>,
        entryViewLayoutStore: StoreOf<EntryViewLayoutFeature>,
        action: @escaping () -> Void,
    ) {
        if !selectedIds.contains(item.id) {
            entryViewLayoutStore.send(.internal(.setSelectionState(
                ids: [item.id],
                lastSelectedId: item.id,
                rangeAnchorId: item.id,
                shouldScrollToSelection: false,
            )))
        }
        action()
    }
}
