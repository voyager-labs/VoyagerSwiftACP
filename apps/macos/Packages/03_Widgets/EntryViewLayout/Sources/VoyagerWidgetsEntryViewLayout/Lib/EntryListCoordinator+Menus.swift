@preconcurrency import AppKit
import ComposableArchitecture

import VoyagerEntitiesEntry
import VoyagerEntitiesTag
import VoyagerFeaturesEntryOperations

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

    func preloadOpenWithApplications(selectedEntries: [EntryModel]) {
        let selectedFiles = selectedEntries.filter { !$0.isFolder }
        if selectedFiles.isEmpty {
            return
        }

        if selectedFiles.count > 1 {
            sendEntryOperations(.openWith(.loadCommonApplicationsForFiles(files: selectedFiles)))
        } else if let file = selectedFiles.first,
                  state.entryOperations.applicationsForItems[file.fullPath] == nil
        {
            sendEntryOperations(.openWith(.loadApplicationsForFile(file: file)))
        }
    }

    func openWithApplications(selectedEntries: [EntryModel]) -> [ApplicationInfo] {
        let selectedFiles = selectedEntries.filter { !$0.isFolder }
        let applications: [ApplicationInfo] = if selectedFiles.count > 1 {
            state.entryOperations.commonApplicationsForSelectedFiles
        } else if let file = selectedFiles.first {
            state.entryOperations.applicationsForItems[file.fullPath] ?? []
        } else {
            [] as [ApplicationInfo]
        }
        return applications
    }

    func entryForRow(_ row: Int?) -> EntryModel? {
        guard let row, row >= 0 else { return nil }
        guard let item = tableView.item(atRow: row) as? OutlineItem else { return nil }
        guard case let .entry(entry) = item.kind else { return nil }
        return entry
    }

    func selectedEntries(rowEntry: EntryModel?) -> [EntryModel] {
        let selectedIds = state.selectedIds
        if selectedIds.isEmpty {
            return rowEntry.map { [$0] } ?? []
        }
        return state.entries.filter { selectedIds.contains($0.id) }
    }

    var isTrashFolder: Bool {
        guard let trashPath = entryOpenClient.trashDirectoryPath() else {
            return false
        }
        let path = state.currentPath
        return path == trashPath || path.hasPrefix(trashPath + "/")
    }

    func dragOperation(from resolved: EntryDropResolvedOperation) -> NSDragOperation {
        switch resolved {
        case .none:
            []
        case .copy:
            .copy
        case .move:
            .move
        }
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
            canPaste: !state.entryOperations.clipboardItems.isEmpty,
            favoriteTags: finderFavoritesTagClient.favoriteTags(),
            openWithApplications: openWithApplications(selectedEntries: selectedEntries),
        )
        let coordinator = EntryContextMenuCoordinator(store: store, rowEntry: rowEntry)
        contextMenuCoordinator = coordinator
        return EntryContextMenuBuilder.makeMenu(configuration: .init(
            target: coordinator,
            selectedCount: menuSpec.selectedCount,
            rowEntryPathForOpenInNewTab: menuSpec.rowEntryPathForOpenInNewTab,
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
