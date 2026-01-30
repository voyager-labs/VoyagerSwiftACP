import AppKit
import ComposableArchitecture

extension EntryListTableViewController: NSTableViewDataSource {
    func numberOfRows(in _: NSTableView) -> Int {
        rows.count
    }

    func tableView(_: NSTableView, pasteboardWriterForRow row: Int) -> (any NSPasteboardWriting)? {
        guard row >= 0, row < rows.count else { return nil }
        guard case let .entry(entry) = rows[row].kind else { return nil }
        return NSURL(fileURLWithPath: entry.fullPath)
    }

    func tableView(
        _ tableView: NSTableView,
        validateDrop info: any NSDraggingInfo,
        proposedRow row: Int,
        proposedDropOperation _: NSTableView.DropOperation,
    ) -> NSDragOperation {
        var destinationPath = store.state.currentPath
        if row >= 0,
           row < rows.count,
           case let .entry(entry) = rows[row].kind,
           entry.isDirectory
        {
            tableView.setDropRow(row, dropOperation: .on)
            destinationPath = entry.fullPath
        } else {
            tableView.setDropRow(-1, dropOperation: .on)
        }

        let sourcePaths = entryClient.loadDragPaths()
        let isInternalDrag = !sourcePaths.isEmpty
        let wantsCopy = isInternalDrag ? entryClient.loadDragWithOption() : NSEvent.modifierFlags.contains(.option)

        if isInternalDrag, !wantsCopy {
            let sourceParent = URL(fileURLWithPath: sourcePaths[0]).deletingLastPathComponent().path
            if sourceParent == destinationPath {
                return []
            }

            // 자기 자신의 하위 폴더로 이동 방지
            for sourcePath in sourcePaths {
                if destinationPath == sourcePath || isDescendantPath(destinationPath, of: sourcePath) {
                    return []
                }
            }
        }

        let allowed = info.draggingSourceOperationMask
        let preferred: NSDragOperation = wantsCopy ? .copy : .move
        if !preferred.isDisjoint(with: allowed) {
            return preferred.intersection(allowed)
        }

        // 외부 드래그에서 move 불가(copy만 가능 등) fallback
        return NSDragOperation.copy.intersection(allowed)
    }

    func tableView(
        _: NSTableView,
        acceptDrop info: any NSDraggingInfo,
        row: Int,
        dropOperation: NSTableView.DropOperation,
    ) -> Bool {
        var destinationPath = store.state.currentPath
        if dropOperation == .on,
           row >= 0,
           row < rows.count,
           case let .entry(entry) = rows[row].kind,
           entry.isDirectory
        {
            destinationPath = entry.fullPath
        }

        let internalPaths = entryClient.loadDragPaths()
        if !internalPaths.isEmpty {
            fsStore.send(.handleDrop(providers: [], destinationPath: destinationPath))
            return true
        }

        let pasteboard = info.draggingPasteboard
        let options: [NSPasteboard.ReadingOptionKey: Any] = [
            .urlReadingFileURLsOnly: true,
        ]
        guard let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: options) as? [URL],
              !urls.isEmpty
        else {
            return false
        }

        let allowed = info.draggingSourceOperationMask
        let preferred: NSDragOperation = NSEvent.modifierFlags.contains(.option) ? .copy : .move
        let resolved = preferred.isDisjoint(with: allowed)
            ? NSDragOperation.copy.intersection(allowed)
            : preferred.intersection(allowed)
        guard !resolved.isEmpty else {
            return false
        }
        let isOptionPressed = resolved.contains(.copy) && !resolved.contains(.move)
        fsStore.send(.dropItems(
            sourcePaths: urls.map(\.path),
            destinationPath: destinationPath,
            isOptionDrag: isOptionPressed,
        ))
        return true
    }
}
