@preconcurrency import AppKit
import ComposableArchitecture
import UniformTypeIdentifiers
import VoyagerEntitiesEntry
import VoyagerEntitiesTag

extension EntryListOutlineItem {
    func orderedDistinctEntries() -> [EntryModel] {
        var seen: Set<EntryModel.ID> = []
        return flattenEntries().compactMap { id, item in
            guard seen.insert(id).inserted,
                  case let .entry(entry) = item.kind
            else { return nil }
            return entry
        }
    }
}

struct EntryListCanonicalSelection: Equatable {
    let ids: Set<EntryModel.ID>
    let focus: EntryModel.ID?
    let anchor: EntryModel.ID?
}

struct EntryListSelectionPlan {
    let canonical: EntryListCanonicalSelection
    let physicalRows: IndexSet
    let activeOccurrence: EntryListOutlineItem?
    let anchorOccurrence: EntryListOutlineItem?
}

extension EntryListCoordinator {
    public func outlineView(_: NSOutlineView, shouldCollapseItem _: Any) -> Bool {
        tableView.prepareDisclosureSelectionCallbacks()
        return true
    }

    public func outlineView(_: NSOutlineView, shouldExpandItem _: Any) -> Bool {
        tableView.prepareDisclosureSelectionCallbacks()
        return true
    }

    func handleSelectionMouseDown(forRow row: Int, event: NSEvent, isDisclosureHit: Bool) -> Bool {
        guard let item = tableView.item(atRow: row) as? OutlineItem else { return false }
        guard !isDisclosureHit else { return false }
        if event.modifierFlags.contains(.shift) {
            guard isSelectable(item) else { return true }
            applyRangeSelection(destination: item, destinationRow: row)
            return true
        }
        switch item.kind {
        case .group:
            applyGroupCursorSelection(item)
            return true
        case .entry, .empty, .error:
            return false
        }
    }

    func handleSelectionKeyDown(forRow row: Int, event: NSEvent) -> Bool {
        guard let item = tableView.item(atRow: row) as? OutlineItem,
              isSelectable(item)
        else { return false }
        if event.modifierFlags.contains(.shift) {
            applyRangeSelection(destination: item, destinationRow: row)
        } else if case .group = item.kind {
            applyGroupCursorSelection(item)
        } else {
            applyReplacementSelection(destination: item, destinationRow: row)
        }
        return true
    }

    func prepareContextMenuSelection(
        forRow row: Int,
        event _: NSEvent,
        isDisclosureHit: Bool,
    ) -> EntryListView.ContextMenuSelectionHandling {
        guard let item = tableView.item(atRow: row) as? OutlineItem else { return .suppressed }
        switch item.kind {
        case .group:
            guard !isDisclosureHit else { return .suppressed }
            return applyGroupSelection(item, commandPressed: false).isEmpty ? .suppressed : .prepared
        case .entry:
            return .native
        case .empty, .error:
            return .suppressed
        }
    }

    private func applyGroupCursorSelection(_ item: OutlineItem) {
        guard isSelectable(item),
              let row = tableView.liveRow(for: item)
        else { return }
        applySelectionPlan(EntryListSelectionPlan(
            canonical: EntryListCanonicalSelection(ids: [], focus: nil, anchor: nil),
            physicalRows: IndexSet(integer: row),
            activeOccurrence: item,
            anchorOccurrence: item,
        ))
    }

    @discardableResult
    func applyGroupSelection(_ item: OutlineItem, commandPressed: Bool) -> [EntryModel] {
        let groupEntries = item.orderedDistinctEntries()
        guard !groupEntries.isEmpty else { return [] }

        let presentationIDs = orderedPresentationEntries().map(\.id)
        let validIDs = Set(presentationIDs)
        let groupIDs = Set(groupEntries.map(\.id))
        var selectedIDs = state.selectedIds.intersection(validIDs)
        let focus: EntryModel.ID?
        let activeOccurrence: OutlineItem?

        if commandPressed, groupIDs.isSubset(of: selectedIDs) {
            selectedIDs.subtract(groupIDs)
            focus = presentationIDs.last(where: selectedIDs.contains)
            activeOccurrence = selectionOccurrence(for: focus, preserving: nil)
        } else if commandPressed {
            selectedIDs.formUnion(groupIDs)
            focus = groupEntries.last?.id
            activeOccurrence = item
        } else {
            selectedIDs = groupIDs
            focus = groupEntries.last?.id
            activeOccurrence = item
        }
        let groupRows = tableView.liveRow(for: item).map { IndexSet(integer: $0) } ?? []

        applySelectionPlan(EntryListSelectionPlan(
            canonical: EntryListCanonicalSelection(ids: selectedIDs, focus: focus, anchor: focus),
            physicalRows: physicalSelectionRows(
                for: selectedIDs,
                includingGroupRows: groupRows,
                preservingSelectedGroupRows: commandPressed,
            ),
            activeOccurrence: activeOccurrence,
            anchorOccurrence: activeOccurrence,
        ))
        return groupEntries
    }

    func normalizeNativeSelection(
        physicalRows: IndexSet,
        context: EntryListNativeSelectionContext?,
    ) {
        if let context,
           context.modifierFlags.contains(.command),
           let destination = context.destinationOccurrence as? OutlineItem,
           case let .entry(entry) = destination.kind
        {
            applyNativeCommandSelection(destination: destination, entry: entry)
            return
        }
        if context == nil,
           physicalRows.count == 1,
           let row = physicalRows.first,
           let group = tableView.item(atRow: row) as? OutlineItem,
           case .group = group.kind,
           !group.orderedDistinctEntries().isEmpty
        {
            _ = applyGroupSelection(group, commandPressed: false)
            return
        }
        let entries = orderedEntries(inPhysicalRows: physicalRows)
        let selectedIDs = Set(entries.map(\.id))
        let destination = context?.destinationOccurrence as? OutlineItem
        let destinationRow = tableView.liveRow(for: destination)
        let focus = if let destination,
                       let destinationRow,
                       physicalRows.contains(destinationRow)
        {
            focusIdentifier(for: destination)
        } else {
            orderedPresentationEntries().last(where: { selectedIDs.contains($0.id) })?.id
        }
        let activeOccurrence = if let destination,
                                  let destinationRow,
                                  physicalRows.contains(destinationRow)
        {
            destination
        } else {
            selectionOccurrence(for: focus, preserving: nil)
        }

        preloadOpenWithApplications(selectedEntries: entries)
        applySelectionPlan(EntryListSelectionPlan(
            canonical: EntryListCanonicalSelection(ids: selectedIDs, focus: focus, anchor: focus),
            physicalRows: physicalRows,
            activeOccurrence: activeOccurrence,
            anchorOccurrence: activeOccurrence,
        ))
    }

    private func applyNativeCommandSelection(destination: OutlineItem, entry: EntryModel) {
        let presentationEntries = orderedPresentationEntries()
        let validIDs = Set(presentationEntries.map(\.id))
        var selectedIDs = state.selectedIds.intersection(validIDs)
        if selectedIDs.contains(entry.id) {
            selectedIDs.remove(entry.id)
        } else {
            selectedIDs.insert(entry.id)
        }
        let focus = selectedIDs.contains(entry.id)
            ? entry.id
            : presentationEntries.last(where: { selectedIDs.contains($0.id) })?.id
        let activeOccurrence = selectionOccurrence(
            for: focus,
            preserving: selectedIDs.contains(entry.id) ? destination : nil,
        )
        preloadOpenWithApplications(selectedEntries: presentationEntries.filter { selectedIDs.contains($0.id) })
        applySelectionPlan(EntryListSelectionPlan(
            canonical: EntryListCanonicalSelection(ids: selectedIDs, focus: focus, anchor: focus),
            physicalRows: physicalSelectionRows(for: selectedIDs),
            activeOccurrence: activeOccurrence,
            anchorOccurrence: activeOccurrence,
        ))
    }

    func physicalSelectionRows(
        for selectedIDs: Set<EntryModel.ID>,
        includingGroupRows: IndexSet = [],
        preservingSelectedGroupRows: Bool = true,
        forcingGroupRows: IndexSet = [],
    ) -> IndexSet {
        let includedGroupNames = Set(includingGroupRows.compactMap { row -> String? in
            guard let item = tableView.item(atRow: row) as? OutlineItem,
                  case let .group(name, _, _) = item.kind
            else { return nil }
            return name
        })
        let selectedGroupNames = preservingSelectedGroupRows
            ? tableView.selectedGroupNames.union(includedGroupNames)
            : includedGroupNames
        let forcedGroupNames = Set(forcingGroupRows.compactMap { row -> String? in
            guard let item = tableView.item(atRow: row) as? OutlineItem,
                  case let .group(name, _, _) = item.kind
            else { return nil }
            return name
        })
        var indexes = IndexSet()
        for row in 0 ..< tableView.numberOfRows {
            guard let item = tableView.item(atRow: row) as? OutlineItem else { continue }
            switch item.kind {
            case let .group(name, _, _):
                let groupIDs = item.orderedDistinctEntries().map(\.id)
                if forcedGroupNames.contains(name)
                    || (selectedGroupNames.contains(name)
                        && !groupIDs.isEmpty
                        && groupIDs.allSatisfy(selectedIDs.contains))
                {
                    indexes.insert(row)
                }
            case let .entry(entry) where selectedIDs.contains(entry.id):
                indexes.insert(row)
            case .entry, .empty, .error:
                break
            }
        }
        return indexes
    }

    func selectionOccurrence(
        for id: EntryModel.ID?,
        preserving occurrence: AnyObject?,
    ) -> OutlineItem? {
        if id == nil,
           let occurrence = occurrence as? OutlineItem,
           case let .group(name, _, _) = occurrence.kind
        {
            if tableView.liveRow(for: occurrence) != nil {
                return occurrence
            }
            for row in 0 ..< tableView.numberOfRows {
                guard let item = tableView.item(atRow: row) as? OutlineItem,
                      case let .group(currentName, _, _) = item.kind,
                      currentName == name
                else { continue }
                return item
            }
            return nil
        }
        guard let id else { return nil }
        if let occurrence = occurrence as? OutlineItem,
           occurrenceRepresents(occurrence, id: id)
        {
            if tableView.liveRow(for: occurrence) != nil {
                return occurrence
            }
            if case let .group(name, _, _) = occurrence.kind {
                for row in 0 ..< tableView.numberOfRows {
                    guard let item = tableView.item(atRow: row) as? OutlineItem,
                          case let .group(currentName, _, _) = item.kind,
                          currentName == name,
                          occurrenceRepresents(item, id: id)
                    else { continue }
                    return item
                }
            }
        }

        for row in 0 ..< tableView.numberOfRows {
            guard let item = tableView.item(atRow: row) as? OutlineItem,
                  case let .entry(entry) = item.kind,
                  entry.id == id
            else { continue }
            return item
        }
        for row in 0 ..< tableView.numberOfRows {
            guard let item = tableView.item(atRow: row) as? OutlineItem,
                  case .group = item.kind,
                  occurrenceRepresents(item, id: id)
            else { continue }
            return item
        }
        return nil
    }

    func preservedSelectionOccurrence(
        _ occurrence: AnyObject?,
        focus: EntryModel.ID?,
    ) -> AnyObject? {
        guard let occurrence = occurrence as? EntryListOutlineItem,
              case .group = occurrence.kind
        else { return occurrence }
        let entries = occurrence.orderedDistinctEntries()
        guard focus == nil || entries.allSatisfy({ state.selectedIds.contains($0.id) }) else { return nil }
        return occurrence
    }

    private func applyRangeSelection(destination: OutlineItem, destinationRow: Int) {
        let anchorOccurrence = [tableView.rangeAnchorOccurrence, tableView.activeSelectionOccurrence]
            .compactMap { $0 as? OutlineItem }
            .first(where: { tableView.liveRow(for: $0) != nil })
        guard let anchorOccurrence,
              let anchorRow = tableView.liveRow(for: anchorOccurrence)
        else {
            applyReplacementSelection(destination: destination, destinationRow: destinationRow)
            return
        }

        let bounds = min(anchorRow, destinationRow) ... max(anchorRow, destinationRow)
        let rangeRows = IndexSet(bounds.filter { row in
            guard let item = tableView.item(atRow: row) as? OutlineItem else { return false }
            return isSelectable(item)
        })
        let selectedEntries = orderedEntries(
            inPhysicalRows: rangeRows,
            anchorRow: anchorRow,
            destinationRow: destinationRow,
        )
        let selectedIDs = Set(selectedEntries.map(\.id))
        let validIDs = Set(orderedPresentationEntries().map(\.id))
        let anchor = state.rangeAnchorId.flatMap { validIDs.contains($0) ? $0 : nil }
            ?? focusIdentifier(for: anchorOccurrence)
        applySelectionPlan(EntryListSelectionPlan(
            canonical: EntryListCanonicalSelection(
                ids: selectedIDs,
                focus: focusIdentifier(for: destination),
                anchor: anchor,
            ),
            physicalRows: physicalSelectionRows(
                for: selectedIDs,
                includingGroupRows: rangeRows,
                preservingSelectedGroupRows: false,
            ),
            activeOccurrence: destination,
            anchorOccurrence: anchorOccurrence,
        ))
    }

    private func applyReplacementSelection(destination: OutlineItem, destinationRow: Int) {
        if case .group = destination.kind {
            applyGroupCursorSelection(destination)
            return
        }
        let entries = selectionEntries(for: destination)
        guard !entries.isEmpty else { return }
        let selectedIDs = Set(entries.map(\.id))
        let physicalRows: IndexSet = if case .group = destination.kind {
            physicalSelectionRows(
                for: selectedIDs,
                includingGroupRows: IndexSet(integer: destinationRow),
                preservingSelectedGroupRows: false,
            )
        } else {
            IndexSet(integer: destinationRow)
        }
        let focus = entries.last?.id
        applySelectionPlan(EntryListSelectionPlan(
            canonical: EntryListCanonicalSelection(ids: selectedIDs, focus: focus, anchor: focus),
            physicalRows: physicalRows,
            activeOccurrence: destination,
            anchorOccurrence: destination,
        ))
    }

    private func applySelectionPlan(_ plan: EntryListSelectionPlan) {
        isUpdatingSelectionFromStore = true
        defer { isUpdatingSelectionFromStore = false }
        tableView.applyCanonicalSelection(
            plan.physicalRows,
            activeOccurrence: plan.activeOccurrence,
            anchorOccurrence: plan.anchorOccurrence,
        )
        guard plan.canonical.ids != state.selectedIds
            || plan.canonical.focus != state.lastSelectedId
            || plan.canonical.anchor != state.rangeAnchorId
        else { return }
        store.send(.view(.updateSelection(
            ids: plan.canonical.ids,
            lastSelectedId: plan.canonical.focus,
            rangeAnchorId: plan.canonical.anchor,
            shouldScrollToSelection: false,
        )))
    }

    private func orderedPresentationEntries() -> [EntryModel] {
        var seen: Set<EntryModel.ID> = []
        return outlineItems.flatMap { item in
            item.orderedDistinctEntries().compactMap { entry in
                seen.insert(entry.id).inserted ? entry : nil
            }
        }
    }

    private func orderedEntries(
        inPhysicalRows rows: IndexSet,
        anchorRow: Int? = nil,
        destinationRow: Int? = nil,
    ) -> [EntryModel] {
        var seen: Set<EntryModel.ID> = []
        let entries = rows.flatMap { row -> [EntryModel] in
            guard let item = tableView.item(atRow: row) as? OutlineItem else { return [] }
            switch item.kind {
            case .group:
                guard (anchorRow == nil && destinationRow == nil)
                    || anchorRow == row
                    || destinationRow == row
                else { return [] }
                return item.orderedDistinctEntries()
            case let .entry(entry):
                return [entry]
            case .empty, .error:
                return []
            }
        }
        return entries.compactMap { entry in
            seen.insert(entry.id).inserted ? entry : nil
        }
    }

    private func focusIdentifier(for item: OutlineItem) -> EntryModel.ID? {
        selectionEntries(for: item).last?.id
    }

    private func selectionEntries(for item: OutlineItem) -> [EntryModel] {
        switch item.kind {
        case let .entry(entry):
            [entry]
        case .group:
            item.orderedDistinctEntries()
        case .empty, .error:
            []
        }
    }

    private func isSelectable(_ item: OutlineItem) -> Bool {
        !item.orderedDistinctEntries().isEmpty
    }

    private func occurrenceRepresents(_ item: OutlineItem, id: EntryModel.ID) -> Bool {
        item.orderedDistinctEntries().contains(where: { $0.id == id })
    }
}

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
            self?.store.send(.view(action))
        }
    }

    func syncVisibleColumnsFromTableView() {
        let columns = tableView.tableColumns.compactMap { tableColumn in
            EntryListColumn(rawValue: tableColumn.identifier.rawValue)
        }
        let normalized = EntryListColumn.normalizeVisibleColumns(columns)
        if normalized != state.listVisibleColumns {
            store.send(.view(.updateListVisibleColumns(normalized)))
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
        store.send(.view(.preloadOpenWithApplications(selectedEntries)))
    }

    func openWithApplications(selectedEntries _: [EntryModel]) -> [ApplicationInfo] {
        state.entryOperations.commonApplicationsForSelectedFiles
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
        guard let trashPath = state.trashDirectoryPath else {
            return false
        }
        let path = state.currentPath
        return path == trashPath || path.hasPrefix(trashPath + "/")
    }
}

extension EntryListCoordinator: EntryListView.EntryListTableViewContextMenuProviding {
    func contextMenu(forRow row: Int?, event _: NSEvent) -> NSMenu {
        updateContextMenuAnchor(forRow: row)
        let rowItem = row.flatMap { tableView.item(atRow: $0) as? OutlineItem }
        let rowEntry = entryForRow(row)
        let target: EntryContextMenuTarget
        if let rowItem, case .group = rowItem.kind {
            let entries = rowItem.orderedDistinctEntries()
            guard !entries.isEmpty else { return NSMenu() }
            target = .init(selectedIds: Set(entries.map(\.id)), entries: entries)
        } else if let rowItem, case .empty = rowItem.kind {
            return NSMenu()
        } else if let rowItem, case .error = rowItem.kind {
            return NSMenu()
        } else {
            let displayEntries = state.hierarchyProjectionIsActive
                ? state.visibleSelectableEntries(isNormalDirectoryPage: true)
                : state.entries
            target = EntryContextMenuTarget.resolve(
                displayEntries: displayEntries,
                selectedIds: state.selectedIds,
                rowEntry: rowEntry,
            )
        }
        synchronizeContextMenuSelection(target)
        preloadOpenWithApplications(selectedEntries: target.entries)
        let serviceNames = entryOpenClient.serviceNames()
        let menuSpec = makeMenuSpec(target: target, rowEntry: rowEntry, serviceNames: serviceNames)
        let coordinator = EntryContextMenuCoordinator(
            store: store,
            target: target,
            anchorView: tableView,
            anchorScreenPoint: contextMenuAnchor,
        )
        contextMenuCoordinator = coordinator
        return coordinator.observeOpenWithMenu(EntryContextMenuBuilder.makeMenu(
            configuration: makeMenuConfiguration(target: target, menuSpec: menuSpec, coordinator: coordinator),
        ))
    }

    private func makeMenuSpec(
        target: EntryContextMenuTarget,
        rowEntry: EntryModel?,
        serviceNames: [String],
    ) -> EntryContextMenuSpec {
        EntryContextMenuSpecFactory.make(
            selectedIds: target.selectedIds,
            selectedEntries: target.entries,
            rowEntry: rowEntry,
            isTrashFolder: isTrashFolder,
            restorableTrashPaths: state.entryOperations.restorableTrashPaths,
            canPaste: !state.entryOperations.clipboardItems.isEmpty,
            favoriteTags: finderFavoritesTagClient.favoriteTags(),
            openWithApplications: openWithApplications(selectedEntries: target.entries),
            isOpenWithApplicationsLoading: target.entries.contains { entry in
                guard !entry.isFolder else { return false }
                let typeID = UTType(filenameExtension: entry.fileExtension)?.identifier ?? UTType.data.identifier
                return state.entryOperations.openWithInFlightTypeIDs.contains(typeID)
                    || state.entryOperations.applicationsForTypes[typeID] == nil
            },
            serviceNames: serviceNames,
        )
    }

    private func makeMenuConfiguration(
        target: EntryContextMenuTarget,
        menuSpec: EntryContextMenuSpec,
        coordinator: EntryContextMenuCoordinator,
    ) -> EntryContextMenuBuilder.Configuration {
        .init(
            target: coordinator,
            selectedCount: menuSpec.selectedCount,
            rowEntryPathForOpenInNewWindow: menuSpec.rowEntryPathForOpenInNewWindow,
            openInNewTabPaths: menuSpec.openInNewTabPaths,
            serviceNames: menuSpec.serviceNames,
            canPaste: menuSpec.canPaste,
            showCompress: menuSpec.showCompress,
            showExtract: menuSpec.showExtract,
            isTrashFolder: menuSpec.isTrashFolder,
            canPutBack: menuSpec.canPutBack,
            openWithApplications: menuSpec.openWithApplications,
            showOpenWith: menuSpec.showOpenWith,
            paletteTags: menuSpec.paletteTags,
            knownTags: menuSpec.knownTags,
            canPerformEntryCommands: (!state.entryOperations.isLoading || state.isCollectionMode)
                && !target.containsBusyEntry(
                    busyEntryPaths: Set(state.entryOperations.itemStates.filter(\.value.isBusy).map(\.key)),
                ),
            isOpenWithApplicationsLoading: menuSpec.isOpenWithApplicationsLoading,
        )
    }

    private func synchronizeContextMenuSelection(_ target: EntryContextMenuTarget) {
        guard state.selectedIds != target.selectedIds else { return }
        _ = MainActor.assumeIsolated {
            store.send(.view(.updateSelection(
                ids: target.selectedIds,
                lastSelectedId: target.entries.last?.id,
                rangeAnchorId: target.entries.last?.id,
                shouldScrollToSelection: false,
            )))
        }
    }
}
