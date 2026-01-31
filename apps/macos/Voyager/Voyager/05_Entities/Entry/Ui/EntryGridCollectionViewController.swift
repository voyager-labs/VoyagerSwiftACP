import AppKit
import Combine
import ComposableArchitecture
import IdentifiedCollections
import SwiftUI

final class EntryGridCollectionViewController: NSViewController {
    struct Section {
        let title: String?
        let colorCode: Int?
        let count: Int
        let items: [Entry]
        let isCollapsed: Bool
    }

    let store: StoreOf<FileManagerFeature>
    let fsStore: StoreOf<EntriesFeature>
    var cancellables: Set<AnyCancellable> = []

    let scrollView = NSScrollView()
    let collectionView = EntryGridCollectionView()
    let flowLayout = NSCollectionViewFlowLayout()

    var sections: [Section] = []
    var indexPathByEntryId: [String: IndexPath] = [:]
    var isUpdatingSelectionFromStore = false
    private var lastRenamingItemId: String?
    var hasRestoredScrollPosition = false
    var dropTargetEntryId: String?
    var contextMenuAnchor: CGPoint?

    @Dependency(\.entryClient)
    var entryClient
    @Dependency(\.workspaceClient)
    var workspaceClient
    @Dependency(\.fileManagerWindowClient)
    var fileManagerWindowClient

    private let horizontalPadding: CGFloat = 12
    private let minSpacing: CGFloat = 2
    private let verticalSpacing: CGFloat = 8

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
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupCollectionView()
        observeStore()
        rebuildSectionsAndReload()
        updateDropTargetBorder(isTargeted: store.state.entries.isDropTargeted)
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        updateLayout()
        updateGridColumnCountIfNeeded(for: view.bounds.width)
    }

    private func setupCollectionView() {
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.clear.cgColor

        scrollView.wantsLayer = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.automaticallyAdjustsContentInsets = false
        scrollView.contentInsets = NSEdgeInsets(top: 4, left: 0, bottom: 0, right: 0)

        collectionView.collectionViewLayout = flowLayout
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.isSelectable = true
        collectionView.allowsMultipleSelection = true
        collectionView.allowsEmptySelection = true
        collectionView.backgroundColors = [.clear]
        collectionView.contextMenuProvider = self
        collectionView.register(
            EntryGridCollectionViewItem.self,
            forItemWithIdentifier: NSUserInterfaceItemIdentifier("EntryGridCollectionViewItem"),
        )
        collectionView.register(
            EntryGridSectionHeaderView.self,
            forSupplementaryViewOfKind: NSCollectionView.elementKindSectionHeader,
            withIdentifier: NSUserInterfaceItemIdentifier("EntryGridSectionHeaderView"),
        )

        collectionView.setDraggingSourceOperationMask([.copy, .move], forLocal: true)
        collectionView.setDraggingSourceOperationMask([.copy], forLocal: false)
        collectionView.registerForDraggedTypes([.fileURL])

        scrollView.documentView = collectionView
        view.addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        let doubleClick = NSClickGestureRecognizer(target: self, action: #selector(handleDoubleClick(_:)))
        doubleClick.numberOfClicksRequired = 2
        collectionView.addGestureRecognizer(doubleClick)

        updateLayout()
    }

    func rebuildSectionsAndReload() {
        sections = makeSections(state: store.state.entries)
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
        updateGridColumnCountIfNeeded(for: view.bounds.width)
    }

    private func makeSections(state: EntriesFeature.State) -> [Section] {
        if state.groupKey == .none {
            return [
                Section(
                    title: nil,
                    colorCode: nil,
                    count: state.displayItems.count,
                    items: Array(state.displayItems),
                    isCollapsed: false,
                ),
            ]
        }

        return state.groupedItems.map { group in
            let showHeader = !group.groupName.isEmpty && state.groupKey != .name
            let colorCode: Int? = if state.groupKey == .tags {
                EntryTagUtils.getTagNameToColorCodeMapping()[group.groupName]
            } else {
                nil
            }
            let isCollapsed = state.collapsedGroups.contains(group.groupName)
            return Section(
                title: showHeader ? group.groupName : nil,
                colorCode: colorCode,
                count: group.count,
                items: isCollapsed ? [] : group.items,
                isCollapsed: isCollapsed,
            )
        }
    }

    func updateLayout() {
        flowLayout.minimumInteritemSpacing = minSpacing
        flowLayout.minimumLineSpacing = verticalSpacing
        flowLayout.sectionInset = NSEdgeInsets(
            top: 8,
            left: horizontalPadding,
            bottom: horizontalPadding,
            right: horizontalPadding,
        )
        flowLayout.headerReferenceSize = NSSize(width: view.bounds.width, height: 36)

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
        if store.state.entries.gridColumnCount != columns {
            fsStore.send(.updateGridColumnCount(columns))
        }
    }

    func syncSelectionFromStore() {
        let selectedIds = store.state.entries.selectedIds
        let indexPaths = Set(selectedIds.compactMap { indexPathByEntryId[$0] })

        isUpdatingSelectionFromStore = true
        collectionView.selectItems(at: indexPaths, scrollPosition: [])
        isUpdatingSelectionFromStore = false
    }

    func syncRenamingFromStore() {
        let renamingItemId = store.state.entries.renamingItemId
        let previousRenamingItemId = lastRenamingItemId
        lastRenamingItemId = renamingItemId

        if let previousRenamingItemId, let previousIndexPath = indexPathByEntryId[previousRenamingItemId] {
            collectionView.reloadItems(at: [previousIndexPath])
        }

        guard let renamingItemId, let indexPath = indexPathByEntryId[renamingItemId] else {
            view.window?.makeFirstResponder(collectionView)
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

    func saveScrollPosition() {
        ScrollPositionUtils.saveScrollPosition(
            scrollView: scrollView,
            currentPath: store.state.currentPath,
            store: store,
        )
    }

    func restoreScrollPositionIfNeeded() {
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

    func scrollToSelectionIfNeeded() {
        guard store.state.entries.shouldScrollToSelection else { return }
        let targetId = store.state.entries.lastSelectedId ?? store.state.entries.selectedIds.first
        guard let targetId, let indexPath = indexPathByEntryId[targetId] else {
            fsStore.send(.resetScrollFlag)
            return
        }
        collectionView.scrollToItems(at: [indexPath], scrollPosition: .centeredVertically)
        fsStore.send(.resetScrollFlag)
    }

    func reloadVisibleItems() {
        let visibleIndexPaths = collectionView.indexPathsForVisibleItems()
        collectionView.reloadItems(at: visibleIndexPaths)
    }

    func updateDropTargetBorder(isTargeted: Bool) {
        scrollView.layer?.borderWidth = isTargeted ? 2 : 0
        scrollView.layer?.borderColor = isTargeted ? NSColor.controlAccentColor.cgColor : nil
    }

    func setDropTargetEntryId(_ entryId: String?) {
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

    func entry(at indexPath: IndexPath?) -> Entry? {
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

    func selectedEntries(fallback: Entry?) -> [Entry] {
        let selectedIds = store.state.entries.selectedIds
        if selectedIds.isEmpty {
            return fallback.map { [$0] } ?? []
        }
        return store.state.entries.displayItems.filter { selectedIds.contains($0.id) }
    }

    var isTrashFolder: Bool {
        guard case let .folder(path) = store.state.navigationState,
              let trashPath = entryClient.trashDirectoryPath()
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
        EntryContextMenuUtils.sendWithSelection(entry, fsStore: fsStore, action: {
            self.saveScrollPosition()
            self.store.send(.entries(.openSelectedItem))
        })
    }
}

extension EntryGridCollectionViewController {
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
    }

    private func observeDisplayItems() {
        store.publisher.entries.displayItems
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.rebuildSectionsAndReload()
            }
            .store(in: &cancellables)
    }

    private func observeGroupKey() {
        store.publisher.entries.groupKey
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.rebuildSectionsAndReload()
            }
            .store(in: &cancellables)
    }

    private func observeGroupedItems() {
        store.publisher.entries.groupedItems
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.rebuildSectionsAndReload()
            }
            .store(in: &cancellables)
    }

    private func observeCollapsedGroups() {
        store.publisher.entries.collapsedGroups
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.rebuildSectionsAndReload()
            }
            .store(in: &cancellables)
    }

    private func observeSelectedIds() {
        store.publisher.entries.selectedIds
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.syncSelectionFromStore()
            }
            .store(in: &cancellables)
    }

    private func observeRenamingItemId() {
        store.publisher.entries.renamingItemId
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.syncRenamingFromStore()
            }
            .store(in: &cancellables)
    }

    private func observeThumbnailsReady() {
        store.publisher.entries.thumbnailsReady
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.reloadVisibleItems()
            }
            .store(in: &cancellables)
    }

    private func observeGridIconSize() {
        store.publisher.gridIconSize
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateLayout()
                self?.reloadVisibleItems()
            }
            .store(in: &cancellables)
    }

    private func observeGridTextSize() {
        store.publisher.gridTextSize
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateLayout()
                self?.reloadVisibleItems()
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

    private func observeCurrentPath() {
        store.publisher.currentPath
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.hasRestoredScrollPosition = false
            }
            .store(in: &cancellables)
    }

    private func observeDisplayItemCountForScrollRestore() {
        store.publisher.entries.displayItems
            .map(\.count)
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.restoreScrollPositionIfNeeded()
            }
            .store(in: &cancellables)
    }
}
