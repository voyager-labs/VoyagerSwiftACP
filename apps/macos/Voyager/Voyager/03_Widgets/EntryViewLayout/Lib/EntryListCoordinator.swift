import AppKit
import Combine
import ComposableArchitecture
import VoyagerEntitiesEntry
import VoyagerEntitiesTag
import VoyagerFeaturesEntryArrangements
import VoyagerFeaturesEntryOperations
import VoyagerShared

struct EntryListCoordinatorSortDescriptorChange: Equatable {
    let sortKey: SortKey
    let sortOrder: SortOrder
}

struct EntryListCoordinatorSortSignature: Hashable {
    var key: String?
    var ascending: Bool

    init(descriptors: [NSSortDescriptor]) {
        guard let first = descriptors.first, let key = first.key else {
            self.key = nil
            ascending = true
            return
        }
        self.key = key
        ascending = first.ascending
    }
}

struct EntryListCoordinatorSortSyncGate {
    private var suppressCountBySignature: [EntryListCoordinatorSortSignature: Int] = [:]

    mutating func beginApply(_ signature: EntryListCoordinatorSortSignature) {
        suppressCountBySignature[signature, default: 0] += 1
    }

    mutating func consumeIfSuppressed(_ signature: EntryListCoordinatorSortSignature) -> Bool {
        guard let count = suppressCountBySignature[signature], count > 0 else { return false }
        if count == 1 {
            suppressCountBySignature[signature] = nil
        } else {
            suppressCountBySignature[signature] = count - 1
        }
        return true
    }
}

enum EntryListCoordinatorSortDescriptorMapper {
    static func change(from descriptors: [NSSortDescriptor]) -> EntryListCoordinatorSortDescriptorChange? {
        guard let first = descriptors.first else { return nil }
        guard let key = first.key else { return nil }
        guard let column = EntryListColumn(rawValue: key) else { return nil }
        guard let sortKey = column.sortKey else { return nil }
        let sortOrder: SortOrder = first.ascending ? .ascending : .descending
        return EntryListCoordinatorSortDescriptorChange(sortKey: sortKey, sortOrder: sortOrder)
    }

    static func actionsNeeded(
        currentSortKey: SortKey,
        currentSortOrder: SortOrder,
        change: EntryListCoordinatorSortDescriptorChange,
    ) -> (sortKey: SortKey?, sortOrder: SortOrder?) {
        let setKey: SortKey? = currentSortKey == change.sortKey ? nil : change.sortKey
        let setOrder: SortOrder? = currentSortOrder == change.sortOrder ? nil : change.sortOrder
        return (setKey, setOrder)
    }
}

enum EntryListCoordinatorDateFormatting {
    private nonisolated struct CacheKey: Hashable {
        let template: String
        let localeIdentifier: String
        let timeZoneIdentifier: String
    }

    private nonisolated static let lock = NSLock()
    private nonisolated(unsafe) static var cache: [CacheKey: DateFormatter] = [:]

    nonisolated static func template(forWidth width: CGFloat) -> String {
        guard width.isFinite, width > 0 else {
            return "yMd"
        }

        if width < 140 {
            return "yMd"
        } else if width < 220 {
            return "MMMd"
        } else {
            return "yMMMdjm"
        }
    }

    nonisolated static func format(
        _ date: Date,
        width: CGFloat,
        locale: Locale = .current,
        timeZone: TimeZone = .current,
    ) -> String {
        let template = template(forWidth: width)
        let key = CacheKey(
            template: template,
            localeIdentifier: locale.identifier,
            timeZoneIdentifier: timeZone.identifier,
        )

        lock.lock()
        defer { lock.unlock() }

        let formatter = cache[key] ?? {
            let formatter = DateFormatter()
            formatter.locale = locale
            formatter.timeZone = timeZone
            formatter.setLocalizedDateFormatFromTemplate(template)
            cache[key] = formatter
            return formatter
        }()

        return formatter.string(from: date)
    }
}

typealias EntryListSortDescriptorChange = EntryListCoordinatorSortDescriptorChange
typealias EntryListSortSyncGate = EntryListCoordinatorSortSyncGate
typealias EntryListSortDescriptorMapper = EntryListCoordinatorSortDescriptorMapper
typealias EntryListDateFormatting = EntryListCoordinatorDateFormatting

@MainActor
final class EntryListCoordinator: NSObject {
    typealias RenderSnapshot = EntryListCoordinatorRenderSnapshot
    enum EntryListOutlineItemKind {
        case group(name: String, colorCode: Int?, isCollapsed: Bool)
        case entry(EntryModel)
    }

    final class OutlineItem: Hashable {
        let kind: EntryListOutlineItemKind
        let children: [OutlineItem]
        let id: String
        init(kind: EntryListOutlineItemKind, children: [OutlineItem] = []) {
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

    let store: StoreOf<EntryViewLayoutFeature>
    var state: EntryViewLayoutState { store.state }

    func sendEntryOperations(_ action: EntryOperationsFeature.Action) {
        store.send(.entryOperations(action))
    }

    func sendEntryArrangements(_ action: EntryArrangementsFeature.Action) {
        store.send(.entryArrangements(action))
    }

    weak var view: EntryListView?
    var didBind = false
    var scrollView: NSScrollView {
        guard let view else { preconditionFailure("EntryListView is not bound") }
        return view.scrollView
    }

    var tableView: EntryListView.EntryListTableView {
        guard let view else { preconditionFailure("EntryListView is not bound") }
        return view.tableView
    }

    var nameColumnIndex: Int? {
        let index = tableView.column(withIdentifier: NSUserInterfaceItemIdentifier(EntryListColumn.name.rawValue))
        return index >= 0 ? index : nil
    }

    var outlineItems: [OutlineItem] = []
    var entryItemById: [EntryModel.ID: OutlineItem] = [:]
    var groupItemByName: [String: OutlineItem] = [:]
    var sortSyncGate = EntryListCoordinatorSortSyncGate()
    var isApplyingColumnsFromStore = false
    var isUpdatingSelectionFromStore = false
    var hasRestoredScrollPosition = false
    var isUpdatingGroupExpansion = false
    var lastRenamingItemId: EntryModel.ID?
    var contextMenuAnchor: CGPoint?
    var contextMenuCoordinator: EntryContextMenuCoordinator?
    var boundsDidChangeObserver: NSObjectProtocol?
    var lastRenderSnapshot: RenderSnapshot?
    var renderObservationCancellable: AnyCancellable?
    let visibleRowsPrefetchThrottler = MainThreadThrottler(intervalMs: 150, latest: true)
    let dateModifiedResizeDebouncer = MainThreadDebouncer(intervalMs: 150)
    var thumbnailImagesByPath: [String: NSImage] = [:]
    @Dependency(\.entryOpenClient)
    var entryOpenClient
    @Dependency(\.entryFileOpsClient)
    var entryFileOpsClient
    @Dependency(\.workspaceClient)
    var workspaceClient
    @Dependency(\.entryThumbnailCacheClient)
    var entryThumbnailCacheClient
    @Dependency(\.finderFavoritesTagClient)
    var finderFavoritesTagClient
    @Dependency(\.notificationCenterClient)
    var notificationCenterClient
    init(store: StoreOf<EntryViewLayoutFeature>) { self.store = store
        super.init()
    }

    func bind(to view: EntryListView) {
        self.view = view
        tableView.delegate = self
        tableView.dataSource = self
        tableView.contextMenuProvider = self
        tableView.target = self
        tableView.doubleAction = #selector(handleDoubleClick)
        configureHeaderMenu()
        applyColumnsFromStore(state.listVisibleColumns)
        guard !didBind else {
            applyColumnsFromStore(state.listVisibleColumns)
            updateDropTargetBorder(isTargeted: state.isDropTargeted)
            return
        }
        didBind = true
        observeListStore()
        observeTableView()
        rebuildRowsAndReload()
        updateDropTargetBorder(isTargeted: state.isDropTargeted)
    }

    func updateRootView(_ view: EntryListView) {
        guard self.view !== view else { return }
        self.view = view
        tableView.delegate = self
        tableView.dataSource = self
        tableView.contextMenuProvider = self
        tableView.target = self
        tableView.doubleAction = #selector(handleDoubleClick)
        configureHeaderMenu()
        applyColumnsFromStore(state.listVisibleColumns)
    }

    func applyColumnsFromStore(_ visibleColumns: [EntryListColumn]) {
        isApplyingColumnsFromStore = true
        view?.applyColumns(visibleColumns)
        isApplyingColumnsFromStore = false
    }

    func observeTableView() {
        if let boundsDidChangeObserver { notificationCenterClient.removeObserver(boundsDidChangeObserver) }
        boundsDidChangeObserver = notificationCenterClient.addObserver(
            NSView.boundsDidChangeNotification,
            scrollView.contentView,
        ) { [weak self] _ in
            DispatchQueue.main.async { [weak self] in
                self?.visibleRowsPrefetchThrottler.schedule { [weak self] in
                    self?.requestThumbnailsForVisibleRows()
                }
            }
        }
    }

    func reloadVisibleDateModifiedCells() {
        let dateModifiedColumnIndex = tableView.column(
            withIdentifier: NSUserInterfaceItemIdentifier(EntryListColumn.dateModified.rawValue),
        )
        guard dateModifiedColumnIndex >= 0 else { return }
        let visibleRange = tableView.rows(in: tableView.visibleRect)
        guard visibleRange.length > 0 else { return }
        let start = visibleRange.location
        let end = visibleRange.location + visibleRange.length
        let rowIndexes = IndexSet(integersIn: start ..< end)
        let columnIndexes = IndexSet(integer: dateModifiedColumnIndex)
        tableView.reloadData(forRowIndexes: rowIndexes, columnIndexes: columnIndexes)
    }

    func rebuildRowsAndReload() {
        let previousGraph = (outlineItems, entryItemById, groupItemByName)

        outlineItems = makeOutlineItems(state: state)
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
        syncListRenamingFromStore()
        requestThumbnailsForVisibleRows()

        DispatchQueue.main.async {
            _ = previousGraph
        }
    }

    func requestThumbnailsForVisibleRows() {
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
        pruneThumbnailSession(keeping: paths)
        store.send(.entryThumbnail(.requestThumbnails(paths: Array(paths))))
        refreshVisibleNameCellIcons(for: refreshThumbnailProjection(paths: paths))
    }

    func pruneThumbnailSession(keeping paths: Set<String>) {
        thumbnailImagesByPath = thumbnailImagesByPath.filter { paths.contains($0.key) }
    }

    func resetThumbnailSession() {
        thumbnailImagesByPath.removeAll(keepingCapacity: false)
    }

    func refreshThumbnailProjection(paths: Set<String>) -> Set<String> {
        var changedPaths: Set<String> = []

        for path in paths {
            let cachedImage = entryThumbnailCacheClient.getThumbnail(for: path)
            if let cachedImage {
                if thumbnailImagesByPath[path] == nil {
                    changedPaths.insert(path)
                }
                thumbnailImagesByPath[path] = cachedImage
            } else if thumbnailImagesByPath.removeValue(forKey: path) != nil {
                changedPaths.insert(path)
            }
        }

        return changedPaths
    }

    func refreshThumbnailProjectionForVisibleRows() {
        guard tableView.numberOfRows > 0 else { return }
        let visibleRange = tableView.rows(in: tableView.visibleRect)
        guard visibleRange.length > 0 else { return }

        var visiblePaths: Set<String> = []
        for row in visibleRange.location ..< (visibleRange.location + visibleRange.length) {
            guard let outlineItem = tableView.item(atRow: row) as? OutlineItem else { continue }
            guard case let .entry(entry) = outlineItem.kind, !entry.isFolder else { continue }
            visiblePaths.insert(entry.fullPath)
        }

        refreshVisibleNameCellIcons(for: refreshThumbnailProjection(paths: visiblePaths))
    }

    func saveScrollPosition() {
        let offset = scrollView.contentView.bounds.origin
        store.send(.delegate(.saveScrollOffset(offset, forPath: state.currentPath)))
    }

    func scrollToSelectionIfNeeded() {
        guard state.shouldScrollToSelection else { return }
        let targetId = state.lastSelectedId
            ?? state.selectedIds.first
        guard let targetId, let item = entryItemById[targetId] else {
            store.send(.internal(.resetScrollFlag))
            return
        }
        let row = tableView.row(forItem: item)
        guard row >= 0 else {
            store.send(.internal(.resetScrollFlag))
            return
        }
        tableView.scrollRowToVisible(row)
        store.send(.internal(.resetScrollFlag))
    }

    func updateDropTargetBorder(isTargeted: Bool) {
        scrollView.layer?.borderWidth = isTargeted ? 2 : 0
        scrollView.layer?.borderColor = isTargeted ? NSColor.controlAccentColor.cgColor : nil
    }

    func makeOutlineItems(state: EntryViewLayoutState) -> [OutlineItem] {
        if state.entryArrangements.groupKey == .none {
            return state.entries.map { OutlineItem(kind: .entry($0)) }
        }
        var result: [OutlineItem] = []
        for group in state.entryArrangements.groupedItems {
            let items = group.items.map { OutlineItem(kind: .entry($0)) }
            if !group.groupName.isEmpty, state.entryArrangements.groupKey != .name {
                let isCollapsed = state.entryArrangements.collapsedGroups.contains(group.groupName)
                let groupItem = OutlineItem(
                    kind: .group(name: group.groupName, colorCode: group.colorCode, isCollapsed: isCollapsed),
                    children: items,
                )
                result.append(groupItem)
            } else {
                result.append(contentsOf: items)
            }
        }
        return result
    }

    func applyGroupExpansionState() {
        isUpdatingGroupExpansion = true
        for (name, item) in groupItemByName {
            if state.entryArrangements.collapsedGroups.contains(name) {
                tableView.collapseItem(item)
            } else {
                tableView.expandItem(item)
            }
        }
        isUpdatingGroupExpansion = false
    }

    func restoreScrollPositionIfNeeded() {
        let itemCount = state.entries.count
        guard itemCount != 0 else { return }
        guard !hasRestoredScrollPosition,
              let savedOffset = state.savedScrollOffset
        else {
            return
        }
        scrollView.contentView.scroll(to: savedOffset)
        hasRestoredScrollPosition = true
    }
}
