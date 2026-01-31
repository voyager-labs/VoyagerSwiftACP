import AppKit
import ComposableArchitecture

extension EntryGridCollectionViewController: NSCollectionViewDelegate, NSCollectionViewDelegateFlowLayout {
    func collectionView(_ collectionView: NSCollectionView, didSelectItemsAt _: Set<IndexPath>) {
        updateSelectionFromCollectionView(collectionView)
    }

    func collectionView(_ collectionView: NSCollectionView, didDeselectItemsAt _: Set<IndexPath>) {
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
        fsStore.send(.startDrag(paths: paths))
    }

    func collectionView(
        _: NSCollectionView,
        draggingSession _: NSDraggingSession,
        endedAt _: NSPoint,
        dragOperation operation: NSDragOperation,
    ) {
        guard operation.isEmpty else { return }
        fsStore.send(.startDrag(paths: []))
        fsStore.send(.setDropTargeted(false))
    }

    func collectionView(
        _: NSCollectionView,
        validateDrop draggingInfo: NSDraggingInfo,
        proposedIndexPath proposedDropIndexPath: AutoreleasingUnsafeMutablePointer<NSIndexPath?>,
        dropOperation proposedDropOperation: UnsafeMutablePointer<NSCollectionView.DropOperation>,
    ) -> NSDragOperation {
        let indexPath = proposedDropIndexPath.pointee as IndexPath?
        var destinationPath = store.state.currentPath
        var targetEntryId: String?

        if let indexPath,
           let entry = entry(at: indexPath),
           entry.isDirectory
        {
            destinationPath = entry.fullPath
            targetEntryId = entry.id
            proposedDropOperation.pointee = .on
        } else {
            proposedDropOperation.pointee = .before
        }

        let sourcePaths = entryClient.loadDragPaths()
        let isInternalDrag = !sourcePaths.isEmpty
        let wantsCopy = isInternalDrag ? entryClient.loadDragWithOption() : NSEvent.modifierFlags.contains(.option)

        if isInternalDrag, !wantsCopy {
            let sourceParent = URL(fileURLWithPath: sourcePaths[0]).deletingLastPathComponent().path
            if sourceParent == destinationPath {
                setDropTargetEntryId(nil)
                fsStore.send(.setDropTargeted(false))
                return []
            }

            let destinationComponents = URL(fileURLWithPath: destinationPath)
                .standardizedFileURL.pathComponents
            for sourcePath in sourcePaths {
                if destinationPath == sourcePath {
                    setDropTargetEntryId(nil)
                    fsStore.send(.setDropTargeted(false))
                    return []
                }

                let sourceComponents = URL(fileURLWithPath: sourcePath)
                    .standardizedFileURL.pathComponents
                if destinationComponents.count > sourceComponents.count,
                   Array(destinationComponents.prefix(sourceComponents.count)) == sourceComponents
                {
                    setDropTargetEntryId(nil)
                    fsStore.send(.setDropTargeted(false))
                    return []
                }
            }
        }

        let allowed = draggingInfo.draggingSourceOperationMask
        let preferred: NSDragOperation = wantsCopy ? .copy : .move
        let resolved = preferred.isDisjoint(with: allowed)
            ? NSDragOperation.copy.intersection(allowed)
            : preferred.intersection(allowed)

        setDropTargetEntryId(targetEntryId)
        fsStore.send(.setDropTargeted(!resolved.isEmpty))
        return resolved
    }

    func collectionView(
        _: NSCollectionView,
        acceptDrop draggingInfo: NSDraggingInfo,
        indexPath: IndexPath,
        dropOperation: NSCollectionView.DropOperation,
    ) -> Bool {
        var destinationPath = store.state.currentPath
        if dropOperation == .on,
           let entry = entry(at: indexPath),
           entry.isDirectory
        {
            destinationPath = entry.fullPath
        }

        let internalPaths = entryClient.loadDragPaths()
        if !internalPaths.isEmpty {
            fsStore.send(.handleDrop(providers: [], destinationPath: destinationPath))
            setDropTargetEntryId(nil)
            fsStore.send(.setDropTargeted(false))
            return true
        }

        let pasteboard = draggingInfo.draggingPasteboard
        let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        guard let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: options) as? [URL],
              !urls.isEmpty
        else {
            setDropTargetEntryId(nil)
            fsStore.send(.setDropTargeted(false))
            return false
        }

        let allowed = draggingInfo.draggingSourceOperationMask
        let preferred: NSDragOperation = NSEvent.modifierFlags.contains(.option) ? .copy : .move
        let resolved = preferred.isDisjoint(with: allowed)
            ? NSDragOperation.copy.intersection(allowed)
            : preferred.intersection(allowed)
        guard !resolved.isEmpty else {
            setDropTargetEntryId(nil)
            fsStore.send(.setDropTargeted(false))
            return false
        }

        let isOptionPressed = resolved.contains(.copy) && !resolved.contains(.move)
        fsStore.send(.dropItems(
            sourcePaths: urls.map(\.path),
            destinationPath: destinationPath,
            isOptionDrag: isOptionPressed,
        ))
        setDropTargetEntryId(nil)
        fsStore.send(.setDropTargeted(false))
        return true
    }

    private func updateSelectionFromCollectionView(_ collectionView: NSCollectionView) {
        guard !isUpdatingSelectionFromStore else { return }

        let selectedIndexPaths = collectionView.selectionIndexPaths
        let selectedIds: Set<String> = Set(selectedIndexPaths.compactMap { indexPath in
            entry(at: indexPath)?.id
        })

        let lastSelectedId = selectedIndexPaths
            .max()
            .flatMap { entry(at: $0)?.id }

        fsStore.send(.setSelectedIds(ids: selectedIds, lastSelectedId: lastSelectedId))
    }
}
