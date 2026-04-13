import AppKit

import VoyagerWidgetsEntryViewLayout

enum ContentPaneContextMenuBuilder {
    struct Configuration {
        let isTrashFolder: Bool
        let viewLayout: EntryViewLayoutState.Mode
        let sortKey: SortKey
        let sortOrder: VoyagerWidgetsEntryViewLayout.SortOrder
        let groupKey: GroupKey
    }

    static func makeMenu(
        configuration: Configuration,
        target: ContentPaneContextMenuCoordinator,
    ) -> NSMenu {
        let menu = NSMenu()

        if configuration.isTrashFolder {
            menu.addItem(menuItem(
                title: "Empty Trash",
                action: #selector(ContentPaneContextMenuCoordinator.contextMenuEmptyTrash),
                target: target,
            ))
        } else {
            let newFolder = menuItem(
                title: "New Folder",
                action: #selector(ContentPaneContextMenuCoordinator.contextMenuCreateNewFolder),
                target: target,
            )
            newFolder.keyEquivalent = "n"
            newFolder.keyEquivalentModifierMask = [.command, .shift]
            menu.addItem(newFolder)
        }

        menu.addItem(.separator())

        let viewMenu = NSMenuItem(title: "View", action: nil, keyEquivalent: "")
        viewMenu.submenu = makeViewMenu(configuration: configuration, target: target)
        menu.addItem(viewMenu)

        let sortMenu = NSMenuItem(title: "Sort By", action: nil, keyEquivalent: "")
        sortMenu.submenu = makeSortMenu(configuration: configuration, target: target)
        menu.addItem(sortMenu)

        let groupMenu = NSMenuItem(title: "Group By", action: nil, keyEquivalent: "")
        groupMenu.submenu = makeGroupMenu(configuration: configuration, target: target)
        menu.addItem(groupMenu)

        return menu
    }

    private static func makeViewMenu(
        configuration: Configuration,
        target: ContentPaneContextMenuCoordinator,
    ) -> NSMenu {
        let menu = NSMenu()
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
        target: ContentPaneContextMenuCoordinator,
    ) -> NSMenu {
        let menu = NSMenu()
        for item in EntryArrangementMenuItems.sortItems {
            let menuItem = menuItem(
                title: item.title,
                action: #selector(ContentPaneContextMenuCoordinator.contextMenuSetSortKey(_:)),
                target: target,
            )
            menuItem.representedObject = item.key.rawValue
            menuItem.state = configuration.sortKey == item.key ? .on : .off
            menu.addItem(menuItem)
        }
        menu.addItem(.separator())

        let ascending = menuItem(
            title: "Ascending",
            action: #selector(ContentPaneContextMenuCoordinator.contextMenuSetSortOrder(_:)),
            target: target,
        )
        ascending.representedObject = SortOrder.ascending.rawValue
        ascending.state = configuration.sortOrder == .ascending ? .on : .off
        menu.addItem(ascending)

        let descending = menuItem(
            title: "Descending",
            action: #selector(ContentPaneContextMenuCoordinator.contextMenuSetSortOrder(_:)),
            target: target,
        )
        descending.representedObject = SortOrder.descending.rawValue
        descending.state = configuration.sortOrder == .descending ? .on : .off
        menu.addItem(descending)

        return menu
    }

    private static func makeGroupMenu(
        configuration: Configuration,
        target: ContentPaneContextMenuCoordinator,
    ) -> NSMenu {
        let menu = NSMenu()
        let none = menuItem(
            title: "None",
            action: #selector(ContentPaneContextMenuCoordinator.contextMenuSetGroupKey(_:)),
            target: target,
        )
        none.representedObject = GroupKey.none.rawValue
        none.state = configuration.groupKey == .none ? .on : .off
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
            menu.addItem(menuItem)
        }
        return menu
    }

    private static func menuItem(
        title: String,
        action: Selector,
        target: ContentPaneContextMenuCoordinator,
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = target
        return item
    }
}
