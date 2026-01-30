import AppKit
import Combine
import ComposableArchitecture
import SwiftUI

final class EntryListTableViewController: NSViewController {
    enum RowKind: Equatable {
        case groupHeader(title: String, colorCode: Int?)
        case entry(Entry)
    }

    struct Row: Equatable {
        let kind: RowKind

        var id: String {
            switch kind {
            case let .groupHeader(title, _):
                "group:\(title)"
            case let .entry(entry):
                entry.id
            }
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
    private var cancellables: Set<AnyCancellable> = []

    private let scrollView = NSScrollView()
    let tableView = EntryListTableView()

    private(set) var rows: [Row] = []
    private(set) var rowIndexByEntryId: [String: Int] = [:]

    private var columnWidthCache: [Column: CGFloat] = [:]
    private var isUpdatingColumnsFromStore = false
    private(set) var isUpdatingSortFromStore = false

    private var lastInteractedRow: Int?
    private(set) var isUpdatingSelectionFromStore = false
    private var hasRestoredScrollPosition = false

    private var lastRenamingItemId: String?

    private(set) var contextMenuAnchor: CGPoint?

    @Dependency(\.entryClient)
    var entryClient

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

        store.publisher.entries.renamingItemId
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.syncRenamingFromStore()
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

    private func syncRenamingFromStore() {
        let renamingItemId = store.state.entries.renamingItemId
        let previousRenamingItemId = lastRenamingItemId
        lastRenamingItemId = renamingItemId

        let nameColumnIndexes = IndexSet(integer: 0)

        if let previousRenamingItemId,
           let row = rowIndexByEntryId[previousRenamingItemId]
        {
            tableView.reloadData(forRowIndexes: IndexSet(integer: row), columnIndexes: nameColumnIndexes)
        }

        guard let renamingItemId,
              let row = rowIndexByEntryId[renamingItemId]
        else {
            view.window?.makeFirstResponder(tableView)
            return
        }

        tableView.reloadData(forRowIndexes: IndexSet(integer: row), columnIndexes: nameColumnIndexes)
        beginRenaming(row: row)
    }

    private func beginRenaming(row: Int) {
        guard row >= 0, row < rows.count else { return }

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
}
