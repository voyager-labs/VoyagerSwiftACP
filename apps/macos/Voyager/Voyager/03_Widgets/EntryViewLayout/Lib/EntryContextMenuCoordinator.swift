import AppKit
import ComposableArchitecture
import CoreGraphics

final class EntryContextMenuCoordinator: NSObject {
    private let store: StoreOf<EntryViewLayoutFeature>
    private let rowEntry: EntryModel?

    init(store: StoreOf<EntryViewLayoutFeature>, rowEntry: EntryModel? = nil) {
        self.store = store
        self.rowEntry = rowEntry
    }

    @objc
    func contextMenuOpenSelectedItem() {
        store.send(.delegate(.saveScrollOffset(.zero, forPath: store.state.currentPath)))
        store.send(.delegate(.executeCommand(.navigation(.openSelectedItem))))
    }

    @objc
    func contextMenuOpenSelectedItemInNewTab(_ sender: NSMenuItem) {
        guard let path = sender.representedObject as? String else { return }
        store.send(.delegate(.openPathInNewTab(path)))
    }

    @objc
    func contextMenuQuickLookSelectedItem() {
        store.send(.delegate(.executeCommand(.navigation(.quickLookSelectedItem))))
    }

    @objc
    func contextMenuGetInfoForSelectedItems() {
        store.send(.delegate(.executeCommand(.navigation(.getInfoForSelectedItems))))
    }

    @objc
    func contextMenuShareSelectedItems() {
        store.send(.delegate(.executeCommand(.navigation(.shareSelectedItems(anchor: nil)))))
    }

    @objc
    func contextMenuRevealSelectedItemsInFinder() {
        store.send(.delegate(.executeCommand(.navigation(.revealSelectedItemsInFinder))))
    }

    @objc
    func contextMenuCopySelectedItems() {
        store.send(.delegate(.executeCommand(.clipboard(.copySelectedItems))))
    }

    @objc
    func contextMenuCopySelectedAbsolutePaths() {
        store.send(.delegate(.executeCommand(.clipboard(.copySelectedAbsolutePaths))))
    }

    @objc
    func contextMenuCopySelectedURLs() {
        store.send(.delegate(.executeCommand(.clipboard(.copySelectedURLs))))
    }

    @objc
    func contextMenuCutSelectedItems() {
        store.send(.delegate(.executeCommand(.clipboard(.cutSelectedItems))))
    }

    @objc
    func contextMenuPasteItems() {
        store.send(.delegate(.executeCommand(.clipboard(.pasteItems(destinationPath: store.state.currentPath)))))
    }

    @objc
    func contextMenuStartRename() {
        if let rowEntry {
            store.send(.delegate(.startRename(id: rowEntry.id, text: rowEntry.name)))
            return
        }

        let selectedEntries = store.state.entries.filter { store.state.selectedIds.contains($0.id) }
        guard selectedEntries.count == 1, let item = selectedEntries.first else { return }
        store.send(.delegate(.startRename(id: item.id, text: item.name)))
    }

    @objc
    func contextMenuDuplicateSelectedItems() {
        store.send(.delegate(.executeCommand(.clipboard(.duplicateSelectedItems))))
    }

    @objc
    func contextMenuCreateAliasForSelectedItems() {
        store.send(.delegate(.executeCommand(.mutation(.createAliasForSelectedItems))))
    }

    @objc
    func contextMenuCompressSelectedItems() {
        store.send(.delegate(.executeCommand(.mutation(.compressSelectedItems))))
    }

    @objc
    func contextMenuExtractSelectedItem() {
        store.send(.delegate(.executeCommand(.mutation(.extractSelectedItem))))
    }

    @objc
    func contextMenuMoveSelectedItemsToTrash() {
        store.send(.delegate(.executeCommand(.mutation(.moveSelectedItemsToTrash))))
    }

    @objc
    func contextMenuDeleteSelectedItemsImmediately() {
        store.send(.delegate(.executeCommand(.mutation(.deleteSelectedItemsImmediately))))
    }

    @objc
    func contextMenuPutBackSelectedItems() {
        store.send(.delegate(.executeCommand(.mutation(.putBackSelectedItems))))
    }

    @objc
    func contextMenuEmptyTrash() {
        store.send(.delegate(.executeCommand(.mutation(.emptyTrash))))
    }

    @objc
    func contextMenuOpenWithOther() {
        store.send(.delegate(.executeCommand(.navigation(.openWithSelectedItem(
            bundleID: nil,
            shouldSetAsDefault: false,
        )))))
    }

    @objc
    func contextMenuOpenWithApp(_ sender: NSMenuItem) {
        let bundleID = sender.representedObject as? String
        store.send(.delegate(.executeCommand(.navigation(.openWithSelectedItem(
            bundleID: bundleID,
            shouldSetAsDefault: false,
        )))))
    }

    @objc
    func contextMenuToggleTag(_ sender: NSMenuItem) {
        guard let tagName = sender.representedObject as? String else { return }
        store.send(.delegate(.executeCommand(.mutation(.toggleTagForSelectedItem(tag: tagName)))))
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
