@preconcurrency import AppKit
import ComposableArchitecture
import VoyagerEntitiesEntry
import VoyagerEntitiesTag
import VoyagerShared

struct EntryListCoordinatorSortDescriptorChange: Equatable {
    let sortKey: SortKey
    let sortOrder: VoyagerShared.SortOrder
}

struct EntryListCoordinatorSortSignature: Hashable {
    var key: String?
    var ascending: Bool

    init(descriptors: [NSSortDescriptor]) {
        guard let first = descriptors.first, let key = first.key else {
            key = nil
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
        let sortOrder: VoyagerShared.SortOrder = first.ascending ? .ascending : .descending
        return EntryListCoordinatorSortDescriptorChange(sortKey: sortKey, sortOrder: sortOrder)
    }

    static func actionNeeded(
        currentSortKey: SortKey,
        currentSortOrder: VoyagerShared.SortOrder,
        change: EntryListCoordinatorSortDescriptorChange,
    ) -> EntryListCoordinatorSortDescriptorChange? {
        guard currentSortKey != change.sortKey || currentSortOrder != change.sortOrder else {
            return nil
        }
        return change
    }
}

enum EntryListCoordinatorDateFormatting {
    nonisolated private struct CacheKey: Hashable {
        let template: String
        let localeIdentifier: String
        let timeZoneIdentifier: String
    }

    nonisolated private static let lock = NSLock()
    nonisolated(unsafe) private static var cache: [CacheKey: DateFormatter] = [:]

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
public final class EntryListCoordinator: NSObject {
    typealias RenderSnapshot = EntryListCoordinatorRenderSnapshot
    typealias OutlineItem = EntryListOutlineItem

    let store: StoreOf<EntryViewLayoutFeature>
    var state: EntryViewLayoutState {
        store.state
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
    var outlineItemByID: [String: OutlineItem] = [:]
    var groupItemByName: [String: OutlineItem] = [:]
    let projectionSession = EntryListCoordinatorProjectionSession()
    var lastAppliedVisibleRows: [EntryListOutlineProjection.ItemID] = []
    var renderedProjectionRevision: Int? {
        projectionSession.renderedProjectionRevision
    }

    var isApplyingStoreProjection: Bool {
        projectionSession.isApplyingStoreProjection
    }

    var pendingProjection: EntryListOutlineProjection? {
        projectionSession.pendingProjection
    }

    var sortSyncGate = EntryListCoordinatorSortSyncGate()
    var isApplyingColumnsFromStore = false
    var isUpdatingSelectionFromStore = false
    var hasRestoredScrollPosition = false
    var isUpdatingGroupExpansion = false
    var isApplyingHierarchyExpansion = false
    var lastRenamingItemId: EntryModel.ID?
    var contextMenuAnchor: CGPoint?
    var contextMenuCoordinator: EntryContextMenuCoordinator?
    var boundsDidChangeObserver: NSObjectProtocol?
    var lastRenderSnapshot: RenderSnapshot?
    var isRenderObservationEnabled = true
    let renderThrottler = MainThreadThrottler(intervalMs: 16, latest: true)
    let visibleRowsPrefetchThrottler = MainThreadThrottler(intervalMs: 150, latest: true)
    let dateModifiedResizeDebouncer = MainThreadDebouncer(intervalMs: 150)
    var thumbnailImagesByPath: [String: NSImage] = [:]
    @Dependency(\.workspaceClient)
    var workspaceClient
    @Dependency(\.entryThumbnailCacheClient)
    var entryThumbnailCacheClient
    @Dependency(\.finderFavoritesTagClient)
    var finderFavoritesTagClient
    @Dependency(\.notificationCenterClient)
    var notificationCenterClient
    init(store: StoreOf<EntryViewLayoutFeature>) {
        self.store = store
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
        lastRenderSnapshot = RenderSnapshot(state: state)
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
        let snapshot = RenderSnapshot(state: state)
        if snapshot.isHierarchyOutlineEnabled {
            applyStoreProjection(snapshot.outlineProjection)
            return
        }

        projectionSession.reset()
        outlineItems = makeOutlineItems(state: state)
        rebuildItemIndexes()
        lastAppliedVisibleRows = []
        CATransaction.begin()
        CATransaction.setAnimationDuration(0)
        tableView.reloadData()
        syncListSelectionFromStore()
        applyGroupExpansionState()
        scrollToSelectionIfNeeded()
        restoreScrollPositionIfNeeded()
        syncListRenamingFromStore()
        CATransaction.commit()
        requestThumbnailsForVisibleRows()
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
        store.send(.view(.saveScrollOffset(offset, forPath: state.currentPath)))
    }

    func scrollToSelectionIfNeeded() {
        guard state.shouldScrollToSelection else { return }
        let targetId = state.lastSelectedId
            ?? state.selectedIds.first
        guard let targetId, let item = entryItemById[targetId] else {
            store.send(.view(.resetScrollFlag))
            return
        }
        let row = tableView.row(forItem: item)
        guard row >= 0 else {
            store.send(.view(.resetScrollFlag))
            return
        }
        tableView.scrollRowToVisible(row)
        store.send(.view(.resetScrollFlag))
    }

    func updateDropTargetBorder(isTargeted: Bool) {
        scrollView.layer?.borderWidth = isTargeted ? 2 : 0
        scrollView.layer?.borderColor = isTargeted ? NSColor.controlAccentColor.cgColor : nil
    }

    func makeOutlineItems(state: EntryViewLayoutState) -> [OutlineItem] {
        state.presentation.sections.flatMap { section -> [OutlineItem] in
            let entries = section.items.map { OutlineItem(kind: .entry($0)) }
            guard let title = section.title else { return entries }
            return [
                OutlineItem(
                    kind: .group(
                        name: title,
                        colorCode: section.colorCode,
                        isCollapsed: section.isCollapsed,
                    ),
                    children: entries,
                ),
            ]
        }
    }

    func applyStoreProjection(_ projection: EntryListOutlineProjection) {
        let oldVisibleRows = lastAppliedVisibleRows

        projectionSession.apply(projection) { [weak self] projection, items in
            guard let self else { return }

            let newVisibleRows = projection.visibleRows

            if tryIncrementalRowUpdate(old: oldVisibleRows, new: newVisibleRows, items: items) {
                lastAppliedVisibleRows = newVisibleRows
                return
            }

            outlineItems = items
            rebuildItemIndexes()
            CATransaction.begin()
            CATransaction.setAnimationDuration(0)
            tableView.reloadData()
            applyFolderExpansionState(for: projection)
            syncListSelectionFromStore()
            scrollToSelectionIfNeeded()
            restoreScrollPositionIfNeeded()
            syncListRenamingFromStore()
            CATransaction.commit()
            requestThumbnailsForVisibleRows()
            lastAppliedVisibleRows = newVisibleRows
        }
    }

    private func tryIncrementalRowUpdate(
        old: [EntryListOutlineProjection.ItemID],
        new: [EntryListOutlineProjection.ItemID],
        items: [OutlineItem],
    ) -> Bool {
        guard !old.isEmpty, !new.isEmpty else { return false }

        let oldSet = Set(old)
        let newSet = Set(new)
        let removed = oldSet.subtracting(newSet)
        let added = newSet.subtracting(oldSet)

        guard added.isEmpty, !removed.isEmpty, removed.count <= 20 else { return false }

        var oldIdx = 0
        for newItem in new {
            while oldIdx < old.count, removed.contains(old[oldIdx]) {
                oldIdx += 1
            }
            guard oldIdx < old.count, old[oldIdx] == newItem else { return false }
            oldIdx += 1
        }

        guard let removedRootChildIndices = rootRemovalIndexes(for: removed) else { return false }

        let incomingItemsByID = Dictionary(uniqueKeysWithValues: items.flatMap { $0.flattenItems() })
        for item in outlineItems.flatMap({ $0.flattenItems().map(\.1) }) {
            guard let incoming = incomingItemsByID[item.id] else { continue }
            item.kind = incoming.kind
            item.isLoadingChildren = incoming.isLoadingChildren
        }
        for index in removedRootChildIndices.reversed() {
            outlineItems.remove(at: index)
        }
        rebuildItemIndexes()

        tableView.beginUpdates()
        tableView.removeItems(at: removedRootChildIndices, inParent: nil, withAnimation: .slideLeft)
        tableView.endUpdates()

        syncListSelectionFromStore()
        requestThumbnailsForVisibleRows()

        return true
    }

    private func rootRemovalIndexes(
        for removed: Set<EntryListOutlineProjection.ItemID>,
    ) -> IndexSet? {
        var indexes = IndexSet()
        for (index, item) in outlineItems.enumerated() {
            guard case let .entry(entry) = item.kind else { return nil }
            if removed.contains(.entry(entry.id)) {
                indexes.insert(index)
            }
        }
        return indexes.count == removed.count ? indexes : nil
    }

    func rebuildItemIndexes() {
        entryItemById = Dictionary(uniqueKeysWithValues: outlineItems.flatMap { $0.flattenEntries() })
        outlineItemByID = Dictionary(uniqueKeysWithValues: outlineItems.flatMap { $0.flattenItems() })
        groupItemByName = Dictionary(uniqueKeysWithValues: outlineItems.compactMap { item in
            if case let .group(name, _, _) = item.kind {
                return (name, item)
            }
            return nil
        })
    }

    func applyFolderExpansionState(for projection: EntryListOutlineProjection) {
        for itemID in projection.rootItemIDs {
            applyFolderExpansionState(itemID: itemID, projection: projection)
        }
    }

    func applyFolderExpansionState(itemID: EntryListOutlineProjection.ItemID, projection: EntryListOutlineProjection) {
        guard case let .entry(entryID) = itemID,
              let item = outlineItemByID["entry:\(entryID)"]
        else {
            return
        }
        if projection.childrenByParent[itemID] != nil {
            tableView.expandItem(item)
        } else {
            tableView.collapseItem(item)
        }
        for childID in projection.childrenByParent[itemID, default: []] {
            applyFolderExpansionState(itemID: childID, projection: projection)
        }
    }

    var isHierarchyOutlineEnabled: Bool {
        RenderSnapshot(state: state).isHierarchyOutlineEnabled
    }

    func isCurrentOutlineItem(_ item: OutlineItem) -> Bool {
        outlineItemByID[item.id] === item
    }

    func applyGroupExpansionState() {
        isUpdatingGroupExpansion = true
        for (name, item) in groupItemByName {
            if state.collapsedGroups.contains(name) {
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
