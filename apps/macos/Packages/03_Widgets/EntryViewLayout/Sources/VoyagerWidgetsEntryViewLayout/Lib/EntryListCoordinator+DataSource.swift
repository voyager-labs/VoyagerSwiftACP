@preconcurrency import AppKit
import ComposableArchitecture
import VoyagerEntitiesEntry

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
        case let .entry(entry):
            return isHierarchyOutlineEnabled && entry.supportsListHierarchyExpansion
        case .empty, .error:
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
        proposedChildIndex _: Int,
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

        let validation = EntryViewLayoutDropValidationAdapter.resolve(
            draggingInfo: info,
            destinationPath: destinationPath,
        )
        let operation = EntryViewLayoutDropValidationAdapter.dragOperation(from: validation.resolvedOperation)
        store.send(.view(.setDropTargeted(!operation.isEmpty)))
        return operation
    }

    public func outlineView(
        _: NSOutlineView,
        acceptDrop info: any NSDraggingInfo,
        item: Any?,
        childIndex _: Int,
    ) -> Bool {
        var destinationPath = state.currentPath
        if let outlineItem = item as? OutlineItem,
           case let .entry(entry) = outlineItem.kind,
           entry.isFolder
        {
            destinationPath = entry.fullPath
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
        let sourcePaths = urls.map(\.path)
        let validation = EntryViewLayoutDropValidationAdapter.resolve(
            sourcePaths: sourcePaths,
            destinationPath: destinationPath,
            allowedOperations: info.draggingSourceOperationMask,
            prefersCopy: NSEvent.modifierFlags.contains(.option),
        )
        guard !EntryViewLayoutDropValidationAdapter.dragOperation(from: validation.resolvedOperation).isEmpty else {
            store.send(.view(.setDropTargeted(false)))
            return false
        }
        store.send(.view(.dropItems(
            sourcePaths: sourcePaths,
            destinationPath: destinationPath,
            isOptionDrag: validation.isOptionDrag,
        )))
        store.send(.view(.setDropTargeted(false)))
        return true
    }
}

extension EntryListCoordinator: NSTextFieldDelegate {
    public func controlTextDidChange(_ notification: Notification) {
        guard let renamingItemId = state.renamingItemId else { return }
        guard let textField = notification.object as? NSTextField else { return }
        guard (textField.delegate as AnyObject?) === self else { return }
        guard let renamingItem = state.entries.first(where: { $0.id == renamingItemId }) else { return }
        store.send(.view(.startRename(item: renamingItem, text: textField.stringValue)))
    }

    public func control(_ control: NSControl, textView _: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        guard state.renamingItemId != nil else { return false }
        guard let textField = control as? NSTextField else { return false }
        guard (textField.delegate as AnyObject?) === self else { return false }

        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            store.send(.view(.commitRename(itemID: state.renamingItemId ?? "", newName: textField.stringValue)))
            return true
        }
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            store.send(.view(.updateSelection(
                ids: state.selectedIds,
                lastSelectedId: state.lastSelectedId,
                rangeAnchorId: state.rangeAnchorId,
                shouldScrollToSelection: false,
            )))
            return true
        }
        if commandSelector == #selector(NSResponder.insertTab(_:)) {
            store.send(.view(.commitRename(itemID: state.renamingItemId ?? "", newName: textField.stringValue)))
            return true
        }

        return false
    }

    public func controlTextDidEndEditing(_ notification: Notification) {
        guard state.renamingItemId != nil else { return }
        guard let textField = notification.object as? NSTextField else { return }
        guard (textField.delegate as AnyObject?) === self else { return }
        store.send(.view(.commitRename(itemID: state.renamingItemId ?? "", newName: textField.stringValue)))
    }
}
