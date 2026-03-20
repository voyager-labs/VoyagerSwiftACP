import AppKit
import ComposableArchitecture
import Foundation
import VoyagerShared

extension EntryGridCoordinator {
    func observeStore() {
        observeRenderLoop()
        observeScrollForThumbnailPrefetch()
    }

    func observeRenderLoop() {
        observe { [weak self] in
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
        if shouldRebuildSections(previous: previous, snapshot: snapshot) {
            rebuildSectionsAndReload()
        }
        syncSelectionIfNeeded(previous: previous, snapshot: snapshot)
        syncRenamingIfNeeded(previous: previous, snapshot: snapshot)
        updateGridMetricsIfNeeded(previous: previous, snapshot: snapshot)
        saveScrollPositionIfNeeded(previous: previous, snapshot: snapshot)
        scrollToSelectionIfNeeded(previous: previous, snapshot: snapshot)
        updateDropTargetBorderIfNeeded(previous: previous, snapshot: snapshot)
        resetThumbnailSessionIfNeeded(previous: previous, snapshot: snapshot)
        restoreScrollOffsetIfNeeded(previous: previous, snapshot: snapshot)
    }

    func shouldRebuildSections(previous: RenderSnapshot, snapshot: RenderSnapshot) -> Bool {
        previous.entries != snapshot.entries || previous.groupKey != snapshot.groupKey
            || previous.groupedItems != snapshot.groupedItems || previous.collapsedGroups != snapshot.collapsedGroups
    }

    func syncSelectionIfNeeded(previous: RenderSnapshot, snapshot: RenderSnapshot) {
        if previous.selectedIds != snapshot.selectedIds { syncSelectionFromStore() }
    }

    func syncRenamingIfNeeded(previous: RenderSnapshot, snapshot: RenderSnapshot) {
        if previous.renamingItemId != snapshot.renamingItemId { syncRenamingFromStore() }
    }

    func updateGridMetricsIfNeeded(previous: RenderSnapshot, snapshot: RenderSnapshot) {
        guard previous.gridIconSize != snapshot.gridIconSize || previous.gridTextSize != snapshot.gridTextSize else {
            return
        }
        if let width = view?.bounds.width { updateLayout(for: width) }
        reloadVisibleItems()
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

    func resetThumbnailSessionIfNeeded(previous: RenderSnapshot, snapshot: RenderSnapshot) {
        if previous.currentPath != snapshot.currentPath { resetThumbnailSession()
            hasRestoredScrollPosition = false
        }
    }

    func restoreScrollOffsetIfNeeded(previous: RenderSnapshot, snapshot: RenderSnapshot) {
        if previous.entriesCount != snapshot.entriesCount { restoreScrollPositionIfNeeded() }
    }

    func observeScrollForThumbnailPrefetch() {
        if let boundsDidChangeObserver {
            notificationCenterClient.removeObserver(boundsDidChangeObserver)
        }
        boundsDidChangeObserver = notificationCenterClient.addObserver(
            NSView.boundsDidChangeNotification,
            scrollView.contentView,
        ) { [weak self] _ in
            DispatchQueue.main.async { [weak self] in
                self?.thumbnailPrefetchThrottler.schedule { [weak self] in
                    self?.requestThumbnailsForVisibleArea()
                }
            }
        }
    }

    func requestThumbnailsForVisibleArea() {
        guard let layout = collectionView.collectionViewLayout else { return }

        let visibleRect = collectionView.visibleRect
        guard visibleRect.height > 0 else { return }

        let prefetchRect = visibleRect.insetBy(dx: 0, dy: -visibleRect.height)

        let indexPaths: [IndexPath] = layout.layoutAttributesForElements(in: prefetchRect).compactMap { attr in
            guard attr.representedElementCategory == .item else { return nil }
            return attr.indexPath
        }
        guard !indexPaths.isEmpty else { return }

        var paths: Set<String> = []
        paths.reserveCapacity(indexPaths.count)
        for indexPath in indexPaths {
            guard let entry = entry(at: indexPath) else { continue }
            guard !entry.isFolder else { continue }
            paths.insert(entry.fullPath)
        }

        guard !paths.isEmpty else { return }
        requestThumbnails(paths: paths)
    }

    func reloadItemsForUpdatedThumbnails(paths: Set<String>) {
        guard !paths.isEmpty else { return }
        var indexPaths = Set<IndexPath>()
        for path in paths {
            guard let indexPath = indexPathByEntryId[path] else { continue }
            indexPaths.insert(indexPath)
        }
        guard !indexPaths.isEmpty else { return }
        collectionView.reloadItems(at: indexPaths)
    }

    func requestThumbnails(paths: Set<String>) {
        pruneThumbnailSession(keeping: paths)
        let scale = NSScreen.main?.backingScaleFactor ?? 3.0
        let size = CGSize(width: 256, height: 256)
        let thumbnailGeneratorClient = thumbnailGeneratorClient
        for path in paths where thumbnailImagesByPath[path] == nil && thumbnailTasksByPath[path] == nil {
            let task = Task.detached(priority: .utility) { [weak self] in
                let image = await thumbnailGeneratorClient.generateThumbnail(
                    for: URL(fileURLWithPath: path),
                    size: size,
                    scale: scale,
                )
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    guard self.thumbnailTasksByPath[path] != nil else { return }
                    self.thumbnailTasksByPath[path] = nil
                    guard let image else { return }
                    self.thumbnailImagesByPath[path] = image
                    self.reloadItemsForUpdatedThumbnails(paths: [path])
                }
            }
            thumbnailTasksByPath[path] = task
        }
    }

    func pruneThumbnailSession(keeping paths: Set<String>) {
        thumbnailImagesByPath = thumbnailImagesByPath.filter { paths.contains($0.key) }
        for (path, task) in thumbnailTasksByPath where !paths.contains(path) {
            task.cancel()
            thumbnailTasksByPath[path] = nil
        }
    }

    func resetThumbnailSession() {
        for task in thumbnailTasksByPath.values {
            task.cancel()
        }
        thumbnailTasksByPath.removeAll(keepingCapacity: false)
        thumbnailImagesByPath.removeAll(keepingCapacity: false)
    }
}

extension EntryGridCoordinator: NSCollectionViewDataSource {
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
        let isCut = state.entryOperations.clipboardItems.contains(entry.fullPath)
            && state.entryOperations.clipboardOperation == .cut
        let isRenaming = state.entryOperations.renamingItemId == entry.id
        let thumbnail = thumbnailImagesByPath[entry.fullPath]
        let isDropTargeted = dropTargetEntryId == entry.id

        item.configure(.init(
            entry: entry,
            iconSize: state.gridIconSize,
            textSize: state.gridTextSize,
            thumbnail: thumbnail,
            isCut: isCut,
            isHidden: entry.isHidden,
            isRenaming: isRenaming,
            renamingText: state.entryOperations.renamingText,
            isDropTargeted: isDropTargeted,
            workspaceClient: workspaceClient,
            onRenameUpdate: { [weak self] text in
                self?.sendEntryOperations(.updateRenamingText(text))
            },
            onRenameCommit: { [weak self] in
                self?.sendEntryOperations(.commitRename)
            },
            onRenameCancel: { [weak self] in
                self?.sendEntryOperations(.cancelRename)
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
        ) as? EntryGridSectionHeaderView else {
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
                    sendEntryArrangements(.toggleCollapsedGroup(title))
                }
            },
        )
        return header
    }
}

extension EntryGridCoordinator: NSCollectionViewDelegate, NSCollectionViewDelegateFlowLayout {
    func collectionView(_ collectionView: NSCollectionView, didSelectItemsAt _: Set<IndexPath>) {
        guard !isLassoSelecting else { return }
        updateSelectionFromCollectionView(collectionView)
    }

    func collectionView(_ collectionView: NSCollectionView, didDeselectItemsAt _: Set<IndexPath>) {
        guard !isLassoSelecting else { return }
        updateSelectionFromCollectionView(collectionView)
    }

    func collectionView(
        _ collectionView: NSCollectionView,
        layout _: NSCollectionViewLayout,
        referenceSizeForHeaderInSection section: Int,
    ) -> NSSize {
        let hasHeader = sections[section].title != nil
        return hasHeader ? NSSize(width: collectionView.bounds.width, height: 32) : .zero
    }

    func collectionView(
        _: NSCollectionView,
        layout _: NSCollectionViewLayout,
        sizeForItemAt _: IndexPath,
    ) -> NSSize {
        flowLayout.itemSize
    }

    func collectionView(
        _: NSCollectionView,
        draggingSession _: NSDraggingSession,
        willBeginAt _: NSPoint,
        forItemsAt indexPaths: Set<IndexPath>,
    ) {
        let paths = indexPaths.compactMap { indexPath -> String? in
            guard let entry = entry(at: indexPath) else { return nil }
            return entry.fullPath
        }
        guard !paths.isEmpty else { return }
        sendEntryOperations(.saveDragPaths(paths))
    }

    func collectionView(
        _: NSCollectionView,
        draggingSession _: NSDraggingSession,
        endedAt _: NSPoint,
        dragOperation operation: NSDragOperation,
    ) {
        guard EntryViewLayoutDragStateClearRuleSet.shouldClearAfterSessionEnd(operation: operation) else { return }
        sendEntryOperations(.saveDragPaths([]))
        store.send(.view(.setDropTargeted(false)))
    }

    @MainActor
    func collectionView(
        _: NSCollectionView,
        validateDrop draggingInfo: any NSDraggingInfo,
        proposedIndexPath proposedDropIndexPath: AutoreleasingUnsafeMutablePointer<NSIndexPath>,
        dropOperation proposedDropOperation: UnsafeMutablePointer<NSCollectionView.DropOperation>,
    ) -> NSDragOperation {
        // proposedIndexPath는 insertion position 기반이라 hover 타겟과 어긋날 수 있습니다.
        // 실제 커서 위치로 hit-test 해서 drop target을 결정합니다.
        let draggingLocation = draggingInfo.draggingLocation
        let localPoint = collectionView.convert(draggingLocation, from: nil)
        let hoverIndexPath = collectionView.indexPathForItem(at: localPoint)

        if let hoverIndexPath {
            proposedDropIndexPath.pointee = hoverIndexPath as NSIndexPath
        }

        let indexPath = hoverIndexPath ?? (proposedDropIndexPath.pointee as IndexPath)
        var destinationPath = state.currentPath
        var targetEntryId: EntryModel.ID?

        if let entry = entry(at: indexPath),
           entry.isFolder,
           !entryLoadingClient.isPackageDirectory(URL(fileURLWithPath: entry.fullPath))
        {
            destinationPath = entry.fullPath
            targetEntryId = entry.id
            proposedDropOperation.pointee = .on
        } else {
            proposedDropOperation.pointee = .before
        }

        let sourcePaths = entryFileOpsClient.loadDragPaths()
        let wantsCopy = sourcePaths.isEmpty
            ? NSEvent.modifierFlags.contains(.option)
            : entryFileOpsClient.loadDragWithOption()
        let allowed = draggingInfo.draggingSourceOperationMask
        sendEntryOperations(.validateDrop(context: .init(
            sourcePaths: sourcePaths,
            destinationPath: destinationPath,
            allowedOperationsRawValue: allowed.rawValue,
            prefersCopy: wantsCopy,
        )))
        let operation = dragOperation(from: state.entryOperations.dropValidationResult.resolvedOperation)

        setDropTargetEntryId(operation.isEmpty ? nil : targetEntryId)
        store.send(.view(.setDropTargeted(!operation.isEmpty)))
        return operation
    }

    func collectionView(
        _: NSCollectionView,
        acceptDrop draggingInfo: NSDraggingInfo,
        indexPath: IndexPath,
        dropOperation: NSCollectionView.DropOperation,
    ) -> Bool {
        var destinationPath = state.currentPath
        if dropOperation == .on,
           let entry = entry(at: indexPath),
           entry.isFolder,
           !entryLoadingClient.isPackageDirectory(URL(fileURLWithPath: entry.fullPath))
        {
            destinationPath = entry.fullPath
        }

        let internalPaths = entryFileOpsClient.loadDragPaths()
        let wantsCopy = internalPaths.isEmpty
            ? NSEvent.modifierFlags.contains(.option)
            : entryFileOpsClient.loadDragWithOption()
        let allowed = draggingInfo.draggingSourceOperationMask
        sendEntryOperations(.validateDrop(context: .init(
            sourcePaths: internalPaths,
            destinationPath: destinationPath,
            allowedOperationsRawValue: allowed.rawValue,
            prefersCopy: wantsCopy,
        )))
        let validation = state.entryOperations.dropValidationResult
        let resolvedOperation = dragOperation(from: validation.resolvedOperation)
        guard !resolvedOperation.isEmpty else {
            setDropTargetEntryId(nil)
            store.send(.view(.setDropTargeted(false)))
            return false
        }

        if !internalPaths.isEmpty {
            sendEntryOperations(.handleDrop(providers: [], destinationPath: destinationPath))
            setDropTargetEntryId(nil)
            store.send(.view(.setDropTargeted(false)))
            return true
        }

        let pasteboard = draggingInfo.draggingPasteboard
        let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        guard let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: options) as? [URL],
              !urls.isEmpty
        else {
            setDropTargetEntryId(nil)
            store.send(.view(.setDropTargeted(false)))
            return false
        }
        sendEntryOperations(.dropItems(
            sourcePaths: urls.map(\.path),
            destinationPath: destinationPath,
            isOptionDrag: validation.isOptionDrag,
        ))
        setDropTargetEntryId(nil)
        store.send(.view(.setDropTargeted(false)))
        return true
    }

    func updateSelectionFromCollectionView(_ collectionView: NSCollectionView) {
        guard !isUpdatingSelectionFromStore else { return }

        let selectedIndexPaths = collectionView.selectionIndexPaths
        let selectedIds: Set<EntryModel.ID> = Set(selectedIndexPaths.compactMap { indexPath in
            entry(at: indexPath)?.id
        })

        let lastSelectedId = selectedIndexPaths
            .max()
            .flatMap { entry(at: $0)?.id }

        let selectedEntries = selectedIndexPaths.compactMap { entry(at: $0) }
        preloadOpenWithApplications(selectedEntries: selectedEntries)
        store.send(.internal(.setSelectionState(
            ids: selectedIds,
            lastSelectedId: lastSelectedId,
            rangeAnchorId: lastSelectedId,
            shouldScrollToSelection: false,
        )))
    }
}

extension EntryGridCoordinator: EntryGridView.EntryGridCollectionViewMenuProviding {
    func contextMenu(for indexPath: IndexPath?, event: NSEvent) -> NSMenu {
        updateContextMenuAnchor(event)
        let rowEntry = entry(at: indexPath)
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
        let coordinator = EntryContextMenuCoordinator(store: store)
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
