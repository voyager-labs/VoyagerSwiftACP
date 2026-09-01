@preconcurrency import AppKit
import Dependencies
import VoyagerEntitiesEntry
import VoyagerEntitiesTag
import VoyagerShared

enum EntryContextMenuBuilder {
    struct Configuration {
        let target: EntryContextMenuCoordinator
        let selectedCount: Int
        let rowEntryPathForOpenInNewWindow: String?
        let openInNewTabPaths: [String]?
        let serviceNames: [String]
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
        let isOpenWithApplicationsLoading: Bool
        let canRename: Bool

        init(
            target: EntryContextMenuCoordinator,
            selectedCount: Int,
            rowEntryPathForOpenInNewWindow: String?,
            openInNewTabPaths: [String]?,
            serviceNames: [String],
            canPaste: Bool,
            showCompress: Bool,
            showExtract: Bool,
            isTrashFolder: Bool,
            canPutBack: Bool,
            openWithApplications: [ApplicationInfo],
            showOpenWith: Bool,
            paletteTags: [EntryContextMenuTagSpec],
            knownTags: [EntryContextMenuTagSpec],
            canPerformEntryCommands: Bool,
            isOpenWithApplicationsLoading: Bool = false,
            canRename: Bool = true,
        ) {
            self.target = target
            self.selectedCount = selectedCount
            self.rowEntryPathForOpenInNewWindow = rowEntryPathForOpenInNewWindow
            self.openInNewTabPaths = openInNewTabPaths
            self.serviceNames = serviceNames
            self.canPaste = canPaste
            self.showCompress = showCompress
            self.showExtract = showExtract
            self.isTrashFolder = isTrashFolder
            self.canPutBack = canPutBack
            self.openWithApplications = openWithApplications
            self.showOpenWith = showOpenWith
            self.paletteTags = paletteTags
            self.knownTags = knownTags
            self.canPerformEntryCommands = canPerformEntryCommands
            self.isOpenWithApplicationsLoading = isOpenWithApplicationsLoading
            self.canRename = canRename
        }
    }

    /// Open With 아이콘은 프로세스 수명 동안 standardized 앱 URL을 key로 재사용한다.
    /// 메뉴 생성은 MainActor에서 직렬화되므로 추가 동기화는 필요하지 않다.
    nonisolated(unsafe) private static let openWithIconCache = NSCache<NSURL, NSImage>()

    @MainActor
    static func makeMenu(configuration: Configuration) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.delegate = configuration.target

        addOpenItems(to: menu, configuration: configuration)
        addInfoItems(to: menu, configuration: configuration)
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

    @MainActor
    static func updateOpenWithMenu(
        _ menu: NSMenu,
        applications: [ApplicationInfo],
        isLoading: Bool,
        target: EntryContextMenuCoordinator,
    ) {
        menu.removeAllItems()

        if isLoading {
            let loadingItem = NSMenuItem(title: "Loading Applications…", action: nil, keyEquivalent: "")
            loadingItem.isEnabled = false
            menu.addItem(loadingItem)
        } else if !applications.isEmpty {
            menu.addItem(NSMenuItem.separator())
            for app in applications {
                let item = menuItem(
                    title: app.name,
                    action: #selector(EntryContextMenuCoordinator.contextMenuOpenWithApp(_:)),
                    target: target,
                )
                item.representedObject = app.bundleID
                item.state = app.isDefault ? .on : .off
                if let url = app.applicationURL {
                    loadOpenWithIcon(for: url, into: item)
                }
                menu.addItem(item)
            }
        }

        if !applications.isEmpty {
            menu.addItem(NSMenuItem.separator())
        }
        menu.addItem(menuItem(
            title: "Other…",
            action: #selector(EntryContextMenuCoordinator.contextMenuOpenWithOther),
            target: target,
        ))
    }

    @MainActor
    private static func addOpenItems(to menu: NSMenu, configuration: Configuration) {
        let open = menuItem(
            title: "Open",
            action: #selector(EntryContextMenuCoordinator.contextMenuOpenSelectedItem),
            target: configuration.target,
        )
        open.keyEquivalent = keyEquivalent(for: NSDownArrowFunctionKey)
        open.keyEquivalentModifierMask = .command
        menu.addItem(open)

        if let openInNewTabPaths = configuration.openInNewTabPaths, !openInNewTabPaths.isEmpty {
            let openInNewTab = menuItem(
                title: "Open in New Tab",
                action: #selector(EntryContextMenuCoordinator.contextMenuOpenInNewTab(_:)),
                target: configuration.target,
            )
            openInNewTab.representedObject = openInNewTabPaths
            menu.addItem(openInNewTab)
        }

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

    private static func addInfoItems(to menu: NSMenu, configuration: Configuration) {
        let getInfo = menuItem(
            title: "Get Info",
            action: #selector(EntryContextMenuCoordinator.contextMenuGetInfoForSelectedItems),
            target: configuration.target,
        )
        getInfo.keyEquivalent = "i"
        getInfo.keyEquivalentModifierMask = .command
        menu.addItem(getInfo)
        menu.addItem(menuItem(
            title: "Share…",
            action: #selector(EntryContextMenuCoordinator.contextMenuShareSelectedItems),
            target: configuration.target,
        ))
        if configuration.selectedCount > 0, !configuration.serviceNames.isEmpty {
            let servicesItem = NSMenuItem(title: "Services", action: nil, keyEquivalent: "")
            let servicesMenu = NSMenu()
            servicesMenu.autoenablesItems = false
            for serviceName in configuration.serviceNames {
                let serviceItem = menuItem(
                    title: serviceName,
                    action: #selector(EntryContextMenuCoordinator.contextMenuPerformService(_:)),
                    target: configuration.target,
                )
                serviceItem.representedObject = serviceName
                servicesMenu.addItem(serviceItem)
            }
            servicesItem.submenu = servicesMenu
            menu.addItem(servicesItem)
        }
        menu.addItem(menuItem(
            title: "Reveal in Finder",
            action: #selector(EntryContextMenuCoordinator.contextMenuRevealSelectedItemsInFinder),
            target: configuration.target,
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
        renameItem.isEnabled = configuration.canRename && configuration.selectedCount == 1
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

    @MainActor
    private static func buildOpenWithMenu(configuration: Configuration) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false

        updateOpenWithMenu(
            menu,
            applications: configuration.openWithApplications,
            isLoading: configuration.isOpenWithApplicationsLoading,
            target: configuration.target,
        )
        return menu
    }

    @MainActor
    private static func loadOpenWithIcon(for url: URL, into item: NSMenuItem) {
        let key = url.standardizedFileURL as NSURL
        if let cached = openWithIconCache.object(forKey: key) {
            item.image = cached
            return
        }

        @Dependency(\.workspaceClient)
        var workspaceClient
        Task { @MainActor [weak item] in
            let icon = await workspaceClient.iconForFileAsync(url.path)
            let resized = resize(icon, to: NSSize(width: 16, height: 16))
            resized.isTemplate = false
            openWithIconCache.setObject(resized, forKey: key)
            await MainActor.run {
                guard let item, item.representedObject != nil else { return }
                item.image = resized
            }
        }
    }

    private static func resize(_ image: NSImage, to size: NSSize) -> NSImage {
        let resized = NSImage(size: size)
        resized.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: size))
        resized.unlockFocus()
        return resized
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
