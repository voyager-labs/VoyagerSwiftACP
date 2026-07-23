@preconcurrency import AppKit
import Combine
import ComposableArchitecture
import VoyagerEntitiesEntry
import VoyagerShared

public extension EntryListCoordinator {
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

extension EntryListOutlineItem {
    func flattenEntries() -> [(EntryModel.ID, EntryListOutlineItem)] {
        switch kind {
        case let .entry(entry):
            [(entry.id, self)] + children.flatMap { $0.flattenEntries() }
        case .group, .empty, .error:
            children.flatMap { $0.flattenEntries() }
        }
    }

    func flattenItems() -> [(String, EntryListOutlineItem)] {
        [(id, self)] + children.flatMap { $0.flattenItems() }
    }
}

extension EntryListCoordinator: NSOutlineViewDelegate {
    public func outlineView(_: NSOutlineView, rowViewForItem _: Any) -> NSTableRowView? {
        EntryListSelectionRowView()
    }

    public func outlineView(_: NSOutlineView, shouldEdit tableColumn: NSTableColumn?, item: Any) -> Bool {
        guard let tableColumn else { return false }
        guard tableColumn.identifier.rawValue == EntryListColumn.name.rawValue else { return false }
        guard let outlineItem = item as? OutlineItem else { return false }
        guard case let .entry(entry) = outlineItem.kind else { return false }
        guard state.renamingItemId == entry.id else { return false }
        return true
    }

    public func outlineView(
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
        store.send(.view(.startDrag(paths: paths)))
    }

    public func outlineView(
        _: NSOutlineView,
        draggingSession _: NSDraggingSession,
        endedAt _: NSPoint,
        operation: NSDragOperation,
    ) {
        guard EntryViewLayoutDragStateClearRuleSet.shouldClearAfterSessionEnd(operation: operation) else { return }
        store.send(.view(.startDrag(paths: [])))
        store.send(.view(.setDropTargeted(false)))
    }

    public func outlineView(_ outlineView: NSOutlineView, sortDescriptorsDidChange _: [NSSortDescriptor]) {
        let signature = EntryListCoordinatorSortSignature(descriptors: outlineView.sortDescriptors)
        guard !sortSyncGate.consumeIfSuppressed(signature) else { return }

        guard let change = EntryListCoordinatorSortDescriptorMapper.change(from: outlineView.sortDescriptors)
        else { return }
        let needed = EntryListCoordinatorSortDescriptorMapper.actionsNeeded(
            currentSortKey: state.sortKey.sharedSortKey,
            currentSortOrder: state.sortOrder,
            change: change,
        )
        if let sortKey = needed.sortKey {
            let widgetSortKey = EntryViewLayoutSortKey.fromShared(sortKey)
            store.send(.delegate(.sortChanged(widgetSortKey, needed.sortOrder ?? state.sortOrder)))
        }
        if let sortOrder = needed.sortOrder {
            store.send(.delegate(.sortChanged(state.sortKey, sortOrder)))
        }
    }

    public func outlineViewColumnDidMove(_ notification: Notification) {
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

    public func outlineViewColumnDidResize(_ notification: Notification) {
        guard let column = notification.userInfo?["NSTableColumn"] as? NSTableColumn else { return }
        guard column.identifier.rawValue == EntryListColumn.dateModified.rawValue else { return }
        dateModifiedResizeDebouncer.schedule { [weak self] in
            self?.reloadVisibleDateModifiedCells()
        }
    }

    public func outlineView(_: NSOutlineView, isGroupItem item: Any) -> Bool {
        guard let outlineItem = item as? OutlineItem else { return false }
        if case .group = outlineItem.kind {
            return true
        }
        return false
    }

    public func outlineView(_: NSOutlineView, shouldSelectItem item: Any) -> Bool {
        guard let outlineItem = item as? OutlineItem else { return false }
        switch outlineItem.kind {
        case .entry:
            return true
        case .group, .empty, .error:
            return false
        }
    }

    public func outlineView(_ outlineView: NSOutlineView, heightOfRowByItem item: Any) -> CGFloat {
        guard let outlineItem = item as? OutlineItem else { return outlineView.rowHeight }
        switch outlineItem.kind {
        case .group:
            return 32
        case .entry:
            return max(24, state.listIconSize + 4)
        case .empty, .error:
            return 24
        }
    }

    public func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
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
            return makeEntryCell(
                outlineView: outlineView,
                columnId: columnId,
                entry: entry,
                isLoadingChildren: outlineItem.isLoadingChildren,
            )
        case .empty:
            return makeStatusCell(
                outlineView: outlineView,
                tableColumn: tableColumn,
                title: "Empty folder",
                retryFolderID: nil,
            )
        case let .error(parent, failure):
            return makeStatusCell(
                outlineView: outlineView,
                tableColumn: tableColumn,
                title: statusTitle(for: failure),
                retryFolderID: parent,
            )
        }
    }

    private func makeEntryCell(
        outlineView: NSOutlineView,
        columnId: String,
        entry: EntryModel,
        isLoadingChildren: Bool,
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
            isLoadingChildren: isLoadingChildren,
        )
        view.configure(configuration)
        return view
    }

    public func outlineViewSelectionDidChange(_: Notification) {
        guard !isUpdatingSelectionFromStore, !projectionSession.isApplyingStoreProjection else { return }

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

        let acceptedIDs = Set(selectedEntries.map(\.id))
        preloadOpenWithApplications(selectedEntries: selectedEntries)
        store.send(.internal(.setSelectionState(
            ids: acceptedIDs,
            lastSelectedId: lastSelectedId,
            rangeAnchorId: lastSelectedId,
            shouldScrollToSelection: false,
        )))
    }

    public func outlineViewItemDidExpand(_ notification: Notification) {
        guard !isUpdatingGroupExpansion, !projectionSession.isApplyingStoreProjection else { return }
        guard let item = notification.userInfo?["NSObject"] as? OutlineItem else { return }
        guard isCurrentOutlineItem(item) else { return }
        switch item.kind {
        case let .group(name, _, _):
            if state.collapsedGroups.contains(name) {
                store.send(.delegate(.groupChanged(state.groupKey)))
            }
        case let .entry(entry) where isHierarchyOutlineEnabled:
            sendProjectionIntent(.disclosureExpand(entry.id, revision: state.outlineProjectionRevision))
        case .entry, .empty, .error:
            return
        }
    }

    public func outlineViewItemDidCollapse(_ notification: Notification) {
        guard !isUpdatingGroupExpansion, !projectionSession.isApplyingStoreProjection else { return }
        guard let item = notification.userInfo?["NSObject"] as? OutlineItem else { return }
        guard isCurrentOutlineItem(item) else { return }
        switch item.kind {
        case let .group(name, _, _):
            if !state.collapsedGroups.contains(name) {
                store.send(.delegate(.groupChanged(state.groupKey)))
            }
        case let .entry(entry) where isHierarchyOutlineEnabled:
            sendProjectionIntent(.disclosureCollapse(entry.id, revision: state.outlineProjectionRevision))
        case .entry, .empty, .error:
            return
        }
    }

    func sendProjectionIntent(_ intent: EntryListCoordinatorProjectionIntent) {
        guard let acceptedIntent = projectionSession.accept(intent) else { return }
        switch acceptedIntent {
        case let .folderExpansionRequested(id):
            store.send(.hierarchy(.folderExpansionRequested(id: id)))
        case let .folderCollapseRequested(id):
            store.send(.hierarchy(.folderCollapseRequested(id: id)))
        case let .folderRetryRequested(id):
            store.send(.hierarchy(.folderRetryRequested(id: id)))
        case .selection, .navigate:
            break
        }
    }
}

extension EntryListCoordinator {
    public func observeListStore() {
        observeRenderLoop()
    }

    public func observeRenderLoop() {
        renderObservationCancellable?.cancel()
        renderObservationCancellable = store.publisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                renderThrottler.schedule { [weak self] in
                    self?.processRender()
                }
            }
    }

    private func processRender() {
        let snapshot = RenderSnapshot(state: state)

        guard let previous = lastRenderSnapshot else {
            lastRenderSnapshot = snapshot
            return
        }

        handleSnapshotChanges(previous: previous, snapshot: snapshot)

        lastRenderSnapshot = snapshot
    }

    func handleSnapshotChanges(previous: RenderSnapshot, snapshot: RenderSnapshot) {
        handleVisibleColumnsChange(previous: previous, snapshot: snapshot)
        rebuildRowsIfNeeded(previous: previous, snapshot: snapshot)
        updateListMetricsIfNeeded(previous: previous, snapshot: snapshot)
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
        syncListSortIndicators(sortKey: snapshot.sortKey.sharedSortKey, sortOrder: snapshot.sortOrder)
        syncListRenamingFromStore()
        tableView.reloadData()
        requestThumbnailsForVisibleRows()
    }

    func rebuildRowsIfNeeded(previous: RenderSnapshot, snapshot: RenderSnapshot) {
        guard previous.isHierarchyOutlineEnabled == snapshot.isHierarchyOutlineEnabled else {
            rebuildRowsAndReload()
            return
        }

        if snapshot.isHierarchyOutlineEnabled {
            if previous.outlineProjection != snapshot.outlineProjection {
                rebuildRowsAndReload()
            }
            return
        }

        if previous.entries != snapshot.entries
            || previous.groupKey != snapshot.groupKey
            || !previous.outlineProjection.hasSameStructure(as: snapshot.outlineProjection)
            || previous.isHierarchyOutlineEnabled != snapshot.isHierarchyOutlineEnabled
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
        guard previous.clipboardCutPaths != snapshot.clipboardCutPaths
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
            syncListSortIndicators(sortKey: snapshot.sortKey.sharedSortKey, sortOrder: snapshot.sortOrder)
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

    public func syncListSortIndicators(sortKey: SortKey, sortOrder: VoyagerShared.SortOrder) {
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

    public func syncListSelectionFromStore() {
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

    public func syncListRenamingFromStore() {
        let currentRenamingItemId = state.renamingItemId
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

public extension EntryListCoordinator {
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
                isLoadingChildren: outlineItem.isLoadingChildren,
            )
            cell.configure(configuration)
        }
    }
}
