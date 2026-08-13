@preconcurrency import AppKit
import ComposableArchitecture
import Foundation
import SwiftNavigation
import VoyagerEntitiesEntry
import VoyagerEntitiesTag
import VoyagerShared

extension EntryGridCoordinator {
    public func observeStore() {
        observeRenderLoop()
        observeScrollForThumbnailPrefetch()
    }

    public func observeRenderLoop() {
        observe { [weak self] in
            guard let self else { return }
            let snapshot = RenderSnapshot(state: state)
            guard isRenderObservationEnabled else { return }

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
        } else if !applyIncrementalEntryRemoval(previous: previous, snapshot: snapshot) {
            reloadVisibleItemsForEntryContentChange(previous: previous, snapshot: snapshot)
        }
        syncSelectionIfNeeded(previous: previous, snapshot: snapshot)
        reloadVisibleItemsIfNeeded(previous: previous, snapshot: snapshot)
        syncRenamingIfNeeded(previous: previous, snapshot: snapshot)
        updateGridMetricsIfNeeded(previous: previous, snapshot: snapshot)
        saveScrollPositionIfNeeded(previous: previous, snapshot: snapshot)
        scrollToSelectionIfNeeded(previous: previous, snapshot: snapshot)
        updateDropTargetBorderIfNeeded(previous: previous, snapshot: snapshot)
        syncThumbnailProjectionIfNeeded(previous: previous, snapshot: snapshot)
        resetThumbnailSessionIfNeeded(previous: previous, snapshot: snapshot)
        restoreScrollOffsetIfNeeded(previous: previous, snapshot: snapshot)
    }

    func shouldRebuildSections(previous: RenderSnapshot, snapshot: RenderSnapshot) -> Bool {
        let changes = snapshot.presentation.changes(from: previous.presentation)
        guard changes.sectionStructureChanged || changes.groupExpansionChanged else { return false }
        guard !changes.groupExpansionChanged else { return true }

        let previousSections = previous.presentation.sections
        let nextSections = snapshot.presentation.sections
        let isSingleUngroupedSection = previousSections.count == 1
            && nextSections.count == 1
            && previousSections[0].title == nil
            && nextSections[0].title == nil
        guard isSingleUngroupedSection else { return true }

        let previousIDs = previous.entries.map(\.id)
        let nextIDs = snapshot.entries.map(\.id)
        return !canApplyIncrementalEntryRemoval(previousIDs: previousIDs, nextIDs: nextIDs)
    }

    func reloadVisibleItemsForEntryContentChange(previous: RenderSnapshot, snapshot: RenderSnapshot) {
        let changedIDs = snapshot.presentation.changes(from: previous.presentation).updatedEntryIDs
        guard !changedIDs.isEmpty else { return }
        updateSectionsFromState()
        let visibleIndexPaths: Set<IndexPath> = MainActor.assumeIsolated {
            collectionView.indexPathsForVisibleItems()
        }
        let changedIndexPaths = Set(changedIDs.compactMap { indexPathByEntryId[$0] })
            .intersection(visibleIndexPaths)
        guard !changedIndexPaths.isEmpty else { return }
        MainActor.assumeIsolated {
            collectionView.reloadItems(at: changedIndexPaths)
        }
    }

    func applyIncrementalEntryRemoval(previous: RenderSnapshot, snapshot: RenderSnapshot) -> Bool {
        let previousIDs = previous.entries.map(\.id)
        let nextIDs = snapshot.entries.map(\.id)
        guard canApplyIncrementalEntryRemoval(previousIDs: previousIDs, nextIDs: nextIDs) else { return false }

        let nextIDSet = Set(nextIDs)
        let removedIndexPaths = Set(previousIDs.enumerated().compactMap { index, id in
            nextIDSet.contains(id) ? nil : IndexPath(item: index, section: 0)
        })
        updateSectionsFromState()
        MainActor.assumeIsolated {
            collectionView.performBatchUpdates {
                collectionView.deleteItems(at: removedIndexPaths)
            }
        }
        return true
    }

    func canApplyIncrementalEntryRemoval(
        previousIDs: [EntryModel.ID],
        nextIDs: [EntryModel.ID],
    ) -> Bool {
        let nextIDSet = Set(nextIDs)
        return previousIDs.count > nextIDs.count
            && previousIDs.filter(nextIDSet.contains) == nextIDs
    }

    func syncSelectionIfNeeded(previous: RenderSnapshot, snapshot: RenderSnapshot) {
        if previous.selectedIds != snapshot.selectedIds { syncSelectionFromStore() }
    }

    func reloadVisibleItemsIfNeeded(previous: RenderSnapshot, snapshot: RenderSnapshot) {
        guard previous.clipboardCutPaths != snapshot.clipboardCutPaths else { return }
        reloadVisibleItems()
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
        if previous.currentPath != snapshot.currentPath {
            resetThumbnailSession()
            hasRestoredScrollPosition = false
        }
    }

    func syncThumbnailProjectionIfNeeded(previous: RenderSnapshot, snapshot: RenderSnapshot) {
        guard previous.outlineProjectionRevision != snapshot.outlineProjectionRevision else { return }
        refreshThumbnailProjectionForVisibleArea()
    }

    func restoreScrollOffsetIfNeeded(previous: RenderSnapshot, snapshot: RenderSnapshot) {
        if previous.entriesCount != snapshot.entriesCount { restoreScrollPositionIfNeeded() }
    }

    public func observeScrollForThumbnailPrefetch() {
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

    public func requestThumbnailsForVisibleArea() {
        guard let layout = collectionView.collectionViewLayout else { return }
        let visibleRect = collectionView.visibleRect
        guard visibleRect.height > 0 else { return }

        let prefetchRect = visibleRect.insetBy(dx: 0, dy: -visibleRect.height)

        let layoutAttrs: [NSCollectionViewLayoutAttributes] = MainActor.assumeIsolated {
            layout.layoutAttributesForElements(in: prefetchRect)
        }
        let indexPaths: [IndexPath] = layoutAttrs.compactMap { attr in
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
        pruneThumbnailSession(keeping: paths)
        reloadItemsForUpdatedThumbnails(paths: refreshThumbnailProjection(paths: paths))
    }

    public func reloadItemsForUpdatedThumbnails(paths: Set<String>) {
        guard !paths.isEmpty else { return }
        var indexPaths = Set<IndexPath>()
        for path in paths {
            guard let indexPath = indexPathByEntryId[path] else { continue }
            indexPaths.insert(indexPath)
        }
        guard !indexPaths.isEmpty else { return }
        collectionView.reloadItems(at: indexPaths)
    }

    public func pruneThumbnailSession(keeping paths: Set<String>) {
        thumbnailImagesByPath = thumbnailImagesByPath.filter { paths.contains($0.key) }
    }

    public func resetThumbnailSession() {
        thumbnailImagesByPath.removeAll(keepingCapacity: false)
    }

    public func refreshThumbnailProjection(paths: Set<String>) -> Set<String> {
        var changedPaths: Set<String> = []

        for path in paths {
            let cachedImage = entryThumbnailCacheClient.getThumbnail(for: path)
            if let cachedImage {
                if thumbnailImagesByPath[path] == nil {
                    changedPaths.insert(path)
                }
                thumbnailImagesByPath[path] = cachedImage
            } else if thumbnailImagesByPath.removeValue(forKey: path) != nil {
                changedPaths.insert(path)
            }
        }

        return changedPaths
    }

    public func refreshThumbnailProjectionForVisibleArea() {
        guard let layout = collectionView.collectionViewLayout else { return }
        let visibleRect = collectionView.visibleRect
        guard visibleRect.height > 0 else { return }

        let layoutAttrs: [NSCollectionViewLayoutAttributes] = MainActor.assumeIsolated {
            layout.layoutAttributesForElements(in: visibleRect)
        }
        let indexPaths: [IndexPath] = layoutAttrs.compactMap { attr in
            guard attr.representedElementCategory == .item else { return nil }
            return attr.indexPath
        }
        guard !indexPaths.isEmpty else { return }

        var visiblePaths: Set<String> = []
        for indexPath in indexPaths {
            guard let entry = entry(at: indexPath), !entry.isFolder else { continue }
            visiblePaths.insert(entry.fullPath)
        }

        reloadItemsForUpdatedThumbnails(paths: refreshThumbnailProjection(paths: visiblePaths))
    }
}

extension EntryGridCoordinator: NSCollectionViewDataSource {
    public func numberOfSections(in _: NSCollectionView) -> Int {
        sections.count
    }

    public func collectionView(_: NSCollectionView, numberOfItemsInSection section: Int) -> Int {
        sections[section].items.count
    }

    public func collectionView(
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
        let isCut = state.entryOperations.clipboardOperation == .cut
            && state.entryOperations.clipboardItems.contains(entry.fullPath)
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
                guard let self else { return }
                store.send(.view(.startRename(item: entry, text: text)))
            },
            onRenameCommit: { [weak self] in
                guard let self else { return }
                store.send(.view(.commitRename(itemID: entry.id, newName: state.entryOperations.renamingText)))
            },
            onRenameCancel: { [weak self] in
                guard let self else { return }
                store.send(.delegate(.renameCanceled))
            },
        ))
        let isSelected = state.selectedIds.contains(entry.id)
        item.isSelected = isSelected
        item.refreshSelectionAppearance(isSelected: isSelected)

        return item
    }

    public func collectionView(
        _: NSCollectionView,
        pasteboardWriterForItemAt indexPath: IndexPath,
    ) -> NSPasteboardWriting? {
        guard let entry = entry(at: indexPath) else { return nil }
        return NSURL(fileURLWithPath: entry.fullPath)
    }

    public func collectionView(
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
                    store.send(.view(.toggleGroup(title)))
                }
            },
        )
        return header
    }
}

extension EntryGridCoordinator: NSCollectionViewDelegate, NSCollectionViewDelegateFlowLayout {
    public func collectionView(_ collectionView: NSCollectionView, didSelectItemsAt _: Set<IndexPath>) {
        guard !isLassoSelecting else { return }
        updateSelectionFromCollectionView(collectionView)
    }

    public func collectionView(_ collectionView: NSCollectionView, didDeselectItemsAt _: Set<IndexPath>) {
        guard !isLassoSelecting else { return }
        updateSelectionFromCollectionView(collectionView)
    }

    public func collectionView(
        _ collectionView: NSCollectionView,
        layout _: NSCollectionViewLayout,
        referenceSizeForHeaderInSection section: Int,
    ) -> NSSize {
        let hasHeader = sections[section].title != nil
        return hasHeader ? NSSize(width: collectionView.bounds.width, height: 32) : .zero
    }

    public func collectionView(
        _: NSCollectionView,
        layout _: NSCollectionViewLayout,
        sizeForItemAt _: IndexPath,
    ) -> NSSize {
        flowLayout.itemSize
    }

    public func collectionView(
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
        store.send(.view(.startDrag(paths: paths)))
    }

    public func collectionView(
        _: NSCollectionView,
        draggingSession _: NSDraggingSession,
        endedAt _: NSPoint,
        dragOperation operation: NSDragOperation,
    ) {
        guard EntryViewLayoutDragStateClearRuleSet.shouldClearAfterSessionEnd(operation: operation) else { return }
        store.send(.view(.startDrag(paths: [])))
        clearDropTargetState()
        store.send(.view(.setDropTargeted(false)))
    }

    @MainActor
    public func collectionView(
        _: NSCollectionView,
        validateDrop draggingInfo: any NSDraggingInfo,
        proposedIndexPath proposedDropIndexPath: AutoreleasingUnsafeMutablePointer<NSIndexPath>,
        dropOperation proposedDropOperation: UnsafeMutablePointer<NSCollectionView.DropOperation>,
    ) -> NSDragOperation {
        let draggingLocation = draggingInfo.draggingLocation
        let localPoint = collectionView.convert(draggingLocation, from: nil)
        let primaryIndexPath = collectionView.indexPathForItem(at: localPoint)
        let fallbackIndexPath = primaryIndexPath == nil ? indexPathForVisibleItem(containing: localPoint) : nil
        let pointResolvedIndexPath = primaryIndexPath ?? fallbackIndexPath
        let hoverIndexPath = resolvedEntryTargetIndexPath(
            pointResolved: pointResolvedIndexPath,
            localPoint: localPoint,
        )
        if let hoverIndexPath = hoverIndexPath as? NSIndexPath {
            proposedDropIndexPath.pointee = hoverIndexPath
        }
        let indexPath = hoverIndexPath ?? (proposedDropIndexPath.pointee as IndexPath)
        var destinationPath = state.currentPath
        var targetEntryId: EntryModel.ID?
        if let entry = entry(at: indexPath),
           entry.isFolder,
           !entry.isPackage
        {
            destinationPath = entry.fullPath
            targetEntryId = entry.id
            proposedDropOperation.pointee = .on
        } else {
            proposedDropOperation.pointee = .before
        }
        let validation = EntryViewLayoutDropValidationAdapter.resolve(
            draggingInfo: draggingInfo,
            destinationPath: destinationPath,
        )
        let operation = EntryViewLayoutDropValidationAdapter.dragOperation(from: validation.resolvedOperation)
        setDropTargetEntryId(operation.isEmpty ? nil : targetEntryId)
        validatedDropDestinationPath = operation.isEmpty ? nil : destinationPath
        store.send(.view(.setDropTargeted(!operation.isEmpty)))

        return operation
    }

    public func collectionView(
        _: NSCollectionView,
        acceptDrop draggingInfo: NSDraggingInfo,
        indexPath _: IndexPath,
        dropOperation _: NSCollectionView.DropOperation,
    ) -> Bool {
        let destinationPath = validatedDropDestinationPath ?? state.currentPath
        let sourcePaths = EntryViewLayoutDropValidationAdapter.sourcePaths(from: draggingInfo.draggingPasteboard)
        guard !sourcePaths.isEmpty else {
            clearDropTargetState()
            store.send(.view(.setDropTargeted(false)))
            return false
        }
        let validation = EntryViewLayoutDropValidationAdapter.resolve(
            sourcePaths: sourcePaths,
            destinationPath: destinationPath,
            allowedOperations: draggingInfo.draggingSourceOperationMask,
            prefersCopy: NSEvent.modifierFlags.contains(.option),
        )
        guard !EntryViewLayoutDropValidationAdapter.dragOperation(from: validation.resolvedOperation).isEmpty else {
            clearDropTargetState()
            store.send(.view(.setDropTargeted(false)))
            return false
        }
        store.send(.view(.dropItems(
            sourcePaths: sourcePaths,
            destinationPath: destinationPath,
            isOptionDrag: validation.isOptionDrag,
        )))
        return true
    }

    public func updateSelectionFromCollectionView(_ collectionView: NSCollectionView) {
        guard !isUpdatingSelectionFromStore else { return }
        let selectedIndexPaths = collectionView.selectionIndexPaths
        let selectedIds: Set<EntryModel.ID> = Set(selectedIndexPaths.compactMap { indexPath in
            entry(at: indexPath)?.id
        })
        let lastSelectedId = selectedIndexPaths.max().flatMap { entry(at: $0)?.id }
        let selectedEntries = selectedIndexPaths.compactMap { entry(at: $0) }
        preloadOpenWithApplications(selectedEntries: selectedEntries)
        store.send(.view(.updateSelection(
            ids: selectedIds,
            lastSelectedId: lastSelectedId,
            rangeAnchorId: lastSelectedId,
            shouldScrollToSelection: false,
        )))
    }
}
