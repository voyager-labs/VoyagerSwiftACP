@preconcurrency import AppKit
import VoyagerEntitiesEntry
import VoyagerFeaturesEntryOperations

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
    ) -> EntryListEntryCellViewConfiguration {
        let isCut = state.entryOperations.clipboardItems.contains(entry.fullPath)
            && state.entryOperations.clipboardOperation == .cut

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
                isRenaming: state.entryOperations.renamingItemId == entry.id,
                renamingText: state.entryOperations.renamingText,
                workspaceClient: workspaceClient,
                onRenameUpdate: { [weak self] text in
                    guard let self else { return }
                    guard state.entryOperations.renamingItemId != nil else { return }
                    sendEntryOperations(.edit(.updateRenamingText(text)))
                },
                onRenameCommit: { [weak self] in
                    guard let self else { return }
                    guard state.entryOperations.renamingItemId != nil else { return }
                    sendEntryOperations(.edit(.commitRename))
                },
                onRenameCancel: { [weak self] in
                    guard let self else { return }
                    guard state.entryOperations.renamingItemId != nil else { return }
                    sendEntryOperations(.edit(.cancelRename))
                },
            ),
        )
    }
}
