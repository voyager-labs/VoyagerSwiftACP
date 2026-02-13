import AppKit

enum EntryContextMenuBuilder {
    struct Configuration {
        let target: EntryContextMenuActionHandler
        let selectedCount: Int
        let rowEntryPathForOpenInNewTab: String?
        let canPaste: Bool
        let showCompress: Bool
        let showExtract: Bool
        let isTrashFolder: Bool
        let openWithApplications: [ApplicationInfo]
        let showOpenWith: Bool
        let tags: [EntryContextMenuTagItem]
    }

    static func makeMenu(configuration: Configuration) -> NSMenu {
        let menu = NSMenu()

        addOpenItems(to: menu, configuration: configuration)
        addInfoItems(to: menu, target: configuration.target)
        addClipboardItems(to: menu, configuration: configuration)
        addRenameItems(to: menu, configuration: configuration)
        addDuplicateItems(to: menu, target: configuration.target)
        addCompressItems(to: menu, configuration: configuration)
        addTagsItems(to: menu, configuration: configuration)
        addTrashItems(to: menu, configuration: configuration)

        return menu
    }

    private static func addOpenItems(to menu: NSMenu, configuration: Configuration) {
        menu.addItem(menuItem(
            title: "Open",
            action: #selector(EntryContextMenuActionHandler.contextMenuOpenSelectedItem),
            target: configuration.target,
        ))

        if let path = configuration.rowEntryPathForOpenInNewTab {
            let openInNewTab = menuItem(
                title: "Open in New Tab",
                action: #selector(EntryContextMenuActionHandler.contextMenuOpenSelectedItemInNewTab(_:)),
                target: configuration.target,
            )
            openInNewTab.representedObject = path
            menu.addItem(openInNewTab)
        }

        if configuration.showOpenWith {
            let openWithItem = NSMenuItem(title: "Open With", action: nil, keyEquivalent: "")
            openWithItem.submenu = buildOpenWithMenu(configuration: configuration)
            menu.addItem(openWithItem)
        }

        menu.addItem(menuItem(
            title: "Quick Look",
            action: #selector(EntryContextMenuActionHandler.contextMenuQuickLookSelectedItem),
            target: configuration.target,
        ))
        menu.addItem(NSMenuItem.separator())
    }

    private static func addInfoItems(to menu: NSMenu, target: EntryContextMenuActionHandler) {
        menu.addItem(menuItem(
            title: "Get Info",
            action: #selector(EntryContextMenuActionHandler.contextMenuGetInfoForSelectedItems),
            target: target,
        ))
        menu.addItem(menuItem(
            title: "Share…",
            action: #selector(EntryContextMenuActionHandler.contextMenuShareSelectedItems),
            target: target,
        ))
        menu.addItem(menuItem(
            title: "Reveal in Finder",
            action: #selector(EntryContextMenuActionHandler.contextMenuRevealSelectedItemsInFinder),
            target: target,
        ))
        menu.addItem(NSMenuItem.separator())
    }

    private static func addClipboardItems(to menu: NSMenu, configuration: Configuration) {
        menu.addItem(menuItem(
            title: "Copy",
            action: #selector(EntryContextMenuActionHandler.contextMenuCopySelectedItems),
            target: configuration.target,
        ))
        menu.addItem(menuItem(
            title: "Copy Absolute Paths",
            action: #selector(EntryContextMenuActionHandler.contextMenuCopySelectedAbsolutePaths),
            target: configuration.target,
        ))
        menu.addItem(menuItem(
            title: "Copy URLs",
            action: #selector(EntryContextMenuActionHandler.contextMenuCopySelectedURLs),
            target: configuration.target,
        ))
        menu.addItem(menuItem(
            title: "Cut",
            action: #selector(EntryContextMenuActionHandler.contextMenuCutSelectedItems),
            target: configuration.target,
        ))

        let pasteItem = menuItem(
            title: "Paste",
            action: #selector(EntryContextMenuActionHandler.contextMenuPasteItems),
            target: configuration.target,
        )
        pasteItem.isEnabled = configuration.canPaste
        menu.addItem(pasteItem)
        menu.addItem(NSMenuItem.separator())
    }

    private static func addRenameItems(to menu: NSMenu, configuration: Configuration) {
        let renameItem = menuItem(
            title: "Rename",
            action: #selector(EntryContextMenuActionHandler.contextMenuStartRename),
            target: configuration.target,
        )
        renameItem.isEnabled = configuration.selectedCount == 1
        menu.addItem(renameItem)
    }

    private static func addDuplicateItems(to menu: NSMenu, target: EntryContextMenuActionHandler) {
        menu.addItem(menuItem(
            title: "Duplicate",
            action: #selector(EntryContextMenuActionHandler.contextMenuDuplicateSelectedItems),
            target: target,
        ))
        menu.addItem(menuItem(
            title: "Make Alias",
            action: #selector(EntryContextMenuActionHandler.contextMenuCreateAliasForSelectedItems),
            target: target,
        ))
        menu.addItem(NSMenuItem.separator())
    }

    private static func addCompressItems(to menu: NSMenu, configuration: Configuration) {
        if configuration.showCompress {
            menu.addItem(menuItem(
                title: "Compress",
                action: #selector(EntryContextMenuActionHandler.contextMenuCompressSelectedItems),
                target: configuration.target,
            ))
        }
        if configuration.showExtract {
            menu.addItem(menuItem(
                title: "Extract",
                action: #selector(EntryContextMenuActionHandler.contextMenuExtractSelectedItem),
                target: configuration.target,
            ))
        }
        if configuration.showCompress || configuration.showExtract {
            menu.addItem(NSMenuItem.separator())
        }
    }

    private static func addTagsItems(to menu: NSMenu, configuration: Configuration) {
        guard !configuration.tags.isEmpty else { return }

        let tagsItem = NSMenuItem(title: "Tags…", action: nil, keyEquivalent: "")
        tagsItem.submenu = buildTagsMenu(configuration: configuration)
        menu.addItem(tagsItem)
        menu.addItem(NSMenuItem.separator())
    }

    private static func addTrashItems(to menu: NSMenu, configuration: Configuration) {
        if configuration.isTrashFolder {
            menu.addItem(menuItem(
                title: "Put Back",
                action: #selector(EntryContextMenuActionHandler.contextMenuPutBackSelectedItems),
                target: configuration.target,
            ))
            menu.addItem(menuItem(
                title: "Delete Immediately",
                action: #selector(EntryContextMenuActionHandler.contextMenuDeleteSelectedItemsImmediately),
                target: configuration.target,
            ))
            menu.addItem(NSMenuItem.separator())
            menu.addItem(menuItem(
                title: "Empty Trash",
                action: #selector(EntryContextMenuActionHandler.contextMenuEmptyTrash),
                target: configuration.target,
            ))
        } else {
            menu.addItem(menuItem(
                title: "Move to Trash",
                action: #selector(EntryContextMenuActionHandler.contextMenuMoveSelectedItemsToTrash),
                target: configuration.target,
            ))
        }
    }

    private static func buildOpenWithMenu(configuration: Configuration) -> NSMenu {
        let menu = NSMenu()

        menu.addItem(menuItem(
            title: "Other…",
            action: #selector(EntryContextMenuActionHandler.contextMenuOpenWithOther),
            target: configuration.target,
        ))

        if !configuration.openWithApplications.isEmpty {
            menu.addItem(NSMenuItem.separator())
            for app in configuration.openWithApplications {
                let item = menuItem(
                    title: app.name,
                    action: #selector(EntryContextMenuActionHandler.contextMenuOpenWithApp(_:)),
                    target: configuration.target,
                )
                item.representedObject = app.bundleID
                item.state = app.isDefault ? .on : .off
                menu.addItem(item)
            }
        }

        return menu
    }

    private static func buildTagsMenu(configuration: Configuration) -> NSMenu {
        let menu = NSMenu()

        for tag in configuration.tags {
            let item = menuItem(
                title: tag.name,
                action: #selector(EntryContextMenuActionHandler.contextMenuToggleTag(_:)),
                target: configuration.target,
            )
            item.representedObject = tag.name
            item.state = selectionStateValue(tag.state)
            item.image = tagDotImage(colorCode: tag.colorCode)
            menu.addItem(item)
        }

        return menu
    }

    private static func selectionStateValue(_ state: EntryContextMenuTagItem.SelectionState) -> NSControl.StateValue {
        switch state {
        case .on:
            .on
        case .off:
            .off
        case .mixed:
            .mixed
        }
    }

    private static func tagDotImage(colorCode: Int) -> NSImage {
        TagDotImageFactory.make(tagColor: TagColor(colorCode: colorCode), size: 11, inset: 1)
    }

    private static func menuItem(title: String, action: Selector, target: AnyObject) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = target
        return item
    }
}
