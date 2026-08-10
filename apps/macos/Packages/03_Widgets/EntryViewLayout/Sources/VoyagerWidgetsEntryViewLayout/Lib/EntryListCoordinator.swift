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
    enum PostReloadUpdateKind {
        case fullReload
        case incremental(preservesScrollAnchor: Bool)
    }

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
    var entryItemsByID: [EntryModel.ID: [OutlineItem]] = [:]
    var outlineItemByID: [String: OutlineItem] = [:]
    var entryItemById: [EntryModel.ID: OutlineItem] = [:]
    var groupItemByName: [String: OutlineItem] = [:]
    let projectionSession = EntryListCoordinatorProjectionSession()
    var lastAppliedVisibleRows: [EntryListOutlineProjection.ItemID] = []
    var lastProjectionHasHierarchyTopology = false
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
    var isUpdatingGroupExpansion = false
    var isApplyingHierarchyExpansion = false
    var lastRenamingItemId: EntryModel.ID?
    var contextMenuAnchor: CGPoint?
    var contextMenuCoordinator: EntryContextMenuCoordinator?
    var boundsDidChangeObserver: NSObjectProtocol?
    var lastRenderSnapshot: RenderSnapshot?
    var restoredScrollForCurrentPath = false
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
        CATransaction.begin()
        CATransaction.setAnimationDuration(0)
        rebuildRowsAndReload()
        restoreScrollPositionIfNeeded()
        if !restoredScrollForCurrentPath {
            scrollToSelectionIfNeeded()
        }
        CATransaction.commit()
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
        let previousPath = lastRenderSnapshot?.currentPath ?? snapshot.currentPath
        let pathChanged = previousPath != snapshot.currentPath
        if snapshot.isHierarchyOutlineEnabled {
            applyStoreProjection(snapshot.outlineProjection, pathChanged: pathChanged)
            return
        }

        let flatItems = makeOutlineItems(state: state)
        let presentationStructureChanged = flatItems.count != outlineItems.count
            || zip(flatItems, outlineItems).contains { incoming, current in
                guard incoming.id == current.id else { return true }
                switch (incoming.kind, current.kind) {
                case let (.group(incomingName, incomingColor, incomingCollapsed),
                          .group(currentName, currentColor, currentCollapsed)):
                    return incomingName != currentName
                        || incomingColor != currentColor
                        || incomingCollapsed != currentCollapsed
                        || incoming.children.map(\.id) != current.children.map(\.id)
                default:
                    return false
                }
            }
        if presentationStructureChanged,
           snapshot.outlineProjection.revision == projectionSession.renderedProjectionRevision
        {
            projectionSession.reset()
            applyPostReloadPresentation(
                pathChanged: pathChanged,
                structureChanged: true,
                updateKind: .fullReload,
                selectionChanged: false,
            ) {
                outlineItems = flatItems
                rebuildItemIndexes()
                lastAppliedVisibleRows = []
                tableView.reloadData()
                applyGroupExpansionState()
            }
        } else {
            projectionSession.apply(snapshot.outlineProjection, flatItems: flatItems) { [weak self] _, items in
                guard let self else { return }
                applyPostReloadPresentation(
                    pathChanged: pathChanged,
                    structureChanged: true,
                    updateKind: .fullReload,
                    selectionChanged: false,
                ) {
                    outlineItems = items
                    rebuildItemIndexes()
                    lastAppliedVisibleRows = []
                    tableView.reloadData()
                    applyGroupExpansionState()
                }
            }
        }
    }

    func applyPostReloadPresentation(
        pathChanged: Bool,
        structureChanged: Bool,
        updateKind: PostReloadUpdateKind,
        selectionChanged: Bool,
        materialize: () -> Void,
    ) {
        if pathChanged {
            restoredScrollForCurrentPath = false
        }
        let shouldRestoreSavedOffset = pathChanged || !restoredScrollForCurrentPath
        let capturedAnchor = pathChanged ? nil : captureScrollAnchor()
        materialize()

        if structureChanged || selectionChanged {
            syncListSelectionFromStore()
        }
        let scrolledToSelection = scrollToSelectionIfNeeded()
        if scrolledToSelection {
            restoredScrollForCurrentPath = true
        }
        if !scrolledToSelection {
            let restoredSavedOffset = shouldRestoreSavedOffset ? restoreScrollPositionIfNeeded() : false
            if !restoredSavedOffset {
                let preservesScrollAnchor: Bool = switch updateKind {
                case .fullReload:
                    false
                case let .incremental(preservesScrollAnchor):
                    preservesScrollAnchor
                }
                if !preservesScrollAnchor {
                    restoreScrollAnchor(capturedAnchor)
                }
            }
        }
        if structureChanged {
            syncListRenamingFromStore()
        }
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

    @discardableResult
    func scrollToSelectionIfNeeded() -> Bool {
        guard state.shouldScrollToSelection else { return false }
        let targetId = state.lastSelectedId
            ?? state.selectedIds.first
        guard let targetId else {
            store.send(.view(.resetScrollFlag))
            return false
        }
        guard let row = entryItemsByID[targetId]?
            .lazy
            .map({ self.tableView.row(forItem: $0) })
            .first(where: { $0 >= 0 })
        else {
            return false
        }
        tableView.scrollRowToVisible(row)
        store.send(.view(.resetScrollFlag))
        return true
    }

    func updateDropTargetBorder(isTargeted: Bool) {
        scrollView.layer?.borderWidth = isTargeted ? 2 : 0
        scrollView.layer?.borderColor = isTargeted ? NSColor.controlAccentColor.cgColor : nil
    }

    func makeOutlineItems(state: EntryViewLayoutState) -> [OutlineItem] {
        makeOutlineItems(presentation: state.presentation)
    }

    func makeOutlineItems(presentation: EntryViewLayoutPresentation) -> [OutlineItem] {
        presentation.sections.flatMap { section -> [OutlineItem] in
            let entries = section.items.map { OutlineItem(kind: .entry($0), identityScope: section.id) }
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

    func applyStoreProjection(_ projection: EntryListOutlineProjection, pathChanged: Bool = false) {
        let oldVisibleRows = lastAppliedVisibleRows

        projectionSession.apply(projection) { [weak self] projection, items in
            guard let self else { return }

            applyPostReloadPresentation(
                pathChanged: pathChanged,
                structureChanged: true,
                updateKind: .fullReload,
                selectionChanged: false,
            ) {
                let newVisibleRows = projection.visibleRows
                let hasHierarchyTopology = !projection.childrenByParent.isEmpty
                let shouldForceFullReload = lastProjectionHasHierarchyTopology || hasHierarchyTopology
                if shouldForceFullReload || !tryIncrementalRowUpdate(
                    old: oldVisibleRows,
                    new: newVisibleRows,
                    items: items,
                    projection: projection,
                ) {
                    outlineItems = items
                    rebuildItemIndexes()
                    tableView.reloadData()
                    applyFolderExpansionState(for: projection)
                }
                lastAppliedVisibleRows = newVisibleRows
                lastProjectionHasHierarchyTopology = hasHierarchyTopology
            }
        }
    }

    private func tryIncrementalRowUpdate(
        old: [EntryListOutlineProjection.ItemID],
        new: [EntryListOutlineProjection.ItemID],
        items: [OutlineItem],
        projection: EntryListOutlineProjection,
    ) -> Bool {
        guard let plan = makeIncrementalRowUpdatePlan(old: old, new: new, items: items, projection: projection)
        else { return false }

        outlineItems = plan.items
        rebuildItemIndexes()

        tableView.beginUpdates()
        if !plan.removedIndexes.isEmpty {
            tableView.removeItems(at: plan.removedIndexes, inParent: nil, withAnimation: .slideLeft)
        }
        if !plan.insertedIndexes.isEmpty {
            tableView.insertItems(at: plan.insertedIndexes, inParent: nil, withAnimation: .slideDown)
        }
        for operation in plan.moves {
            tableView.moveItem(at: operation.from, inParent: nil, to: operation.to, inParent: nil)
        }
        tableView.endUpdates()
        if !plan.updatedRowIndexes.isEmpty {
            let columnIndexes = IndexSet(integersIn: 0 ..< tableView.numberOfColumns)
            tableView.reloadData(forRowIndexes: plan.updatedRowIndexes, columnIndexes: columnIndexes)
        }
        return true
    }

    private struct IncrementalRowUpdatePlan {
        let items: [OutlineItem]
        let removedIndexes: IndexSet
        let insertedIndexes: IndexSet
        let moves: [(from: Int, to: Int)]
        let updatedRowIndexes: IndexSet
    }

    private func makeIncrementalRowUpdatePlan(
        old: [EntryListOutlineProjection.ItemID],
        new: [EntryListOutlineProjection.ItemID],
        items: [OutlineItem],
        projection: EntryListOutlineProjection,
    ) -> IncrementalRowUpdatePlan? {
        guard !old.isEmpty, !new.isEmpty,
              old.allSatisfy({ if case .entry = $0 { true } else { false } }),
              new.allSatisfy({ if case .entry = $0 { true } else { false } }),
              projection.childrenByParent.isEmpty
        else { return nil }

        let oldSet = Set(old)
        let newSet = Set(new)
        let changedCount = oldSet.subtracting(newSet).count + newSet.subtracting(oldSet).count
        guard changedCount * 2 <= max(old.count, new.count) else { return nil }
        guard Set(old).count == old.count, Set(new).count == new.count else { return nil }

        let oldItemsByID = Dictionary(uniqueKeysWithValues: outlineItems.compactMap { item -> (
            EntryListOutlineProjection.ItemID,
            OutlineItem
        )? in
            guard case let .entry(entry) = item.kind else { return nil }
            return (.entry(entry.id), item)
        })
        let incomingItemsByID = Dictionary(uniqueKeysWithValues: items.flatMap { $0.flattenItems() }
            .compactMap { _, item -> (
                EntryListOutlineProjection.ItemID,
                OutlineItem
            )? in
                guard case let .entry(entry) = item.kind else { return nil }
                return (.entry(entry.id), item)
            })
        guard oldItemsByID.count == old.count,
              incomingItemsByID.count == new.count
        else { return nil }

        var current = old
        let removed = oldSet.subtracting(newSet)
        let removedIndexes = IndexSet(current.enumerated()
            .compactMap { removed.contains($0.element) ? $0.offset : nil })
        for index in removedIndexes.reversed() {
            current.remove(at: index)
        }
        let inserted = newSet.subtracting(oldSet)
        var insertIndexes = IndexSet()
        for (index, itemID) in new.enumerated() where inserted.contains(itemID) {
            current.insert(itemID, at: index)
            insertIndexes.insert(index)
        }

        var moveOperations: [(from: Int, to: Int)] = []
        for (targetIndex, itemID) in new.enumerated() {
            guard let currentIndex = current.firstIndex(of: itemID) else { return nil }
            if currentIndex != targetIndex {
                current.remove(at: currentIndex)
                current.insert(itemID, at: targetIndex)
                moveOperations.append((currentIndex, targetIndex))
            }
        }
        guard current == new else { return nil }

        let updatedRowIndexes = IndexSet(new.enumerated().compactMap { index, itemID in
            guard let oldItem = oldItemsByID[itemID],
                  let incomingItem = incomingItemsByID[itemID],
                  case let .entry(oldEntry) = oldItem.kind,
                  case let .entry(incomingEntry) = incomingItem.kind
            else { return nil }
            return oldEntry == incomingEntry ? nil : index
        })
        outlineItems = new.compactMap { itemID in
            guard let existing = oldItemsByID[itemID] else { return incomingItemsByID[itemID] }
            if let incoming = incomingItemsByID[itemID] {
                existing.kind = incoming.kind
                existing.isLoadingChildren = incoming.isLoadingChildren
            }
            return existing
        }
        return .init(items: new.compactMap { itemID in
            guard let existing = oldItemsByID[itemID] else { return incomingItemsByID[itemID] }
            if let incoming = incomingItemsByID[itemID] {
                existing.kind = incoming.kind
                existing.isLoadingChildren = incoming.isLoadingChildren
            }
            return existing
        }, removedIndexes: removedIndexes, insertedIndexes: insertIndexes,
        moves: moveOperations, updatedRowIndexes: updatedRowIndexes)
    }

    func rebuildItemIndexes() {
        entryItemsByID = outlineItems.flatMap { $0.flattenEntries() }.reduce(into: [:]) { itemsByID, element in
            itemsByID[element.0, default: []].append(element.1)
        }
        outlineItemByID = Dictionary(uniqueKeysWithValues: outlineItems.flatMap { $0.flattenItems() })
        entryItemById = Dictionary(
            outlineItems.flatMap { $0.flattenEntries() },
            uniquingKeysWith: { first, _ in first },
        )
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

    struct ScrollAnchor {
        let entryId: EntryModel.ID
        let pixelOffset: CGFloat
    }

    func captureScrollAnchor() -> ScrollAnchor? {
        let rows = tableView.rows(in: scrollView.contentView.bounds)
        guard rows.location != NSNotFound,
              rows.length > 0,
              let item = tableView.item(atRow: rows.location) as? OutlineItem,
              case let .entry(entry) = item.kind
        else {
            return nil
        }
        let rowOrigin = tableView.rect(ofRow: rows.location).origin.y
        return ScrollAnchor(
            entryId: entry.id,
            pixelOffset: rowOrigin - scrollView.contentView.bounds.origin.y,
        )
    }

    func restoreScrollAnchor(_ anchor: ScrollAnchor?) {
        guard let anchor else { return }
        guard let row = entryItemsByID[anchor.entryId]?
            .lazy
            .map({ self.tableView.row(forItem: $0) })
            .first(where: { $0 >= 0 })
        else {
            scrollToSelectionIfNeeded()
            return
        }
        let rowOrigin = tableView.rect(ofRow: row).origin.y
        let targetOrigin = CGPoint(
            x: scrollView.contentView.bounds.origin.x,
            y: rowOrigin - anchor.pixelOffset,
        )
        scrollView.contentView.scroll(to: targetOrigin)
    }

    @discardableResult
    func restoreScrollPositionIfNeeded() -> Bool {
        let itemCount = state.entries.count
        guard itemCount != 0 else { return false }
        guard let savedOffset = state.savedScrollOffset else { return false }
        guard !restoredScrollForCurrentPath else { return false }
        restoredScrollForCurrentPath = true
        scrollView.contentView.scroll(to: savedOffset)
        return true
    }
}
