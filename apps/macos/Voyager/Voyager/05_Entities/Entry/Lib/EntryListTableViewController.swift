import AppKit
import Combine
import ComposableArchitecture
import SwiftUI

final class EntryListTableViewController: NSViewController {
    final class OutlineItem: Hashable {
        enum Kind {
            case group(name: String, colorCode: Int?, isCollapsed: Bool)
            case entry(Entry)
        }

        let kind: Kind
        let children: [OutlineItem]
        let id: String

        init(kind: Kind, children: [OutlineItem] = []) {
            self.kind = kind
            self.children = children
            switch kind {
            case let .group(name, _, _):
                id = "group:\(name)"
            case let .entry(entry):
                id = entry.id
            }
        }

        static func == (lhs: OutlineItem, rhs: OutlineItem) -> Bool {
            lhs.id == rhs.id
        }

        func hash(into hasher: inout Hasher) {
            hasher.combine(id)
        }
    }

    enum Column: String {
        case name
        case dateModified
        case size
        case kind
    }

    let store: StoreOf<FileManagerFeature>
    let fsStore: StoreOf<EntriesFeature>
    var cancellables: Set<AnyCancellable> = []

    let scrollView = NSScrollView()
    let tableView = EntryListTableView()

    private(set) var outlineItems: [OutlineItem] = []
    private(set) var entryItemById: [String: OutlineItem] = [:]
    private var groupItemByName: [String: OutlineItem] = [:]

    var columnWidthCache: [Column: CGFloat] = [:]
    var isUpdatingColumnsFromStore = false
    var isUpdatingSortFromStore = false

    private var lastInteractedRow: Int?
    var isUpdatingSelectionFromStore = false
    var hasRestoredScrollPosition = false
    var isUpdatingGroupExpansion = false

    var lastRenamingItemId: String?

    private(set) var contextMenuAnchor: CGPoint?

    @Dependency(\.entryClient)
    var entryClient: EntryClient
    @Dependency(\.fileManagerWindowClient)
    var fileManagerWindowClient: FileManagerWindowClient

    func isDescendantPath(_ destinationPath: String, of sourcePath: String) -> Bool {
        let destinationComponents = URL(fileURLWithPath: destinationPath)
            .standardizedFileURL.pathComponents
        let sourceComponents = URL(fileURLWithPath: sourcePath)
            .standardizedFileURL.pathComponents

        guard destinationComponents.count > sourceComponents.count else {
            return false
        }

        return Array(destinationComponents.prefix(sourceComponents.count)) == sourceComponents
    }

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

    func updateContextMenuAnchor(forRow row: Int?) {
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
        observeListStore()
        observeTableView()
        rebuildRowsAndReload()
        updateDropTargetBorder(isTargeted: store.state.entries.isDropTargeted)
    }

    private func observeTableView() {
        NotificationCenter.default.publisher(for: NSTableView.columnDidResizeNotification, object: tableView)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                self?.handleListColumnDidResize(notification)
            }
            .store(in: &cancellables)
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        applyListColumnLayout()
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

        tableView.outlineTableColumn = nameColumn
        tableView.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
    }

    func rebuildRowsAndReload() {
        outlineItems = makeOutlineItems(state: store.state)
        entryItemById = Dictionary(uniqueKeysWithValues: outlineItems.flatMap { $0.flattenEntries() })
        groupItemByName = Dictionary(uniqueKeysWithValues: outlineItems.compactMap { item in
            if case let .group(name, _, _) = item.kind {
                return (name, item)
            }
            return nil
        })

        tableView.reloadData()
        applyListColumnLayout()
        syncListSelectionFromStore()
        applyGroupExpansionState()
        scrollToSelectionIfNeeded()
        restoreScrollPositionIfNeeded()
    }

    func saveScrollPosition() {
        ScrollPositionUtils.saveScrollPosition(
            scrollView: scrollView,
            currentPath: store.state.currentPath,
            store: store,
        )
    }

    func scrollToSelectionIfNeeded() {
        guard store.state.entries.shouldScrollToSelection else { return }

        let targetId = store.state.entries.lastSelectedId
            ?? store.state.entries.selectedIds.first
        guard let targetId, let item = entryItemById[targetId] else {
            fsStore.send(.resetScrollFlag)
            return
        }
        let row = tableView.row(forItem: item)
        guard row >= 0 else {
            fsStore.send(.resetScrollFlag)
            return
        }

        tableView.scrollRowToVisible(row)
        fsStore.send(.resetScrollFlag)
    }

    func updateDropTargetBorder(isTargeted: Bool) {
        scrollView.layer?.borderWidth = isTargeted ? 2 : 0
        scrollView.layer?.borderColor = isTargeted ? NSColor.controlAccentColor.cgColor : nil
    }

    private func makeOutlineItems(state: FileManagerFeature.State) -> [OutlineItem] {
        let entries = state.entries

        if entries.groupKey == .none {
            return entries.displayItems.map { OutlineItem(kind: .entry($0)) }
        }

        var result: [OutlineItem] = []

        for group in entries.groupedItems {
            let items = group.items.map { OutlineItem(kind: .entry($0)) }
            if !group.groupName.isEmpty, entries.groupKey != .name {
                let colorCode: Int? = if entries.groupKey == .tags {
                    EntryTagUtils.getTagNameToColorCodeMapping()[group.groupName]
                } else {
                    nil
                }
                let isCollapsed = entries.collapsedGroups.contains(group.groupName)
                let groupItem = OutlineItem(
                    kind: .group(name: group.groupName, colorCode: colorCode, isCollapsed: isCollapsed),
                    children: items
                )
                result.append(groupItem)
            } else {
                result.append(contentsOf: items)
            }
        }

        return result
    }

    private func applyGroupExpansionState() {
        isUpdatingGroupExpansion = true
        for (name, item) in groupItemByName {
            if store.state.entries.collapsedGroups.contains(name) {
                tableView.collapseItem(item)
            } else {
                tableView.expandItem(item)
            }
        }
        isUpdatingGroupExpansion = false
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
        guard clickedRow >= 0 else { return }
        guard let item = tableView.item(atRow: clickedRow) as? OutlineItem else { return }
        guard case let .entry(entry) = item.kind else { return }
        EntryContextMenuUtils.sendWithSelection(entry, fsStore: fsStore, action: {
            self.saveScrollPosition()
            self.store.send(.entries(.openSelectedItem))
        })
    }
}

extension EntryListTableViewController: NSOutlineViewDelegate {
    func outlineView(_: NSOutlineView, shouldEdit tableColumn: NSTableColumn?, item: Any) -> Bool {
        guard let tableColumn else { return false }
        guard tableColumn.identifier.rawValue == Column.name.rawValue else { return false }
        guard let outlineItem = item as? OutlineItem else { return false }
        guard case let .entry(entry) = outlineItem.kind else { return false }
        guard store.state.entries.renamingItemId == entry.id else { return false }
        return true
    }

    func outlineView(
        _: NSOutlineView,
        draggingSession _: NSDraggingSession,
        willBeginAt _: NSPoint,
        forItems items: [Any],
    ) {
        let paths = items.compactMap { item -> String? in
            guard let outlineItem = item as? OutlineItem else { return nil }
            guard case let .entry(entry) = outlineItem.kind else { return nil }
            return entry.fullPath
        }
        guard !paths.isEmpty else { return }
        fsStore.send(.startDrag(paths: paths))
    }

    func outlineView(
        _: NSOutlineView,
        draggingSession _: NSDraggingSession,
        endedAt _: NSPoint,
        operation: NSDragOperation,
    ) {
        guard operation.isEmpty else { return }
        fsStore.send(.startDrag(paths: []))
        fsStore.send(.setDropTargeted(false))
    }

    func outlineView(_ outlineView: NSOutlineView, sortDescriptorsDidChange _: [NSSortDescriptor]) {
        guard !isUpdatingSortFromStore else { return }
        guard let descriptor = outlineView.sortDescriptors.first else { return }
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

    func outlineView(_: NSOutlineView, isGroupItem item: Any) -> Bool {
        guard let outlineItem = item as? OutlineItem else { return false }
        if case .group = outlineItem.kind {
            return true
        }
        return false
    }

    func outlineView(_: NSOutlineView, shouldSelectItem item: Any) -> Bool {
        guard let outlineItem = item as? OutlineItem else { return false }
        if case .group = outlineItem.kind {
            return false
        }
        return true
    }

    func outlineView(_ outlineView: NSOutlineView, heightOfRowByItem item: Any) -> CGFloat {
        guard let outlineItem = item as? OutlineItem else { return outlineView.rowHeight }
        switch outlineItem.kind {
        case .group:
            return 32
        case .entry:
            return max(24, store.state.listIconSize + 4)
        }
    }

    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        guard let outlineItem = item as? OutlineItem else { return nil }

        let columnId = tableColumn?.identifier.rawValue ?? "unknown"
        let cellIdentifier = NSUserInterfaceItemIdentifier("cell-\(columnId)")
        let view = makeCellView(tableView: outlineView, identifier: cellIdentifier)

        switch outlineItem.kind {
        case let .group(title, colorCode, _):
            configureGroupHeaderCell(view, title: title, colorCode: colorCode)
            return view
        case let .entry(entry):
            configureEntryCell(view, entry: entry, columnId: columnId)
            return view
        }
    }

    func outlineViewSelectionDidChange(_: Notification) {
        guard !isUpdatingSelectionFromStore else { return }

        let selectedIndexes = tableView.selectedRowIndexes
        let selectedIds: Set<String> = Set(selectedIndexes.compactMap { index in
            guard let outlineItem = tableView.item(atRow: index) as? OutlineItem else { return nil }
            guard case let .entry(entry) = outlineItem.kind else { return nil }
            return entry.id
        })

        let clickedRow = tableView.clickedRow
        let lastSelectedId: String? = if selectedIndexes.contains(clickedRow),
                                         let item = tableView.item(atRow: clickedRow) as? OutlineItem,
                                         case let .entry(entry) = item.kind
        {
            entry.id
        } else if let lastIndex = selectedIndexes.last,
                  let item = tableView.item(atRow: lastIndex) as? OutlineItem,
                  case let .entry(entry) = item.kind
        {
            entry.id
        } else {
            nil
        }

        fsStore.send(.setSelectedIds(ids: selectedIds, lastSelectedId: lastSelectedId))
    }

    func outlineViewItemDidExpand(_ notification: Notification) {
        guard !isUpdatingGroupExpansion else { return }
        guard let item = notification.userInfo?["NSObject"] as? OutlineItem else { return }
        guard case let .group(name, _, _) = item.kind else { return }
        if store.state.entries.collapsedGroups.contains(name) {
            fsStore.send(.toggleGroup(name))
        }
    }

    func outlineViewItemDidCollapse(_ notification: Notification) {
        guard !isUpdatingGroupExpansion else { return }
        guard let item = notification.userInfo?["NSObject"] as? OutlineItem else { return }
        guard case let .group(name, _, _) = item.kind else { return }
        if !store.state.entries.collapsedGroups.contains(name) {
            fsStore.send(.toggleGroup(name))
        }
    }
}

extension EntryListTableViewController: NSOutlineViewDataSource {
    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        guard let item else { return outlineItems.count }
        guard let outlineItem = item as? OutlineItem else { return 0 }
        return outlineItem.children.count
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        guard let outlineItem = item as? OutlineItem else { return false }
        switch outlineItem.kind {
        case .group:
            return !outlineItem.children.isEmpty
        case .entry:
            return false
        }
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        guard let item else { return outlineItems[index] }
        guard let outlineItem = item as? OutlineItem else { return outlineItems[index] }
        return outlineItem.children[index]
    }

    func outlineView(_: NSOutlineView, pasteboardWriterForItem item: Any) -> (any NSPasteboardWriting)? {
        guard let outlineItem = item as? OutlineItem else { return nil }
        guard case let .entry(entry) = outlineItem.kind else { return nil }
        return NSURL(fileURLWithPath: entry.fullPath)
    }

    func outlineView(
        _ outlineView: NSOutlineView,
        validateDrop info: any NSDraggingInfo,
        proposedItem item: Any?,
        proposedChildIndex _: Int,
    ) -> NSDragOperation {
        var destinationPath = store.state.currentPath
        if let outlineItem = item as? OutlineItem,
           case let .entry(entry) = outlineItem.kind,
           entry.isDirectory
        {
            outlineView.setDropItem(outlineItem, dropChildIndex: NSOutlineViewDropOnItemIndex)
            destinationPath = entry.fullPath
        } else {
            outlineView.setDropItem(nil, dropChildIndex: -1)
        }

        let sourcePaths = entryClient.loadDragPaths()
        let isInternalDrag = !sourcePaths.isEmpty
        let wantsCopy = isInternalDrag ? entryClient.loadDragWithOption() : NSEvent.modifierFlags.contains(.option)

        if isInternalDrag, !wantsCopy {
            let sourceParent = URL(fileURLWithPath: sourcePaths[0]).deletingLastPathComponent().path
            if sourceParent == destinationPath {
                fsStore.send(.setDropTargeted(false))
                return []
            }

            // 자기 자신의 하위 폴더로 이동 방지
            for sourcePath in sourcePaths {
                if destinationPath == sourcePath || isDescendantPath(destinationPath, of: sourcePath) {
                    fsStore.send(.setDropTargeted(false))
                    return []
                }
            }
        }

        let allowed = info.draggingSourceOperationMask
        let preferred: NSDragOperation = wantsCopy ? .copy : .move
        if !preferred.isDisjoint(with: allowed) {
            let operation = preferred.intersection(allowed)
            fsStore.send(.setDropTargeted(!operation.isEmpty))
            return operation
        }

        // 외부 드래그에서 move 불가(copy만 가능 등) fallback
        let fallback = NSDragOperation.copy.intersection(allowed)
        fsStore.send(.setDropTargeted(!fallback.isEmpty))
        return fallback
    }

    func outlineView(
        _: NSOutlineView,
        acceptDrop info: any NSDraggingInfo,
        item: Any?,
        childIndex _: Int,
    ) -> Bool {
        var destinationPath = store.state.currentPath
        if let outlineItem = item as? OutlineItem,
           case let .entry(entry) = outlineItem.kind,
           entry.isDirectory
        {
            destinationPath = entry.fullPath
        }

        let internalPaths = entryClient.loadDragPaths()
        if !internalPaths.isEmpty {
            fsStore.send(.handleDrop(providers: [], destinationPath: destinationPath))
            fsStore.send(.setDropTargeted(false))
            return true
        }

        let pasteboard = info.draggingPasteboard
        let options: [NSPasteboard.ReadingOptionKey: Any] = [
            .urlReadingFileURLsOnly: true,
        ]
        guard let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: options) as? [URL],
              !urls.isEmpty
        else {
            fsStore.send(.setDropTargeted(false))
            return false
        }

        let allowed = info.draggingSourceOperationMask
        let preferred: NSDragOperation = NSEvent.modifierFlags.contains(.option) ? .copy : .move
        let resolved = preferred.isDisjoint(with: allowed)
            ? NSDragOperation.copy.intersection(allowed)
            : preferred.intersection(allowed)
        guard !resolved.isEmpty else {
            fsStore.send(.setDropTargeted(false))
            return false
        }
        let isOptionPressed = resolved.contains(.copy) && !resolved.contains(.move)
        fsStore.send(.dropItems(
            sourcePaths: urls.map(\.path),
            destinationPath: destinationPath,
            isOptionDrag: isOptionPressed
        ))
        fsStore.send(.setDropTargeted(false))
        return true
    }
}

private extension EntryListTableViewController {
    func makeCellView(
        tableView: NSTableView,
        identifier: NSUserInterfaceItemIdentifier,
    ) -> NSTableCellView {
        let view = (tableView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView)
            ?? NSTableCellView()
        view.identifier = identifier
        return view
    }

    @discardableResult
    func setText(
        _ text: String,
        in view: NSTableCellView,
        font: NSFont = .systemFont(ofSize: 12),
    ) -> NSTextField {
        let label = view.textField ?? {
            let textField = NSTextField(labelWithString: "")
            textField.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(textField)
            NSLayoutConstraint.activate([
                textField.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                textField.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor),
                textField.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            ])
            view.textField = textField
            return textField
        }()
        label.font = font
        label.stringValue = text
        return label
    }

    func configureGroupHeaderCell(_ view: NSTableCellView, title: String, colorCode: Int?) {
        let prefix = colorCode != nil ? "● " : ""
        setText(prefix + title, in: view, font: .systemFont(ofSize: 12, weight: .semibold))
    }

    func configureEntryCell(_ view: NSTableCellView, entry: Entry, columnId: String) {
        switch Column(rawValue: columnId) {
        case .name:
            let isRenaming = store.state.entries.renamingItemId == entry.id
            let nameText = isRenaming ? store.state.entries.renamingText : entry.name
            let textField = setText(nameText, in: view, font: .systemFont(ofSize: store.state.listTextSize))
            textField.lineBreakMode = .byTruncatingMiddle
            textField.usesSingleLineMode = true

            textField.isEditable = isRenaming
            textField.isSelectable = isRenaming
            textField.isBordered = isRenaming
            textField.drawsBackground = isRenaming
            textField.backgroundColor = isRenaming ? .textBackgroundColor : .clear
            textField.focusRingType = isRenaming ? .default : .none
            textField.delegate = isRenaming ? self : nil

        case .dateModified:
            setText(
                entry.formattedModifiedDate,
                in: view,
                font: .systemFont(ofSize: max(10, store.state.listTextSize - 1))
            )

        case .size:
            setText(
                entry.formattedSize,
                in: view,
                font: .systemFont(ofSize: max(10, store.state.listTextSize - 1))
            )

        case .kind:
            let kindText = entry.fileExtension.lowercased() == "voycoll" ? "Voyager Collection" : entry.kind
            setText(
                kindText,
                in: view,
                font: .systemFont(ofSize: max(10, store.state.listTextSize - 1))
            )

        case .none:
            setText("", in: view)
        }
    }
}

extension EntryListTableViewController {
    func observeListStore() {
        observeDisplayItems()
        observeGroupKey()
        observeGroupedItems()
        observeCurrentPath()
        observeSelectedIds()
        observeRenamingItemId()
        observeColumnWidths()
        observeSortIndicators()
        observeShowHiddenFiles()
        observeShouldScrollToSelection()
        observeDropTargeted()
    }

    func applyListColumnLayout() {
        guard tableView.tableColumns.count == 4 else { return }
        let layout = store.state.columnWidths.makeAbsoluteWidths(
            totalWidth: scrollView.bounds.width,
            padding: ListColumnLayoutUtils.outerPadding,
            spacing: ListColumnLayoutUtils.columnSpacing
        )

        isUpdatingColumnsFromStore = true
        tableView.tableColumns[0].width = layout.name
        tableView.tableColumns[1].width = layout.date
        tableView.tableColumns[2].width = layout.size
        tableView.tableColumns[3].width = layout.kind

        cacheColumnWidths()
        isUpdatingColumnsFromStore = false
    }

    func handleListColumnDidResize(_ notification: Notification) {
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
                spacing: ListColumnLayoutUtils.columnSpacing
            )
        ))
    }

    func syncListSortIndicators(sortKey: SortKey, sortOrder: SortOrder) {
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

    func syncListSelectionFromStore() {
        let selectedIds = store.state.entries.selectedIds
        let indexes = IndexSet(selectedIds.compactMap { id in
            guard let item = entryItemById[id] else { return nil }
            let row = tableView.row(forItem: item)
            return row >= 0 ? row : nil
        })

        isUpdatingSelectionFromStore = true
        tableView.selectRowIndexes(indexes, byExtendingSelection: false)
        isUpdatingSelectionFromStore = false
    }

    func syncListRenamingFromStore() {
        let renamingItemId = store.state.entries.renamingItemId
        let previousRenamingItemId = lastRenamingItemId
        lastRenamingItemId = renamingItemId

        let nameColumnIndexes = IndexSet(integer: 0)

        if let previousRenamingItemId,
           let item = entryItemById[previousRenamingItemId]
        {
            let row = tableView.row(forItem: item)
            if row >= 0 {
                tableView.reloadData(forRowIndexes: IndexSet(integer: row), columnIndexes: nameColumnIndexes)
            }
        }

        guard let renamingItemId,
              let item = entryItemById[renamingItemId]
        else {
            view.window?.makeFirstResponder(tableView)
            return
        }

        let row = tableView.row(forItem: item)
        guard row >= 0 else {
            view.window?.makeFirstResponder(tableView)
            return
        }
        tableView.reloadData(forRowIndexes: IndexSet(integer: row), columnIndexes: nameColumnIndexes)
        beginRenaming(row: row)
    }

    private func observeDisplayItems() {
        store.publisher.entries.displayItems
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.rebuildRowsAndReload()
            }
            .store(in: &cancellables)
    }

    private func observeGroupKey() {
        store.publisher.entries.groupKey
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.rebuildRowsAndReload()
            }
            .store(in: &cancellables)
    }

    private func observeGroupedItems() {
        store.publisher.entries.groupedItems
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.rebuildRowsAndReload()
            }
            .store(in: &cancellables)
    }

    private func observeCurrentPath() {
        store.publisher.currentPath
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.hasRestoredScrollPosition = false
            }
            .store(in: &cancellables)
    }

    private func observeSelectedIds() {
        store.publisher.entries.selectedIds
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.syncListSelectionFromStore()
            }
            .store(in: &cancellables)
    }

    private func observeRenamingItemId() {
        store.publisher.entries.renamingItemId
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.syncListRenamingFromStore()
            }
            .store(in: &cancellables)
    }

    private func observeColumnWidths() {
        store.publisher.columnWidths
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.applyListColumnLayout()
            }
            .store(in: &cancellables)
    }

    private func observeSortIndicators() {
        Publishers.CombineLatest(store.publisher.sortKey, store.publisher.sortOrder)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] sortKey, sortOrder in
                self?.syncListSortIndicators(sortKey: sortKey, sortOrder: sortOrder)
            }
            .store(in: &cancellables)
    }

    private func observeShowHiddenFiles() {
        store.publisher.showHiddenFiles
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.saveScrollPosition()
            }
            .store(in: &cancellables)
    }

    private func observeShouldScrollToSelection() {
        store.publisher.entries.shouldScrollToSelection
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] shouldScroll in
                guard shouldScroll else { return }
                self?.scrollToSelectionIfNeeded()
            }
            .store(in: &cancellables)
    }

    private func observeDropTargeted() {
        store.publisher.entries.isDropTargeted
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isTargeted in
                self?.updateDropTargetBorder(isTargeted: isTargeted)
            }
            .store(in: &cancellables)
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

    private func beginRenaming(row: Int) {
        guard row >= 0, row < tableView.numberOfRows else { return }

        tableView.scrollRowToVisible(row)

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }

            // 셀 생성/업데이트 이후에 first responder를 잡아야 editColumn이 안정적으로 동작함
            _ = tableView.view(atColumn: 0, row: row, makeIfNecessary: true)
            tableView.editColumn(0, row: row, with: nil, select: true)

            guard let cell = tableView.view(atColumn: 0, row: row, makeIfNecessary: false) as? NSTableCellView,
                  let textField = cell.textField
            else {
                return
            }

            textField.stringValue = store.state.entries.renamingText
            textField.delegate = self
            view.window?.makeFirstResponder(textField)
            textField.selectText(nil)
        }
    }
}

private extension EntryListTableViewController.OutlineItem {
    func flattenEntries() -> [(String, EntryListTableViewController.OutlineItem)] {
        switch kind {
        case .entry:
            return [(id, self)]
        case .group:
            return children.flatMap { $0.flattenEntries() }
        }
    }
}
