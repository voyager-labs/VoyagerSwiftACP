import AppKit

protocol EntryListTableViewContextMenuProviding: AnyObject {
    func contextMenu(forRow row: Int?, event: NSEvent) -> NSMenu
}

final class EntryListTableView: NSOutlineView {
    weak var contextMenuProvider: EntryListTableViewContextMenuProviding?

    override func mouseDown(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        if row(at: location) == -1 {
            deselectAll(nil)
        }
        super.mouseDown(with: event)
    }

    override func rightMouseDown(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        let row = row(at: location)

        if row != -1, !selectedRowIndexes.contains(row) {
            selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        }

        guard let contextMenuProvider else {
            super.rightMouseDown(with: event)
            return
        }

        let menu = contextMenuProvider.contextMenu(forRow: row == -1 ? nil : row, event: event)
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }
}
