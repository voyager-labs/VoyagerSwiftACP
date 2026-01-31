import AppKit
import ComposableArchitecture
import IdentifiedCollections
import SwiftUI

extension EntryGridCollectionViewController: EntryGridCollectionViewMenuProviding {
    func contextMenu(for indexPath: IndexPath?, event: NSEvent) -> NSMenu {
        updateContextMenuAnchor(event)

        let menu = NSMenu()
        let rowEntry = entry(at: indexPath)
        let selectedIds = store.state.entries.selectedIds
        let selectedEntries = selectedEntries(fallback: rowEntry)
        let selectedCount = selectedIds.isEmpty ? (rowEntry == nil ? 0 : 1) : selectedIds.count

        addOpenItems(to: menu, rowEntry: rowEntry, selectedEntries: selectedEntries)
        addInfoItems(to: menu)
        addClipboardItems(to: menu)
        addRenameItems(to: menu, selectedCount: selectedCount)
        addDuplicateItems(to: menu)
        addCompressItems(to: menu, selectedEntries: selectedEntries)
        addTagsItems(to: menu, selectedEntries: selectedEntries)
        addTrashItems(to: menu, isTrashFolder: isTrashFolder)
        return menu
    }
}

private extension EntryGridCollectionViewController {
    func updateContextMenuAnchor(_ event: NSEvent) {
        if let window = view.window {
            let screenPoint = window.convertPoint(toScreen: event.locationInWindow)
            contextMenuAnchor = screenPoint
        } else {
            contextMenuAnchor = nil
        }
    }

    func addOpenItems(to menu: NSMenu, rowEntry: Entry?, selectedEntries: [Entry]) {
        menu.addItem(withTitle: "Open", action: #selector(contextMenuOpenSelectedItem), keyEquivalent: "")

        if let rowEntry, rowEntry.isDirectory {
            let openInNewTab = NSMenuItem(
                title: "Open in New Tab",
                action: #selector(contextMenuOpenSelectedItemInNewTab(_:)),
                keyEquivalent: "",
            )
            openInNewTab.representedObject = rowEntry.fullPath
            menu.addItem(openInNewTab)
        }

        if let openWithMenu = buildOpenWithMenu(selectedEntries: selectedEntries) {
            let openWithItem = NSMenuItem(title: "Open With", action: nil, keyEquivalent: "")
            openWithItem.submenu = openWithMenu
            menu.addItem(openWithItem)
        }

        menu.addItem(withTitle: "Quick Look", action: #selector(contextMenuQuickLookSelectedItem), keyEquivalent: "")
        menu.addItem(NSMenuItem.separator())
    }

    func addInfoItems(to menu: NSMenu) {
        menu.addItem(withTitle: "Get Info", action: #selector(contextMenuGetInfoForSelectedItems), keyEquivalent: "")
        menu.addItem(withTitle: "Share…", action: #selector(contextMenuShareSelectedItems), keyEquivalent: "")
        menu.addItem(
            withTitle: "Reveal in Finder",
            action: #selector(contextMenuRevealSelectedItemsInFinder),
            keyEquivalent: "",
        )
        menu.addItem(NSMenuItem.separator())
    }

    func addClipboardItems(to menu: NSMenu) {
        menu.addItem(withTitle: "Copy", action: #selector(contextMenuCopySelectedItems), keyEquivalent: "")
        menu.addItem(
            withTitle: "Copy Absolute Paths",
            action: #selector(contextMenuCopySelectedAbsolutePaths),
            keyEquivalent: "",
        )
        menu.addItem(withTitle: "Copy URLs", action: #selector(contextMenuCopySelectedURLs), keyEquivalent: "")
        menu.addItem(withTitle: "Cut", action: #selector(contextMenuCutSelectedItems), keyEquivalent: "")

        let pasteItem = NSMenuItem(title: "Paste", action: #selector(contextMenuPasteItems), keyEquivalent: "")
        pasteItem.isEnabled = !store.state.entries.clipboardItems.isEmpty
        menu.addItem(pasteItem)
        menu.addItem(NSMenuItem.separator())
    }

    func addRenameItems(to menu: NSMenu, selectedCount: Int) {
        let renameItem = NSMenuItem(title: "Rename", action: #selector(contextMenuStartRename), keyEquivalent: "")
        renameItem.isEnabled = selectedCount == 1
        menu.addItem(renameItem)
    }

    func addDuplicateItems(to menu: NSMenu) {
        menu.addItem(withTitle: "Duplicate", action: #selector(contextMenuDuplicateSelectedItems), keyEquivalent: "")
        menu.addItem(
            withTitle: "Make Alias",
            action: #selector(contextMenuCreateAliasForSelectedItems),
            keyEquivalent: "",
        )
        menu.addItem(NSMenuItem.separator())
    }

    func addCompressItems(to menu: NSMenu, selectedEntries: [Entry]) {
        let (showCompress, showExtract) = EntryContextMenuUtils
            .calculateCompressExtractOptions(selectedItems: IdentifiedArrayOf(uniqueElements: selectedEntries))
        if showCompress {
            menu.addItem(withTitle: "Compress", action: #selector(contextMenuCompressSelectedItems), keyEquivalent: "")
        }
        if showExtract {
            menu.addItem(withTitle: "Extract", action: #selector(contextMenuExtractSelectedItem), keyEquivalent: "")
        }
        if showCompress || showExtract {
            menu.addItem(NSMenuItem.separator())
        }
    }

    func addTagsItems(to menu: NSMenu, selectedEntries: [Entry]) {
        if let tagsMenu = buildTagsMenu(selectedEntries: selectedEntries) {
            let tagsItem = NSMenuItem(title: "Tags", action: nil, keyEquivalent: "")
            tagsItem.submenu = tagsMenu
            menu.addItem(tagsItem)
            menu.addItem(NSMenuItem.separator())
        }
    }

    func addTrashItems(to menu: NSMenu, isTrashFolder: Bool) {
        if isTrashFolder {
            menu.addItem(withTitle: "Put Back", action: #selector(contextMenuPutBackSelectedItems), keyEquivalent: "")
            menu.addItem(
                withTitle: "Delete Immediately",
                action: #selector(contextMenuDeleteSelectedItemsImmediately),
                keyEquivalent: "",
            )
            menu.addItem(NSMenuItem.separator())
            menu.addItem(withTitle: "Empty Trash", action: #selector(contextMenuEmptyTrash), keyEquivalent: "")
        } else {
            menu.addItem(
                withTitle: "Move to Trash",
                action: #selector(contextMenuMoveSelectedItemsToTrash),
                keyEquivalent: "",
            )
        }
    }

    @objc
    func contextMenuOpenSelectedItem() {
        saveScrollPosition()
        fsStore.send(.openSelectedItem)
    }

    @objc
    func contextMenuOpenSelectedItemInNewTab(_ sender: NSMenuItem) {
        guard let path = sender.representedObject as? String else { return }
        Task {
            _ = await fileManagerWindowClient.openWindow(path)
        }
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
    func contextMenuCopySelectedAbsolutePaths() {
        fsStore.send(.copySelectedAbsolutePaths)
    }

    @objc
    func contextMenuCopySelectedURLs() {
        fsStore.send(.copySelectedURLs)
    }

    @objc
    func contextMenuCutSelectedItems() {
        fsStore.send(.cutSelectedItems)
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

    @objc
    func contextMenuDeleteSelectedItemsImmediately() {
        fsStore.send(.deleteSelectedItemsImmediately)
    }

    @objc
    func contextMenuPutBackSelectedItems() {
        fsStore.send(.putBackSelectedItems)
    }

    @objc
    func contextMenuEmptyTrash() {
        fsStore.send(.emptyTrash)
    }

    @objc
    func contextMenuDuplicateSelectedItems() {
        fsStore.send(.duplicateSelectedItems)
    }

    @objc
    func contextMenuCreateAliasForSelectedItems() {
        fsStore.send(.createAliasForSelectedItems)
    }

    @objc
    func contextMenuCompressSelectedItems() {
        fsStore.send(.compressSelectedItems)
    }

    @objc
    func contextMenuExtractSelectedItem() {
        fsStore.send(.extractSelectedItem)
    }

    @objc
    func contextMenuOpenWithOther() {
        fsStore.send(.openWithSelectedItem(bundleID: nil, shouldSetAsDefault: false))
    }

    @objc
    func contextMenuOpenWithApp(_ sender: NSMenuItem) {
        let bundleID = sender.representedObject as? String
        fsStore.send(.openWithSelectedItem(bundleID: bundleID, shouldSetAsDefault: false))
    }

    @objc
    func contextMenuToggleTag(_ sender: NSMenuItem) {
        guard let tagName = sender.representedObject as? String else { return }
        fsStore.send(.toggleTagForSelectedItem(tag: tagName))
    }

    func buildTagsMenu(selectedEntries: [Entry]) -> NSMenu? {
        let tagNames = EntryTagUtils.getFavoriteTagNames()
        guard !tagNames.isEmpty else { return nil }

        let menu = NSMenu()
        for tagName in tagNames {
            let item = NSMenuItem(title: tagName, action: #selector(contextMenuToggleTag(_:)), keyEquivalent: "")
            item.representedObject = tagName
            if !selectedEntries.isEmpty {
                let allSelectedHaveTag = selectedEntries.allSatisfy { entry in
                    entry.tags?.contains(where: { $0.name == tagName }) == true
                }
                item.state = allSelectedHaveTag ? .on : .off
            }
            menu.addItem(item)
        }
        return menu
    }

    func buildOpenWithMenu(selectedEntries: [Entry]) -> NSMenu? {
        let selectedFiles = selectedEntries.filter { !$0.isDirectory }
        if selectedFiles.isEmpty {
            return nil
        }

        if selectedFiles.count > 1 {
            fsStore.send(.operations(.loadCommonApplicationsForFiles(files: selectedFiles)))
        } else if let file = selectedFiles.first {
            if fsStore.state.operations.applicationsForItems[file.fullPath] == nil {
                fsStore.send(.operations(.loadApplicationsForFile(file: file)))
            }
        }

        let menu = NSMenu()
        let otherItem = NSMenuItem(title: "Other…", action: #selector(contextMenuOpenWithOther), keyEquivalent: "")
        menu.addItem(otherItem)

        let applications: [ApplicationInfo] = if selectedFiles.count > 1 {
            fsStore.state.operations.commonApplicationsForSelectedFiles
        } else if let file = selectedFiles.first {
            fsStore.state.operations.applicationsForItems[file.fullPath] ?? []
        } else {
            []
        }

        if !applications.isEmpty {
            menu.addItem(NSMenuItem.separator())
            for app in applications {
                let appItem = NSMenuItem(
                    title: app.name,
                    action: #selector(contextMenuOpenWithApp(_:)),
                    keyEquivalent: "",
                )
                appItem.representedObject = app.bundleID
                if app.isDefault {
                    appItem.state = .on
                }
                menu.addItem(appItem)
            }
        }

        return menu
    }
}
