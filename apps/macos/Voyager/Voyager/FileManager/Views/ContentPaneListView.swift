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

    @State private var availableWidth: CGFloat = 0
    @State private var rowPositions: [String: CGRect] = [:]
    @State private var scrollViewHeight: CGFloat = 0
    @State private var nsScrollView: NSScrollView?
    @State private var hasRestoredScrollPosition: Bool = false

    private let rowHeight: CGFloat = 24

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

    private func findNearestItemAtY(_ yPosition: CGFloat) -> String? {
        guard !rowPositions.isEmpty else { return nil }

        var nearest: (id: String, distance: CGFloat)?
        for (itemId, rect) in rowPositions {
            let centerY = rect.midY
            let distance = abs(yPosition - centerY)

            if let nearestDistance = nearest?.distance {
                if distance < nearestDistance {
                    nearest = (itemId, distance)
                }
            } else {
                nearest = (itemId, distance)
            }
        }
        return nearest?.id
    }

    @ViewBuilder
    private func itemRow(
        item: FSItem,
        fsStore: Store<FSItemsFeature.State, FSItemsFeature.Action>,
        geometry: GeometryProxy,
        isTrashFolder: Bool = false
    ) -> FSItemListView {
        let selectedIds = fsStore.selectedIds
        let clipboardItems = fsStore.clipboardItems
        let thumbnailsReady = fsStore.thumbnailsReady

        let selectedItems = fsStore.items.filter { selectedIds.contains($0.id) }
        let (showCompress, showExtract) = calculateCompressExtractOptions(selectedItems: selectedItems)

        let handlers = makeContextMenuHandlers(
            item: item,
            fsStore: fsStore,
            saveScrollPosition: saveScrollPositionBeforeOpen,
            isTrashFolder: isTrashFolder,
            onEmptyTrash: { store.send(.emptyTrash) }
        )

        FSItemListView(
            item: item,
            isSelected: selectedIds.contains(item.id),
            isCut: clipboardItems.contains(item.fullPath) && fsStore.clipboardOperation == .cut,
            isRenaming: fsStore.renamingItemId == item.id,
            renamingText: fsStore.renamingText,
            availableWidth: geometry.size.width,
            applications: fsStore.operations.applicationsForItems[item.fullPath],
            isThumbnailReady: thumbnailsReady.contains(item.fullPath),
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

    private func zebraBackgroundColor(for index: Int) -> Color {
        index % 2 == 0 ? Color.clear : Color.primary.opacity(0.05)
    }

    @ViewBuilder
    private func styledItemRow(
        item: FSItem,
        index: Int,
        fsStore: Store<FSItemsFeature.State, FSItemsFeature.Action>,
        geometry: GeometryProxy
    ) -> some View {
        let bgColor = zebraBackgroundColor(for: index)

        itemRow(
            item: item,
            fsStore: fsStore,
            geometry: geometry,
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
        geometry: GeometryProxy
    ) -> some View {
        ForEach(Array(fsStore.groupedItems.enumerated()), id: \.element.groupName) { index, group in
            if index > 0 {
                Spacer().frame(height: 16)
            }

            if !group.groupName.isEmpty && fsStore.groupKey != .name {
                groupHeader(group: group, fsStore: fsStore)
            }

            ForEach(Array(group.items.enumerated()), id: \.element.id) { itemIndex, item in
                styledItemRow(item: item, index: itemIndex, fsStore: fsStore, geometry: geometry)
            }
        }
    }

    @ViewBuilder
    private func listContent(
        fsStore: Store<FSItemsFeature.State, FSItemsFeature.Action>,
        geometry: GeometryProxy
    ) -> some View {
        Color.clear.frame(height: 0).id("scrollTop")

        if fsStore.groupKey == .none {
            ForEach(Array(fsStore.items.enumerated()), id: \.element.id) { index, item in
                styledItemRow(item: item, index: index, fsStore: fsStore, geometry: geometry)
            }
        } else {
            groupedItemsContent(fsStore: fsStore, geometry: geometry)
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
                    .allowsHitTesting(false)
            }

            if partialHeight > 0 {
                zebraBackgroundColor(for: itemsCount + fullRows)
                    .frame(height: partialHeight)
                    .frame(maxWidth: .infinity)
                    .allowsHitTesting(false)
            }
        }
    }

    var body: some View {
        let fsStore = store.scope(state: \.fsItems, action: \.fsItems)

        GeometryReader { geometry in
            VStack(spacing: 0) {
                ColumnHeaderView(
                    sortKey: fsStore.sortKey,
                    sortOrder: fsStore.sortOrder,
                    availableWidth: geometry.size.width,
                    onSortKeyChange: { key in
                        store.send(.changeSortKey(key))
                    },
                    onSortOrderToggle: {
                        let newOrder = fsStore.sortOrder == .ascending ? SortOrder.descending : SortOrder.ascending
                        store.send(.changeSortOrder(newOrder))
                    }
                )

                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            listContent(fsStore: fsStore, geometry: geometry)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if fsStore.isRenaming {
                                fsStore.send(.commitRename)
                            }
                            fsStore.send(.clearSelection)
                        }
                    }
                    .background(
                        GeometryReader { scrollGeometry in
                            Color.clear
                                .onAppear {
                                    scrollViewHeight = scrollGeometry.size.height
                                }
                                .onChange(of: scrollGeometry.size.height) { newHeight in
                                    scrollViewHeight = newHeight
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
                                guard !rowPositions.isEmpty else { return }

                                if fsStore.listRowDragSelection != nil {
                                    if let currentItemId = findItemAtPoint(value.location) {
                                        fsStore.send(.updateListRowDrag(currentItemId: currentItemId))
                                    }
                                } else {
                                    guard let nearestItemId = findNearestItemAtY(value.startLocation.y)
                                    else { return }

                                    let modifiers: ModifierFlags = {
                                        if NSEvent.modifierFlags.contains(.command) {
                                            return .command
                                        } else if NSEvent.modifierFlags.contains(.shift) {
                                            return .shift
                                        } else {
                                            return .none
                                        }
                                    }()

                                    fsStore.send(.startListRowDrag(
                                        startItemId: nearestItemId,
                                        modifierFlags: modifiers
                                    ))
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
                    delegate: FileDropDelegate(store: store, fsStore: fsStore)
                )
            }
        }
    }
}

// swiftlint:enable type_body_length
