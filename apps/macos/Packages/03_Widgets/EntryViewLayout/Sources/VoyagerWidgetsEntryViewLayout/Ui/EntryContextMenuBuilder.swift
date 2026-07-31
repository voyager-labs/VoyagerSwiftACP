@preconcurrency import AppKit
import VoyagerEntitiesEntry
import VoyagerEntitiesTag
import VoyagerShared

enum EntryContextMenuBuilder {
    struct Configuration {
        let target: EntryContextMenuCoordinator
        let selectedCount: Int
        let rowEntryPathForOpenInNewWindow: String?
        let canPaste: Bool
        let showCompress: Bool
        let showExtract: Bool
        let isTrashFolder: Bool
        let canPutBack: Bool
        let openWithApplications: [ApplicationInfo]
        let showOpenWith: Bool
        let paletteTags: [EntryContextMenuTagSpec]
        let knownTags: [EntryContextMenuTagSpec]
        let canPerformEntryCommands: Bool
    }

    static func makeMenu(configuration: Configuration) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.delegate = configuration.target

        addOpenItems(to: menu, configuration: configuration)
        addInfoItems(to: menu, target: configuration.target)
        addClipboardItems(to: menu, configuration: configuration)
        addRenameItems(to: menu, configuration: configuration)
        addDuplicateItems(to: menu, target: configuration.target)
        addCompressItems(to: menu, configuration: configuration)
        addTagsItems(to: menu, configuration: configuration)
        addTrashItems(to: menu, configuration: configuration)

        if !configuration.canPerformEntryCommands {
            menu.items.forEach { $0.isEnabled = false }
        }

        return menu
    }

    private static func addOpenItems(to menu: NSMenu, configuration: Configuration) {
        let open = menuItem(
            title: "Open",
            action: #selector(EntryContextMenuCoordinator.contextMenuOpenSelectedItem),
            target: configuration.target,
        )
        open.keyEquivalent = keyEquivalent(for: NSDownArrowFunctionKey)
        open.keyEquivalentModifierMask = .command
        menu.addItem(open)

        if let path = configuration.rowEntryPathForOpenInNewWindow {
            let openInNewWindow = menuItem(
                title: "Open in New Window",
                action: #selector(EntryContextMenuCoordinator.contextMenuOpenSelectedItemInNewWindow(_:)),
                target: configuration.target,
            )
            openInNewWindow.representedObject = path
            menu.addItem(openInNewWindow)
        }

        if configuration.showOpenWith {
            let openWithItem = NSMenuItem(title: "Open With", action: nil, keyEquivalent: "")
            openWithItem.submenu = buildOpenWithMenu(configuration: configuration)
            menu.addItem(openWithItem)
        }

        let quickLook = menuItem(
            title: "Quick Look",
            action: #selector(EntryContextMenuCoordinator.contextMenuQuickLookSelectedItem),
            target: configuration.target,
        )
        quickLook.keyEquivalent = " "
        quickLook.keyEquivalentModifierMask = []
        menu.addItem(quickLook)
        menu.addItem(NSMenuItem.separator())
    }

    private static func addInfoItems(to menu: NSMenu, target: EntryContextMenuCoordinator) {
        let getInfo = menuItem(
            title: "Get Info",
            action: #selector(EntryContextMenuCoordinator.contextMenuGetInfoForSelectedItems),
            target: target,
        )
        getInfo.keyEquivalent = "i"
        getInfo.keyEquivalentModifierMask = .command
        menu.addItem(getInfo)
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
        let copy = menuItem(
            title: "Copy",
            action: #selector(EntryContextMenuCoordinator.contextMenuCopySelectedItems),
            target: configuration.target,
        )
        copy.keyEquivalent = "c"
        copy.keyEquivalentModifierMask = .command
        menu.addItem(copy)
        let copyAbsolutePaths = menuItem(
            title: "Copy Absolute Paths",
            action: #selector(EntryContextMenuCoordinator.contextMenuCopySelectedAbsolutePaths),
            target: configuration.target,
        )
        copyAbsolutePaths.keyEquivalent = "c"
        copyAbsolutePaths.keyEquivalentModifierMask = [.command, .option]
        menu.addItem(copyAbsolutePaths)
        let copyURLs = menuItem(
            title: configuration.selectedCount == 1 ? "Copy URL" : "Copy URLs",
            action: #selector(EntryContextMenuCoordinator.contextMenuCopySelectedURLs),
            target: configuration.target,
        )
        copyURLs.keyEquivalent = "u"
        copyURLs.keyEquivalentModifierMask = [.command, .option]
        menu.addItem(copyURLs)
        let cut = menuItem(
            title: "Cut",
            action: #selector(EntryContextMenuCoordinator.contextMenuCutSelectedItems),
            target: configuration.target,
        )
        cut.keyEquivalent = "x"
        cut.keyEquivalentModifierMask = .command
        menu.addItem(cut)

        let pasteItem = menuItem(
            title: "Paste",
            action: #selector(EntryContextMenuCoordinator.contextMenuPasteItems),
            target: configuration.target,
        )
        pasteItem.isEnabled = configuration.canPaste
        pasteItem.keyEquivalent = "v"
        pasteItem.keyEquivalentModifierMask = .command
        menu.addItem(pasteItem)
        let selectAll = menuItem(
            title: "Select All",
            action: #selector(EntryContextMenuCoordinator.contextMenuSelectAll),
            target: configuration.target,
        )
        selectAll.keyEquivalent = "a"
        selectAll.keyEquivalentModifierMask = .command
        menu.addItem(selectAll)
        menu.addItem(NSMenuItem.separator())
    }

    private static func addRenameItems(to menu: NSMenu, configuration: Configuration) {
        let renameItem = menuItem(
            title: "Rename",
            action: #selector(EntryContextMenuCoordinator.contextMenuStartRename),
            target: configuration.target,
        )
        renameItem.keyEquivalent = "\r"
        renameItem.isEnabled = configuration.selectedCount == 1
        menu.addItem(renameItem)
    }

    private static func addDuplicateItems(to menu: NSMenu, target: EntryContextMenuCoordinator) {
        let duplicate = menuItem(
            title: "Duplicate",
            action: #selector(EntryContextMenuCoordinator.contextMenuDuplicateSelectedItems),
            target: target,
        )
        duplicate.keyEquivalent = "d"
        duplicate.keyEquivalentModifierMask = .command
        menu.addItem(duplicate)
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
        guard configuration.selectedCount > 0 else { return }

        let tagsItem = menuItem(
            title: "Tags…",
            action: #selector(EntryContextMenuCoordinator.contextMenuShowTags(_:)),
            target: configuration.target,
        )
        tagsItem.representedObject = configuration.knownTags

        if !configuration.paletteTags.isEmpty {
            let palette = MainActor.assumeIsolated {
                EntryFavoriteTagsPaletteView(
                    tags: configuration.paletteTags,
                    isEnabled: configuration.canPerformEntryCommands,
                    onSelect: { tag in
                        let mode: TagMutationMode = tag.selection == .on ? .remove : .add
                        configuration.target.performTagMutation(name: tag.name, mode: mode)
                    },
                )
            }
            let paletteItem = NSMenuItem()
            paletteItem.isEnabled = configuration.canPerformEntryCommands
            paletteItem.view = palette
            menu.addItem(paletteItem)
        }

        menu.addItem(tagsItem)
        menu.addItem(NSMenuItem.separator())
    }

    private static func addTrashItems(to menu: NSMenu, configuration: Configuration) {
        if configuration.isTrashFolder {
            let putBack = menuItem(
                title: "Put Back",
                action: #selector(EntryContextMenuCoordinator.contextMenuPutBackSelectedItems),
                target: configuration.target,
            )
            putBack.isEnabled = configuration.canPutBack
            menu.addItem(putBack)
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
            let moveToTrash = menuItem(
                title: "Move to Trash",
                action: #selector(EntryContextMenuCoordinator.contextMenuMoveSelectedItemsToTrash),
                target: configuration.target,
            )
            moveToTrash.keyEquivalent = keyEquivalent(for: NSBackspaceCharacter)
            moveToTrash.keyEquivalentModifierMask = .command
            menu.addItem(moveToTrash)
        }
    }

    private static func buildOpenWithMenu(configuration: Configuration) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false

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

    private static func menuItem(title: String, action: Selector, target: AnyObject) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = target
        return item
    }

    private static func keyEquivalent(for character: Int) -> String {
        UnicodeScalar(character).map(String.init) ?? ""
    }
}
