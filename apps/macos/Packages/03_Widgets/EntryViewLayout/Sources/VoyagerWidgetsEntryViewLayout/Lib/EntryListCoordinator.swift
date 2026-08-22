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

    enum PostReloadUpdateKind {
        case fullReload
        case incremental(preservesScrollAnchor: Bool)
    }

    static let maxIncrementalRootMoveOperations = 32

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
    @Dependency(\.entryOpenClient)
    var entryOpenClient
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
        consumeInitialTypeScrollTargetIfNeeded()
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
        applyFlatItemsPresentation(
            makeOutlineItems(state: state),
            pathChanged: pathChanged,
            snapshot: snapshot,
        )
    }

    private func applyFlatItemsPresentation(
        _ flatItems: [OutlineItem],
        pathChanged: Bool,
        snapshot: RenderSnapshot,
    ) {
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
