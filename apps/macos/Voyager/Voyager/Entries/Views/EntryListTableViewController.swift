import AppKit
import Combine
import ComposableArchitecture
import SwiftUI

// swiftlint:disable type_body_length

final class EntryListTableViewController: NSViewController {
    struct Row: Equatable {
        enum Kind: Equatable {
            case groupHeader(title: String, colorCode: Int?)
            case entry(Entry)
        }

        let kind: Kind

        var id: String {
            switch kind {
            case let .groupHeader(title, _):
                "group:\(title)"
            case let .entry(entry):
                entry.id
            }
        }
    }

    private enum Column: String {
        case name
        case dateModified
        case size
        case kind
    }

    private let store: StoreOf<FileManagerFeature>
    private let fsStore: StoreOf<EntriesFeature>
    private var cancellables: Set<AnyCancellable> = []

    private let scrollView = NSScrollView()
    private let tableView = EntryListTableView()

    private var rows: [Row] = []
    private var rowIndexByEntryId: [String: Int] = [:]

    private var columnWidthCache: [Column: CGFloat] = [:]
    private var isUpdatingColumnsFromStore = false
    private var isUpdatingSortFromStore = false

    private var lastInteractedRow: Int?
    private var isUpdatingSelectionFromStore = false
    private var hasRestoredScrollPosition = false

    private var contextMenuAnchor: CGPoint?

    @Dependency(\.entryClient)
    private var entryClient

    init(store: StoreOf<FileManagerFeature>) {
        self.store = store
        fsStore = store.scope(state: \.entries, action: \.entries)
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.clear.cgColor

        scrollView.wantsLayer = true
        scrollView.layer?.backgroundColor = NSColor.clear.cgColor
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.automaticallyAdjustsContentInsets = false
        scrollView.contentInsets = NSEdgeInsets(
            top: 0,
            left: ListColumnLayoutUtils.outerPadding,
            bottom: 0,
            right: ListColumnLayoutUtils.outerPadding,
        )

        tableView.wantsLayer = true
        tableView.layer?.backgroundColor = NSColor.clear.cgColor
        tableView.headerView = NSTableHeaderView()
        tableView.delegate = self
        tableView.dataSource = self
        tableView.contextMenuProvider = self
        tableView.allowsMultipleSelection = true
        tableView.allowsEmptySelection = true
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.intercellSpacing = NSSize(width: ListColumnLayoutUtils.columnSpacing, height: 0)
        tableView.doubleAction = #selector(handleDoubleClick)

        tableView.registerForDraggedTypes([.fileURL])
        tableView.setDraggingSourceOperationMask([.copy, .move], forLocal: true)
        tableView.setDraggingSourceOperationMask([.copy], forLocal: false)

        scrollView.documentView = tableView

        view.addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    private func updateContextMenuAnchor(forRow row: Int?) {
        guard let row, row >= 0 else {
            contextMenuAnchor = nil
            return
        }
        guard let window = view.window else {
            contextMenuAnchor = nil
            return
        }

        let rectInTable = tableView.rect(ofRow: row)
        let rectInWindow = tableView.convert(rectInTable, to: nil)
        let rectInScreen = window.convertToScreen(rectInWindow)
        contextMenuAnchor = CGPoint(x: rectInScreen.midX, y: rectInScreen.midY)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupColumns()
        observeStore()
        observeTableView()
        rebuildRowsAndReload()
    }

    private func observeTableView() {
        NotificationCenter.default.publisher(for: NSTableView.columnDidResizeNotification, object: tableView)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                self?.handleColumnDidResize(notification)
            }
            .store(in: &cancellables)
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        applyColumnLayout()
    }

    private func setupColumns() {
        let nameColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(Column.name.rawValue))
        nameColumn.title = "Name"
        nameColumn.resizingMask = .userResizingMask
        nameColumn.sortDescriptorPrototype = NSSortDescriptor(key: Column.name.rawValue, ascending: true)

        let dateColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(Column.dateModified.rawValue))
        dateColumn.title = "Date Modified"
        dateColumn.resizingMask = .userResizingMask
        dateColumn.sortDescriptorPrototype = NSSortDescriptor(key: Column.dateModified.rawValue, ascending: true)

        let sizeColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(Column.size.rawValue))
        sizeColumn.title = "Size"
        sizeColumn.resizingMask = .userResizingMask
        sizeColumn.sortDescriptorPrototype = NSSortDescriptor(key: Column.size.rawValue, ascending: true)

        let kindColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(Column.kind.rawValue))
        kindColumn.title = "Kind"
        kindColumn.resizingMask = .userResizingMask
        kindColumn.sortDescriptorPrototype = NSSortDescriptor(key: Column.kind.rawValue, ascending: true)

        tableView.addTableColumn(nameColumn)
        tableView.addTableColumn(dateColumn)
        tableView.addTableColumn(sizeColumn)
        tableView.addTableColumn(kindColumn)

        tableView.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
    }

    private func observeStore() {
        store.publisher.entries.displayItems
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.rebuildRowsAndReload()
            }
            .store(in: &cancellables)

        store.publisher.entries.groupKey
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.rebuildRowsAndReload()
            }
            .store(in: &cancellables)

        store.publisher.entries.groupedItems
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.rebuildRowsAndReload()
            }
            .store(in: &cancellables)

        store.publisher.currentPath
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.hasRestoredScrollPosition = false
            }
            .store(in: &cancellables)

        store.publisher.entries.selectedIds
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.syncSelectionFromStore()
            }
            .store(in: &cancellables)

        store.publisher.columnWidths
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.applyColumnLayout()
            }
            .store(in: &cancellables)

        Publishers.CombineLatest(store.publisher.sortKey, store.publisher.sortOrder)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] sortKey, sortOrder in
                self?.syncSortIndicators(sortKey: sortKey, sortOrder: sortOrder)
            }
            .store(in: &cancellables)
    }

    private func rebuildRowsAndReload() {
        rows = makeRows(state: store.state)
        rowIndexByEntryId = Dictionary(uniqueKeysWithValues: rows.enumerated().compactMap { index, row in
            if case let .entry(entry) = row.kind {
                return (entry.id, index)
            }
            return nil
        })

        tableView.reloadData()
        applyColumnLayout()
        syncSelectionFromStore()
        restoreScrollPositionIfNeeded()
    }

    private func makeRows(state: FileManagerFeature.State) -> [Row] {
        let entries = state.entries

        if entries.groupKey == .none {
            return entries.displayItems.map { Row(kind: .entry($0)) }
        }

        var result: [Row] = []

        for group in entries.groupedItems {
            if !group.groupName.isEmpty, entries.groupKey != .name {
                let colorCode: Int? = if entries.groupKey == .tags {
                    EntryTagUtils.getTagNameToColorCodeMapping()[group.groupName]
                } else {
                    nil
                }
                result.append(Row(kind: .groupHeader(title: group.groupName, colorCode: colorCode)))
            }
            result.append(contentsOf: group.items.map { Row(kind: .entry($0)) })
        }

        return result
    }

    private func applyColumnLayout() {
        guard tableView.tableColumns.count == 4 else { return }
        let layout = store.state.columnWidths.makeAbsoluteWidths(
            totalWidth: scrollView.bounds.width,
            padding: ListColumnLayoutUtils.outerPadding,
            spacing: ListColumnLayoutUtils.columnSpacing,
        )

        isUpdatingColumnsFromStore = true
        tableView.tableColumns[0].width = layout.name
        tableView.tableColumns[1].width = layout.date
        tableView.tableColumns[2].width = layout.size
        tableView.tableColumns[3].width = layout.kind

        cacheColumnWidths()
        isUpdatingColumnsFromStore = false
    }

    private func handleColumnDidResize(_ notification: Notification) {
        guard !isUpdatingColumnsFromStore else { return }

        guard let resizedColumn = notification.userInfo?["NSTableColumn"] as? NSTableColumn else {
            return
        }
        guard let column = Column(rawValue: resizedColumn.identifier.rawValue) else {
            return
        }

        guard let previousWidth = columnWidthCache[column] else {
            columnWidthCache[column] = resizedColumn.width
            return
        }

        let delta = resizedColumn.width - previousWidth
        guard abs(delta) >= 0.5 else { return }

        columnWidthCache[column] = resizedColumn.width
        store.send(.updateColumnWidth(
            FileManagerFeature.ColumnUpdate(
                column: listColumn(for: column),
                delta: delta,
                totalWidth: scrollView.bounds.width,
                padding: ListColumnLayoutUtils.outerPadding,
                spacing: ListColumnLayoutUtils.columnSpacing,
            ),
        ))
    }

    private func listColumn(for column: Column) -> ListColumnWidthsUtils.Column {
        switch column {
        case .name:
            .name
        case .dateModified:
            .date
        case .size:
            .size
        case .kind:
            .kind
        }
    }

    private func cacheColumnWidths() {
        guard tableView.tableColumns.count == 4 else { return }
        columnWidthCache[.name] = tableView.tableColumns[0].width
        columnWidthCache[.dateModified] = tableView.tableColumns[1].width
        columnWidthCache[.size] = tableView.tableColumns[2].width
        columnWidthCache[.kind] = tableView.tableColumns[3].width
    }

    private func syncSortIndicators(sortKey: SortKey, sortOrder: SortOrder) {
        guard !isUpdatingSortFromStore else { return }

        let ascending = sortOrder == .ascending
        let descriptorKey: String? = switch sortKey {
        case .name:
            Column.name.rawValue
        case .dateModified:
            Column.dateModified.rawValue
        case .size:
            Column.size.rawValue
        case .kind:
            Column.kind.rawValue
        default:
            nil
        }

        isUpdatingSortFromStore = true
        if let descriptorKey {
            tableView.sortDescriptors = [NSSortDescriptor(key: descriptorKey, ascending: ascending)]
        } else {
            tableView.sortDescriptors = []
        }
        isUpdatingSortFromStore = false
    }

    private func syncSelectionFromStore() {
        let selectedIds = store.state.entries.selectedIds
        let indexes = IndexSet(selectedIds.compactMap { rowIndexByEntryId[$0] })

        isUpdatingSelectionFromStore = true
        tableView.selectRowIndexes(indexes, byExtendingSelection: false)
        isUpdatingSelectionFromStore = false
    }

    private func restoreScrollPositionIfNeeded() {
        let itemCount = store.state.entries.displayItems.count
        guard itemCount != 0 else { return }

        if store.state.scrollPositions[store.state.currentPath] != nil {
            ScrollPositionUtils.restoreScrollPosition(
                scrollView: scrollView,
                currentPath: store.state.currentPath,
                scrollPositions: store.state.scrollPositions,
                hasRestored: &hasRestoredScrollPosition,
            )
        } else {
            scrollView.contentView.scroll(to: .zero)
        }
    }

    @objc
    private func handleDoubleClick() {
        let clickedRow = tableView.clickedRow
        guard clickedRow >= 0, clickedRow < rows.count else { return }
        guard case let .entry(entry) = rows[clickedRow].kind else { return }
        EntryContextMenuUtils.sendWithSelection(entry, fsStore: fsStore, action: {
            self.store.send(.entries(.openSelectedItem))
        })
    }

    @objc
    private func contextMenuOpenSelectedItem() {
        fsStore.send(.openSelectedItem)
    }

    @objc
    private func contextMenuQuickLookSelectedItem() {
        fsStore.send(.quickLookSelectedItem)
    }

    @objc
    private func contextMenuGetInfoForSelectedItems() {
        fsStore.send(.getInfoForSelectedItems)
    }

    @objc
    private func contextMenuShareSelectedItems() {
        fsStore.send(.shareSelectedItems(anchor: contextMenuAnchor))
    }

    @objc
    private func contextMenuRevealSelectedItemsInFinder() {
        fsStore.send(.revealSelectedItemsInFinder)
    }

    @objc
    private func contextMenuCopySelectedItems() {
        fsStore.send(.copySelectedItems)
    }

    @objc
    private func contextMenuPasteItems() {
        fsStore.send(.pasteItems(destinationPath: store.state.currentPath))
    }

    @objc
    private func contextMenuStartRename() {
        guard let id = store.state.entries.selectedIds.first else { return }
        fsStore.send(.startRename(id: id))
    }

    @objc
    private func contextMenuMoveSelectedItemsToTrash() {
        fsStore.send(.moveSelectedItemsToTrash)
    }
}

private final class EntryListTableView: NSTableView {
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

private protocol EntryListTableViewContextMenuProviding: AnyObject {
    func contextMenu(forRow row: Int?, event: NSEvent) -> NSMenu
}

extension EntryListTableViewController: EntryListTableViewContextMenuProviding {
    fileprivate func contextMenu(forRow row: Int?, event _: NSEvent) -> NSMenu {
        updateContextMenuAnchor(forRow: row)

        let menu = NSMenu()
        let selectedIds = store.state.entries.selectedIds

        menu.addItem(withTitle: "Open", action: #selector(contextMenuOpenSelectedItem), keyEquivalent: "")
        menu.addItem(withTitle: "Quick Look", action: #selector(contextMenuQuickLookSelectedItem), keyEquivalent: "")
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "Get Info", action: #selector(contextMenuGetInfoForSelectedItems), keyEquivalent: "")
        menu.addItem(withTitle: "Share…", action: #selector(contextMenuShareSelectedItems), keyEquivalent: "")
        menu.addItem(
            withTitle: "Reveal in Finder",
            action: #selector(contextMenuRevealSelectedItemsInFinder),
            keyEquivalent: "",
        )
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "Copy", action: #selector(contextMenuCopySelectedItems), keyEquivalent: "")
        menu.addItem(withTitle: "Paste", action: #selector(contextMenuPasteItems), keyEquivalent: "")
        menu.addItem(NSMenuItem.separator())

        let renameItem = NSMenuItem(title: "Rename", action: #selector(contextMenuStartRename), keyEquivalent: "")
        renameItem.isEnabled = selectedIds.count == 1
        menu.addItem(renameItem)

        menu.addItem(
            withTitle: "Move to Trash",
            action: #selector(contextMenuMoveSelectedItemsToTrash),
            keyEquivalent: "",
        )
        return menu
    }
}

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
        proposedDropOperation dropOperation: NSTableView.DropOperation,
    ) -> NSDragOperation {
        _ = info

        var destinationPath = store.state.currentPath
        if dropOperation == .on,
           row >= 0,
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
        let isOptionDrag = isInternalDrag
            ? entryClient.loadDragWithOption()
            : NSEvent.modifierFlags.contains(.option)

        if isInternalDrag, !isOptionDrag {
            let sourceParent = URL(fileURLWithPath: sourcePaths[0]).deletingLastPathComponent().path
            if sourceParent == destinationPath {
                return []
            }

            // 자기 자신의 하위 폴더로 이동 방지
            for sourcePath in sourcePaths {
                if destinationPath.hasPrefix(sourcePath + "/") || destinationPath == sourcePath {
                    return []
                }
            }
        }

        return isOptionDrag ? .copy : .move
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

        let isOptionPressed = NSEvent.modifierFlags.contains(.option)
        fsStore.send(.dropItems(
            sourcePaths: urls.map(\.path),
            destinationPath: destinationPath,
            isOptionDrag: isOptionPressed,
        ))
        return true
    }
}

extension EntryListTableViewController: NSTableViewDelegate {
    func tableView(
        _: NSTableView,
        draggingSession _: NSDraggingSession,
        willBeginAt _: NSPoint,
        forRowsWith rowIndexes: IndexSet,
    ) {
        let paths = rowIndexes.compactMap { index -> String? in
            guard index >= 0, index < rows.count else { return nil }
            guard case let .entry(entry) = rows[index].kind else { return nil }
            return entry.fullPath
        }
        guard !paths.isEmpty else { return }
        fsStore.send(.startDrag(paths: paths))
    }

    func tableView(
        _: NSTableView,
        draggingSession _: NSDraggingSession,
        endedAt _: NSPoint,
        operation: NSDragOperation,
    ) {
        guard operation == [] else { return }
        fsStore.send(.startDrag(paths: []))
    }

    func tableView(_ tableView: NSTableView, sortDescriptorsDidChange _: [NSSortDescriptor]) {
        guard !isUpdatingSortFromStore else { return }
        guard let descriptor = tableView.sortDescriptors.first else { return }
        guard let key = descriptor.key else { return }
        guard let column = Column(rawValue: key) else { return }

        let sortKey: SortKey = switch column {
        case .name:
            .name
        case .dateModified:
            .dateModified
        case .size:
            .size
        case .kind:
            .kind
        }
        let sortOrder: SortOrder = descriptor.ascending ? .ascending : .descending

        if store.state.sortKey != sortKey {
            store.send(.changeSortKey(sortKey))
        }
        if store.state.sortOrder != sortOrder {
            store.send(.changeSortOrder(sortOrder))
        }
    }

    func tableView(_: NSTableView, isGroupRow row: Int) -> Bool {
        guard row >= 0, row < rows.count else { return false }
        if case .groupHeader = rows[row].kind {
            return true
        }
        return false
    }

    func tableView(_: NSTableView, shouldSelectRow row: Int) -> Bool {
        guard row >= 0, row < rows.count else { return false }
        if case .groupHeader = rows[row].kind {
            return false
        }
        return true
    }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        guard row >= 0, row < rows.count else { return tableView.rowHeight }

        switch rows[row].kind {
        case .groupHeader:
            return 32
        case .entry:
            return max(24, store.state.listIconSize + 4)
        }
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard row >= 0, row < rows.count else { return nil }

        let identifier = tableColumn?.identifier.rawValue
        let cellIdentifier = NSUserInterfaceItemIdentifier("cell-\(identifier ?? "unknown")")

        let view = (tableView.makeView(withIdentifier: cellIdentifier, owner: self) as? NSTableCellView)
            ?? NSTableCellView()
        view.identifier = cellIdentifier

        func setText(_ text: String, font: NSFont = .systemFont(ofSize: 12)) {
            let label = view.textField ?? {
                let tf = NSTextField(labelWithString: "")
                tf.translatesAutoresizingMaskIntoConstraints = false
                view.addSubview(tf)
                NSLayoutConstraint.activate([
                    tf.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                    tf.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor),
                    tf.centerYAnchor.constraint(equalTo: view.centerYAnchor),
                ])
                view.textField = tf
                return tf
            }()
            label.font = font
            label.stringValue = text
        }

        switch rows[row].kind {
        case let .groupHeader(title, colorCode):
            let prefix = if let colorCode {
                "● "
            } else {
                ""
            }
            _ = prefix
            setText(title, font: .systemFont(ofSize: 12, weight: .semibold))
            return view

        case let .entry(entry):
            switch Column(rawValue: identifier ?? "") {
            case .name:
                setText(entry.name, font: .systemFont(ofSize: store.state.listTextSize))
            case .dateModified:
                setText(entry.formattedModifiedDate, font: .systemFont(ofSize: max(10, store.state.listTextSize - 1)))
            case .size:
                setText(entry.formattedSize, font: .systemFont(ofSize: max(10, store.state.listTextSize - 1)))
            case .kind:
                let kindText = entry.fileExtension.lowercased() == "voycoll" ? "Voyager Collection" : entry.kind
                setText(kindText, font: .systemFont(ofSize: max(10, store.state.listTextSize - 1)))
            case .none:
                setText("")
            }

            return view
        }
    }

    func tableViewSelectionDidChange(_: Notification) {
        guard !isUpdatingSelectionFromStore else { return }

        let selectedIndexes = tableView.selectedRowIndexes
        let selectedIds: Set<String> = Set(selectedIndexes.compactMap { index in
            guard index >= 0, index < rows.count else { return nil }
            guard case let .entry(entry) = rows[index].kind else { return nil }
            return entry.id
        })

        let clickedRow = tableView.clickedRow
        let lastSelectedId: String? = if selectedIndexes.contains(clickedRow),
                                         clickedRow >= 0,
                                         clickedRow < rows.count,
                                         case let .entry(entry) = rows[clickedRow].kind
        {
            entry.id
        } else if let lastIndex = selectedIndexes.last,
                  lastIndex >= 0,
                  lastIndex < rows.count,
                  case let .entry(entry) = rows[lastIndex].kind
        {
            entry.id
        } else {
            nil
        }

        fsStore.send(.setSelectedIds(ids: selectedIds, lastSelectedId: lastSelectedId))
    }
}

// swiftlint:enable type_body_length
