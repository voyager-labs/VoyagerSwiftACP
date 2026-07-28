@preconcurrency import AppKit
import VoyagerEntitiesEntry

extension EntryListCoordinator {
    func makeStatusCell(
        outlineView: NSOutlineView,
        tableColumn: NSTableColumn?,
        title: String,
        retryFolderID: EntryModel.ID?,
    ) -> NSView {
        let resolvedColumn = tableColumn ?? outlineView.outlineTableColumn
        let columnID = resolvedColumn?.identifier.rawValue ?? EntryListColumn.name.rawValue
        guard columnID == outlineView.outlineTableColumn?.identifier.rawValue else {
            let identifier = NSUserInterfaceItemIdentifier("entry-status-empty-cell-\(columnID)")
            let cell = (outlineView.makeView(withIdentifier: identifier, owner: self) as? EntryListEmptyCellView)
                ?? EntryListEmptyCellView()
            cell.identifier = identifier
            return cell
        }

        let identifier = NSUserInterfaceItemIdentifier("entry-status-cell")
        let cell = (outlineView.makeView(withIdentifier: identifier, owner: self) as? EntryListStatusCellView)
            ?? EntryListStatusCellView()
        cell.identifier = identifier
        let onRetry: (() -> Void)? = retryFolderID.map { folderID in
            { [weak self] in
                guard let self else { return }
                sendProjectionIntent(.retry(folderID, revision: state.outlineProjectionRevision))
            }
        }
        cell.configure(title: title, onRetry: onRetry)
        return cell
    }

    func statusTitle(for failure: EntryListHierarchyFailure) -> String {
        switch failure {
        case .permissionDenied:
            "Unable to load folder"
        case let .unavailable(description):
            description
        }
    }

    func makeEntryCellConfiguration(
        entry: EntryModel,
        columnId: String,
        columnWidth: CGFloat,
        thumbnail: NSImage?,
        isLoadingChildren: Bool,
    ) -> EntryListEntryCellViewConfiguration {
        let isCut = state.clipboardCutPaths.contains(entry.fullPath)

        return .init(
            context: .init(
                model: entry,
                columnId: columnId,
                iconSize: state.listIconSize,
                textSize: state.listTextSize,
                columnWidth: columnWidth,
                thumbnail: thumbnail,
                isHidden: entry.isHidden,
                isCut: isCut,
                isLoadingChildren: isLoadingChildren,
                isRenaming: state.renamingItemId == entry.id,
                renamingText: entry.name,
                workspaceClient: workspaceClient,
                onRenameUpdate: { [weak self] text in
                    guard let self else { return }
                    guard state.renamingItemId != nil else { return }
                    store.send(.view(.startRename(item: entry, text: text)))
                },
                onRenameCommit: { [weak self] in
                    guard let self else { return }
                    guard state.renamingItemId != nil else { return }
                    store.send(.view(.commitRename(itemID: entry.id, newName: entry.name)))
                },
                onRenameCancel: { [weak self] in
                    guard let self else { return }
                    guard state.renamingItemId != nil else { return }
                    store.send(.view(.updateSelection(
                        ids: state.selectedIds,
                        lastSelectedId: state.lastSelectedId,
                        rangeAnchorId: state.rangeAnchorId,
                        shouldScrollToSelection: false,
                    )))
                },
            ),
        )
    }

    func makeStatusCell(
        outlineView: NSOutlineView,
        tableColumn: NSTableColumn?,
        title: String,
        retryFolderID: EntryModel.ID?,
    ) -> NSView {
        let resolvedColumn = tableColumn ?? outlineView.outlineTableColumn
        let columnID = resolvedColumn?.identifier.rawValue ?? EntryListColumn.name.rawValue
        guard columnID == outlineView.outlineTableColumn?.identifier.rawValue else {
            let identifier = NSUserInterfaceItemIdentifier("entry-status-empty-cell-\(columnID)")
            let cell = (outlineView.makeView(withIdentifier: identifier, owner: self) as? EntryListEmptyCellView)
                ?? EntryListEmptyCellView()
            cell.identifier = identifier
            return cell
        }

        let identifier = NSUserInterfaceItemIdentifier("entry-status-cell-\(columnID)")
        let cell = (outlineView.makeView(withIdentifier: identifier, owner: self) as? EntryListStatusCellView)
            ?? EntryListStatusCellView()
        cell.identifier = identifier
        cell.setAccessibilityParent(outlineView)
        cell.configure(title: title, retryTitle: retryFolderID == nil ? nil : "Retry") { [weak self] in
            guard let self, let retryFolderID else { return }
            sendProjectionIntent(.retry(retryFolderID, revision: state.outlineProjectionRevision))
        }
        return cell
    }

    func statusTitle(for failure: EntryListHierarchyFailure) -> String {
        switch failure {
        case .permissionDenied:
            "Unable to load folder"
        case let .unavailable(description):
            description
        }
    }
}
