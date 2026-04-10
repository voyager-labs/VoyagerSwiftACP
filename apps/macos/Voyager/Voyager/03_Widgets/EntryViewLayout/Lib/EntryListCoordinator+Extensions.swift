import AppKit
import Combine
import ComposableArchitecture

extension EntryListCoordinator {
    func beginRenaming(row: Int) {
        guard row >= 0, row < tableView.numberOfRows else { return }
        guard let nameColumnIndex else { return }

        tableView.scrollRowToVisible(row)
        isUpdatingSelectionFromStore = true
        tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        isUpdatingSelectionFromStore = false

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }

            _ = tableView.view(atColumn: nameColumnIndex, row: row, makeIfNecessary: true)

            guard let cell = tableView
                .view(atColumn: nameColumnIndex, row: row, makeIfNecessary: false) as? EntryListEntryCellView
            else {
                return
            }

            cell.beginRenaming()
        }
    }
}

extension EntryListCoordinator.OutlineItem {
    func flattenEntries() -> [(EntryModel.ID, EntryListCoordinator.OutlineItem)] {
        switch kind {
        case let .entry(entry):
            [(entry.id, self)]
        case .group:
            children.flatMap { $0.flattenEntries() }
        }
    }
}

extension EntryListCoordinator: NSOutlineViewDelegate {
    func outlineView(_: NSOutlineView, shouldEdit tableColumn: NSTableColumn?, item: Any) -> Bool {
        guard let tableColumn else { return false }
        guard tableColumn.identifier.rawValue == EntryListColumn.name.rawValue else { return false }
        guard let outlineItem = item as? OutlineItem else { return false }
        guard case let .entry(entry) = outlineItem.kind else { return false }
        guard state.entryOperations.renamingItemId == entry.id else { return false }
        return true
    }

    func outlineView(
        _: NSOutlineView,
        draggingSession _: NSDraggingSession,
        willBeginAt _: NSPoint,
        forItems items: [Any],
    ) {
        let paths = items.compactMap { item -> String? in
            guard let outlineItem = item as? OutlineItem else { return nil }
            guard case let .entry(entry) = outlineItem.kind else { return nil }
            return entry.fullPath
        }
        guard !paths.isEmpty else { return }
        sendEntryOperations(.routing(.saveDragPaths(paths)))
    }

    func outlineView(
        _: NSOutlineView,
        draggingSession _: NSDraggingSession,
        endedAt _: NSPoint,
        operation: NSDragOperation,
    ) {
        guard EntryViewLayoutDragStateClearRuleSet.shouldClearAfterSessionEnd(operation: operation) else { return }
        sendEntryOperations(.routing(.saveDragPaths([])))
        store.send(.view(.setDropTargeted(false)))
    }

    func outlineView(_ outlineView: NSOutlineView, sortDescriptorsDidChange _: [NSSortDescriptor]) {
        let signature = EntryListCoordinatorSortSignature(descriptors: outlineView.sortDescriptors)
        guard !sortSyncGate.consumeIfSuppressed(signature) else { return }

        guard let change = EntryListCoordinatorSortDescriptorMapper.change(from: outlineView.sortDescriptors)
        else { return }
        let needed = EntryListCoordinatorSortDescriptorMapper.actionsNeeded(
            currentSortKey: state.entryArrangements.sortKey,
            currentSortOrder: state.entryArrangements.sortOrder,
            change: change,
        )
        if let sortKey = needed.sortKey { sendEntryArrangements(.setSortKey(sortKey)) }
        if let sortOrder = needed.sortOrder { sendEntryArrangements(.setSortOrder(sortOrder)) }
    }

    func outlineViewColumnDidMove(_ notification: Notification) {
        guard !isApplyingColumnsFromStore else { return }

        let userInfo = notification.userInfo ?? [:]
        let oldIndex = userInfo["NSOldColumn"] as? Int
        let newIndex = userInfo["NSNewColumn"] as? Int

        if let oldIndex, let newIndex {
            store.send(.internal(.moveListColumn(from: oldIndex, to: newIndex)))
            return
        }

        syncVisibleColumnsFromTableView()
    }

    func outlineViewColumnDidResize(_ notification: Notification) {
        guard let column = notification.userInfo?["NSTableColumn"] as? NSTableColumn else { return }
        guard column.identifier.rawValue == EntryListColumn.dateModified.rawValue else { return }
        dateModifiedResizeDebouncer.schedule { [weak self] in
            self?.reloadVisibleDateModifiedCells()
        }
    }

    func outlineView(_: NSOutlineView, isGroupItem item: Any) -> Bool {
        guard let outlineItem = item as? OutlineItem else { return false }
        if case .group = outlineItem.kind {
            return true
        }
        return false
    }

    func outlineView(_: NSOutlineView, shouldSelectItem item: Any) -> Bool {
        guard let outlineItem = item as? OutlineItem else { return false }
        if case .group = outlineItem.kind {
            return false
        }
        return true
    }

    func outlineView(_ outlineView: NSOutlineView, heightOfRowByItem item: Any) -> CGFloat {
        guard let outlineItem = item as? OutlineItem else { return outlineView.rowHeight }
        switch outlineItem.kind {
        case .group:
            return 32
        case .entry:
            return max(24, state.listIconSize + 4)
        }
    }

    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        guard let outlineItem = item as? OutlineItem else { return nil }

        switch outlineItem.kind {
        case let .group(title, colorCode, _):
            return makeGroupRowView(
                outlineView: outlineView,
                tableColumn: tableColumn,
                title: title,
                colorCode: colorCode,
            )
        case let .entry(entry):
            let resolvedTableColumn = tableColumn ?? outlineView.outlineTableColumn
            let columnId = resolvedTableColumn?.identifier.rawValue ?? EntryListColumn.name.rawValue
            return makeEntryCell(outlineView: outlineView, columnId: columnId, entry: entry)
        }
    }

    private func makeEntryCell(
        outlineView: NSOutlineView,
        columnId: String,
        entry: EntryModel,
    ) -> EntryListEntryCellView {
        let entryIdentifier = NSUserInterfaceItemIdentifier("entry-cell-\(columnId)")
        let view = (outlineView.makeView(withIdentifier: entryIdentifier, owner: self) as? EntryListEntryCellView)
            ?? EntryListEntryCellView()
        view.identifier = entryIdentifier

        let columnWidth = outlineView
            .tableColumn(withIdentifier: NSUserInterfaceItemIdentifier(columnId))?
            .width ?? 0
        let thumbnail = thumbnailImagesByPath[entry.fullPath]
        let configuration = makeEntryCellConfiguration(
            entry: entry,
            columnId: columnId,
            columnWidth: columnWidth,
            thumbnail: thumbnail,
        )
        view.configure(configuration)
        return view
    }

    func outlineViewSelectionDidChange(_: Notification) {
        guard !isUpdatingSelectionFromStore else { return }

        let selectedIndexes = tableView.selectedRowIndexes
        let selectedEntries: [EntryModel] = selectedIndexes.compactMap { index in
            guard let outlineItem = tableView.item(atRow: index) as? OutlineItem else { return nil }
            guard case let .entry(entry) = outlineItem.kind else { return nil }
            return entry
        }
        let selectedIds: Set<EntryModel.ID> = Set(selectedEntries.map(\.id))

        let clickedRow = tableView.clickedRow
        let lastSelectedId: EntryModel.ID? = if selectedIndexes.contains(clickedRow),
                                                let item = tableView.item(atRow: clickedRow) as? OutlineItem,
                                                case let .entry(entry) = item.kind
        {
            entry.id
        } else if let lastIndex = selectedIndexes.last,
                  let item = tableView.item(atRow: lastIndex) as? OutlineItem,
                  case let .entry(entry) = item.kind
        {
            entry.id
        } else {
            nil
        }

        preloadOpenWithApplications(selectedEntries: selectedEntries)
        store.send(.internal(.setSelectionState(
            ids: selectedIds,
            lastSelectedId: lastSelectedId,
            rangeAnchorId: lastSelectedId,
            shouldScrollToSelection: false,
        )))
    }

    func outlineViewItemDidExpand(_ notification: Notification) {
        guard !isUpdatingGroupExpansion else { return }
        guard let item = notification.userInfo?["NSObject"] as? OutlineItem else { return }
        guard case let .group(name, _, _) = item.kind else { return }
        if state.entryArrangements.collapsedGroups.contains(name) {
            sendEntryArrangements(.toggleCollapsedGroup(name))
        }
    }

    func outlineViewItemDidCollapse(_ notification: Notification) {
        guard !isUpdatingGroupExpansion else { return }
        guard let item = notification.userInfo?["NSObject"] as? OutlineItem else { return }
        guard case let .group(name, _, _) = item.kind else { return }
        if !state.entryArrangements.collapsedGroups.contains(name) {
            sendEntryArrangements(.toggleCollapsedGroup(name))
        }
    }
}

extension EntryListCoordinator {
    func observeListStore() {
        observeRenderLoop()
    }

    func observeRenderLoop() {
        renderObservationCancellable?.cancel()
        renderObservationCancellable = store.publisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                let snapshot = RenderSnapshot(state: state)

                guard let previous = lastRenderSnapshot else {
                    lastRenderSnapshot = snapshot
                    return
                }

                handleSnapshotChanges(previous: previous, snapshot: snapshot)

                lastRenderSnapshot = snapshot
            }
    }

    func handleSnapshotChanges(previous: RenderSnapshot, snapshot: RenderSnapshot) {
        handleVisibleColumnsChange(previous: previous, snapshot: snapshot)
        rebuildRowsIfNeeded(previous: previous, snapshot: snapshot)
        resetThumbnailSessionIfNeeded(previous: previous, snapshot: snapshot)
        syncSelectionIfNeeded(previous: previous, snapshot: snapshot)
        reloadVisibleRowsIfNeeded(previous: previous, snapshot: snapshot)
        syncRenamingIfNeeded(previous: previous, snapshot: snapshot)
        syncSortIndicatorsIfNeeded(previous: previous, snapshot: snapshot)
        saveScrollPositionIfNeeded(previous: previous, snapshot: snapshot)
        scrollToSelectionIfNeeded(previous: previous, snapshot: snapshot)
        updateDropTargetBorderIfNeeded(previous: previous, snapshot: snapshot)
        syncThumbnailProjectionIfNeeded(previous: previous, snapshot: snapshot)
    }

    func handleVisibleColumnsChange(previous: RenderSnapshot, snapshot: RenderSnapshot) {
        guard previous.listVisibleColumns != snapshot.listVisibleColumns else { return }
        isApplyingColumnsFromStore = true
        view?.applyColumns(snapshot.listVisibleColumns)
        isApplyingColumnsFromStore = false
        syncListSortIndicators(sortKey: snapshot.sortKey, sortOrder: snapshot.sortOrder)
        syncListRenamingFromStore()
        tableView.reloadData()
        requestThumbnailsForVisibleRows()
    }

    func rebuildRowsIfNeeded(previous: RenderSnapshot, snapshot: RenderSnapshot) {
        if previous.entries != snapshot.entries
            || previous.groupKey != snapshot.groupKey
            || previous.groupedItems != snapshot.groupedItems
        {
            rebuildRowsAndReload()
        }
    }

    func resetThumbnailSessionIfNeeded(previous: RenderSnapshot, snapshot: RenderSnapshot) {
        if previous.currentPath != snapshot.currentPath { resetThumbnailSession()
            hasRestoredScrollPosition = false
        }
    }

    func syncSelectionIfNeeded(previous: RenderSnapshot, snapshot: RenderSnapshot) {
        if previous.selectedIds != snapshot.selectedIds { syncListSelectionFromStore() }
    }

    func reloadVisibleRowsIfNeeded(previous: RenderSnapshot, snapshot: RenderSnapshot) {
        guard previous.clipboardItems != snapshot.clipboardItems
            || previous.clipboardOperation != snapshot.clipboardOperation
        else {
            return
        }

        let rows = tableView.rows(in: tableView.visibleRect)
        guard rows.location != NSNotFound, rows.length > 0 else { return }
        tableView.reloadData(forRowIndexes: IndexSet(integersIn: rows.location ..< NSMaxRange(rows)),
                             columnIndexes: IndexSet(integersIn: 0 ..< tableView.numberOfColumns))
    }

    func syncRenamingIfNeeded(previous: RenderSnapshot, snapshot: RenderSnapshot) {
        if previous.renamingItemId != snapshot.renamingItemId { syncListRenamingFromStore() }
    }

    func syncSortIndicatorsIfNeeded(previous: RenderSnapshot, snapshot: RenderSnapshot) {
        if previous.sortKey != snapshot.sortKey || previous.sortOrder != snapshot.sortOrder {
            syncListSortIndicators(sortKey: snapshot.sortKey, sortOrder: snapshot.sortOrder)
        }
    }

    func saveScrollPositionIfNeeded(previous: RenderSnapshot, snapshot: RenderSnapshot) {
        if previous.showHiddenFiles != snapshot.showHiddenFiles { saveScrollPosition() }
    }

    func scrollToSelectionIfNeeded(previous: RenderSnapshot, snapshot: RenderSnapshot) {
        if !previous.shouldScrollToSelection, snapshot.shouldScrollToSelection { scrollToSelectionIfNeeded() }
    }

    func updateDropTargetBorderIfNeeded(previous: RenderSnapshot, snapshot: RenderSnapshot) {
        if previous.isDropTargeted != snapshot
            .isDropTargeted { updateDropTargetBorder(isTargeted: snapshot.isDropTargeted) }
    }

    func syncThumbnailProjectionIfNeeded(previous: RenderSnapshot, snapshot: RenderSnapshot) {
        guard previous.thumbnailRenderVersion != snapshot.thumbnailRenderVersion else { return }
        refreshThumbnailProjectionForVisibleRows()
    }

    func syncListSortIndicators(sortKey: SortKey, sortOrder: SortOrder) {
        let ascending = sortOrder == .ascending
        let descriptorKey = state.listVisibleColumns
            .first { $0.sortKey == sortKey }?
            .rawValue

        let targetDescriptors: [NSSortDescriptor] = if let descriptorKey {
            [NSSortDescriptor(key: descriptorKey, ascending: ascending)]
        } else {
            []
        }
        let currentSignature = EntryListCoordinatorSortSignature(descriptors: tableView.sortDescriptors)
        let targetSignature = EntryListCoordinatorSortSignature(descriptors: targetDescriptors)
        guard currentSignature != targetSignature else { return }

        sortSyncGate.beginApply(targetSignature)
        tableView.sortDescriptors = targetDescriptors
    }

    func syncListSelectionFromStore() {
        let selectedIds = state.selectedIds
        let indexes = IndexSet(selectedIds.compactMap { id in
            guard let item = entryItemById[id] else { return nil }
            let row = tableView.row(forItem: item)
            return row >= 0 ? row : nil
        })

        isUpdatingSelectionFromStore = true
        tableView.selectRowIndexes(indexes, byExtendingSelection: false)
        isUpdatingSelectionFromStore = false
    }

    func syncListRenamingFromStore() {
        let currentRenamingItemId = state.entryOperations.renamingItemId
        let previousRenamingItemId = lastRenamingItemId
        lastRenamingItemId = currentRenamingItemId

        guard let nameColumnIndex else { return }
        let nameColumnIndexes = IndexSet(integer: nameColumnIndex)

        if let previousRenamingItemId,
           let item = entryItemById[previousRenamingItemId]
        {
            let row = tableView.row(forItem: item)
            if row >= 0 {
                tableView.reloadData(forRowIndexes: IndexSet(integer: row), columnIndexes: nameColumnIndexes)
            }
        }

        guard let renamingItemId = currentRenamingItemId,
              let item = entryItemById[renamingItemId]
        else {
            view?.window?.makeFirstResponder(tableView)
            return
        }

        let row = tableView.row(forItem: item)
        guard row >= 0 else {
            view?.window?.makeFirstResponder(tableView)
            return
        }
        tableView.reloadData(forRowIndexes: IndexSet(integer: row), columnIndexes: nameColumnIndexes)
        beginRenaming(row: row)
    }
}

extension EntryListCoordinator {
    func refreshVisibleNameCellIcons(for paths: Set<String>? = nil) {
        guard tableView.numberOfRows > 0 else { return }
        guard let nameColumnIndex else { return }

        let visibleRange = tableView.rows(in: tableView.visibleRect)
        guard visibleRange.length > 0 else { return }

        let dateModifiedWidth = tableView
            .tableColumn(withIdentifier: NSUserInterfaceItemIdentifier(EntryListColumn.dateModified.rawValue))?
            .width ?? 0

        for row in visibleRange.location ..< (visibleRange.location + visibleRange.length) {
            guard let cell = tableView
                .view(atColumn: nameColumnIndex, row: row, makeIfNecessary: false) as? EntryListEntryCellView
            else {
                continue
            }
            guard let outlineItem = tableView.item(atRow: row) as? OutlineItem else { continue }
            guard case let .entry(entry) = outlineItem.kind else { continue }
            if let paths, !paths.contains(entry.fullPath) { continue }

            let thumbnail = thumbnailImagesByPath[entry.fullPath]
            let configuration = makeEntryCellConfiguration(
                entry: entry,
                columnId: EntryListColumn.name.rawValue,
                columnWidth: dateModifiedWidth,
                thumbnail: thumbnail,
            )
            cell.configure(configuration)
        }
    }
}
