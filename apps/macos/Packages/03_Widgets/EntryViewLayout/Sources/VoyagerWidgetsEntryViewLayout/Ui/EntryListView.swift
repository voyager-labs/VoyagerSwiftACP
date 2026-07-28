@preconcurrency import AppKit
import ComposableArchitecture
import SwiftUI

@MainActor
public struct EntryListViewRepresentable: NSViewRepresentable {
    public let store: StoreOf<EntryViewLayoutFeature>
    public let blankSpaceMenuProvider: (() -> NSMenu)?

    public init(
        store: StoreOf<EntryViewLayoutFeature>,
        blankSpaceMenuProvider: (() -> NSMenu)?,
    ) {
        self.store = store
        self.blankSpaceMenuProvider = blankSpaceMenuProvider
    }

    public func makeCoordinator() -> EntryListCoordinator {
        EntryListCoordinator(store: store)
    }

    public func makeNSView(context: Context) -> EntryListView {
        let view = EntryListView()
        context.coordinator.bind(to: view)
        view.tableView.blankSpaceContextMenuProvider = blankSpaceMenuProvider
        return view
    }

    public func updateNSView(_ view: EntryListView, context: Context) {
        context.coordinator.updateRootView(view)
        view.tableView.blankSpaceContextMenuProvider = blankSpaceMenuProvider
    }
}

final class EntryListSelectionRowView: NSTableRowView {
    private var tableView: NSTableView? {
        var view: NSView? = self
        while let currentView = view {
            if let tableView = currentView as? NSTableView {
                return tableView
            }
            view = currentView.superview
        }
        return nil
    }

    override var isEmphasized: Bool {
        didSet {
            super.isEmphasized = true
        }
    }

    override func drawBackground(in dirtyRect: NSRect) {
        guard !isSelected else {
            super.drawBackground(in: dirtyRect)
            return
        }

        guard let tableView,
              tableView.row(for: self) % 2 == 1 else { return }

        let isDark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let backgroundColor = isDark
            ? NSColor.white.withAlphaComponent(0.035)
            : NSColor.black.withAlphaComponent(0.055)
        backgroundColor.setFill()
        dirtyRect.fill()
    }
}

public final class EntryListView: NSView {
    @MainActor
    protocol EntryListTableViewContextMenuProviding: AnyObject {
        func contextMenu(forRow row: Int?, event: NSEvent) -> NSMenu
    }

    final class EntryListTableView: NSOutlineView {
        weak var contextMenuProvider: EntryListTableViewContextMenuProviding?
        var blankSpaceContextMenuProvider: (() -> NSMenu)?

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

            if row == -1 {
                deselectAll(nil)
                if let menu = blankSpaceContextMenuProvider?() {
                    NSMenu.popUpContextMenu(menu, with: event, for: self)
                    return
                }
                super.rightMouseDown(with: event)
                return
            }

            if !selectedRowIndexes.contains(row) {
                selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            }

            guard let contextMenuProvider else {
                super.rightMouseDown(with: event)
                return
            }

            let menu = contextMenuProvider.contextMenu(forRow: row, event: event)
            NSMenu.popUpContextMenu(menu, with: event, for: self)
        }
    }

    final class EntryListScrollView: NSScrollView {
        override func tile() {
            super.tile()

            guard let headerClipView = subviews
                .compactMap({ $0 as? NSClipView })
                .first(where: { $0.documentView is NSTableHeaderView })
            else { return }

            headerClipView.drawsBackground = false
            headerClipView.backgroundColor = NSColor.clear
            for subview in headerClipView.subviews where !(subview is NSTableHeaderView) {
                subview.isHidden = true
            }
        }
    }

    let scrollView = EntryListScrollView()
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
        scrollView.contentView.wantsLayer = true
        scrollView.contentView.layer?.backgroundColor = NSColor.clear.cgColor
        scrollView.contentView.drawsBackground = false
        scrollView.contentView.backgroundColor = NSColor.clear
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.automaticallyAdjustsContentInsets = false
        scrollView.contentView.postsBoundsChangedNotifications = true
        scrollView.contentInsets = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)

        tableView.wantsLayer = true
        tableView.layer?.backgroundColor = NSColor.clear.cgColor
        tableView.backgroundColor = NSColor.clear
        tableView.headerView = NSTableHeaderView()
        tableView.allowsColumnReordering = true
        tableView.allowsColumnResizing = true
        tableView.allowsMultipleSelection = true
        tableView.allowsEmptySelection = true
        tableView.usesAlternatingRowBackgroundColors = false
        tableView.intercellSpacing = NSSize(width: 4, height: 0)
        tableView.registerForDraggedTypes([.fileURL])
        tableView.setDraggingSourceOperationMask([.copy, .move], forLocal: true)
        tableView.setDraggingSourceOperationMask([.copy], forLocal: false)
        tableView.autoresizesOutlineColumn = false
        tableView.columnAutoresizingStyle = .noColumnAutoresizing
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
            tableColumn.sortDescriptorPrototype = NSSortDescriptor(
                key: sortDescriptorKey,
                ascending: column.defaultSortAscending,
            )
        } else {
            tableColumn.sortDescriptorPrototype = nil
        }

        availableColumns[column] = tableColumn
        return tableColumn
    }
}
