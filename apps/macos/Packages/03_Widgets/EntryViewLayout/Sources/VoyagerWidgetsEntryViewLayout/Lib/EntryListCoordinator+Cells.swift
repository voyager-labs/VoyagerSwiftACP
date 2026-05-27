@preconcurrency import AppKit
import VoyagerEntitiesEntry
import VoyagerFeaturesEntryOperations

extension EntryListCoordinator {
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
