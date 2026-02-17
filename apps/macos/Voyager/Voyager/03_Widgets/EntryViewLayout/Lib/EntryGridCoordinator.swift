// swiftlint:disable file_length
import AppKit
import Combine
import ComposableArchitecture

final class EntryGridCoordinator: NSObject {
    struct Section {
        let title: String?
        let colorCode: Int?
        let count: Int
        let items: [EntryModel]
        let isCollapsed: Bool
    }

    let store: StoreOf<FileManagerContentFeature>
    private var cancellables: Set<AnyCancellable> = []

    private weak var view: EntryGridView?
    private var didBind = false

    private var scrollView: NSScrollView {
        guard let view else { preconditionFailure("EntryGridView is not bound") }
        return view.scrollView
    }

    private var collectionView: EntryGridView.EntryGridCollectionView {
        guard let view else { preconditionFailure("EntryGridView is not bound") }
        return view.collectionView
    }

    private var flowLayout: NSCollectionViewFlowLayout {
        guard let view else { preconditionFailure("EntryGridView is not bound") }
        return view.flowLayout
    }

    private var sections: [Section] = []
    private var indexPathByEntryId: [String: IndexPath] = [:]
    private var isUpdatingSelectionFromStore = false
    private var isLassoSelecting = false
    private var lastRenamingItemId: String?
    private var hasRestoredScrollPosition = false
    private var dropTargetEntryId: String?
    private var contextMenuAnchor: CGPoint?
    private var lastLassoSelectedIds: Set<String> = []
    private var contextMenuCoordinator: EntryContextMenuCoordinator?

    @Dependency(\.entryOpenClient)
    private var entryOpenClient
    @Dependency(\.entryLoadingClient)
    private var entryLoadingClient
    @Dependency(\.entryFileOpsClient)
    private var entryFileOpsClient
    @Dependency(\.workspaceClient)
    private var workspaceClient
    @Dependency(\.entryThumbnailCacheClient)
    private var entryThumbnailCacheClient
    @Dependency(\.fileManagerWindowClient)
    private var fileManagerWindowClient

    private let horizontalPadding: CGFloat = 12
    private let minSpacing: CGFloat = 2
    private let verticalSpacing: CGFloat = 8

    init(store: StoreOf<FileManagerContentFeature>) {
        self.store = store
        super.init()
    }

    func bind(to view: EntryGridView) {
        self.view = view

        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.contextMenuProvider = self
        collectionView.onLassoActiveChanged = { [weak self] isActive in
            self?.isLassoSelecting = isActive
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
            updateDropTargetBorder(isTargeted: store.state.entryViewLayout.isDropTargeted)
            return
        }

        didBind = true
        observeStore()
        rebuildSectionsAndReload()
        updateDropTargetBorder(isTargeted: store.state.entryViewLayout.isDropTargeted)
    }

    func updateView(_ view: EntryGridView) {
        guard view !== view else { return }
        self.view = view
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.contextMenuProvider = self
        collectionView.onLassoActiveChanged = { [weak self] isActive in
            self?.isLassoSelecting = isActive
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

    private func ensureDoubleClickGesture() {
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

    private func rebuildSectionsAndReload() {
        sections = makeSections(state: store.state)
        indexPathByEntryId = [:]
        for (sectionIndex, section) in sections.enumerated() {
            for (itemIndex, entry) in section.items.enumerated() {
                indexPathByEntryId[entry.id] = IndexPath(item: itemIndex, section: sectionIndex)
            }
        }

        collectionView.reloadData()
        syncSelectionFromStore()
        scrollToSelectionIfNeeded()
        restoreScrollPositionIfNeeded()
        if let width = view?.bounds.width {
            updateGridColumnCountIfNeeded(for: width)
        }

        // 레이아웃 반영 이후 visible(+prefetch) 영역 썸네일 요청
        DispatchQueue.main.async { [weak self] in
            self?.requestThumbnailsForVisibleArea()
        }
    }

    private func makeSections(state: FileManagerContentState) -> [Section] {
        if store.state.entryArrangements.groupKey == .none {
            return [
                Section(
                    title: nil,
                    colorCode: nil,
                    count: state.entryOperations.displayItems.count,
                    items: Array(state.entryOperations.displayItems),
                    isCollapsed: false,
                ),
            ]
        }

        return store.state.entryArrangements.groupedItems.map { group in
            let showHeader = !group.groupName.isEmpty && store.state.entryArrangements.groupKey != .name
            let colorCode: Int? = if store.state.entryArrangements.groupKey == .tags {
                resolveTagColorCode(tagName: group.groupName, items: group.items)
            } else {
                nil
            }
            let isCollapsed = store.state.entryArrangements.collapsedGroups.contains(group.groupName)
            return Section(
                title: showHeader ? group.groupName : nil,
                colorCode: colorCode,
                count: group.count,
                items: isCollapsed ? [] : group.items,
                isCollapsed: isCollapsed,
            )
        }
    }

    private func resolveTagColorCode(tagName: String, items: [EntryModel]) -> Int? {
        for item in items {
            if let colorCode = item.tags?.first(where: { $0.name == tagName })?.colorCode {
                return colorCode
            }
        }
        return nil
    }

    private func updateLayout(for width: CGFloat) {
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

    private func makeItemSize() -> NSSize {
        let iconSize = store.state.gridIconSize
        let textSize = store.state.gridTextSize
        let itemWidth = max(120, max(iconSize + 16, 112))
        let textHeight = max(50, textSize * 3 + 18)
        let totalHeight = iconSize + textHeight + 32
        return NSSize(width: itemWidth, height: totalHeight)
    }

    private func updateGridColumnCountIfNeeded(for width: CGFloat) {
        let availableWidth = max(1, width - (horizontalPadding * 2))
        let itemWidth = makeItemSize().width
        let columns = max(1, Int((availableWidth + minSpacing) / (itemWidth + minSpacing)))
        if store.state.entryViewLayout.gridColumnCount != columns {
            store.send(.entryViewLayout(.updateGridColumnCount(columns)))
        }
    }

    private func syncSelectionFromStore() {
        let selectedIds = store.state.entryViewLayout.selectedIds
        let indexPaths = Set(selectedIds.compactMap { indexPathByEntryId[$0] })

        isUpdatingSelectionFromStore = true
        applySelection(indexPaths)
        isUpdatingSelectionFromStore = false
    }

    private func syncRenamingFromStore() {
        let renamingItemId = store.state.entryViewLayout.renamingItemId
        let previousRenamingItemId = lastRenamingItemId
        lastRenamingItemId = renamingItemId

        if let previousRenamingItemId, let previousIndexPath = indexPathByEntryId[previousRenamingItemId] {
            collectionView.reloadItems(at: [previousIndexPath])
        }

        guard let renamingItemId, let indexPath = indexPathByEntryId[renamingItemId] else {
            view?.window?.makeFirstResponder(collectionView)
            return
        }

        collectionView.reloadItems(at: [indexPath])
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if let item = collectionView.item(at: indexPath) as? EntryGridCollectionViewItem {
                item.beginRenaming()
            }
        }
    }

    private func saveScrollPosition() {
        let offset = scrollView.contentView.bounds.origin
        store.send(.saveScrollOffset(offset, forPath: store.state.navigation.currentPath))
    }

    private func restoreScrollPositionIfNeeded() {
        let itemCount = store.state.entryOperations.displayItems.count
        guard itemCount != 0 else { return }

        guard !hasRestoredScrollPosition,
              let savedOffset = store.state.navigation.scrollPositions[store.state.navigation.currentPath]
        else {
            return
        }

        scrollView.contentView.scroll(to: savedOffset)
        hasRestoredScrollPosition = true
    }

    private func scrollToSelectionIfNeeded() {
        guard store.state.entryViewLayout.shouldScrollToSelection else { return }
        let targetId = store.state.entryViewLayout.lastSelectedId ?? store.state.entryViewLayout.selectedIds.first
        guard let targetId, let indexPath = indexPathByEntryId[targetId] else {
            store.send(.entryViewLayout(.resetScrollFlag))
            return
        }
        collectionView.scrollToItems(at: [indexPath], scrollPosition: .centeredVertically)
        store.send(.entryViewLayout(.resetScrollFlag))
    }

    private func reloadVisibleItems() {
        let visibleIndexPaths = collectionView.indexPathsForVisibleItems()
        collectionView.reloadItems(at: visibleIndexPaths)
    }

    private func updateDropTargetBorder(isTargeted: Bool) {
        scrollView.layer?.borderWidth = isTargeted ? 2 : 0
        scrollView.layer?.borderColor = isTargeted ? NSColor.controlAccentColor.cgColor : nil
    }

    private func setDropTargetEntryId(_ entryId: String?) {
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

    private func entry(at indexPath: IndexPath?) -> EntryModel? {
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

    private func selectedEntries(fallback: EntryModel?) -> [EntryModel] {
        let selectedIds = store.state.entryViewLayout.selectedIds
        if selectedIds.isEmpty {
            return fallback.map { [$0] } ?? []
        }
        return store.state.entryOperations.displayItems.filter { selectedIds.contains($0.id) }
    }

    private var isTrashFolder: Bool {
        guard case let .folder(path) = store.state.navigation.navigationState,
              let trashPath = entryOpenClient.trashDirectoryPath()
        else {
            return false
        }
        return path == trashPath || path.hasPrefix(trashPath + "/")
    }

    @objc
    private func handleDoubleClick(_ recognizer: NSClickGestureRecognizer) {
        let point = recognizer.location(in: collectionView)
        guard let indexPath = collectionView.indexPathForItem(at: point) else { return }
        guard let entry = entry(at: indexPath) else { return }
        EntryContextMenuUtils.sendWithSelection(
            entry,
            selectedIds: store.state.entryViewLayout.selectedIds,
            contentStore: store,
            action: { [weak self] in
                guard let self else { return }
                saveScrollPosition()
                store.send(.entryViewLayout(.openSelectedItem))
            },
        )
    }

    private func handleLassoSelection(indexPaths: Set<IndexPath>, isFinal: Bool) {
        // NSCollectionView 러버밴드 선택은 드래그 중 isSelected 업데이트가 즉시 오지 않는 경우가 있어
        // 선택 집합을 직접 적용하여 셀 하이라이트를 실시간으로 반영합니다.
        isUpdatingSelectionFromStore = true
        applySelection(indexPaths)
        isUpdatingSelectionFromStore = false

        let ids: Set<String> = Set(indexPaths.compactMap { entry(at: $0)?.id })
        let lastSelectedId = indexPaths.max().flatMap { entry(at: $0)?.id }

        if !isFinal {
            // 중복 send 방지(드래그 중 이벤트가 많음)
            guard ids != lastLassoSelectedIds else { return }
            lastLassoSelectedIds = ids
            store.send(.entryViewLayout(.setSelectedIdsFromLasso(ids: ids, lastSelectedId: lastSelectedId)))
            return
        }

        lastLassoSelectedIds = []
        store.send(.entryViewLayout(.setSelectedIds(ids: ids, lastSelectedId: lastSelectedId)))
    }

    func applySelection(_ indexPaths: Set<IndexPath>) {
        let current = collectionView.selectionIndexPaths
        let toDeselect = current.subtracting(indexPaths)
        if !toDeselect.isEmpty {
            collectionView.deselectItems(at: toDeselect)
        }
        let toSelect = indexPaths.subtracting(current)
        if !toSelect.isEmpty {
            collectionView.selectItems(at: toSelect, scrollPosition: [])
        }
    }
}

private extension EntryGridCoordinator {
    func observeStore() {
        observeDisplayItems()
        observeGroupKey()
        observeGroupedItems()
        observeCollapsedGroups()
        observeSelectedIds()
        observeRenamingItemId()
        observeThumbnailsReady()
        observeGridIconSize()
        observeGridTextSize()
        observeShowHiddenFiles()
        observeShouldScrollToSelection()
        observeDropTargeted()
        observeCurrentPath()
        observeDisplayItemCountForScrollRestore()
        observeScrollForThumbnailPrefetch()
    }

    func observeScrollForThumbnailPrefetch() {
        NotificationCenter.default.publisher(for: NSView.boundsDidChangeNotification, object: scrollView.contentView)
            .receive(on: DispatchQueue.main)
            .throttle(for: .milliseconds(150), scheduler: DispatchQueue.main, latest: true)
            .sink { [weak self] _ in
                self?.requestThumbnailsForVisibleArea()
            }
            .store(in: &cancellables)
    }

    func requestThumbnailsForVisibleArea() {
        guard let layout = collectionView.collectionViewLayout else { return }

        let visibleRect = collectionView.visibleRect
        guard visibleRect.height > 0 else { return }

        // Finder 스타일: 현재 화면 + 위/아래 1 화면 정도를 프리패치
        let prefetchRect = visibleRect.insetBy(dx: 0, dy: -visibleRect.height)

        let attributes = layout.layoutAttributesForElements(in: prefetchRect)
        let indexPaths: [IndexPath] = attributes.compactMap { attr in
            guard attr.representedElementCategory == .item else { return nil }
            return attr.indexPath
        }
        guard !indexPaths.isEmpty else { return }

        var paths: Set<String> = []
        paths.reserveCapacity(indexPaths.count)
        for indexPath in indexPaths {
            guard let entry = entry(at: indexPath) else { continue }
            guard !entry.isDirectory else { continue }
            paths.insert(entry.fullPath)
        }

        guard !paths.isEmpty else { return }
        store.send(.entries(.requestThumbnails(paths: Array(paths))))
    }

    func observeDisplayItems() {
        store.publisher.entryOperations.displayItems
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.rebuildSectionsAndReload()
            }
            .store(in: &cancellables)
    }

    func observeGroupKey() {
        store.publisher.entryArrangements.groupKey
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.rebuildSectionsAndReload()
            }
            .store(in: &cancellables)
    }

    func observeGroupedItems() {
        store.publisher.entryArrangements.groupedItems
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.rebuildSectionsAndReload()
            }
            .store(in: &cancellables)
    }

    func observeCollapsedGroups() {
        store.publisher.entryArrangements.collapsedGroups
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.rebuildSectionsAndReload()
            }
            .store(in: &cancellables)
    }

    func observeSelectedIds() {
        store.publisher.entryViewLayout.selectedIds
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.syncSelectionFromStore()
            }
            .store(in: &cancellables)
    }

    func observeRenamingItemId() {
        store.publisher.entryViewLayout.renamingItemId
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.syncRenamingFromStore()
            }
            .store(in: &cancellables)
    }

    func observeThumbnailsReady() {
        store.publisher.entryThumbnails.thumbnailsReady
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.reloadVisibleItems()
            }
            .store(in: &cancellables)
    }

    func observeGridIconSize() {
        store.publisher.gridIconSize
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                if let width = view?.bounds.width {
                    updateLayout(for: width)
                }
                reloadVisibleItems()
            }
            .store(in: &cancellables)
    }

    func observeGridTextSize() {
        store.publisher.gridTextSize
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                if let width = view?.bounds.width {
                    updateLayout(for: width)
                }
                reloadVisibleItems()
            }
            .store(in: &cancellables)
    }

    func observeShowHiddenFiles() {
        store.publisher.entryViewLayout.showHiddenFiles
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.saveScrollPosition()
            }
            .store(in: &cancellables)
    }

    func observeShouldScrollToSelection() {
        store.publisher.entryViewLayout.shouldScrollToSelection
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] shouldScroll in
                guard shouldScroll else { return }
                self?.scrollToSelectionIfNeeded()
            }
            .store(in: &cancellables)
    }

    func observeDropTargeted() {
        store.publisher.entryViewLayout.isDropTargeted
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isTargeted in
                self?.updateDropTargetBorder(isTargeted: isTargeted)
            }
            .store(in: &cancellables)
    }

    func observeCurrentPath() {
        store.publisher.navigation.currentPath
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.hasRestoredScrollPosition = false
            }
            .store(in: &cancellables)
    }

    func observeDisplayItemCountForScrollRestore() {
        store.publisher.entryOperations.displayItems
            .map(\.count)
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.restoreScrollPositionIfNeeded()
            }
            .store(in: &cancellables)
    }
}

extension EntryGridCoordinator: NSCollectionViewDataSource {
    func numberOfSections(in _: NSCollectionView) -> Int {
        sections.count
    }

    func collectionView(_: NSCollectionView, numberOfItemsInSection section: Int) -> Int {
        sections[section].items.count
    }

    func collectionView(
        _ collectionView: NSCollectionView,
        itemForRepresentedObjectAt indexPath: IndexPath,
    ) -> NSCollectionViewItem {
        let identifier = NSUserInterfaceItemIdentifier("EntryGridCollectionViewItem")
        guard let item = collectionView.makeItem(withIdentifier: identifier, for: indexPath)
            as? EntryGridCollectionViewItem
        else {
            return NSCollectionViewItem()
        }

        let entry = sections[indexPath.section].items[indexPath.item]
        let isCut = store.state.entryOperations.clipboardItems.contains(entry.fullPath)
            && store.state.entryOperations.clipboardOperation == .cut
        let isRenaming = store.state.entryViewLayout.renamingItemId == entry.id
        let isThumbnailReady = store.state.entryThumbnails.thumbnailsReady.contains(entry.fullPath)
        let thumbnail = isThumbnailReady ? entryThumbnailCacheClient.getThumbnail(for: entry.fullPath) : nil
        let isDropTargeted = dropTargetEntryId == entry.id

        item.configure(.init(
            entry: entry,
            iconSize: store.state.gridIconSize,
            textSize: store.state.gridTextSize,
            thumbnail: thumbnail,
            isCut: isCut,
            isHidden: entry.isHidden,
            isRenaming: isRenaming,
            renamingText: store.state.entryViewLayout.renamingText,
            isDropTargeted: isDropTargeted,
            workspaceClient: workspaceClient,
            onRenameUpdate: { [weak self] text in
                self?.store.send(.entryViewLayout(.updateRenamingText(text)))
            },
            onRenameCommit: { [weak self] in
                self?.store.send(.entryViewLayout(.commitRename))
            },
            onRenameCancel: { [weak self] in
                self?.store.send(.entryViewLayout(.cancelRename))
            },
        ))

        return item
    }

    func collectionView(
        _: NSCollectionView,
        pasteboardWriterForItemAt indexPath: IndexPath,
    ) -> NSPasteboardWriting? {
        guard let entry = entry(at: indexPath) else { return nil }
        return NSURL(fileURLWithPath: entry.fullPath)
    }

    func collectionView(
        _ collectionView: NSCollectionView,
        viewForSupplementaryElementOfKind kind: String,
        at indexPath: IndexPath,
    ) -> NSView {
        guard kind == NSCollectionView.elementKindSectionHeader else {
            return NSView()
        }
        let identifier = NSUserInterfaceItemIdentifier("EntryGridSectionHeaderView")
        guard let header = collectionView.makeSupplementaryView(
            ofKind: kind,
            withIdentifier: identifier,
            for: indexPath,
        ) as? EntryGridSectionHeaderView else {
            return NSView()
        }

        let section = sections[indexPath.section]
        header.configure(
            title: section.title,
            count: section.count,
            colorCode: section.colorCode,
            isCollapsed: section.isCollapsed,
            onToggle: { [weak self] in
                guard let self else { return }
                if let title = section.title {
                    store.send(.entryArrangements(.toggleCollapsedGroup(title)))
                }
            },
        )
        return header
    }
}

extension EntryGridCoordinator: NSCollectionViewDelegate, NSCollectionViewDelegateFlowLayout {
    func collectionView(_ collectionView: NSCollectionView, didSelectItemsAt _: Set<IndexPath>) {
        guard !isLassoSelecting else { return }
        updateSelectionFromCollectionView(collectionView)
    }

    func collectionView(_ collectionView: NSCollectionView, didDeselectItemsAt _: Set<IndexPath>) {
        guard !isLassoSelecting else { return }
        updateSelectionFromCollectionView(collectionView)
    }

    func collectionView(
        _ collectionView: NSCollectionView,
        layout _: NSCollectionViewLayout,
        referenceSizeForHeaderInSection section: Int,
    ) -> NSSize {
        let hasHeader = sections[section].title != nil
        return hasHeader ? NSSize(width: collectionView.bounds.width, height: 32) : .zero
    }

    func collectionView(
        _: NSCollectionView,
        layout _: NSCollectionViewLayout,
        sizeForItemAt _: IndexPath,
    ) -> NSSize {
        flowLayout.itemSize
    }

    func collectionView(
        _: NSCollectionView,
        draggingSession _: NSDraggingSession,
        willBeginAt _: NSPoint,
        forItemsAt indexPaths: Set<IndexPath>,
    ) {
        let paths = indexPaths.compactMap { indexPath -> String? in
            guard let entry = entry(at: indexPath) else { return nil }
            return entry.fullPath
        }
        guard !paths.isEmpty else { return }
        store.send(.entryViewLayout(.startDrag(paths: paths)))
    }

    func collectionView(
        _: NSCollectionView,
        draggingSession _: NSDraggingSession,
        endedAt _: NSPoint,
        dragOperation operation: NSDragOperation,
    ) {
        guard operation.isEmpty else { return }
        store.send(.entryViewLayout(.startDrag(paths: [])))
        store.send(.entryViewLayout(.setDropTargeted(false)))
    }

    @MainActor
    func collectionView(
        _: NSCollectionView,
        validateDrop draggingInfo: any NSDraggingInfo,
        proposedIndexPath proposedDropIndexPath: AutoreleasingUnsafeMutablePointer<NSIndexPath>,
        dropOperation proposedDropOperation: UnsafeMutablePointer<NSCollectionView.DropOperation>,
    ) -> NSDragOperation {
        // proposedIndexPath는 insertion position 기반이라 hover 타겟과 어긋날 수 있습니다.
        // 실제 커서 위치로 hit-test 해서 drop target을 결정합니다.
        let draggingLocation = draggingInfo.draggingLocation
        let localPoint = collectionView.convert(draggingLocation, from: nil)
        let hoverIndexPath = collectionView.indexPathForItem(at: localPoint)

        if let hoverIndexPath {
            proposedDropIndexPath.pointee = hoverIndexPath as NSIndexPath
        }

        let indexPath = hoverIndexPath ?? (proposedDropIndexPath.pointee as IndexPath)
        var destinationPath = store.state.navigation.currentPath
        var targetEntryId: String?

        if let entry = entry(at: indexPath),
           entry.isDirectory,
           !entryLoadingClient.isPackageDirectory(URL(fileURLWithPath: entry.fullPath))
        {
            destinationPath = entry.fullPath
            targetEntryId = entry.id
            proposedDropOperation.pointee = .on
        } else {
            proposedDropOperation.pointee = .before
        }

        let sourcePaths = entryFileOpsClient.loadDragPaths()
        let isInternalDrag = !sourcePaths.isEmpty
        let wantsCopy = isInternalDrag
            ? entryFileOpsClient.loadDragWithOption()
            : NSEvent.modifierFlags.contains(.option)

        if isInternalDrag, !wantsCopy {
            let sourceParent = URL(fileURLWithPath: sourcePaths[0]).deletingLastPathComponent().path
            if sourceParent == destinationPath {
                setDropTargetEntryId(nil)
                store.send(.entryViewLayout(.setDropTargeted(false)))
                return []
            }

            let destinationComponents = URL(fileURLWithPath: destinationPath)
                .standardizedFileURL.pathComponents
            for sourcePath in sourcePaths {
                if destinationPath == sourcePath {
                    setDropTargetEntryId(nil)
                    store.send(.entryViewLayout(.setDropTargeted(false)))
                    return []
                }

                let sourceComponents = URL(fileURLWithPath: sourcePath)
                    .standardizedFileURL.pathComponents
                if destinationComponents.count > sourceComponents.count,
                   Array(destinationComponents.prefix(sourceComponents.count)) == sourceComponents
                {
                    setDropTargetEntryId(nil)
                    store.send(.entryViewLayout(.setDropTargeted(false)))
                    return []
                }
            }
        }

        let allowed = draggingInfo.draggingSourceOperationMask
        let preferred: NSDragOperation = wantsCopy ? .copy : .move
        let resolved = preferred.isDisjoint(with: allowed)
            ? NSDragOperation.copy.intersection(allowed)
            : preferred.intersection(allowed)

        setDropTargetEntryId(targetEntryId)
        store.send(.entryViewLayout(.setDropTargeted(!resolved.isEmpty)))
        return resolved
    }

    func collectionView(
        _: NSCollectionView,
        acceptDrop draggingInfo: NSDraggingInfo,
        indexPath: IndexPath,
        dropOperation: NSCollectionView.DropOperation,
    ) -> Bool {
        var destinationPath = store.state.navigation.currentPath
        if dropOperation == .on,
           let entry = entry(at: indexPath),
           entry.isDirectory,
           !entryLoadingClient.isPackageDirectory(URL(fileURLWithPath: entry.fullPath))
        {
            destinationPath = entry.fullPath
        }

        let internalPaths = entryFileOpsClient.loadDragPaths()
        if !internalPaths.isEmpty {
            store.send(.entryViewLayout(.handleDrop(providers: [], destinationPath: destinationPath)))
            setDropTargetEntryId(nil)
            store.send(.entryViewLayout(.setDropTargeted(false)))
            return true
        }

        let pasteboard = draggingInfo.draggingPasteboard
        let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        guard let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: options) as? [URL],
              !urls.isEmpty
        else {
            setDropTargetEntryId(nil)
            store.send(.entryViewLayout(.setDropTargeted(false)))
            return false
        }

        let allowed = draggingInfo.draggingSourceOperationMask
        let preferred: NSDragOperation = NSEvent.modifierFlags.contains(.option) ? .copy : .move
        let resolved = preferred.isDisjoint(with: allowed)
            ? NSDragOperation.copy.intersection(allowed)
            : preferred.intersection(allowed)
        guard !resolved.isEmpty else {
            setDropTargetEntryId(nil)
            store.send(.entryViewLayout(.setDropTargeted(false)))
            return false
        }

        let isOptionPressed = resolved.contains(.copy) && !resolved.contains(.move)
        store.send(.entryViewLayout(.dropItems(
            sourcePaths: urls.map(\.path),
            destinationPath: destinationPath,
            isOptionDrag: isOptionPressed,
        )))
        setDropTargetEntryId(nil)
        store.send(.entryViewLayout(.setDropTargeted(false)))
        return true
    }

    private func updateSelectionFromCollectionView(_ collectionView: NSCollectionView) {
        guard !isUpdatingSelectionFromStore else { return }

        let selectedIndexPaths = collectionView.selectionIndexPaths
        let selectedIds: Set<String> = Set(selectedIndexPaths.compactMap { indexPath in
            entry(at: indexPath)?.id
        })

        let lastSelectedId = selectedIndexPaths
            .max()
            .flatMap { entry(at: $0)?.id }

        store.send(.entryViewLayout(.setSelectedIds(ids: selectedIds, lastSelectedId: lastSelectedId)))
    }
}

extension EntryGridCoordinator: EntryGridView.EntryGridCollectionViewMenuProviding {
    func contextMenu(for indexPath: IndexPath?, event: NSEvent) -> NSMenu {
        updateContextMenuAnchor(event)
        let rowEntry = entry(at: indexPath)
        let composed = EntryContextMenuBuilder.makeMenu(input: .init(
            contentStore: store,
            fileManagerWindowClient: fileManagerWindowClient,
            selectedIds: store.state.entryViewLayout.selectedIds,
            selectedEntries: selectedEntries(fallback: rowEntry),
            rowEntry: rowEntry,
            isTrashFolder: isTrashFolder,
            canPaste: !store.state.entryOperations.clipboardItems.isEmpty,
            currentPath: { [weak self] in
                self?.store.state.navigation.currentPath ?? ""
            },
            selectedItemId: { [weak self] in
                self?.store.state.entryViewLayout.selectedIds.first
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

private extension EntryGridCoordinator {
    func updateContextMenuAnchor(_ event: NSEvent) {
        if let window = view?.window {
            let screenPoint = window.convertPoint(toScreen: event.locationInWindow)
            contextMenuAnchor = screenPoint
        } else {
            contextMenuAnchor = nil
        }
    }
}
