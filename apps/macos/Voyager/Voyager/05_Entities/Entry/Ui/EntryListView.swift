import AppKit
import ComposableArchitecture
import SwiftUI

@MainActor
struct EntryListView: NSViewRepresentable {
    let store: StoreOf<FileManagerContentFeature>

    func makeCoordinator() -> EntryListController {
        EntryListController(store: store)
    }

    func makeNSView(context: Context) -> EntryListRootView {
        let view = EntryListRootView()
        context.coordinator.bind(to: view)
        return view
    }

    func updateNSView(_ view: EntryListRootView, context: Context) {
        context.coordinator.updateRootView(view)
    }
}

final class EntryListRootView: NSView {
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

        setupColumns()

        scrollView.documentView = tableView

        addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    private func setupColumns() {
        let nameColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("name"))
        nameColumn.title = "Name"
        nameColumn.minWidth = 220
        nameColumn.maxWidth = 2400
        nameColumn.width = 420
        nameColumn.resizingMask = [.userResizingMask, .autoresizingMask]
        nameColumn.sortDescriptorPrototype = NSSortDescriptor(key: "name", ascending: true)

        let dateColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("dateModified"))
        dateColumn.title = "Date Modified"
        dateColumn.minWidth = 150
        dateColumn.maxWidth = 420
        dateColumn.width = 220
        dateColumn.resizingMask = [.userResizingMask, .autoresizingMask]
        dateColumn.sortDescriptorPrototype = NSSortDescriptor(key: "dateModified", ascending: true)

        let sizeColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("size"))
        sizeColumn.title = "Size"
        sizeColumn.minWidth = 90
        sizeColumn.maxWidth = 220
        sizeColumn.width = 110
        sizeColumn.resizingMask = [.userResizingMask, .autoresizingMask]
        sizeColumn.sortDescriptorPrototype = NSSortDescriptor(key: "size", ascending: true)

        let kindColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("kind"))
        kindColumn.title = "Kind"
        kindColumn.minWidth = 120
        kindColumn.maxWidth = 360
        kindColumn.width = 180
        kindColumn.resizingMask = [.userResizingMask, .autoresizingMask]
        kindColumn.sortDescriptorPrototype = NSSortDescriptor(key: "kind", ascending: true)

        tableView.addTableColumn(nameColumn)
        tableView.addTableColumn(dateColumn)
        tableView.addTableColumn(sizeColumn)
        tableView.addTableColumn(kindColumn)

        tableView.outlineTableColumn = nameColumn
        tableView.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        tableView.autosaveName = "FileManager.EntryList.Columns"
        tableView.autosaveTableColumns = true
    }
}
