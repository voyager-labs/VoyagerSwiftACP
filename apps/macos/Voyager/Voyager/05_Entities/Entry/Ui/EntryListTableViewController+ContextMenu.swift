import AppKit
import ComposableArchitecture

extension EntryListTableViewController: EntryListTableViewContextMenuProviding {
    func contextMenu(forRow row: Int?, event _: NSEvent) -> NSMenu {
        updateContextMenuAnchor(forRow: row)

        let menu = NSMenu()
        let selectedIds = store.state.entries.selectedIds

        menu.addItem(withTitle: "Open", action: #selector(contextMenuOpenSelectedItem), keyEquivalent: "")
        menu.addItem(withTitle: "Quick Look", action: #selector(contextMenuQuickLookSelectedItem), keyEquivalent: "")
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "Get Info", action: #selector(contextMenuGetInfoForSelectedItems), keyEquivalent: "")
        menu.addItem(withTitle: "Share…", action: #selector(contextMenuShareSelectedItems), keyEquivalent: "")
        menu.addItem(
            withTitle: "Reveal in Finder",
            action: #selector(contextMenuRevealSelectedItemsInFinder),
            keyEquivalent: "",
        )
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "Copy", action: #selector(contextMenuCopySelectedItems), keyEquivalent: "")
        menu.addItem(withTitle: "Paste", action: #selector(contextMenuPasteItems), keyEquivalent: "")
        menu.addItem(NSMenuItem.separator())

        let renameItem = NSMenuItem(title: "Rename", action: #selector(contextMenuStartRename), keyEquivalent: "")
        renameItem.isEnabled = selectedIds.count == 1
        menu.addItem(renameItem)

        menu.addItem(
            withTitle: "Move to Trash",
            action: #selector(contextMenuMoveSelectedItemsToTrash),
            keyEquivalent: "",
        )
        return menu
    }
}

private extension EntryListTableViewController {
    @objc
    func contextMenuOpenSelectedItem() {
        fsStore.send(.openSelectedItem)
    }

    @objc
    func contextMenuQuickLookSelectedItem() {
        fsStore.send(.quickLookSelectedItem)
    }

    @objc
    func contextMenuGetInfoForSelectedItems() {
        fsStore.send(.getInfoForSelectedItems)
    }

    @objc
    func contextMenuShareSelectedItems() {
        fsStore.send(.shareSelectedItems(anchor: contextMenuAnchor))
    }

    @objc
    func contextMenuRevealSelectedItemsInFinder() {
        fsStore.send(.revealSelectedItemsInFinder)
    }

    @objc
    func contextMenuCopySelectedItems() {
        fsStore.send(.copySelectedItems)
    }

    @objc
    func contextMenuPasteItems() {
        fsStore.send(.pasteItems(destinationPath: store.state.currentPath))
    }

    @objc
    func contextMenuStartRename() {
        guard let id = store.state.entries.selectedIds.first else { return }
        fsStore.send(.startRename(id: id))
    }

    @objc
    func contextMenuMoveSelectedItemsToTrash() {
        fsStore.send(.moveSelectedItemsToTrash)
    }
}
