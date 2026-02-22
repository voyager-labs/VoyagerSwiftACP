import AppKit
import SwiftUI

@MainActor
struct EntryListViewRepresentable: NSViewRepresentable {
    let adapter: EntryViewLayoutAdapter

    func makeCoordinator() -> EntryListCoordinator {
        EntryListCoordinator(adapter: adapter)
    }

    func makeNSView(context: Context) -> EntryListView {
        let view = EntryListView()
        context.coordinator.bind(to: view)
        return view
    }

    func updateNSView(_ view: EntryListView, context: Context) {
        context.coordinator.updateRootView(view)
    }
}

final class EntryListView: NSView {
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

    let scrollView = NSScrollView()
    let tableView = EntryListTableView()
    private var availableColumns: [EntryListColumn: NSTableColumn] = [:]

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupViewTree()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupViewTree() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor

        scrollView.wantsLayer = true
        scrollView.layer?.backgroundColor = NSColor.clear.cgColor
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.automaticallyAdjustsContentInsets = false
        scrollView.contentView.postsBoundsChangedNotifications = true
        scrollView.contentInsets = NSEdgeInsets(top: 0, left: 16, bottom: 0, right: 16)

        tableView.wantsLayer = true
        tableView.layer?.backgroundColor = NSColor.clear.cgColor
        tableView.headerView = NSTableHeaderView()
        tableView.allowsColumnReordering = true
        tableView.allowsColumnResizing = true
        tableView.allowsMultipleSelection = true
        tableView.allowsEmptySelection = true
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.intercellSpacing = NSSize(width: 8, height: 0)
        tableView.registerForDraggedTypes([.fileURL])
        tableView.setDraggingSourceOperationMask([.copy, .move], forLocal: true)
        tableView.setDraggingSourceOperationMask([.copy], forLocal: false)
        tableView.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        tableView.autosaveName = "FileManager.EntryList.Columns"
        tableView.autosaveTableColumns = true
        applyColumns(EntryListColumn.defaultVisibleColumns)

        scrollView.documentView = tableView

        addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    func applyColumns(_ visibleColumns: [EntryListColumn]) {
        let normalizedColumns = EntryListColumn.normalizeVisibleColumns(visibleColumns)
        let visibleIdentifiers = Set(normalizedColumns.map(\.rawValue))

        for tableColumn in tableView.tableColumns where !visibleIdentifiers.contains(tableColumn.identifier.rawValue) {
            tableView.removeTableColumn(tableColumn)
        }

        for column in normalizedColumns {
            let identifier = NSUserInterfaceItemIdentifier(column.rawValue)
            if tableView.tableColumn(withIdentifier: identifier) == nil {
                tableView.addTableColumn(resolvedTableColumn(for: column))
            }
        }

        for (targetIndex, column) in normalizedColumns.enumerated() {
            let identifier = NSUserInterfaceItemIdentifier(column.rawValue)
            let currentIndex = tableView.column(withIdentifier: identifier)
            guard currentIndex >= 0, currentIndex != targetIndex else { continue }
            tableView.moveColumn(currentIndex, toColumn: targetIndex)
        }

        if let outlineColumn = tableView.tableColumn(
            withIdentifier: NSUserInterfaceItemIdentifier(EntryListColumn.name.rawValue),
        ) {
            tableView.outlineTableColumn = outlineColumn
        }

        tableView.sortDescriptors = tableView.sortDescriptors.filter { descriptor in
            guard let key = descriptor.key else { return false }
            return visibleIdentifiers.contains(key)
        }
    }

    private func resolvedTableColumn(for column: EntryListColumn) -> NSTableColumn {
        if let cached = availableColumns[column] {
            return cached
        }

        let tableColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(column.rawValue))
        tableColumn.title = column.title
        tableColumn.minWidth = column.minWidth
        tableColumn.maxWidth = column.maxWidth
        tableColumn.width = column.defaultWidth
        tableColumn.resizingMask = [.userResizingMask, .autoresizingMask]

        if let sortDescriptorKey = column.sortDescriptorKey {
            tableColumn.sortDescriptorPrototype = NSSortDescriptor(key: sortDescriptorKey, ascending: true)
        } else {
            tableColumn.sortDescriptorPrototype = nil
        }

        availableColumns[column] = tableColumn
        return tableColumn
    }
}
