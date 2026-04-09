import AppKit

extension EntryListCoordinator {
    func makeGroupRowView(
        outlineView: NSOutlineView,
        tableColumn: NSTableColumn?,
        title: String,
        colorCode: Int?,
    ) -> NSView {
        let resolvedTableColumn = tableColumn ?? outlineView.outlineTableColumn
        let columnId = resolvedTableColumn?.identifier.rawValue ?? EntryListColumn.name.rawValue
        let groupHeaderColumnId = outlineView.outlineTableColumn?.identifier.rawValue ?? EntryListColumn.name.rawValue

        if columnId == groupHeaderColumnId {
            return makeGroupHeaderCell(
                outlineView: outlineView,
                columnId: columnId,
                title: title,
                colorCode: colorCode,
            )
        }

        return makeGroupEmptyCell(outlineView: outlineView, columnId: columnId)
    }

    private func makeGroupHeaderCell(
        outlineView: NSOutlineView,
        columnId: String,
        title: String,
        colorCode: Int?,
    ) -> EntryListGroupHeaderCellView {
        let headerIdentifier = NSUserInterfaceItemIdentifier("group-header-cell-\(columnId)")
        let header = (outlineView.makeView(
            withIdentifier: headerIdentifier,
            owner: self,
        ) as? EntryListGroupHeaderCellView)
            ?? EntryListGroupHeaderCellView()
        header.identifier = headerIdentifier
        header.configure(title: title, colorCode: colorCode)
        return header
    }

    private func makeGroupEmptyCell(outlineView: NSOutlineView, columnId: String) -> EntryListEmptyCellView {
        let emptyIdentifier = NSUserInterfaceItemIdentifier("group-empty-cell-\(columnId)")
        let emptyCell = (outlineView.makeView(withIdentifier: emptyIdentifier, owner: self) as? EntryListEmptyCellView)
            ?? EntryListEmptyCellView()
        emptyCell.identifier = emptyIdentifier
        return emptyCell
    }
}
