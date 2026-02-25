// swiftlint:disable file_length
import AppKit
import Combine
import ComposableArchitecture

@MainActor
final class EntryListCoordinator: NSObject {
    final class OutlineItem: Hashable {
        enum Kind {
            case group(name: String, colorCode: Int?, isCollapsed: Bool)
            case entry(EntryModel)
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

    let adapter: EntryViewLayoutAdapter
    private var cancellables: Set<AnyCancellable> = []

    private var store: StoreOf<EntryViewLayoutFeature> { adapter.entryViewLayoutStore }
    private var pageState: EntryViewLayoutAdapter.PageState { adapter.pageState() }

    private weak var view: EntryListView?
    private var didBind = false

    private var scrollView: NSScrollView {
        guard let view else { preconditionFailure("EntryListView is not bound") }
        return view.scrollView
    }

    private var tableView: EntryListView.EntryListTableView {
        guard let view else { preconditionFailure("EntryListView is not bound") }
        return view.tableView
    }

    private var nameColumnIndex: Int? {
        let index = tableView.column(withIdentifier: NSUserInterfaceItemIdentifier(EntryListColumn.name.rawValue))
        return index >= 0 ? index : nil
    }

    private var outlineItems: [OutlineItem] = []
    private var entryItemById: [String: OutlineItem] = [:]
    private var groupItemByName: [String: OutlineItem] = [:]

    private var isUpdatingSortFromStore = false

    private var isUpdatingSelectionFromStore = false
    private var hasRestoredScrollPosition = false
    private var isUpdatingGroupExpansion = false

    private var lastRenamingItemId: String?
    private var contextMenuAnchor: CGPoint?
    private var contextMenuCoordinator: EntryContextMenuCoordinator?

    @Dependency(\.entryOpenClient)
    private var entryOpenClient
    @Dependency(\.entryFileOpsClient)
    private var entryFileOpsClient

    @Dependency(\.workspaceClient)
    private var workspaceClient
    @Dependency(\.entryThumbnailCacheClient)
    private var entryThumbnailCacheClient

    init(adapter: EntryViewLayoutAdapter) {
        self.adapter = adapter
        super.init()
    }

    func bind(to view: EntryListView) {
        self.view = view

        tableView.delegate = self
        tableView.dataSource = self
        tableView.contextMenuProvider = self
        tableView.target = self
        tableView.doubleAction = #selector(handleDoubleClick)
        view.applyColumns(pageState.listVisibleColumns)

        guard !didBind else {
            view.applyColumns(pageState.listVisibleColumns)
            updateDropTargetBorder(isTargeted: pageState.isDropTargeted)
            return
        }

        didBind = true
        observeListStore()
        observeTableView()
        rebuildRowsAndReload()
        updateDropTargetBorder(isTargeted: pageState.isDropTargeted)
    }

    func updateRootView(_ view: EntryListView) {
        guard self.view !== view else { return }
        self.view = view
        tableView.delegate = self
        tableView.dataSource = self
        tableView.contextMenuProvider = self
        tableView.target = self
        tableView.doubleAction = #selector(handleDoubleClick)
        view.applyColumns(pageState.listVisibleColumns)
    }

    private func observeTableView() {
        NotificationCenter.default.publisher(for: NSView.boundsDidChangeNotification, object: scrollView.contentView)
            .receive(on: DispatchQueue.main)
            .throttle(for: .milliseconds(150), scheduler: DispatchQueue.main, latest: true)
            .sink { [weak self] _ in
                self?.requestThumbnailsForVisibleRows()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: NSTableView.columnDidMoveNotification, object: tableView)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.syncVisibleColumnsFromTableView()
            }
            .store(in: &cancellables)
    }

    private func rebuildRowsAndReload() {
        outlineItems = makeOutlineItems(state: pageState)
        entryItemById = Dictionary(uniqueKeysWithValues: outlineItems.flatMap { $0.flattenEntries() })
        groupItemByName = Dictionary(uniqueKeysWithValues: outlineItems.compactMap { item in
            if case let .group(name, _, _) = item.kind {
                return (name, item)
            }
            return nil
        })

        tableView.reloadData()
        syncListSelectionFromStore()
        applyGroupExpansionState()
        scrollToSelectionIfNeeded()
        restoreScrollPositionIfNeeded()
        requestThumbnailsForVisibleRows()
    }

    private func requestThumbnailsForVisibleRows() {
        guard tableView.numberOfRows > 0 else { return }

        let visibleRange = tableView.rows(in: tableView.visibleRect)
        guard visibleRange.length > 0 else { return }

        let extraRows = max(visibleRange.length, 20)
        let startRow = max(0, visibleRange.location - extraRows)
        let endRow = min(tableView.numberOfRows, visibleRange.location + visibleRange.length + extraRows)

        var paths: Set<String> = []
        paths.reserveCapacity(visibleRange.length)

        for row in startRow ..< endRow {
            guard let outlineItem = tableView.item(atRow: row) as? OutlineItem else { continue }
            guard case let .entry(entry) = outlineItem.kind else { continue }
            guard !entry.isFolder else { continue }
            paths.insert(entry.fullPath)
        }

        guard !paths.isEmpty else { return }
        adapter.actions.requestThumbnails(Array(paths))
    }

    private func saveScrollPosition() {
        let offset = scrollView.contentView.bounds.origin
        adapter.actions.saveScrollOffset(offset, pageState.currentPath)
    }

    private func scrollToSelectionIfNeeded() {
        guard pageState.shouldScrollToSelection else { return }

        let targetId = pageState.lastSelectedId
            ?? pageState.selectedIds.first
        guard let targetId, let item = entryItemById[targetId] else {
            store.send(.resetScrollFlag)
            return
        }
        let row = tableView.row(forItem: item)
        guard row >= 0 else {
            store.send(.resetScrollFlag)
            return
        }

        tableView.scrollRowToVisible(row)
        store.send(.resetScrollFlag)
    }

    private func updateDropTargetBorder(isTargeted: Bool) {
        scrollView.layer?.borderWidth = isTargeted ? 2 : 0
        scrollView.layer?.borderColor = isTargeted ? NSColor.controlAccentColor.cgColor : nil
    }

    private func makeOutlineItems(state: EntryViewLayoutAdapter.PageState) -> [OutlineItem] {
        if state.groupKey == .none {
            return state.entries.map { OutlineItem(kind: .entry($0)) }
        }

        var result: [OutlineItem] = []
        for group in state.groupedItems {
            let items = group.items.map { OutlineItem(kind: .entry($0)) }
            if !group.groupName.isEmpty, state.groupKey != .name {
                let colorCode: Int? = if state.groupKey == .tags {
                    resolveTagColorCode(tagName: group.groupName, items: group.items)
                } else {
                    nil
                }
                let isCollapsed = state.collapsedGroups.contains(group.groupName)
                let groupItem = OutlineItem(
                    kind: .group(name: group.groupName, colorCode: colorCode, isCollapsed: isCollapsed),
                    children: items,
                )
                result.append(groupItem)
            } else {
                result.append(contentsOf: items)
            }
        }

        return result
    }

    private func resolveTagColorCode(tagName: String, items: [EntryModel]) -> Int? {
        for item in items {
            if let colorCode = item.facets.tags?.first(where: { $0.name == tagName })?.colorCode {
                return colorCode
            }
        }
        return nil
    }

    private func applyGroupExpansionState() {
        isUpdatingGroupExpansion = true
        for (name, item) in groupItemByName {
            if pageState.collapsedGroups.contains(name) {
                tableView.collapseItem(item)
            } else {
                tableView.expandItem(item)
            }
        }
        isUpdatingGroupExpansion = false
    }

    private func restoreScrollPositionIfNeeded() {
        let itemCount = pageState.entries.count
        guard itemCount != 0 else { return }

        guard !hasRestoredScrollPosition,
              let savedOffset = pageState.savedScrollOffset
        else {
            return
        }

        scrollView.contentView.scroll(to: savedOffset)
        hasRestoredScrollPosition = true
    }

    @objc
    private func handleDoubleClick() {
        let clickedRow = tableView.clickedRow
        guard clickedRow >= 0 else { return }
        guard let item = tableView.item(atRow: clickedRow) as? OutlineItem else { return }
        guard case let .entry(entry) = item.kind else { return }
        EntryContextMenuUtils.sendWithSelection(
            entry,
            selectedIds: pageState.selectedIds,
            entryViewLayoutStore: store,
            action: { [weak self] in
                guard let self else { return }
                saveScrollPosition()
                adapter.actions.openSelectedItem()
            },
        )
    }
}

private extension EntryListCoordinator {
    func syncVisibleColumnsFromTableView() {
        let columns = tableView.tableColumns.compactMap { tableColumn in
            EntryListColumn(rawValue: tableColumn.identifier.rawValue)
        }
        let normalized = EntryListColumn.normalizeVisibleColumns(columns)
        if normalized != pageState.listVisibleColumns {
            store.send(.setListVisibleColumns(normalized))
        }
    }

    func updateContextMenuAnchor(forRow row: Int?) {
        guard let row, row >= 0 else {
            contextMenuAnchor = nil
            return
        }
        guard let window = view?.window else {
            contextMenuAnchor = nil
            return
        }

        let rectInTable = tableView.rect(ofRow: row)
        let rectInWindow = tableView.convert(rectInTable, to: nil)
        let rectInScreen = window.convertToScreen(rectInWindow)
        contextMenuAnchor = CGPoint(x: rectInScreen.midX, y: rectInScreen.midY)
    }

    func beginRenaming(row: Int) {
        guard row >= 0, row < tableView.numberOfRows else { return }
        guard let nameColumnIndex else { return }

        tableView.scrollRowToVisible(row)

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }

            _ = tableView.view(atColumn: nameColumnIndex, row: row, makeIfNecessary: true)
            tableView.editColumn(nameColumnIndex, row: row, with: nil, select: true)

            guard let cell = tableView
                .view(atColumn: nameColumnIndex, row: row, makeIfNecessary: false) as? NSTableCellView,
                let textField = cell.textField
            else {
                return
            }

            textField.stringValue = pageState.renamingText
            textField.delegate = self
            view?.window?.makeFirstResponder(textField)
            textField.selectText(nil)
        }
    }
}

private extension EntryListCoordinator.OutlineItem {
    func flattenEntries() -> [(String, EntryListCoordinator.OutlineItem)] {
        switch kind {
        case .entry:
            [(id, self)]
        case .group:
            children.flatMap { $0.flattenEntries() }
        }
    }
}

extension EntryListCoordinator: NSOutlineViewDelegate {
    func outlineView(_: NSOutlineView, shouldEdit tableColumn: NSTableColumn?, item: Any) -> Bool {
        guard let tableColumn else { return false }
        guard tableColumn.identifier.rawValue == EntryListColumn.name.rawValue else { return false }
        guard let outlineItem = item as? OutlineItem else { return false }
        guard case let .entry(entry) = outlineItem.kind else { return false }
        guard pageState.renamingItemId == entry.id else { return false }
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
        adapter.actions.startDrag(paths)
    }

    func outlineView(
        _: NSOutlineView,
        draggingSession _: NSDraggingSession,
        endedAt _: NSPoint,
        operation: NSDragOperation,
    ) {
        guard operation.isEmpty else { return }
        adapter.actions.startDrag([])
        store.send(.setDropTargeted(false))
    }

    func outlineView(_ outlineView: NSOutlineView, sortDescriptorsDidChange _: [NSSortDescriptor]) {
        guard !isUpdatingSortFromStore else { return }
        guard let descriptor = outlineView.sortDescriptors.first else { return }
        guard let key = descriptor.key else { return }
        guard let column = EntryListColumn(rawValue: key) else { return }
        guard let sortKey = column.sortKey else { return }
        let sortOrder: SortOrder = descriptor.ascending ? .ascending : .descending

        if pageState.sortKey != sortKey {
            adapter.actions.setSortKey(sortKey)
        }
        if pageState.sortOrder != sortOrder {
            adapter.actions.setSortOrder(sortOrder)
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
            return max(24, pageState.listIconSize + 4)
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

        store.send(.setSelectedIds(ids: selectedIds, lastSelectedId: lastSelectedId))
    }

    func outlineViewItemDidExpand(_ notification: Notification) {
        guard !isUpdatingGroupExpansion else { return }
        guard let item = notification.userInfo?["NSObject"] as? OutlineItem else { return }
        guard case let .group(name, _, _) = item.kind else { return }
        if pageState.collapsedGroups.contains(name) {
            adapter.actions.toggleCollapsedGroup(name)
        }
    }

    func outlineViewItemDidCollapse(_ notification: Notification) {
        guard !isUpdatingGroupExpansion else { return }
        guard let item = notification.userInfo?["NSObject"] as? OutlineItem else { return }
        guard case let .group(name, _, _) = item.kind else { return }
        if !pageState.collapsedGroups.contains(name) {
            adapter.actions.toggleCollapsedGroup(name)
        }
    }
}

extension EntryListCoordinator: NSOutlineViewDataSource {
    func outlineView(_: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        guard let item else { return outlineItems.count }
        guard let outlineItem = item as? OutlineItem else { return 0 }
        return outlineItem.children.count
    }

    func outlineView(_: NSOutlineView, isItemExpandable item: Any) -> Bool {
        guard let outlineItem = item as? OutlineItem else { return false }
        switch outlineItem.kind {
        case .group:
            return !outlineItem.children.isEmpty
        case .entry:
            return false
        }
    }

    func outlineView(_: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
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
        var destinationPath = pageState.currentPath
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
        let isInternalDrag = !sourcePaths.isEmpty
        let wantsCopy = isInternalDrag
            ? entryFileOpsClient.loadDragWithOption()
            : NSEvent.modifierFlags.contains(.option)

        if isInternalDrag, !wantsCopy {
            let sourceParent = URL(fileURLWithPath: sourcePaths[0]).deletingLastPathComponent().path
            if sourceParent == destinationPath {
                store.send(.setDropTargeted(false))
                return []
            }

            for sourcePath in sourcePaths {
                if destinationPath == sourcePath || isDescendantPath(destinationPath, of: sourcePath) {
                    store.send(.setDropTargeted(false))
                    return []
                }
            }
        }

        let allowed = info.draggingSourceOperationMask
        let preferred: NSDragOperation = wantsCopy ? .copy : .move
        if !preferred.isDisjoint(with: allowed) {
            let operation = preferred.intersection(allowed)
            store.send(.setDropTargeted(!operation.isEmpty))
            return operation
        }

        let fallback = NSDragOperation.copy.intersection(allowed)
        store.send(.setDropTargeted(!fallback.isEmpty))
        return fallback
    }

    func outlineView(
        _: NSOutlineView,
        acceptDrop info: any NSDraggingInfo,
        item: Any?,
        childIndex _: Int,
    ) -> Bool {
        var destinationPath = pageState.currentPath
        if let outlineItem = item as? OutlineItem,
           case let .entry(entry) = outlineItem.kind,
           entry.isFolder
        {
            destinationPath = entry.fullPath
        }

        let internalPaths = entryFileOpsClient.loadDragPaths()
        if !internalPaths.isEmpty {
            adapter.actions.handleDrop([], destinationPath)
            store.send(.setDropTargeted(false))
            return true
        }

        let pasteboard = info.draggingPasteboard
        let options: [NSPasteboard.ReadingOptionKey: Any] = [
            .urlReadingFileURLsOnly: true,
        ]
        guard let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: options) as? [URL],
              !urls.isEmpty
        else {
            store.send(.setDropTargeted(false))
            return false
        }

        let allowed = info.draggingSourceOperationMask
        let preferred: NSDragOperation = NSEvent.modifierFlags.contains(.option) ? .copy : .move
        let resolved = preferred.isDisjoint(with: allowed)
            ? NSDragOperation.copy.intersection(allowed)
            : preferred.intersection(allowed)
        guard !resolved.isEmpty else {
            store.send(.setDropTargeted(false))
            return false
        }
        let isOptionPressed = resolved.contains(.copy) && !resolved.contains(.move)
        adapter.actions.dropItems(urls.map(\.path), destinationPath, isOptionPressed)
        store.send(.setDropTargeted(false))
        return true
    }
}

private extension EntryListCoordinator {
    enum NameCellConstraintId {
        static let iconLeading = "EntryList.name.icon.leading"
        static let iconCenterY = "EntryList.name.icon.centerY"
        static let iconWidth = "EntryList.name.icon.width"
        static let iconHeight = "EntryList.name.icon.height"

        static let textLeading = "EntryList.name.text.leading"
        static let textTrailing = "EntryList.name.text.trailing"
        static let textCenterY = "EntryList.name.text.centerY"
    }

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

    @discardableResult
    func ensureNameCellLayout(_ view: NSTableCellView) -> (iconView: NSImageView, textField: NSTextField) {
        let iconView: NSImageView = view.imageView ?? {
            let imageView = NSImageView()
            imageView.translatesAutoresizingMaskIntoConstraints = false
            imageView.imageScaling = .scaleProportionallyUpOrDown
            view.addSubview(imageView)
            view.imageView = imageView
            return imageView
        }()
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.imageScaling = .scaleProportionallyUpOrDown

        let textField: NSTextField = view.textField ?? {
            let field = NSTextField(labelWithString: "")
            field.translatesAutoresizingMaskIntoConstraints = false
            field.lineBreakMode = .byTruncatingMiddle
            field.usesSingleLineMode = true
            view.addSubview(field)
            view.textField = field
            return field
        }()
        textField.translatesAutoresizingMaskIntoConstraints = false

        let hasLayoutConstraints = view.constraints.contains { $0.identifier == NameCellConstraintId.iconLeading }
        if !hasLayoutConstraints {
            // 기존 텍스트 전용 제약(leading = view.leading 등)을 제거하고 아이콘 + 텍스트 레이아웃으로 재구성합니다.
            for constraint in view.constraints {
                let first = constraint.firstItem as? NSView
                let second = constraint.secondItem as? NSView
                if first === iconView || first === textField || second === iconView || second === textField {
                    view.removeConstraint(constraint)
                }
            }

            let spacing: CGFloat = 6
            let iconLeading = iconView.leadingAnchor.constraint(equalTo: view.leadingAnchor)
            iconLeading.identifier = NameCellConstraintId.iconLeading
            let iconCenterY = iconView.centerYAnchor.constraint(equalTo: view.centerYAnchor)
            iconCenterY.identifier = NameCellConstraintId.iconCenterY
            let iconWidth = iconView.widthAnchor.constraint(equalToConstant: pageState.listIconSize)
            iconWidth.identifier = NameCellConstraintId.iconWidth
            let iconHeight = iconView.heightAnchor.constraint(equalToConstant: pageState.listIconSize)
            iconHeight.identifier = NameCellConstraintId.iconHeight

            let textLeading = textField.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: spacing)
            textLeading.identifier = NameCellConstraintId.textLeading
            let textTrailing = textField.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor)
            textTrailing.identifier = NameCellConstraintId.textTrailing
            let textCenterY = textField.centerYAnchor.constraint(equalTo: view.centerYAnchor)
            textCenterY.identifier = NameCellConstraintId.textCenterY

            NSLayoutConstraint.activate([
                iconLeading,
                iconCenterY,
                iconWidth,
                iconHeight,
                textLeading,
                textTrailing,
                textCenterY,
            ])
        }

        // 아이콘 크기는 설정 변경에 따라 유동적이므로 항상 업데이트합니다.
        if let iconWidth = view.constraints.first(where: { $0.identifier == NameCellConstraintId.iconWidth }) {
            iconWidth.constant = pageState.listIconSize
        }
        if let iconHeight = view.constraints.first(where: { $0.identifier == NameCellConstraintId.iconHeight }) {
            iconHeight.constant = pageState.listIconSize
        }

        return (iconView: iconView, textField: textField)
    }

    func configureGroupHeaderCell(_ view: NSTableCellView, title: String, colorCode: Int?) {
        view.imageView?.image = nil
        view.imageView?.isHidden = true
        let font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        let textField = setText(title, in: view, font: font)

        guard let colorCode else {
            textField.stringValue = title
            return
        }

        let attachment = NSTextAttachment()
        attachment.image = TagDotImageFactory.make(
            tagColor: TagColor(colorCode: colorCode),
            size: 10,
            inset: 1,
        )
        attachment.bounds = NSRect(x: 0, y: -1, width: 10, height: 10)

        let attributed = NSMutableAttributedString(attachment: attachment)
        attributed.append(NSAttributedString(string: " "))
        attributed.append(NSAttributedString(string: title, attributes: [.font: font]))
        textField.attributedStringValue = attributed
    }

    func configureEntryCell(_ view: NSTableCellView, entry: EntryModel, columnId: String) {
        let display = EntryDisplayModel(entry: entry)
        switch EntryListColumn(rawValue: columnId) {
        case .name:
            let (iconView, _) = ensureNameCellLayout(view)
            iconView.isHidden = false
            let isThumbnailReady = pageState.thumbnailsReady.contains(entry.fullPath)
            let thumbnail = isThumbnailReady
                ? entryThumbnailCacheClient.getThumbnail(for: entry.fullPath)
                : nil
            iconView.image = workspaceClient.entryIcon(for: entry, thumbnail: thumbnail)

            let isRenaming = pageState.renamingItemId == entry.id
            let nameText = isRenaming ? pageState.renamingText : entry.name
            let textField = setText(nameText, in: view, font: .systemFont(ofSize: pageState.listTextSize))
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
                display.formattedModifiedDate,
                in: view,
                font: .systemFont(ofSize: max(10, pageState.listTextSize - 1)),
            )

        case .size:
            setText(
                display.formattedSize,
                in: view,
                font: .systemFont(ofSize: max(10, pageState.listTextSize - 1)),
            )

        case .kind:
            let kindText = entry.fileExtension.lowercased() == CollectionConstants
                .fileExtension ? "Voyager Collection" : entry.facets.kind
            setText(
                kindText,
                in: view,
                font: .systemFont(ofSize: max(10, pageState.listTextSize - 1)),
            )

        case .none:
            setText("", in: view)
        }
    }
}

extension EntryListCoordinator {
    func observeListStore() {
        observeListVisibleColumns()
        observeDisplayItems()
        observeGroupKey()
        observeGroupedItems()
        observeCurrentPath()
        observeSelectedIds()
        observeRenamingItemId()
        observeThumbnailsReady()
        observeSortIndicators()
        observeShowHiddenFiles()
        observeShouldScrollToSelection()
        observeDropTargeted()
    }

    func syncListSortIndicators(sortKey: SortKey, sortOrder: SortOrder) {
        guard !isUpdatingSortFromStore else { return }

        let ascending = sortOrder == .ascending
        let descriptorKey = pageState.listVisibleColumns
            .first { $0.sortKey == sortKey }?
            .rawValue

        isUpdatingSortFromStore = true
        if let descriptorKey {
            tableView.sortDescriptors = [NSSortDescriptor(key: descriptorKey, ascending: ascending)]
        } else {
            tableView.sortDescriptors = []
        }
        isUpdatingSortFromStore = false
    }

    func syncListSelectionFromStore() {
        let selectedIds = pageState.selectedIds
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
        let renamingItemId = pageState.renamingItemId
        let previousRenamingItemId = lastRenamingItemId
        lastRenamingItemId = renamingItemId

        guard let nameColumnIndex else { return }
        let nameColumnIndexes = IndexSet(integer: nameColumnIndex)

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
            view?.window?.makeFirstResponder(tableView)
            return
        }

        let row = tableView.row(forItem: item)
        guard row >= 0 else {
            view?.window?.makeFirstResponder(tableView)
            return
        }
        tableView.reloadData(forRowIndexes: IndexSet(integer: row), columnIndexes: nameColumnIndexes)
        beginRenaming(row: row)
    }

    func observeListVisibleColumns() {
        store.publisher.listVisibleColumns
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] columns in
                guard let self else { return }
                view?.applyColumns(columns)
                syncListSortIndicators(
                    sortKey: pageState.sortKey,
                    sortOrder: pageState.sortOrder,
                )
                syncListRenamingFromStore()
                tableView.reloadData()
                requestThumbnailsForVisibleRows()
            }
            .store(in: &cancellables)
    }

    func observeDisplayItems() {
        adapter.pageStatePublisher
            .map(\.entries)
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.rebuildRowsAndReload()
            }
            .store(in: &cancellables)
    }

    func observeGroupKey() {
        adapter.pageStatePublisher
            .map(\.groupKey)
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.rebuildRowsAndReload()
            }
            .store(in: &cancellables)
    }

    func observeGroupedItems() {
        adapter.pageStatePublisher
            .map(\.groupedItems)
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.rebuildRowsAndReload()
            }
            .store(in: &cancellables)
    }

    func observeCurrentPath() {
        adapter.pageStatePublisher
            .map(\.currentPath)
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.hasRestoredScrollPosition = false
            }
            .store(in: &cancellables)
    }

    func observeSelectedIds() {
        store.publisher.selectedIds
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.syncListSelectionFromStore()
            }
            .store(in: &cancellables)
    }

    func observeRenamingItemId() {
        store.publisher.renamingItemId
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.syncListRenamingFromStore()
            }
            .store(in: &cancellables)
    }

    func observeThumbnailsReady() {
        adapter.pageStatePublisher
            .map(\.thumbnailsReady)
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.refreshVisibleNameCellIcons()
            }
            .store(in: &cancellables)
    }

    func observeSortIndicators() {
        Publishers.CombineLatest(
            adapter.pageStatePublisher
                .map(\.sortKey)
                .removeDuplicates(),
            adapter.pageStatePublisher
                .map(\.sortOrder)
                .removeDuplicates(),
        )
        .receive(on: DispatchQueue.main)
        .sink { [weak self] sortKey, sortOrder in
            self?.syncListSortIndicators(sortKey: sortKey, sortOrder: sortOrder)
        }
        .store(in: &cancellables)
    }

    func observeShowHiddenFiles() {
        store.publisher.showHiddenFiles
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.saveScrollPosition()
            }
            .store(in: &cancellables)
    }

    func observeShouldScrollToSelection() {
        store.publisher.shouldScrollToSelection
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] shouldScroll in
                guard shouldScroll else { return }
                self?.scrollToSelectionIfNeeded()
            }
            .store(in: &cancellables)
    }

    func observeDropTargeted() {
        store.publisher.isDropTargeted
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isTargeted in
                self?.updateDropTargetBorder(isTargeted: isTargeted)
            }
            .store(in: &cancellables)
    }
}

private extension EntryListCoordinator {
    func refreshVisibleNameCellIcons() {
        guard tableView.numberOfRows > 0 else { return }
        guard let nameColumnIndex else { return }

        let visibleRange = tableView.rows(in: tableView.visibleRect)
        guard visibleRange.length > 0 else { return }

        for row in visibleRange.location ..< (visibleRange.location + visibleRange.length) {
            guard let cell = tableView
                .view(atColumn: nameColumnIndex, row: row, makeIfNecessary: false) as? NSTableCellView
            else {
                continue
            }
            guard let outlineItem = tableView.item(atRow: row) as? OutlineItem else { continue }

            switch outlineItem.kind {
            case .group:
                cell.imageView?.image = nil
                cell.imageView?.isHidden = true

            case let .entry(entry):
                if cell.imageView == nil || cell.textField == nil {
                    _ = ensureNameCellLayout(cell)
                }

                let isThumbnailReady = pageState.thumbnailsReady.contains(entry.fullPath)
                let thumbnail = isThumbnailReady
                    ? entryThumbnailCacheClient.getThumbnail(for: entry.fullPath)
                    : nil
                cell.imageView?.isHidden = false
                cell.imageView?.image = workspaceClient.entryIcon(for: entry, thumbnail: thumbnail)
            }
        }
    }
}

extension EntryListCoordinator: EntryListView.EntryListTableViewContextMenuProviding {
    func contextMenu(forRow row: Int?, event _: NSEvent) -> NSMenu {
        updateContextMenuAnchor(forRow: row)
        let rowEntry = entryForRow(row)
        let composed = EntryContextMenuBuilder.makeMenu(input: .init(
            adapter: adapter,
            selectedIds: pageState.selectedIds,
            selectedEntries: selectedEntries(fallback: rowEntry),
            rowEntry: rowEntry,
            isTrashFolder: isTrashFolder,
            canPaste: pageState.canPaste,
            currentPath: { [weak self] in
                self?.pageState.currentPath ?? ""
            },
            selectedItemId: { [weak self] in
                self?.pageState.selectedIds.first
            },
            contextMenuAnchor: { [weak self] in
                self?.contextMenuAnchor
            },
            saveScrollPosition: { [weak self] in
                self?.saveScrollPosition()
            },
        ))
        contextMenuCoordinator = composed.coordinator
        return composed.menu
    }
}

private extension EntryListCoordinator {
    func entryForRow(_ row: Int?) -> EntryModel? {
        guard let row, row >= 0 else { return nil }
        guard let item = tableView.item(atRow: row) as? OutlineItem else { return nil }
        guard case let .entry(entry) = item.kind else { return nil }
        return entry
    }

    func selectedEntries(fallback: EntryModel?) -> [EntryModel] {
        let selectedIds = pageState.selectedIds
        if selectedIds.isEmpty {
            return fallback.map { [$0] } ?? []
        }
        return pageState.entries.filter { selectedIds.contains($0.id) }
    }

    var isTrashFolder: Bool {
        guard let trashPath = entryOpenClient.trashDirectoryPath()
        else {
            return false
        }
        let path = pageState.currentPath
        return path == trashPath || path.hasPrefix(trashPath + "/")
    }

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
}

extension EntryListCoordinator: NSTextFieldDelegate {
    func controlTextDidChange(_ notification: Notification) {
        guard pageState.renamingItemId != nil else { return }
        guard let textField = notification.object as? NSTextField else { return }
        guard (textField.delegate as AnyObject?) === self else { return }
        store.send(.updateRenamingText(textField.stringValue))
    }

    func control(_ control: NSControl, textView _: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        guard pageState.renamingItemId != nil else { return false }
        guard let textField = control as? NSTextField else { return false }
        guard (textField.delegate as AnyObject?) === self else { return false }

        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            adapter.actions.commitRename()
            return true
        }
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            store.send(.cancelRename)
            return true
        }
        if commandSelector == #selector(NSResponder.insertTab(_:)) {
            adapter.actions.commitRename()
            return true
        }

        return false
    }

    func controlTextDidEndEditing(_ notification: Notification) {
        guard pageState.renamingItemId != nil else { return }
        guard let textField = notification.object as? NSTextField else { return }
        guard (textField.delegate as AnyObject?) === self else { return }
        adapter.actions.commitRename()
    }
}
