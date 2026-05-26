@preconcurrency import AppKit
import Combine
import ComposableArchitecture
import VoyagerEntitiesEntry
import VoyagerEntitiesTag
import VoyagerFeaturesEntryArrangements
import VoyagerFeaturesEntryOperations
import VoyagerShared

public final class EntryGridCoordinator: NSObject, @unchecked Sendable {
    typealias Section = EntryGridSection
    typealias RenderSnapshot = EntryGridRenderSnapshot
    let store: StoreOf<EntryViewLayoutFeature>
    var state: EntryViewLayoutState { store.state }

    func sendEntryOperations(_ action: EntryOperationsFeature.Action) {
        store.send(.entryOperations(action))
    }

    func sendEntryArrangements(_ action: EntryArrangementsFeature.Action) {
        store.send(.entryArrangements(action))
    }

    weak var view: EntryGridView?
    var didBind = false
    var scrollView: NSScrollView {
        guard let view else { preconditionFailure("EntryGridView is not bound") }
        return view.scrollView
    }

    var collectionView: EntryGridView.EntryGridCollectionView {
        guard let view else { preconditionFailure("EntryGridView is not bound") }
        return view.collectionView
    }

    var flowLayout: NSCollectionViewFlowLayout {
        guard let view else { preconditionFailure("EntryGridView is not bound") }
        return view.flowLayout
    }

    var sections: [Section] = []
    var indexPathByEntryId: [EntryModel.ID: IndexPath] = [:]
    var isUpdatingSelectionFromStore = false
    var isLassoSelecting = false
    var lastRenamingItemId: EntryModel.ID?
    var hasRestoredScrollPosition = false
    var dropTargetEntryId: EntryModel.ID?
    var validatedDropDestinationPath: String?
    var contextMenuAnchor: CGPoint?
    var lastLassoSelectedIds: Set<EntryModel.ID> = []
    var contextMenuCoordinator: EntryContextMenuCoordinator?
    var lassoAutoscrollController: EntryGridLassoAutoscrollController?
    var boundsDidChangeObserver: NSObjectProtocol?
    var lastRenderSnapshot: RenderSnapshot?
    var renderObservationCancellable: AnyCancellable?
    let thumbnailPrefetchThrottler = MainThreadThrottler(intervalMs: 150, latest: true)
    var thumbnailImagesByPath: [String: NSImage] = [:]
    @Dependency(\.entryOpenClient)
    var entryOpenClient
    @Dependency(\.entryLoadingClient)
    var entryLoadingClient
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
    let horizontalPadding: CGFloat = 12
    let minSpacing: CGFloat = 2
    let verticalSpacing: CGFloat = 8
    init(store: StoreOf<EntryViewLayoutFeature>) {
        self.store = store
        super.init()
    }

    func bind(to view: EntryGridView) {
        self.view = view
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.contextMenuProvider = self
        collectionView.onLassoActiveChanged = { [weak self] isActive in
            self?.setLassoActive(isActive)
        }
        collectionView.onLassoSelectionIndexPathsChanged = { [weak self] indexPaths, isFinal in
            self?.handleLassoSelection(indexPaths: indexPaths, isFinal: isFinal)
        }
        view.onLayout = { [weak self] width in
            guard let self else { return }
            updateLayout(for: width)
            updateGridColumnCountIfNeeded(for: width)
        }
        ensureDoubleClickGesture()
        guard !didBind else {
            updateDropTargetBorder(isTargeted: state.isDropTargeted)
            return
        }
        didBind = true
        observeStore()
        rebuildSectionsAndReload()
        updateDropTargetBorder(isTargeted: state.isDropTargeted)
    }

    func updateView(_ view: EntryGridView) {
        guard self.view !== view else { return }
        self.view = view
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.contextMenuProvider = self
        collectionView.onLassoActiveChanged = { [weak self] isActive in
            self?.setLassoActive(isActive)
        }
        collectionView.onLassoSelectionIndexPathsChanged = { [weak self] indexPaths, isFinal in
            self?.handleLassoSelection(indexPaths: indexPaths, isFinal: isFinal)
        }
        view.onLayout = { [weak self] width in
            guard let self else { return }
            updateLayout(for: width)
            updateGridColumnCountIfNeeded(for: width)
        }
        ensureDoubleClickGesture()
    }

    func ensureDoubleClickGesture() {
        let hasDoubleClickGesture = collectionView.gestureRecognizers.contains { recognizer in
            guard let click = recognizer as? NSClickGestureRecognizer else { return false }
            let isSameTarget = (click.target as AnyObject?) === self
            return click.numberOfClicksRequired == 2
                && isSameTarget
                && click.action == #selector(handleDoubleClick(_:))
        }
        guard !hasDoubleClickGesture else { return }
        let doubleClick = NSClickGestureRecognizer(target: self, action: #selector(handleDoubleClick(_:)))
        doubleClick.numberOfClicksRequired = 2
        collectionView.addGestureRecognizer(doubleClick)
    }

    func rebuildSectionsAndReload() {
        sections = makeSections(state: state)
        indexPathByEntryId = [:]
        let hadDropTarget = dropTargetEntryId != nil || validatedDropDestinationPath != nil || state.isDropTargeted
        clearDropTargetState()
        if hadDropTarget {
            updateDropTargetBorder(isTargeted: false)
            if state.isDropTargeted {
                store.send(.view(.setDropTargeted(false)))
            }
        }
        for (sectionIndex, section) in sections.enumerated() {
            for (itemIndex, entry) in section.items.enumerated() {
                indexPathByEntryId[entry.id] = IndexPath(item: itemIndex, section: sectionIndex)
            }
        }
        collectionView.reloadData()
        syncSelectionFromStore()
        scrollToSelectionIfNeeded()
        restoreScrollPositionIfNeeded()
        if let width = view?.bounds.width { updateGridColumnCountIfNeeded(for: width) }
        DispatchQueue.main.async { [weak self] in
            self?.syncRenamingFromStore()
            self?.requestThumbnailsForVisibleArea()
        }
    }

    func makeSections(state: EntryViewLayoutState) -> [Section] {
        if state.entryArrangements.groupKey == .none {
            return [
                Section(
                    title: nil,
                    colorCode: nil,
                    count: state.entries.count,
                    items: Array(state.entries),
                    isCollapsed: false,
                ),
            ]
        }
        return state.entryArrangements.groupedItems.map { group in
            let showHeader = !group.groupName.isEmpty && state.entryArrangements.groupKey != .name
            let isCollapsed = state.entryArrangements.collapsedGroups.contains(group.groupName)
            return Section(
                title: showHeader ? group.groupName : nil,
                colorCode: group.colorCode,
                count: group.count,
                items: isCollapsed ? [] : group.items,
                isCollapsed: isCollapsed,
            )
        }
    }

    func updateLayout(for width: CGFloat) {
        flowLayout.minimumInteritemSpacing = minSpacing
        flowLayout.minimumLineSpacing = verticalSpacing
        flowLayout.sectionInset = NSEdgeInsets(
            top: 8,
            left: horizontalPadding,
            bottom: horizontalPadding,
            right: horizontalPadding,
        )
        flowLayout.headerReferenceSize = NSSize(width: width, height: 36)
        let itemSize = makeItemSize()
        flowLayout.itemSize = itemSize
    }

    func makeItemSize() -> NSSize {
        let iconSize = state.gridIconSize
        let textSize = state.gridTextSize
        let itemWidth = max(120, max(iconSize + 16, 112))
        let textHeight = max(50, textSize * 3 + 18)
        let totalHeight = iconSize + textHeight + 32
        return NSSize(width: itemWidth, height: totalHeight)
    }

    func updateGridColumnCountIfNeeded(for width: CGFloat) {
        let availableWidth = max(1, width - (horizontalPadding * 2))
        let itemWidth = makeItemSize().width
        let columns = max(1, Int((availableWidth + minSpacing) / (itemWidth + minSpacing)))
        if state.gridColumnCount != columns {
            store.send(.internal(.updateGridColumnCount(columns)))
        }
    }

    func syncSelectionFromStore() {
        let selectedIds = state.selectedIds
        let indexPaths = Set(selectedIds.compactMap { indexPathByEntryId[$0] })
        isUpdatingSelectionFromStore = true
        applySelection(indexPaths)
        isUpdatingSelectionFromStore = false
    }

    func syncRenamingFromStore() {
        let renamingItemId = state.entryOperations.renamingItemId
        let previousRenamingItemId = lastRenamingItemId
        lastRenamingItemId = renamingItemId
        if let previousRenamingItemId, let previousIndexPath = indexPathByEntryId[previousRenamingItemId] {
            collectionView.reloadItems(at: [previousIndexPath])
        }
        guard let renamingItemId, let indexPath = indexPathByEntryId[renamingItemId] else {
            view?.window?.makeFirstResponder(collectionView)
            return
        }
        isUpdatingSelectionFromStore = true
        applySelection([indexPath])
        isUpdatingSelectionFromStore = false
        collectionView.reloadItems(at: [indexPath])
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if let item = collectionView.item(at: indexPath) as? EntryGridCollectionViewItem {
                item.beginRenaming()
            }
        }
    }
}

extension EntryGridCoordinator {
    func saveScrollPosition() {
        let offset = scrollView.contentView.bounds.origin
        store.send(.delegate(.saveScrollOffset(offset, forPath: state.currentPath)))
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

    func scrollToSelectionIfNeeded() {
        guard state.shouldScrollToSelection else { return }
        let targetId = state.lastSelectedId ?? state.selectedIds.first
        guard let targetId, let indexPath = indexPathByEntryId[targetId] else {
            store.send(.internal(.resetScrollFlag))
            return
        }
        collectionView.scrollToItems(at: [indexPath], scrollPosition: .centeredVertically)
        store.send(.internal(.resetScrollFlag))
    }

    func reloadVisibleItems() {
        let visibleIndexPaths: Set<IndexPath> = MainActor.assumeIsolated {
            collectionView.indexPathsForVisibleItems()
        }
        collectionView.reloadItems(at: visibleIndexPaths)
    }

    func updateDropTargetBorder(isTargeted _: Bool) {
        // No-op: item-level icon-zone border (Task 2/3) is now the primary and sufficient
        // drop target signal. A scroll-view-level border created double-emphasis that was
        // Finder-unusual and competed with per-item targeting visual.
    }

    func setDropTargetEntryId(_ entryId: EntryModel.ID?) {
        guard dropTargetEntryId != entryId else { return }
        let previousId = dropTargetEntryId
        dropTargetEntryId = entryId
        var indexPathsToReload: Set<IndexPath> = []
        if let previousId, let previousIndexPath = indexPathByEntryId[previousId] {
            indexPathsToReload.insert(previousIndexPath)
        }
        if let entryId, let newIndexPath = indexPathByEntryId[entryId] {
            indexPathsToReload.insert(newIndexPath)
        }
        if !indexPathsToReload.isEmpty {
            collectionView.reloadItems(at: indexPathsToReload)
        }
    }

    func clearDropTargetState() {
        setDropTargetEntryId(nil)
        validatedDropDestinationPath = nil
    }

    func indexPathForVisibleItem(containing point: NSPoint) -> IndexPath? {
        let visibleItems: Set<IndexPath> = MainActor.assumeIsolated {
            collectionView.indexPathsForVisibleItems()
        }
        for indexPath in visibleItems {
            guard let item = collectionView.item(at: indexPath) else { continue }
            if item.view.frame.contains(point) {
                return indexPath
            }
        }
        return nil
    }

    /// Stabilizes the drop target across subview boundaries within the same entry tile.
    ///
    /// Once a drag is resolved to an entry, the whole tile acts as the drop target
    /// regardless of which subview (thumbnail, icon background, name) the point lands on.
    /// If the current point is still within the established target's frame, keep it;
    /// otherwise fall through to the fresh point-resolution result.
    func resolvedEntryTargetIndexPath(
        pointResolved: IndexPath?,
        localPoint: NSPoint,
    ) -> IndexPath? {
        guard let currentId = dropTargetEntryId,
              let currentIndexPath = indexPathByEntryId[currentId],
              let item = collectionView.item(at: currentIndexPath),
              item.view.frame.contains(localPoint)
        else {
            return pointResolved
        }
        return currentIndexPath
    }

    func entry(at indexPath: IndexPath?) -> EntryModel? {
        guard let indexPath,
              indexPath.section >= 0,
              indexPath.section < sections.count
        else {
            return nil
        }
        let section = sections[indexPath.section]
        guard indexPath.item >= 0, indexPath.item < section.items.count else { return nil }
        return section.items[indexPath.item]
    }

    func selectedEntries(rowEntry: EntryModel?) -> [EntryModel] {
        let selectedIds = state.selectedIds
        if selectedIds.isEmpty {
            return rowEntry.map { [$0] } ?? []
        }
        return state.entries.filter { selectedIds.contains($0.id) }
    }

    var isTrashFolder: Bool {
        guard let trashPath = entryOpenClient.trashDirectoryPath()
        else {
            return false
        }
        let path = state.currentPath
        return path == trashPath || path.hasPrefix(trashPath + "/")
    }

    @objc
    func handleDoubleClick(_ recognizer: NSClickGestureRecognizer) {
        let point = recognizer.location(in: collectionView)
        let indexPath: IndexPath? = MainActor.assumeIsolated {
            collectionView.indexPathForItem(at: point)
        }
        guard let indexPath else { return }
        guard let entry = entry(at: indexPath) else { return }
        EntryContextMenuCoordinator.sendWithSelection(
            entry,
            selectedIds: state.selectedIds,
            entryViewLayoutStore: store,
            action: { [weak self] in
                guard let self else { return }
                saveScrollPosition()
                store.send(.delegate(.executeCommand(.navigation(.openSelectedItem))))
            },
        )
    }

    func setLassoActive(_ isActive: Bool) {
        isLassoSelecting = isActive
        if isActive {
            startLassoAutoscroll()
        } else {
            stopLassoAutoscroll()
        }
    }

    func startLassoAutoscroll() {
        guard lassoAutoscrollController == nil else { return }
        let controller = EntryGridLassoAutoscrollController(
            pointerProvider: { [weak self] in
                guard let self,
                      let window = view?.window
                else {
                    return nil
                }
                let windowPoint = window.mouseLocationOutsideOfEventStream
                return collectionView.convert(windowPoint, from: nil)
            },
            geometryProvider: { [weak self] in
                self?.currentLassoAutoscrollGeometry()
            },
            scrollApplier: { [weak self] origin in
                self?.applyLassoAutoscroll(origin: origin)
            },
            selectionUpdater: { [weak self] pointer in
                self?.collectionView.updateLassoSelectionFromAutoscroll(pointer)
            },
        )
        lassoAutoscrollController = controller
        controller.start()
    }

    func stopLassoAutoscroll() {
        lassoAutoscrollController?.stop()
        lassoAutoscrollController = nil
    }

    func currentLassoAutoscrollGeometry() -> EntryGridLassoAutoscrollGeometry {
        EntryGridLassoAutoscrollGeometry(
            visibleRect: collectionView.visibleRect,
            currentOrigin: scrollView.contentView.bounds.origin,
            documentSize: collectionView.bounds.size,
        )
    }

    func applyLassoAutoscroll(origin: CGPoint) {
        scrollView.contentView.scroll(to: origin)
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    func handleLassoSelection(indexPaths: Set<IndexPath>, isFinal: Bool) {
        isUpdatingSelectionFromStore = true
        applySelection(indexPaths)
        isUpdatingSelectionFromStore = false
        let ids: Set<EntryModel.ID> = Set(indexPaths.compactMap { entry(at: $0)?.id })
        let lastSelectedId = indexPaths.max().flatMap { entry(at: $0)?.id }
        if !isFinal {
            guard ids != lastLassoSelectedIds else { return }
            lastLassoSelectedIds = ids
            store.send(.internal(.setSelectionState(
                ids: ids,
                lastSelectedId: lastSelectedId,
                rangeAnchorId: lastSelectedId,
                shouldScrollToSelection: false,
            )))
            return
        }
        lastLassoSelectedIds = []
        let selectedEntries = indexPaths.compactMap { entry(at: $0) }
        preloadOpenWithApplications(selectedEntries: selectedEntries)
        store.send(.internal(.setSelectionState(
            ids: ids,
            lastSelectedId: lastSelectedId,
            rangeAnchorId: lastSelectedId,
            shouldScrollToSelection: false,
        )))
    }

    func applySelection(_ indexPaths: Set<IndexPath>) {
        let current = collectionView.selectionIndexPaths
        let toDeselect = current.subtracting(indexPaths)
        if !toDeselect.isEmpty { collectionView.deselectItems(at: toDeselect) }
        let toSelect = indexPaths.subtracting(current)
        if !toSelect.isEmpty { collectionView.selectItems(at: toSelect, scrollPosition: []) }
    }
}
