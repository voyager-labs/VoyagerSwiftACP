import AppKit
import ComposableArchitecture
import SwiftUI
@_spi(Advanced)
import SwiftUIIntrospect
import UniformTypeIdentifiers

private struct GridLayoutConfig {
    let columns: Int
    let spacing: CGFloat
    let edgePadding: CGFloat
}

struct ContentPaneGridView: View {
    let store: StoreOf<FileManagerFeature>

    @State private var nsScrollView: NSScrollView?
    @State private var hasRestoredScrollPosition: Bool = false
    @State private var gridColumnCount: Int = 1

    private func saveScrollPositionBeforeOpen() {
        ScrollPositionUtils.saveScrollPosition(
            scrollView: nsScrollView,
            currentPath: store.currentPath,
            store: store
        )
    }

    private var itemWidth: CGFloat {
        max(120, max(store.gridIconSize + 16, 112))
    }

    private let horizontalPadding: CGFloat = 16
    private let minSpacing: CGFloat = 4
    private let maxSpacing: CGFloat = 8
    private let verticalSpacing: CGFloat = 8

    private func resolveLayout(for width: CGFloat) -> GridLayoutConfig {
        let usableWidth = max(width - (horizontalPadding * 2), itemWidth)
        let candidateColumns = max(1, Int((usableWidth + minSpacing) / (itemWidth + minSpacing)))

        if candidateColumns == 1 {
            let padding = max(horizontalPadding, (width - itemWidth) / 2)
            return GridLayoutConfig(columns: 1, spacing: minSpacing, edgePadding: padding)
        }

        let occupiedWidth = CGFloat(candidateColumns) * itemWidth
        let remainingWidth = max(0, usableWidth - occupiedWidth)
        let spacing = min(maxSpacing, max(minSpacing, remainingWidth / CGFloat(candidateColumns - 1)))
        let usedWidth = occupiedWidth + spacing * CGFloat(candidateColumns - 1)
        let edgePadding = max(horizontalPadding, (width - usedWidth) / 2)

        return GridLayoutConfig(columns: candidateColumns, spacing: spacing, edgePadding: edgePadding)
    }

    private func makeColumns(count: Int, spacing: CGFloat) -> [GridItem] {
        Array(
            repeating: GridItem(.fixed(itemWidth), spacing: spacing, alignment: .top),
            count: max(1, count)
        )
    }

    @ViewBuilder
    private func itemGrid(
        item: FSItem,
        store: StoreOf<FileManagerFeature>,
        fsStore: Store<FSItemsFeature.State, FSItemsFeature.Action>,
        isTrashFolder: Bool = false
    ) -> FSItemGridView {
        let selectedIds = fsStore.selectedIds
        let clipboardItems = fsStore.clipboardItems
        let thumbnailsReady = fsStore.thumbnailsReady

        let selectedItems = fsStore.items.filter { selectedIds.contains($0.id) }
        let (showCompress, showExtract) = FSItemContextMenuUtils
            .calculateCompressExtractOptions(selectedItems: selectedItems)

        let handlers = makeContextMenuHandlers(
            item: item,
            fsStore: fsStore,
            saveScrollPosition: saveScrollPositionBeforeOpen,
            isTrashFolder: isTrashFolder,
            onEmptyTrash: { store.send(.emptyTrash) }
        )

        FSItemGridView(
            item: item,
            isSelected: selectedIds.contains(item.id),
            isCut: clipboardItems.contains(item.fullPath) && fsStore.clipboardOperation == .cut,
            isRenaming: fsStore.renamingItemId == item.id,
            renamingText: fsStore.renamingText,
            isThumbnailReady: thumbnailsReady.contains(item.fullPath),
            applications: fsStore.operations.applicationsForItems[item.fullPath],
            iconSize: store.gridIconSize,
            textSize: store.gridTextSize,
            commonApplications: selectedIds.count > 1 ? fsStore.operations.commonApplicationsForSelectedFiles : nil,
            onSelect: handlers.onSelect,
            onOpen: handlers.onOpen,
            onOpenInNewTab: handlers.onOpenInNewTab,
            onQuickLook: handlers.onQuickLook,
            onOpenWithApp: handlers.onOpenWithApp,
            onRenameUpdate: handlers.onRenameUpdate,
            onRenameCommit: handlers.onRenameCommit,
            onRenameCancel: handlers.onRenameCancel,
            onStartDrag: handlers.onStartDrag,
            onDrop: handlers.onDrop,
            onLoadApplications: handlers.onLoadApplications,
            onLoadCommonApplications: handlers.onLoadCommonApplications,
            onPutBack: handlers.onPutBack,
            onMoveToTrash: handlers.onMoveToTrash,
            onDeleteImmediately: handlers.onDeleteImmediately,
            onEmptyTrash: handlers.onEmptyTrash,
            onRename: handlers.onRename,
            onCompress: handlers.onCompress,
            onDuplicate: handlers.onDuplicate,
            onExtract: handlers.onExtract,
            onCopy: handlers.onCopy,
            onCut: handlers.onCut,
            onToggleTag: handlers.onToggleTag,
            selectedCount: fsStore.selectedIds.isEmpty ? 1 : fsStore.selectedIds.count,
            showCompress: showCompress,
            showExtract: showExtract,
            draggingPaths: fsStore.draggingPaths
        )
    }

    var body: some View {
        let fsStore = store.scope(state: \.fsItems, action: \.fsItems)

        GeometryReader { geometry in
            let layout = resolveLayout(for: geometry.size.width)
            let columns = makeColumns(count: layout.columns, spacing: layout.spacing)

            ScrollViewReader { proxy in
                ScrollView {
                    ZStack {
                        Color.clear
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                if fsStore.isRenaming {
                                    fsStore.send(.commitRename)
                                }
                                fsStore.send(.clearSelection)
                            }

                        VStack(spacing: 0) {
                            Color.clear.frame(height: 0).id("scrollTop")
                            LazyVStack(alignment: .leading, spacing: 16) {
                                gridSections(
                                    fsStore: fsStore,
                                    store: store,
                                    columns: columns
                                )
                            }
                        }
                        .padding(.horizontal, layout.edgePadding)
                        .padding(.bottom, horizontalPadding)
                        .frame(maxWidth: .infinity, minHeight: geometry.size.height, alignment: .topLeading)
                    }
                    .coordinateSpace(name: "scrollView")
                    .coordinateSpace(name: "contentPane")
                    .coordinateSpace(name: "gridContainer")
                    .onPreferenceChange(ItemPositionKey.self) { positions in
                        fsStore.send(.updateItemPositions(positions))
                    }
                    .overlay(
                        Group {
                            if let lasso = fsStore.lassoSelection {
                                LassoRectangleView(rect: lasso.rect)
                            }
                        }
                    )
                    .contextMenu {
                        if store.isTrashFolder {
                            Button("Empty Trash") {
                                store.send(.emptyTrash)
                            }
                        } else {
                            Button("New Folder") {
                                store.send(.fsItems(.createNewFolder(currentPath: store.currentPath)))
                            }
                            .keyboardShortcut("n", modifiers: [.command, .shift])
                        }
                    }
                    .simultaneousGesture(
                        DragGesture(minimumDistance: 10, coordinateSpace: .named("contentPane"))
                            .onChanged { value in
                                guard !fsStore.itemPositions.isEmpty else { return }

                                if fsStore.lassoSelection != nil {
                                    fsStore.send(.updateLassoSelection(currentPoint: value.location))

                                    ScrollPositionUtils.performAutoScroll(scrollView: nsScrollView)
                                } else {
                                    let dragDistance = LassoSelectionUtils.calculateDragDistance(
                                        from: value.startLocation,
                                        to: value.location
                                    )

                                    if dragDistance > 15,
                                       !LassoSelectionUtils.isPointOverAnyItem(
                                           value.startLocation,
                                           itemPositions: fsStore.itemPositions
                                       )
                                    {
                                        let modifiers = LassoSelectionUtils.detectModifierFlags()

                                        fsStore.send(.startLassoSelection(
                                            startPoint: value.startLocation,
                                            modifierFlags: modifiers
                                        ))
                                    }
                                }
                            }
                            .onEnded { _ in
                                if fsStore.lassoSelection != nil {
                                    fsStore.send(.endLassoSelection)
                                }
                            }
                    )
                }
                .onChange(of: fsStore.lastSelectedId) { newId in
                    if fsStore.shouldScrollToSelection, let id = newId {
                        proxy.scrollTo(id, anchor: nil)
                        fsStore.send(.resetScrollFlag)
                    }
                }
                .introspect(.scrollView, on: .macOS(.v13...)) { scrollView in
                    nsScrollView = scrollView
                }
                .onChange(of: store.currentPath) { _ in
                    hasRestoredScrollPosition = false
                }
                .onChange(of: fsStore.items.count) { itemCount in
                    guard itemCount != 0 else { return }

                    if store.scrollPositions[store.currentPath] != nil {
                        ScrollPositionUtils.restoreScrollPosition(
                            scrollView: nsScrollView,
                            currentPath: store.currentPath,
                            scrollPositions: store.scrollPositions,
                            hasRestored: &hasRestoredScrollPosition
                        )
                    } else {
                        proxy.scrollTo("scrollTop", anchor: .top)
                    }
                }
            }
            .onAppear {
                updateColumnCountIfNeeded(layout.columns)
            }
            .onChange(of: geometry.size.width) { newWidth in
                let newLayout = resolveLayout(for: newWidth)
                updateColumnCountIfNeeded(newLayout.columns)
            }
        }
        .border(fsStore.isDropTargeted ? Color.accentColor : Color.clear, width: 2)
        .onDrop(
            of: [UTType.fileURL],
            delegate: FSItemDropDelegate(store: store, fsStore: fsStore)
        )
    }

    private func updateColumnCountIfNeeded(_ newValue: Int) {
        guard gridColumnCount != newValue else { return }
        gridColumnCount = newValue
        store.send(.fsItems(.updateGridColumnCount(newValue)))
    }

    @ViewBuilder
    private func gridSections(
        fsStore: Store<FSItemsFeature.State, FSItemsFeature.Action>,
        store: StoreOf<FileManagerFeature>,
        columns: [GridItem]
    ) -> some View {
        if fsStore.groupKey == .none {
            LazyVGrid(columns: columns, alignment: .leading, spacing: verticalSpacing) {
                ForEach(fsStore.items) { item in
                    itemGrid(
                        item: item,
                        store: store,
                        fsStore: fsStore,
                        isTrashFolder: store.isTrashFolder
                    )
                }
            }
        } else {
            ForEach(Array(fsStore.groupedItems.enumerated()), id: \.element.groupName) { index, group in
                if index > 0 {
                    Spacer().frame(height: 16)
                }

                if !group.groupName.isEmpty && fsStore.groupKey != .name {
                    HStack(spacing: 8) {
                        if fsStore.groupKey == .tags,
                           let colorCode = group.items.first?.tags?
                           .first(where: { $0.name == group.groupName })?.colorCode
                        {
                            Circle()
                                .fill(FSItemTagUtils.getTagColor(colorCode: colorCode))
                                .frame(width: 8, height: 8)
                        }
                        Text(group.groupName)
                            .font(.headline)
                            .foregroundColor(.primary)
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                }

                LazyVGrid(columns: columns, alignment: .leading, spacing: verticalSpacing) {
                    ForEach(group.items) { item in
                        itemGrid(
                            item: item,
                            store: store,
                            fsStore: fsStore,
                            isTrashFolder: store.isTrashFolder
                        )
                    }
                }
            }
        }
    }
}
