import AppKit
import ComposableArchitecture

extension EntryGridCollectionViewController: NSCollectionViewDataSource {
    func numberOfSections(in _: NSCollectionView) -> Int {
        sections.count
    }

    func collectionView(_: NSCollectionView, numberOfItemsInSection section: Int) -> Int {
        sections[section].items.count
    }

    func collectionView(
        _ collectionView: NSCollectionView,
        itemForRepresentedObjectAt indexPath: IndexPath,
    ) -> NSCollectionViewItem {
        let identifier = NSUserInterfaceItemIdentifier("EntryGridCollectionViewItem")
        guard let item = collectionView.makeItem(withIdentifier: identifier, for: indexPath)
            as? EntryGridCollectionViewItem
        else {
            return NSCollectionViewItem()
        }

        let entry = sections[indexPath.section].items[indexPath.item]
        let isCut = store.state.entries.clipboardItems.contains(entry.fullPath)
            && store.state.entries.clipboardOperation == .cut
        let isRenaming = store.state.entries.renamingItemId == entry.id
        let isThumbnailReady = store.state.entries.thumbnailsReady.contains(entry.fullPath)
        let isDropTargeted = dropTargetEntryId == entry.id

        item.configure(.init(
            entry: entry,
            iconSize: store.state.gridIconSize,
            textSize: store.state.gridTextSize,
            isThumbnailReady: isThumbnailReady,
            isCut: isCut,
            isHidden: entry.isHidden,
            isRenaming: isRenaming,
            renamingText: store.state.entries.renamingText,
            isDropTargeted: isDropTargeted,
            workspaceClient: workspaceClient,
            onRenameUpdate: { [weak self] text in
                self?.fsStore.send(.updateRenamingText(text))
            },
            onRenameCommit: { [weak self] in
                self?.fsStore.send(.commitRename)
            },
            onRenameCancel: { [weak self] in
                self?.fsStore.send(.cancelRename)
            },
        ))

        return item
    }

    func collectionView(
        _: NSCollectionView,
        pasteboardWriterForItemAt indexPath: IndexPath,
    ) -> NSPasteboardWriting? {
        guard let entry = entry(at: indexPath) else { return nil }
        return NSURL(fileURLWithPath: entry.fullPath)
    }

    func collectionView(
        _ collectionView: NSCollectionView,
        viewForSupplementaryElementOfKind kind: String,
        at indexPath: IndexPath,
    ) -> NSView {
        guard kind == NSCollectionView.elementKindSectionHeader else {
            return NSView()
        }
        let identifier = NSUserInterfaceItemIdentifier("EntryGridSectionHeaderView")
        guard let header = collectionView.makeSupplementaryView(
            ofKind: kind,
            withIdentifier: identifier,
            for: indexPath,
        ) as? EntryGridSectionHeaderView
        else {
            return NSView()
        }

        let section = sections[indexPath.section]
        header.configure(
            title: section.title,
            count: section.count,
            colorCode: section.colorCode,
            isCollapsed: section.isCollapsed,
            onToggle: { [weak self] in
                guard let self else { return }
                if let title = section.title {
                    fsStore.send(.toggleGroup(title))
                }
            },
        )
        return header
    }
}
