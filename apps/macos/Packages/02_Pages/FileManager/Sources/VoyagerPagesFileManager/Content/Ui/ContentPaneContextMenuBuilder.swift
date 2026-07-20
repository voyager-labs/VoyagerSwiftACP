import AppKit
import VoyagerFeaturesEntryArrangements
import VoyagerShared
import VoyagerWidgetsEntryViewLayout

enum ContentPaneContextMenuBuilder {
    struct Configuration {
        let isTrashFolder: Bool
        let viewLayout: EntryViewLayoutState.Mode
        let sortKey: SortKey
        let sortOrder: VoyagerShared.SortOrder
        let groupKey: GroupKey
        let canPaste: Bool
        let itemCount: Int
        let canPerformEntryCommands: Bool

        var canChangeSort: Bool {
            groupKey == .none && canPerformEntryCommands
        }

        var canChangeGroup: Bool {
            canPerformEntryCommands
        }

        var canPasteItems: Bool {
            canPaste && canPerformEntryCommands
        }

        var canSelectAll: Bool {
            itemCount > 0 && canPerformEntryCommands
        }
    }

    static func makeMenu(
        configuration: Configuration,
        target: AnyObject,
    ) -> NSMenu {
        let menu = makeMenuContainer()

        menu.addItem(makePrimaryMenuItem(configuration: configuration, target: target))

        menu.addItem(.separator())

        let paste = menuItem(
            title: "Paste",
            action: #selector(ContentPaneContextMenuCoordinator.contextMenuPaste),
            target: target,
        )
        paste.keyEquivalent = "v"
        paste.keyEquivalentModifierMask = .command
        paste.isEnabled = configuration.canPasteItems
        menu.addItem(paste)

        let selectAll = menuItem(
            title: "Select All",
            action: #selector(ContentPaneContextMenuCoordinator.contextMenuSelectAll),
            target: target,
        )
        selectAll.keyEquivalent = "a"
        selectAll.keyEquivalentModifierMask = .command
        selectAll.isEnabled = configuration.canSelectAll
        menu.addItem(selectAll)
        menu.addItem(.separator())

        let viewMenu = NSMenuItem(title: "View", action: nil, keyEquivalent: "")
        viewMenu.submenu = makeViewMenu(configuration: configuration, target: target)
        menu.addItem(viewMenu)

        let sortMenu = NSMenuItem(title: "Sort By", action: nil, keyEquivalent: "")
        sortMenu.submenu = makeSortMenu(configuration: configuration, target: target)
        sortMenu.isEnabled = configuration.canChangeSort
        menu.addItem(sortMenu)

        let groupMenu = NSMenuItem(title: "Group By", action: nil, keyEquivalent: "")
        groupMenu.submenu = makeGroupMenu(configuration: configuration, target: target)
        groupMenu.isEnabled = configuration.canChangeGroup
        menu.addItem(groupMenu)

        return menu
    }

    static func makeMenuContainer() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        return menu
    }

    static func makePrimaryMenuItem(
        configuration: Configuration,
        target: AnyObject,
    ) -> NSMenuItem {
        if configuration.isTrashFolder {
            let emptyTrash = menuItem(
                title: "Empty Trash",
                action: #selector(ContentPaneContextMenuCoordinator.contextMenuEmptyTrash),
                target: target,
            )
            emptyTrash.isEnabled = configuration.canPerformEntryCommands
            return emptyTrash
        }

        let newFolder = menuItem(
            title: "New Folder",
            action: #selector(ContentPaneContextMenuCoordinator.contextMenuCreateNewFolder),
            target: target,
        )
        newFolder.isEnabled = configuration.canPerformEntryCommands
        newFolder.keyEquivalent = "n"
        newFolder.keyEquivalentModifierMask = [.command, .shift]
        return newFolder
    }

    private static func makeViewMenu(
        configuration: Configuration,
        target: AnyObject,
    ) -> NSMenu {
        let menu = makeMenuContainer()
        let list = menuItem(
            title: "as List",
            action: #selector(ContentPaneContextMenuCoordinator.contextMenuSetLayout(_:)),
            target: target,
        )
        list.representedObject = EntryViewLayoutState.Mode.list.rawValue
        list.state = configuration.viewLayout == .list ? .on : .off
        menu.addItem(list)

        let grid = menuItem(
            title: "as Icon",
            action: #selector(ContentPaneContextMenuCoordinator.contextMenuSetLayout(_:)),
            target: target,
        )
        grid.representedObject = EntryViewLayoutState.Mode.grid.rawValue
        grid.state = configuration.viewLayout == .grid ? .on : .off
        menu.addItem(grid)
        return menu
    }

    private static func makeSortMenu(
        configuration: Configuration,
        target: AnyObject,
    ) -> NSMenu {
        let menu = makeMenuContainer()
        for item in EntryArrangementMenuItems.sortItems {
            let menuItem = menuItem(
                title: item.title,
                action: #selector(ContentPaneContextMenuCoordinator.contextMenuSetSortKey(_:)),
                target: target,
            )
            menuItem.representedObject = item.key.rawValue
            menuItem.state = configuration.sortKey == item.key ? .on : .off
            menuItem.isEnabled = configuration.canChangeSort
            menu.addItem(menuItem)
        }
        menu.addItem(.separator())

        let ascending = menuItem(
            title: "Ascending",
            action: #selector(ContentPaneContextMenuCoordinator.contextMenuSetSortOrder(_:)),
            target: target,
        )
        ascending.representedObject = VoyagerShared.SortOrder.ascending.rawValue
        ascending.state = configuration.sortOrder == .ascending ? .on : .off
        ascending.isEnabled = configuration.canChangeSort
        menu.addItem(ascending)

        let descending = menuItem(
            title: "Descending",
            action: #selector(ContentPaneContextMenuCoordinator.contextMenuSetSortOrder(_:)),
            target: target,
        )
        descending.representedObject = VoyagerShared.SortOrder.descending.rawValue
        descending.state = configuration.sortOrder == .descending ? .on : .off
        descending.isEnabled = configuration.canChangeSort
        menu.addItem(descending)

        return menu
    }

    private static func makeGroupMenu(
        configuration: Configuration,
        target: AnyObject,
    ) -> NSMenu {
        let menu = makeMenuContainer()
        let none = menuItem(
            title: "None",
            action: #selector(ContentPaneContextMenuCoordinator.contextMenuSetGroupKey(_:)),
            target: target,
        )
        none.representedObject = GroupKey.none.rawValue
        none.state = configuration.groupKey == .none ? .on : .off
        none.isEnabled = configuration.canChangeGroup
        menu.addItem(none)

        menu.addItem(.separator())
        for item in EntryArrangementMenuItems.groupItems {
            let menuItem = menuItem(
                title: item.title,
                action: #selector(ContentPaneContextMenuCoordinator.contextMenuSetGroupKey(_:)),
                target: target,
            )
            menuItem.representedObject = item.key.rawValue
            menuItem.state = configuration.groupKey == item.key ? .on : .off
            menuItem.isEnabled = configuration.canChangeGroup
            menu.addItem(menuItem)
        }
        return menu
    }

    private static func menuItem(
        title: String,
        action: Selector,
        target: AnyObject,
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = target
        return item
    }
}
