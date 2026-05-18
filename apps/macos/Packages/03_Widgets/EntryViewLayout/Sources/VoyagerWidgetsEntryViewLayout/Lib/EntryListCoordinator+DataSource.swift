@preconcurrency import AppKit
import ComposableArchitecture

import VoyagerEntitiesEntry
import VoyagerFeaturesEntryOperations

extension EntryListCoordinator: NSOutlineViewDataSource {
    public func outlineView(_: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        guard let item else { return outlineItems.count }
        guard let outlineItem = item as? OutlineItem else { return 0 }
        return outlineItem.children.count
    }

    public func outlineView(_: NSOutlineView, isItemExpandable item: Any) -> Bool {
        guard let outlineItem = item as? OutlineItem else { return false }
        switch outlineItem.kind {
        case .group:
            return !outlineItem.children.isEmpty
        case .entry:
            return false
        }
    }

    public func outlineView(_: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        guard let item else { return outlineItems[index] }
        guard let outlineItem = item as? OutlineItem else { return outlineItems[index] }
        return outlineItem.children[index]
    }

    public func outlineView(_: NSOutlineView, pasteboardWriterForItem item: Any) -> (any NSPasteboardWriting)? {
        guard let outlineItem = item as? OutlineItem else { return nil }
        guard case let .entry(entry) = outlineItem.kind else { return nil }
        return NSURL(fileURLWithPath: entry.fullPath)
    }

    public func outlineView(
        _ outlineView: NSOutlineView,
        validateDrop info: any NSDraggingInfo,
        proposedItem item: Any?,
        proposedChildIndex _: Int
    ) -> NSDragOperation {
        var destinationPath = state.currentPath
        if let outlineItem = item as? OutlineItem,
           case let .entry(entry) = outlineItem.kind,
           entry.isFolder
        {
            outlineView.setDropItem(outlineItem, dropChildIndex: NSOutlineViewDropOnItemIndex)
            destinationPath = entry.fullPath
        } else {
            outlineView.setDropItem(nil, dropChildIndex: -1)
        }

        let sourcePaths = entryFileOpsClient.loadDragPaths()
        let wantsCopy = sourcePaths.isEmpty
            ? NSEvent.modifierFlags.contains(.option)
            : entryFileOpsClient.loadDragWithOption()
        let allowed = info.draggingSourceOperationMask
        sendEntryOperations(.routing(.validateDrop(context: .init(
            sourcePaths: sourcePaths,
            destinationPath: destinationPath,
            allowedOperationsRawValue: allowed.rawValue,
            prefersCopy: wantsCopy
        ))))
        let operation = dragOperation(from: state.entryOperations.dropValidationResult.resolvedOperation)
        store.send(.view(.setDropTargeted(!operation.isEmpty)))
        return operation
    }

    public func outlineView(
        _: NSOutlineView,
        acceptDrop info: any NSDraggingInfo,
        item: Any?,
        childIndex _: Int
    ) -> Bool {
        var destinationPath = state.currentPath
        if let outlineItem = item as? OutlineItem,
           case let .entry(entry) = outlineItem.kind,
           entry.isFolder
        {
            destinationPath = entry.fullPath
        }

        let internalPaths = entryFileOpsClient.loadDragPaths()
        let wantsCopy = internalPaths.isEmpty
            ? NSEvent.modifierFlags.contains(.option)
            : entryFileOpsClient.loadDragWithOption()
        let allowed = info.draggingSourceOperationMask
        sendEntryOperations(.routing(.validateDrop(context: .init(
            sourcePaths: internalPaths,
            destinationPath: destinationPath,
            allowedOperationsRawValue: allowed.rawValue,
            prefersCopy: wantsCopy
        ))))
        let validation = state.entryOperations.dropValidationResult
        let resolvedOperation = dragOperation(from: validation.resolvedOperation)
        guard !resolvedOperation.isEmpty else {
            store.send(.view(.setDropTargeted(false)))
            return false
        }

        if !internalPaths.isEmpty {
            sendEntryOperations(.routing(.handleDrop(providers: [], destinationPath: destinationPath)))
            store.send(.view(.setDropTargeted(false)))
            return true
        }

        let pasteboard = info.draggingPasteboard
        let options: [NSPasteboard.ReadingOptionKey: Any] = [
            .urlReadingFileURLsOnly: true,
        ]
        guard let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: options) as? [URL],
              !urls.isEmpty
        else {
            store.send(.view(.setDropTargeted(false)))
            return false
        }
        sendEntryOperations(.routing(.dropItems(
            sourcePaths: urls.map(\.path),
            destinationPath: destinationPath,
            isOptionDrag: validation.isOptionDrag
        )))
        store.send(.view(.setDropTargeted(false)))
        return true
    }
}

extension EntryListCoordinator: NSTextFieldDelegate {
    public func controlTextDidChange(_ notification: Notification) {
        guard state.entryOperations.renamingItemId != nil else { return }
        guard let textField = notification.object as? NSTextField else { return }
        guard (textField.delegate as AnyObject?) === self else { return }
        sendEntryOperations(.edit(.updateRenamingText(textField.stringValue)))
    }

    public func control(_ control: NSControl, textView _: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        guard state.entryOperations.renamingItemId != nil else { return false }
        guard let textField = control as? NSTextField else { return false }
        guard (textField.delegate as AnyObject?) === self else { return false }

        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            sendEntryOperations(.edit(.commitRename))
            return true
        }
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            sendEntryOperations(.edit(.cancelRename))
            return true
        }
        if commandSelector == #selector(NSResponder.insertTab(_:)) {
            sendEntryOperations(.edit(.commitRename))
            return true
        }

        return false
    }

    public func controlTextDidEndEditing(_ notification: Notification) {
        guard state.entryOperations.renamingItemId != nil else { return }
        guard let textField = notification.object as? NSTextField else { return }
        guard (textField.delegate as AnyObject?) === self else { return }
        sendEntryOperations(.edit(.commitRename))
    }
}
