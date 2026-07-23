@preconcurrency import AppKit
import ComposableArchitecture
import VoyagerEntitiesEntry
import VoyagerEntitiesTag

extension EntryListCoordinator {
    func configureHeaderMenu() {
        let headerView: EntryListHeaderView
        if let existing = tableView.headerView as? EntryListHeaderView {
            headerView = existing
        } else {
            let newHeaderView = EntryListHeaderView()
            tableView.headerView = newHeaderView
            headerView = newHeaderView
        }
        headerView.menuModelProvider = { [weak self] in
            let visibleColumns = self?.state.listVisibleColumns ?? EntryListColumn.defaultVisibleColumns
            return EntryViewLayoutColumnsMenuModel(visibleColumns: visibleColumns)
        }
        headerView.send = { [weak self] action in
            self?.store.send(action)
        }
    }

    func syncVisibleColumnsFromTableView() {
        let columns = tableView.tableColumns.compactMap { tableColumn in
            EntryListColumn(rawValue: tableColumn.identifier.rawValue)
        }
        let normalized = EntryListColumn.normalizeVisibleColumns(columns)
        if normalized != state.listVisibleColumns {
            store.send(.internal(.setListVisibleColumns(normalized)))
        }
    }

    func updateContextMenuAnchor(forRow row: Int?) {
        guard let row, row >= 0 else {
            contextMenuAnchor = nil
            return
        }
        guard let window = view?.window else {
            contextMenuAnchor = nil
            return
        }

        let rectInTable = tableView.rect(ofRow: row)
        let rectInWindow = tableView.convert(rectInTable, to: nil)
        let rectInScreen = window.convertToScreen(rectInWindow)
        contextMenuAnchor = CGPoint(x: rectInScreen.midX, y: rectInScreen.midY)
    }

    func preloadOpenWithApplications(selectedEntries _: [EntryModel]) {
        // Open-with applications are now loaded by the Page bridge (Wave 2)
    }

    func openWithApplications(selectedEntries _: [EntryModel]) -> [ApplicationInfo] {
        [] as [ApplicationInfo]
    }

    func entryForRow(_ row: Int?) -> EntryModel? {
        guard let row, row >= 0 else { return nil }
        guard let item = tableView.item(atRow: row) as? OutlineItem else { return nil }
        guard case let .entry(entry) = item.kind else { return nil }
        return entry
    }

    func selectedEntries(rowEntry: EntryModel?) -> [EntryModel] {
        state.contextMenuSelectedEntries(rowEntry: rowEntry)
    }

    var isTrashFolder: Bool {
        guard let trashPath = entryOpenClient.trashDirectoryPath() else {
            return false
        }
        let path = state.currentPath
        return path == trashPath || path.hasPrefix(trashPath + "/")
    }
}

extension EntryListCoordinator: EntryListView.EntryListTableViewContextMenuProviding {
    func contextMenu(forRow row: Int?, event _: NSEvent) -> NSMenu {
        updateContextMenuAnchor(forRow: row)
        let rowEntry = entryForRow(row)
        let selectedEntries = selectedEntries(rowEntry: rowEntry)
        preloadOpenWithApplications(selectedEntries: selectedEntries)
        let menuSpec = EntryContextMenuSpecFactory.make(
            selectedIds: state.selectedIds,
            selectedEntries: selectedEntries,
            rowEntry: rowEntry,
            isTrashFolder: isTrashFolder,
            canPaste: !state.clipboardCutPaths.isEmpty,
            favoriteTags: finderFavoritesTagClient.favoriteTags(),
            openWithApplications: openWithApplications(selectedEntries: selectedEntries),
        )
        let coordinator = EntryContextMenuCoordinator(store: store, rowEntry: rowEntry)
        contextMenuCoordinator = coordinator
        return EntryContextMenuBuilder.makeMenu(configuration: .init(
            target: coordinator,
            selectedCount: menuSpec.selectedCount,
            rowEntryPathForOpenInNewWindow: menuSpec.rowEntryPathForOpenInNewWindow,
            canPaste: menuSpec.canPaste,
            showCompress: menuSpec.showCompress,
            showExtract: menuSpec.showExtract,
            isTrashFolder: menuSpec.isTrashFolder,
            openWithApplications: menuSpec.openWithApplications,
            showOpenWith: menuSpec.showOpenWith,
            tags: menuSpec.tags,
        ))
    }
}
