import AppKit
import ComposableArchitecture
import IdentifiedCollections
import SwiftUI
@_spi(Advanced)
import SwiftUIIntrospect
import UniformTypeIdentifiers

private struct RightClickMonitorView: NSViewRepresentable {
    let onRightMouseDown: (CGPoint) -> Void

    func makeNSView(context _: Context) -> MonitorView {
        let view = MonitorView()
        view.onRightMouseDown = onRightMouseDown
        return view
    }

    func updateNSView(_ nsView: MonitorView, context _: Context) {
        nsView.onRightMouseDown = onRightMouseDown
    }

    @MainActor
    final class MonitorView: NSView {
        var onRightMouseDown: ((CGPoint) -> Void)?
        private var monitor: Any?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
            guard window != nil else { return }

            monitor = NSEvent.addLocalMonitorForEvents(matching: [.rightMouseDown]) { [weak self] event in
                guard let self, let window else { return event }
                let location = convert(event.locationInWindow, from: nil)
                if bounds.contains(location) {
                    onRightMouseDown?(event.locationInWindow)
                }
                return event
            }
        }

        deinit {
            MainActor.assumeIsolated {
                if let monitor {
                    NSEvent.removeMonitor(monitor)
                }
            }
        }
    }
}

// swiftlint:disable type_body_length
struct ContentPaneGridView: View {
    let store: StoreOf<FileManagerFeature>

    @State private var nsScrollView: NSScrollView?
    @State private var hasRestoredScrollPosition: Bool = false
    @State private var lastGridColumnCount: Int = 1
    private func saveScrollPositionBeforeOpen() {
        ScrollPositionUtils.saveScrollPosition(
            scrollView: nsScrollView,
            currentPath: store.currentPath,
            store: store,
        )
    }

    private func findGridItemId(
        at point: CGPoint,
        itemPositions: [String: CGRect],
        items: IdentifiedArrayOf<FSItem>,
    ) -> String? {
        for item in items {
            let iconRect = itemPositions[item.id + "_icon"]
            let textRect = itemPositions[item.id + "_text"]
            let itemRect = itemPositions[item.id]

            if let iconRect, iconRect.contains(point) {
                return item.id
            }
            if let textRect, textRect.contains(point) {
                return item.id
            }
            if let itemRect, itemRect.contains(point) {
                return item.id
            }
        }
        return nil
    }

    private var itemWidth: CGFloat {
        max(120, max(store.gridIconSize + 16, 112))
    }

    private let horizontalPadding: CGFloat = 12
    private let minSpacing: CGFloat = 2
    private let verticalSpacing: CGFloat = 8

    private func itemGrid(
        item: FSItem,
        store: StoreOf<FileManagerFeature>,
        fsStore: Store<FSItemsFeature.State, FSItemsFeature.Action>,
        isTrashFolder: Bool = false,
    ) -> FSItemGridView {
        let selectedItems = fsStore.displayItems.filter { fsStore.selectedIds.contains($0.id) }
        let (showCompress, showExtract) = FSItemContextMenuUtils
            .calculateCompressExtractOptions(selectedItems: selectedItems)

        let handlers = makeContextMenuHandlers(
            item: item,
            fsStore: fsStore,
            saveScrollPosition: saveScrollPositionBeforeOpen,
            isTrashFolder: isTrashFolder,
            onEmptyTrash: { store.send(.emptyTrash) },
        )

        return buildGridView(
            item: item,
            store: store,
            fsStore: fsStore,
            handlers: handlers,
            showCompress: showCompress,
            showExtract: showExtract,
        )
    }

    private func buildGridView(
        item: FSItem,
        store: StoreOf<FileManagerFeature>,
        fsStore: Store<FSItemsFeature.State, FSItemsFeature.Action>,
        handlers: FSItemContextMenuHandlers,
        showCompress: Bool,
        showExtract: Bool,
    ) -> FSItemGridView {
        let selectedIds = fsStore.selectedIds
        let clipboardItems = fsStore.clipboardItems
        let thumbnailsReady = fsStore.thumbnailsReady

        return FSItemGridView(
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
            draggingPaths: fsStore.draggingPaths,
        )
    }

    var body: some View {
        let fsStore = store.scope(state: \.fsItems, action: \.fsItems)

        GeometryReader { geometry in
            let columns = [GridItem(.adaptive(minimum: itemWidth), spacing: minSpacing, alignment: .top)]
            let availableWidth = geometry.size.width

            VStack(spacing: 0) {
                Color.clear.frame(height: 4)

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

                            VStack(spacing: 0) {
                                Color.clear.frame(height: 0).id("scrollTop")
                                LazyVStack(alignment: .leading, spacing: 16) {
                                    gridSections(
                                        fsStore: fsStore,
                                        store: store,
                                        columns: columns,
                                    )
                                }
                            }
                            .padding(.horizontal, horizontalPadding)
                            .padding(.bottom, horizontalPadding)
                            .frame(maxWidth: .infinity, alignment: .topLeading)
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
                            },
                        )
                        .contextMenu {
                            ContentPaneContextMenu(store: store)
                        }
                        .background(
                            RightClickMonitorView(onRightMouseDown: { windowPoint in
                                guard let nsScrollView else { return }
                                let pointInClip = nsScrollView.contentView.convert(windowPoint, from: nil)
                                let targetId = findGridItemId(
                                    at: pointInClip,
                                    itemPositions: fsStore.itemPositions,
                                    items: fsStore.displayItems,
                                )
                                guard let targetId, !fsStore.selectedIds.contains(targetId) else { return }
                                fsStore.send(.selectItem(
                                    id: targetId,
                                    isCommandPressed: false,
                                    isShiftPressed: false,
                                ))
                            }),
                        )
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
                                            to: value.location,
                                        )

                                        if dragDistance > 15,
                                           !LassoSelectionUtils.isPointOverAnyItem(
                                               value.startLocation,
                                               itemPositions: fsStore.itemPositions,
                                           )
                                        {
                                            let modifiers = LassoSelectionUtils.detectModifierFlags()

                                            fsStore.send(.startLassoSelection(
                                                startPoint: value.startLocation,
                                                modifierFlags: modifiers,
                                            ))
                                        }
                                    }
                                }
                                .onEnded { _ in
                                    if fsStore.lassoSelection != nil {
                                        fsStore.send(.endLassoSelection)
                                    }
                                },
                        )
                    }
                    .onAppear {
                        updateGridColumnCountIfNeeded(for: availableWidth)
                    }
                    .onChange(of: availableWidth) { newWidth in
                        updateGridColumnCountIfNeeded(for: newWidth)
                    }
                    .onChange(of: fsStore.lastSelectedId) { newId in
                        if fsStore.shouldScrollToSelection, let id = newId {
                            proxy.scrollTo(id, anchor: nil)
                            fsStore.send(.resetScrollFlag)
                        }
                    }
                    .onChange(of: store.showHiddenFiles) { _ in
                        ScrollPositionUtils.saveScrollPosition(
                            scrollView: nsScrollView,
                            currentPath: store.currentPath,
                            store: store,
                        )
                    }
                    .introspect(.scrollView, on: .macOS(.v13...)) { scrollView in
                        nsScrollView = scrollView
                    }
                    .onChange(of: store.currentPath) { _ in
                        hasRestoredScrollPosition = false
                    }
                    .onChange(of: fsStore.displayItems.count) { itemCount in
                        guard itemCount != 0 else { return }

                        if store.scrollPositions[store.currentPath] != nil {
                            ScrollPositionUtils.restoreScrollPosition(
                                scrollView: nsScrollView,
                                currentPath: store.currentPath,
                                scrollPositions: store.scrollPositions,
                                hasRestored: &hasRestoredScrollPosition,
                            )
                        } else {
                            proxy.scrollTo("scrollTop", anchor: .top)
                        }
                    }
                }
            }
        }
        .border(fsStore.isDropTargeted ? Color.accentColor : Color.clear, width: 2)
        .onDrop(
            of: [UTType.fileURL],
            delegate: FSItemDropDelegate(store: store, fsStore: fsStore),
        )
    }

    @ViewBuilder
    private func gridSections(
        fsStore: Store<FSItemsFeature.State, FSItemsFeature.Action>,
        store: StoreOf<FileManagerFeature>,
        columns: [GridItem],
    ) -> some View {
        if fsStore.groupKey == .none {
            LazyVGrid(columns: columns, alignment: .leading, spacing: verticalSpacing) {
                ForEach(fsStore.displayItems) { item in
                    itemGrid(
                        item: item,
                        store: store,
                        fsStore: fsStore,
                        isTrashFolder: store.isTrashFolder,
                    )
                }
            }
        } else {
            ForEach(Array(fsStore.groupedItems.enumerated()), id: \.element.groupName) { index, group in
                if index > 0 {
                    Spacer().frame(height: 16)
                }

                if !group.groupName.isEmpty, fsStore.groupKey != .name {
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
                            isTrashFolder: store.isTrashFolder,
                        )
                    }
                }
                .frame(maxWidth: .infinity, alignment: .center)
            }
        }
    }

    private func updateGridColumnCountIfNeeded(for width: CGFloat) {
        let usableWidth = max(width - (horizontalPadding * 2), itemWidth)
        let columns = max(1, Int((usableWidth + minSpacing) / (itemWidth + minSpacing)))
        guard columns != lastGridColumnCount else { return }
        lastGridColumnCount = columns
        store.send(.fsItems(.updateGridColumnCount(columns)))
    }
}

// swiftlint:enable type_body_length
