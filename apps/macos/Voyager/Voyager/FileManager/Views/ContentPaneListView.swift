import AppKit
import ComposableArchitecture
import SwiftUI
@_spi(Advanced)
import SwiftUIIntrospect
import UniformTypeIdentifiers

private struct ListRowPositionKey: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}

// swiftlint:disable type_body_length
struct ContentPaneListView: View {
    let store: StoreOf<FileManagerFeature>

    @State private var contentWidth: CGFloat = 0
    @State private var rowPositions: [String: CGRect] = [:]
    @State private var scrollViewHeight: CGFloat = 0
    @State private var nsScrollView: NSScrollView?
    @State private var hasRestoredScrollPosition: Bool = false

    private var rowHeight: CGFloat {
        max(24, store.listIconSize + 4)
    }

    private func saveScrollPositionBeforeOpen() {
        ScrollPositionUtils.saveScrollPosition(
            scrollView: nsScrollView,
            currentPath: store.currentPath,
            store: store
        )
    }

    private func findItemAtPoint(_ point: CGPoint) -> String? {
        for (itemId, rect) in rowPositions where rect.contains(point) {
            return itemId
        }
        return nil
    }

    private struct NearestItem {
        let id: String
        let distance: CGFloat
    }

    private func findNearestItemAtY(_ yPosition: CGFloat) -> String? {
        guard !rowPositions.isEmpty else { return nil }

        var nearest: NearestItem?
        for (itemId, rect) in rowPositions {
            let centerY = rect.midY
            let distance = abs(yPosition - centerY)

            if let nearestDistance = nearest?.distance {
                if distance < nearestDistance {
                    nearest = NearestItem(id: itemId, distance: distance)
                }
            } else {
                nearest = NearestItem(id: itemId, distance: distance)
            }
        }
        return nearest?.id
    }

    private struct ItemRowProps {
        let handlers: FSItemContextMenuHandlers
        let width: CGFloat
        let showCompress: Bool
        let showExtract: Bool
    }

    private func buildItemRowProps(
        item: FSItem,
        fsStore: Store<FSItemsFeature.State, FSItemsFeature.Action>,
        geometry: GeometryProxy,
        store: StoreOf<FileManagerFeature>,
        isTrashFolder: Bool
    ) -> ItemRowProps {
        let selectedIds = fsStore.selectedIds
        let selectedItems = fsStore.items.filter { selectedIds.contains($0.id) }
        let options = FSItemContextMenuUtils
            .calculateCompressExtractOptions(selectedItems: selectedItems)
        let showCompress = options.showCompress
        let showExtract = options.showExtract

        let handlers = makeContextMenuHandlers(
            item: item,
            fsStore: fsStore,
            saveScrollPosition: saveScrollPositionBeforeOpen,
            isTrashFolder: isTrashFolder,
            onEmptyTrash: { store.send(.emptyTrash) }
        )

        let width = contentWidth > 0 ? contentWidth : geometry.size.width

        return ItemRowProps(
            handlers: handlers,
            width: width,
            showCompress: showCompress,
            showExtract: showExtract
        )
    }

    @ViewBuilder
    private func itemRow(
        item: FSItem,
        fsStore: Store<FSItemsFeature.State, FSItemsFeature.Action>,
        geometry: GeometryProxy,
        store: StoreOf<FileManagerFeature>,
        isTrashFolder: Bool = false
    ) -> FSItemListView {
        let selectedIds = fsStore.selectedIds
        let clipboardItems = fsStore.clipboardItems
        let thumbnailsReady = fsStore.thumbnailsReady
        let props = buildItemRowProps(
            item: item,
            fsStore: fsStore,
            geometry: geometry,
            store: store,
            isTrashFolder: isTrashFolder
        )

        FSItemListView(
            item: item,
            isSelected: selectedIds.contains(item.id),
            isCut: clipboardItems.contains(item.fullPath) && fsStore.clipboardOperation == .cut,
            isRenaming: fsStore.renamingItemId == item.id,
            renamingText: fsStore.renamingText,
            availableWidth: props.width,
            columnWidths: store.columnWidths,
            applications: fsStore.operations.applicationsForItems[item.fullPath],
            isThumbnailReady: thumbnailsReady.contains(item.fullPath),
            iconSize: store.listIconSize,
            textSize: store.listTextSize,
            onSelect: props.handlers.onSelect,
            onOpen: props.handlers.onOpen,
            onOpenInNewTab: props.handlers.onOpenInNewTab,
            onQuickLook: props.handlers.onQuickLook,
            onOpenWithApp: props.handlers.onOpenWithApp,
            onRenameUpdate: props.handlers.onRenameUpdate,
            onRenameCommit: props.handlers.onRenameCommit,
            onRenameCancel: props.handlers.onRenameCancel,
            onStartDrag: props.handlers.onStartDrag,
            onDrop: props.handlers.onDrop,
            onLoadApplications: props.handlers.onLoadApplications,
            onPutBack: props.handlers.onPutBack,
            onMoveToTrash: props.handlers.onMoveToTrash,
            onDeleteImmediately: props.handlers.onDeleteImmediately,
            onEmptyTrash: props.handlers.onEmptyTrash,
            onRename: props.handlers.onRename,
            onCompress: props.handlers.onCompress,
            onDuplicate: props.handlers.onDuplicate,
            onExtract: props.handlers.onExtract,
            onCopy: props.handlers.onCopy,
            onCut: props.handlers.onCut,
            onToggleTag: props.handlers.onToggleTag,
            selectedCount: fsStore.selectedIds.isEmpty ? 1 : fsStore.selectedIds.count,
            showCompress: props.showCompress,
            showExtract: props.showExtract,
            draggingPaths: fsStore.draggingPaths
        )
    }

    private func zebraBackgroundColor(for index: Int) -> Color {
        index % 2 == 0 ? Color.clear : Color.primary.opacity(0.05)
    }

    @ViewBuilder
    private func styledItemRow(
        item: FSItem,
        index: Int,
        fsStore: Store<FSItemsFeature.State, FSItemsFeature.Action>,
        geometry: GeometryProxy,
        store: StoreOf<FileManagerFeature>
    ) -> some View {
        let bgColor = zebraBackgroundColor(for: index)

        itemRow(
            item: item,
            fsStore: fsStore,
            geometry: geometry,
            store: store,
            isTrashFolder: store.isTrashFolder
        )
        .frame(height: rowHeight)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(bgColor)
        .background(
            GeometryReader { itemGeometry in
                Color.clear
                    .preference(
                        key: ListRowPositionKey.self,
                        value: [
                            item.id: itemGeometry.frame(in: .named("listContainer")),
                        ]
                    )
            }
        )
        .id(item.id)
    }

    @ViewBuilder
    private func groupHeader(
        group: GroupedItems,
        fsStore: Store<FSItemsFeature.State, FSItemsFeature.Action>
    ) -> some View {
        HStack(spacing: 8) {
            Spacer().frame(width: 28)

            if fsStore.groupKey == .tags,
               let colorCode = group.items.first?.tags?
               .first(where: { $0.name == group.groupName })?.colorCode
            {
                Circle()
                    .fill(FSItemTagUtils.getTagColor(colorCode: colorCode))
                    .frame(width: 8, height: 8)
                    .overlay(
                        Circle()
                            .stroke(Color.primary.opacity(0.2), lineWidth: 1)
                    )
            }

            Text(group.groupName)
                .font(.headline)
                .foregroundColor(.primary)
            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.bottom, 4)
    }

    @ViewBuilder
    private func groupedItemsContent(
        fsStore: Store<FSItemsFeature.State, FSItemsFeature.Action>,
        geometry: GeometryProxy,
        store: StoreOf<FileManagerFeature>
    ) -> some View {
        ForEach(Array(fsStore.groupedItems.enumerated()), id: \.element.groupName) { index, group in
            if index > 0 {
                Spacer().frame(height: 16)
            }

            if !group.groupName.isEmpty && fsStore.groupKey != .name {
                groupHeader(group: group, fsStore: fsStore)
            }

            ForEach(Array(group.items.enumerated()), id: \.element.id) { itemIndex, item in
                styledItemRow(item: item, index: itemIndex, fsStore: fsStore, geometry: geometry, store: store)
            }
        }
    }

    @ViewBuilder
    private func listContent(
        fsStore: Store<FSItemsFeature.State, FSItemsFeature.Action>,
        geometry: GeometryProxy,
        store: StoreOf<FileManagerFeature>
    ) -> some View {
        Color.clear.frame(height: 0).id("scrollTop")

        if fsStore.groupKey == .none {
            ForEach(Array(fsStore.items.enumerated()), id: \.element.id) { index, item in
                styledItemRow(item: item, index: index, fsStore: fsStore, geometry: geometry, store: store)
            }
        } else {
            groupedItemsContent(fsStore: fsStore, geometry: geometry, store: store)
        }

        emptyRowsView(itemsCount: fsStore.items.count, scrollHeight: scrollViewHeight)
    }

    @ViewBuilder
    private func emptyRowsView(itemsCount: Int, scrollHeight: CGFloat) -> some View {
        let currentHeight = CGFloat(itemsCount) * rowHeight
        let remainingHeight = scrollHeight - currentHeight

        if remainingHeight > 0 {
            let fullRows = Int(remainingHeight / rowHeight)
            let partialHeight = remainingHeight - CGFloat(fullRows) * rowHeight

            ForEach(0 ..< fullRows, id: \.self) { index in
                zebraBackgroundColor(for: itemsCount + index)
                    .frame(height: rowHeight)
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
            }

            if partialHeight > 0 {
                zebraBackgroundColor(for: itemsCount + fullRows)
                    .frame(height: partialHeight)
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
            }
        }
    }

    var body: some View {
        let fsStore = store.scope(state: \.fsItems, action: \.fsItems)

        GeometryReader { geometry in
            VStack(spacing: 0) {
                let headerWidth = contentWidth > 0 ? contentWidth : geometry.size.width

                ColumnHeaderView(
                    sortKey: fsStore.sortKey,
                    sortOrder: fsStore.sortOrder,
                    availableWidth: headerWidth,
                    columnWidths: store.columnWidths,
                    onSortKeyChange: { key in
                        store.send(.changeSortKey(key))
                    },
                    onSortOrderToggle: {
                        let newOrder = fsStore.sortOrder == .ascending ? SortOrder.descending : SortOrder.ascending
                        store.send(.changeSortOrder(newOrder))
                    },
                    onColumnResize: { column, delta in
                        store.send(.updateColumnWidth(
                            FileManagerFeature.ColumnUpdate(
                                column: column,
                                delta: delta,
                                totalWidth: headerWidth,
                                padding: ListColumnLayout.outerPadding,
                                spacing: ListColumnLayout.columnSpacing
                            )
                        ))
                    }
                )

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

                            LazyVStack(alignment: .leading, spacing: 0) {
                                listContent(fsStore: fsStore, geometry: geometry, store: store)
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        }
                    }
                    .background(
                        GeometryReader { scrollGeometry in
                            Color.clear
                                .onAppear {
                                    scrollViewHeight = scrollGeometry.size.height
                                    contentWidth = scrollGeometry.size.width
                                }
                                .onChange(of: scrollGeometry.size.height) { newHeight in
                                    scrollViewHeight = newHeight
                                }
                                .onChange(of: scrollGeometry.size.width) { newWidth in
                                    contentWidth = newWidth
                                }
                        }
                    )
                    .coordinateSpace(name: "scrollView")
                    .coordinateSpace(name: "listContainer")
                    .onPreferenceChange(ListRowPositionKey.self) { positions in
                        rowPositions = positions
                    }
                    .simultaneousGesture(
                        DragGesture(minimumDistance: 10, coordinateSpace: .named("listContainer"))
                            .onChanged { value in
                                if fsStore.listRowDragSelection != nil {
                                    if let currentItemId = findItemAtPoint(value.location) {
                                        fsStore.send(.updateListRowDrag(currentItemId: currentItemId))
                                    }

                                    ScrollPositionUtils.performAutoScroll(scrollView: nsScrollView)
                                } else {
                                    if !fsStore.items.isEmpty {
                                        let startItemId: String?
                                        if let nearestItemId = findNearestItemAtY(value.startLocation.y) {
                                            startItemId = nearestItemId
                                        } else {
                                            let itemIndex = max(0, min(
                                                Int(value.startLocation.y / rowHeight),
                                                fsStore.items.count - 1
                                            ))
                                            startItemId = itemIndex < fsStore.items.count ? fsStore.items[itemIndex]
                                                .id : nil
                                        }

                                        if let itemId = startItemId {
                                            let modifiers = LassoSelectionUtils.detectModifierFlags()
                                            fsStore.send(.startListRowDrag(
                                                startItemId: itemId,
                                                modifierFlags: modifiers
                                            ))
                                        }
                                    }
                                }
                            }
                            .onEnded { _ in
                                if fsStore.listRowDragSelection != nil {
                                    fsStore.send(.endListRowDrag)
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
                .border(fsStore.isDropTargeted ? Color.accentColor : Color.clear, width: 2)
                .onDrop(
                    of: [UTType.fileURL],
                    delegate: FSItemDropDelegate(store: store, fsStore: fsStore)
                )
            }
        }
    }
}

// swiftlint:enable type_body_length
