// swiftlint:disable file_length
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

    @Dependency(\.fileManagerWindowClient)
    private var fileManagerWindowClient
    @Dependency(\.workspaceClient)
    private var workspaceClient
    @Dependency(\.entryClient)
    private var entryClient

    @State private var contentWidth: CGFloat = 0
    @State private var rowPositions: [String: CGRect] = [:]
    @State private var scrollViewHeight: CGFloat = 0
    @State private var nsScrollView: NSScrollView?
    @State private var hasRestoredScrollPosition: Bool = false
    @State private var contextMenuTargetId: String?
    @State private var contextMenuTargetWasSelected = false
    @State private var contextMenuAnchor: CGPoint?

    private var rowHeight: CGFloat {
        max(24, store.listIconSize + 4)
    }

    private func saveScrollPosition() {
        ScrollPositionUtils.saveScrollPosition(
            scrollView: nsScrollView,
            currentPath: store.currentPath,
            store: store,
        )
    }

    private func restoreScrollPosition() {
        ScrollPositionUtils.restoreScrollPosition(
            scrollView: nsScrollView,
            currentPath: store.currentPath,
            scrollPositions: store.scrollPositions,
            hasRestored: &hasRestoredScrollPosition,
        )
    }

    private func performAutoScroll() {
        ScrollPositionUtils.performAutoScroll(
            scrollView: nsScrollView,
            workspaceClient: workspaceClient,
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

    private struct ItemRenderContext {
        let layout: ListColumnLayoutUtils
        let showCompress: Bool
        let showExtract: Bool
    }

    private struct ItemRowProps {
        let handlers: EntryContextMenuHandlers
        let width: CGFloat
        let context: ItemRenderContext
    }

    private func buildItemRowProps(
        item: Entry,
        fsStore: Store<EntriesFeature.State, EntriesFeature.Action>,
        geometry: GeometryProxy,
        store: StoreOf<FileManagerFeature>,
        isTrashFolder: Bool,
        context: ItemRenderContext,
    ) -> ItemRowProps {
        let handlers = makeContextMenuHandlers(
            item: item,
            fsStore: fsStore,
            saveScrollPosition: saveScrollPosition,
            shareAnchorProvider: { contextMenuAnchor },
            isTrashFolder: isTrashFolder,
            onEmptyTrash: { store.send(.entries(.emptyTrash)) },
            openWindow: { path in
                Task {
                    _ = await fileManagerWindowClient.openWindow(path)
                }
            },
        )

        let width = contentWidth > 0 ? contentWidth : geometry.size.width

        return ItemRowProps(
            handlers: handlers,
            width: width,
            context: context,
        )
    }

    @ViewBuilder
    private func itemRow(
        item: Entry,
        fsStore: Store<EntriesFeature.State, EntriesFeature.Action>,
        geometry: GeometryProxy,
        store: StoreOf<FileManagerFeature>,
        context: ItemRenderContext,
        isTrashFolder: Bool = false,
    ) -> some View {
        let props = buildItemRowProps(
            item: item,
            fsStore: fsStore,
            geometry: geometry,
            store: store,
            isTrashFolder: isTrashFolder,
            context: context,
        )

        buildEntryListView(
            item: item,
            fsStore: fsStore,
            store: store,
            props: props,
        )
    }

    // swiftlint:disable function_body_length
    private func buildEntryListView(
        item: Entry,
        fsStore: Store<EntriesFeature.State, EntriesFeature.Action>,
        store: StoreOf<FileManagerFeature>,
        props: ItemRowProps,
    ) -> some View {
        let selectedIds = fsStore.selectedIds
        let selectedURLs = fsStore.displayItems
            .filter { selectedIds.contains($0.id) }
            .map { URL(fileURLWithPath: $0.fullPath) }
        let clipboardItems = fsStore.clipboardItems
        let thumbnailsReady = fsStore.thumbnailsReady
        let isContextMenuTarget = contextMenuTargetId == item.id

        return EntryListView(
            item: item,
            isSelected: selectedIds.contains(item.id),
            isCut: clipboardItems.contains(item.fullPath) && fsStore.clipboardOperation == .cut,
            isRenaming: fsStore.renamingItemId == item.id,
            renamingText: fsStore.renamingText,
            layout: props.context.layout,
            applications: fsStore.operations.applicationsForItems[item.fullPath],
            commonApplications: selectedIds.count > 1 ?
                fsStore.operations.commonApplicationsForSelectedFiles : nil,
            isThumbnailReady: thumbnailsReady.contains(item.fullPath),
            iconSize: store.listIconSize,
            textSize: store.listTextSize,
            onSelect: props.handlers.onSelect,
            onOpen: props.handlers.onOpen,
            onOpenInNewTab: props.handlers.onOpenInNewTab,
            onQuickLook: props.handlers.onQuickLook,
            onGetInfo: props.handlers.onGetInfo,
            onShare: props.handlers.onShare,
            onOpenWithApp: props.handlers.onOpenWithApp,
            onRenameUpdate: props.handlers.onRenameUpdate,
            onRenameCommit: props.handlers.onRenameCommit,
            onRenameCancel: props.handlers.onRenameCancel,
            onStartDrag: props.handlers.onStartDrag,
            onDrop: props.handlers.onDrop,
            onLoadApplications: props.handlers.onLoadApplications,
            onLoadCommonApplications: props.handlers.onLoadCommonApplications,
            onPutBack: props.handlers.onPutBack,
            onMoveToTrash: props.handlers.onMoveToTrash,
            onDeleteImmediately: props.handlers.onDeleteImmediately,
            onEmptyTrash: props.handlers.onEmptyTrash,
            onRename: props.handlers.onRename,
            onCompress: props.handlers.onCompress,
            onDuplicate: props.handlers.onDuplicate,
            onCreateAlias: props.handlers.onCreateAlias,
            onExtract: props.handlers.onExtract,
            onCopy: props.handlers.onCopy,
            onCopyAbsolutePaths: props.handlers.onCopyAbsolutePaths,
            onCopyURLs: props.handlers.onCopyURLs,
            onCut: props.handlers.onCut,
            onToggleTag: props.handlers.onToggleTag,
            onPerformService: props.handlers.onPerformService,
            onRevealInFinder: props.handlers.onRevealInFinder,
            selectedURLs: selectedURLs,
            isContextMenuTarget: isContextMenuTarget,
            contextMenuTargetWasSelected: isContextMenuTarget ? contextMenuTargetWasSelected : false,
            onContextMenuOpen: { windowPoint in
                contextMenuTargetId = item.id
                contextMenuTargetWasSelected = selectedIds.contains(item.id)

                if let window = nsScrollView?.window ?? NSApp.keyWindow {
                    // TODO: 좌표 기반 앵커링을 엔트리 기준 위치로 전환해야 함
                    contextMenuAnchor = window.convertPoint(toScreen: windowPoint)
                } else {
                    contextMenuAnchor = nil
                }

                // Finder behavior: 우클릭한 아이템이 선택에 포함되어 있지 않으면 해당 아이템 1개로 선택을 전환한다.
                if !selectedIds.contains(item.id) {
                    fsStore.send(.selectItem(
                        id: item.id,
                        isCommandPressed: false,
                        isShiftPressed: false,
                    ))
                }
            },
            selectedCount: fsStore.selectedIds.isEmpty ? 1 : fsStore.selectedIds.count,
            showCompress: props.context.showCompress,
            showExtract: props.context.showExtract,
            draggingPaths: fsStore.draggingPaths,
        )
        .equatable()
    }

    // swiftlint:enable function_body_length

    private func zebraBackgroundColor(for index: Int) -> Color {
        index % 2 == 0 ? Color.clear : Color.primary.opacity(0.05)
    }

    @ViewBuilder
    private func styledItemRow(
        item: Entry,
        index: Int,
        fsStore: Store<EntriesFeature.State, EntriesFeature.Action>,
        geometry: GeometryProxy,
        store: StoreOf<FileManagerFeature>,
        context: ItemRenderContext,
    ) -> some View {
        let bgColor = zebraBackgroundColor(for: index)

        itemRow(
            item: item,
            fsStore: fsStore,
            geometry: geometry,
            store: store,
            context: context,
            isTrashFolder: isTrashFolder,
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
                        ],
                    )
            },
        )
        .id(item.id)
    }

    private var isTrashFolder: Bool {
        guard case let .folder(path) = store.navigationState,
              let trashPath = entryClient.trashDirectoryPath()
        else {
            return false
        }
        return path == trashPath || path.hasPrefix(trashPath + "/")
    }

    @ViewBuilder
    private func groupHeader(
        group: GroupedItems,
        fsStore: Store<EntriesFeature.State, EntriesFeature.Action>,
    ) -> some View {
        HStack(spacing: 8) {
            Spacer().frame(width: 28)

            if fsStore.groupKey == .tags,
               let colorCode = group.items.first?.tags?
               .first(where: { $0.name == group.groupName })?.colorCode
            {
                Circle()
                    .fill(EntryTagUtils.getTagColor(colorCode: colorCode))
                    .frame(width: 8, height: 8)
                    .overlay(
                        Circle()
                            .stroke(Color.primary.opacity(0.2), lineWidth: 1),
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

    private func groupedItemsContent(
        fsStore: Store<EntriesFeature.State, EntriesFeature.Action>,
        geometry: GeometryProxy,
        store: StoreOf<FileManagerFeature>,
        context: ItemRenderContext,
    ) -> some View {
        Group {
            ForEach(Array(fsStore.groupedItems.enumerated()), id: \.element.groupName) { index, group in
                if index > 0 {
                    Spacer().frame(height: 16)
                }

                if !group.groupName.isEmpty, fsStore.groupKey != .name {
                    groupHeader(group: group, fsStore: fsStore)
                }

                ForEach(Array(group.items.enumerated()), id: \.element.id) { itemIndex, item in
                    styledItemRow(
                        item: item,
                        index: itemIndex,
                        fsStore: fsStore,
                        geometry: geometry,
                        store: store,
                        context: context,
                    )
                }
            }
        }
    }

    private func listContent(
        fsStore: Store<EntriesFeature.State, EntriesFeature.Action>,
        geometry: GeometryProxy,
        store: StoreOf<FileManagerFeature>,
    ) -> some View {
        let selectedIds = fsStore.selectedIds
        let selectedItems = fsStore.displayItems.filter { selectedIds.contains($0.id) }
        let options = EntryContextMenuUtils
            .calculateCompressExtractOptions(selectedItems: selectedItems)

        let layout = store.columnWidths.makeAbsoluteWidths(
            totalWidth: geometry.size.width,
            padding: ListColumnLayoutUtils.outerPadding,
            spacing: ListColumnLayoutUtils.columnSpacing,
        )

        let context = ItemRenderContext(
            layout: layout,
            showCompress: options.showCompress,
            showExtract: options.showExtract,
        )

        return Group {
            Color.clear.frame(height: 0).id("scrollTop")

            if fsStore.groupKey == .none {
                ForEach(Array(fsStore.displayItems.enumerated()), id: \.element.id) { index, item in
                    styledItemRow(
                        item: item,
                        index: index,
                        fsStore: fsStore,
                        geometry: geometry,
                        store: store,
                        context: context,
                    )
                }
            } else {
                groupedItemsContent(fsStore: fsStore, geometry: geometry, store: store, context: context)
            }

            emptyRowsView(itemsCount: fsStore.displayItems.count, scrollHeight: scrollViewHeight, fsStore: fsStore)
        }
    }

    private func emptyRowTapAction(fsStore: Store<EntriesFeature.State, EntriesFeature.Action>) {
        if fsStore.isRenaming {
            fsStore.send(.commitRename)
        }
        fsStore.send(.clearSelection)
        restoreFileManagerFocus()
    }

    @ViewBuilder
    private func emptyRowsView(
        itemsCount: Int,
        scrollHeight: CGFloat,
        fsStore: Store<EntriesFeature.State, EntriesFeature.Action>,
    ) -> some View {
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
                    .onTapGesture {
                        emptyRowTapAction(fsStore: fsStore)
                    }
            }

            if partialHeight > 0 {
                zebraBackgroundColor(for: itemsCount + fullRows)
                    .frame(height: partialHeight)
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        emptyRowTapAction(fsStore: fsStore)
                    }
            }
        }
    }

    var body: some View {
        let fsStore = store.scope(state: \.entries, action: \.entries)

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
                                padding: ListColumnLayoutUtils.outerPadding,
                                spacing: ListColumnLayoutUtils.columnSpacing,
                            ),
                        ))
                    },
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
                                    restoreFileManagerFocus()
                                }

                            LazyVStack(alignment: .leading, spacing: 0) {
                                listContent(fsStore: fsStore, geometry: geometry, store: store)
                            }
                            .frame(maxWidth: .infinity, alignment: .topLeading)
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
                        },
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

                                    performAutoScroll()
                                } else {
                                    if !fsStore.displayItems.isEmpty {
                                        let startItemId: String?
                                        if let nearestItemId = findNearestItemAtY(value.startLocation.y) {
                                            startItemId = nearestItemId
                                        } else {
                                            let itemIndex = max(0, min(
                                                Int(value.startLocation.y / rowHeight),
                                                fsStore.displayItems.count - 1,
                                            ))
                                            startItemId = itemIndex < fsStore.displayItems.count
                                                ? fsStore.displayItems[itemIndex]
                                                .id : nil
                                        }

                                        if let itemId = startItemId {
                                            let modifiers = LassoSelectionUtils.detectModifierFlags()
                                            fsStore.send(.startListRowDrag(
                                                startItemId: itemId,
                                                modifierFlags: modifiers,
                                            ))
                                        }
                                    }
                                }
                            }
                            .onEnded { _ in
                                if fsStore.listRowDragSelection != nil {
                                    fsStore.send(.endListRowDrag)
                                }
                            },
                    )
                    .contextMenu {
                        ContentPaneContextMenu(store: store)
                    }
                    .onChange(of: fsStore.lastSelectedId) { newId in
                        if fsStore.shouldScrollToSelection, let id = newId {
                            proxy.scrollTo(id, anchor: nil)
                            fsStore.send(.resetScrollFlag)
                        }
                    }
                    .onChange(of: store.showHiddenFiles) { _ in
                        saveScrollPosition()
                    }
                    .introspect(.scrollView, on: .macOS(.v13...)) { scrollView in
                        Task { @MainActor in
                            nsScrollView = scrollView
                        }
                    }
                    .onChange(of: store.currentPath) { _ in
                        hasRestoredScrollPosition = false
                    }
                    .onChange(of: fsStore.displayItems.count) { itemCount in
                        guard itemCount != 0 else { return }

                        if store.scrollPositions[store.currentPath] != nil {
                            restoreScrollPosition()
                        } else {
                            proxy.scrollTo("scrollTop", anchor: .top)
                        }
                    }
                    .onReceive(NotificationCenter.default.publisher(for: NSMenu.didEndTrackingNotification)) { _ in
                        contextMenuTargetId = nil
                        contextMenuTargetWasSelected = false
                    }
                }
                .border(fsStore.isDropTargeted ? Color.accentColor : Color.clear, width: 2)
                .onDrop(
                    of: [UTType.fileURL],
                    delegate: EntryDropDelegate(store: store, fsStore: fsStore),
                )
            }
        }
    }
}

// swiftlint:enable type_body_length
// swiftlint:enable file_length
