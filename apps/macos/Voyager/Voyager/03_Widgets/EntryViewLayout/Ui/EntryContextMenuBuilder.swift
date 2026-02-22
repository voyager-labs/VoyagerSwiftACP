import AppKit

enum EntryContextMenuBuilder {
    struct Input {
        let adapter: EntryViewLayoutAdapter
        let selectedIds: Set<String>
        let selectedEntries: [EntryModel]
        let rowEntry: EntryModel?
        let isTrashFolder: Bool
        let canPaste: Bool
        let currentPath: () -> String
        let selectedItemId: () -> String?
        let contextMenuAnchor: () -> CGPoint?
        let saveScrollPosition: () -> Void
    }

    struct Configuration {
        let target: EntryContextMenuCoordinator
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

    static func makeMenu(input: Input) -> (menu: NSMenu, coordinator: EntryContextMenuCoordinator) {
        let selectedCount = EntryContextMenuDataResolver.selectedCount(
            selectedIds: input.selectedIds,
            fallbackEntry: input.rowEntry,
        )

        let coordinator = EntryContextMenuCoordinator.make(context: .init(
            adapter: input.adapter,
            currentPath: input.currentPath,
            selectedItemId: input.selectedItemId,
            contextMenuAnchor: input.contextMenuAnchor,
            saveScrollPosition: input.saveScrollPosition,
        ))

        let (showCompress, showExtract) = EntryContextMenuDataResolver.resolveCompressExtract(
            selectedEntries: input.selectedEntries,
        )
        let (showOpenWith, openWithApplications) = EntryContextMenuDataResolver.resolveOpenWithMenuData(
            adapter: input.adapter,
            selectedEntries: input.selectedEntries,
        )
        let tags = EntryContextMenuDataResolver.resolveTags(selectedEntries: input.selectedEntries)

        let menu = makeMenu(configuration: .init(
            target: coordinator,
            selectedCount: selectedCount,
            rowEntryPathForOpenInNewTab: input.rowEntry?.isDirectory == true ? input.rowEntry?.fullPath : nil,
            canPaste: input.canPaste,
            showCompress: showCompress,
            showExtract: showExtract,
            isTrashFolder: input.isTrashFolder,
            openWithApplications: openWithApplications,
            showOpenWith: showOpenWith,
            tags: tags,
        ))

        return (menu, coordinator)
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
            action: #selector(EntryContextMenuCoordinator.contextMenuOpenSelectedItem),
            target: configuration.target,
        ))

        if let path = configuration.rowEntryPathForOpenInNewTab {
            let openInNewTab = menuItem(
                title: "Open in New Tab",
                action: #selector(EntryContextMenuCoordinator.contextMenuOpenSelectedItemInNewTab(_:)),
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
            action: #selector(EntryContextMenuCoordinator.contextMenuQuickLookSelectedItem),
            target: configuration.target,
        ))
        menu.addItem(NSMenuItem.separator())
    }

    private static func addInfoItems(to menu: NSMenu, target: EntryContextMenuCoordinator) {
        menu.addItem(menuItem(
            title: "Get Info",
            action: #selector(EntryContextMenuCoordinator.contextMenuGetInfoForSelectedItems),
            target: target,
        ))
        menu.addItem(menuItem(
            title: "Share…",
            action: #selector(EntryContextMenuCoordinator.contextMenuShareSelectedItems),
            target: target,
        ))
        menu.addItem(menuItem(
            title: "Reveal in Finder",
            action: #selector(EntryContextMenuCoordinator.contextMenuRevealSelectedItemsInFinder),
            target: target,
        ))
        menu.addItem(NSMenuItem.separator())
    }

    private static func addClipboardItems(to menu: NSMenu, configuration: Configuration) {
        menu.addItem(menuItem(
            title: "Copy",
            action: #selector(EntryContextMenuCoordinator.contextMenuCopySelectedItems),
            target: configuration.target,
        ))
        menu.addItem(menuItem(
            title: "Copy Absolute Paths",
            action: #selector(EntryContextMenuCoordinator.contextMenuCopySelectedAbsolutePaths),
            target: configuration.target,
        ))
        menu.addItem(menuItem(
            title: "Copy URLs",
            action: #selector(EntryContextMenuCoordinator.contextMenuCopySelectedURLs),
            target: configuration.target,
        ))
        menu.addItem(menuItem(
            title: "Cut",
            action: #selector(EntryContextMenuCoordinator.contextMenuCutSelectedItems),
            target: configuration.target,
        ))

        let pasteItem = menuItem(
            title: "Paste",
            action: #selector(EntryContextMenuCoordinator.contextMenuPasteItems),
            target: configuration.target,
        )
        pasteItem.isEnabled = configuration.canPaste
        menu.addItem(pasteItem)
        menu.addItem(NSMenuItem.separator())
    }

    private static func addRenameItems(to menu: NSMenu, configuration: Configuration) {
        let renameItem = menuItem(
            title: "Rename",
            action: #selector(EntryContextMenuCoordinator.contextMenuStartRename),
            target: configuration.target,
        )
        renameItem.isEnabled = configuration.selectedCount == 1
        menu.addItem(renameItem)
    }

    private static func addDuplicateItems(to menu: NSMenu, target: EntryContextMenuCoordinator) {
        menu.addItem(menuItem(
            title: "Duplicate",
            action: #selector(EntryContextMenuCoordinator.contextMenuDuplicateSelectedItems),
            target: target,
        ))
        menu.addItem(menuItem(
            title: "Make Alias",
            action: #selector(EntryContextMenuCoordinator.contextMenuCreateAliasForSelectedItems),
            target: target,
        ))
        menu.addItem(NSMenuItem.separator())
    }

    private static func addCompressItems(to menu: NSMenu, configuration: Configuration) {
        if configuration.showCompress {
            menu.addItem(menuItem(
                title: "Compress",
                action: #selector(EntryContextMenuCoordinator.contextMenuCompressSelectedItems),
                target: configuration.target,
            ))
        }
        if configuration.showExtract {
            menu.addItem(menuItem(
                title: "Extract",
                action: #selector(EntryContextMenuCoordinator.contextMenuExtractSelectedItem),
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
                action: #selector(EntryContextMenuCoordinator.contextMenuPutBackSelectedItems),
                target: configuration.target,
            ))
            menu.addItem(menuItem(
                title: "Delete Immediately",
                action: #selector(EntryContextMenuCoordinator.contextMenuDeleteSelectedItemsImmediately),
                target: configuration.target,
            ))
            menu.addItem(NSMenuItem.separator())
            menu.addItem(menuItem(
                title: "Empty Trash",
                action: #selector(EntryContextMenuCoordinator.contextMenuEmptyTrash),
                target: configuration.target,
            ))
        } else {
            menu.addItem(menuItem(
                title: "Move to Trash",
                action: #selector(EntryContextMenuCoordinator.contextMenuMoveSelectedItemsToTrash),
                target: configuration.target,
            ))
        }
    }

    private static func buildOpenWithMenu(configuration: Configuration) -> NSMenu {
        let menu = NSMenu()

        menu.addItem(menuItem(
            title: "Other…",
            action: #selector(EntryContextMenuCoordinator.contextMenuOpenWithOther),
            target: configuration.target,
        ))

        if !configuration.openWithApplications.isEmpty {
            menu.addItem(NSMenuItem.separator())
            for app in configuration.openWithApplications {
                let item = menuItem(
                    title: app.name,
                    action: #selector(EntryContextMenuCoordinator.contextMenuOpenWithApp(_:)),
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
                action: #selector(EntryContextMenuCoordinator.contextMenuToggleTag(_:)),
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
