// swiftlint:disable type_body_length
import ComposableArchitecture
import SwiftUI
import UniformTypeIdentifiers

private struct GridItemPositionKey: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}

struct ContentPaneGridView: View {
    let store: StoreOf<FileManagerFeature>

    @State private var savedTopItemId: String?
    @State private var scrollViewHeight: CGFloat = 0

    private func isNearTop(_ geometry: GeometryProxy) -> Bool {
        let frame = geometry.frame(in: .named("scrollView"))
        return frame.minY >= 0 && frame.minY < 50
    }

    private func saveScrollPositionBeforeOpen() {
        if let topId = savedTopItemId {
            store.send(.saveTopVisibleItem(topId, forPath: store.currentPath))
        }
    }

    private func updateGridColumnCount(positions: [String: CGRect]) {
        guard !positions.isEmpty else { return }

        let sortedByY = positions.values.sorted { $0.minY < $1.minY }
        guard let firstItemY = sortedByY.first?.minY else { return }

        let firstRowItems = sortedByY.filter { abs($0.minY - firstItemY) < 1 }
        let columnCount = firstRowItems.count

        store.send(.fsItems(.updateGridColumnCount(columnCount)))
    }

    private let itemMinWidth: CGFloat = 100
    private let itemMaxWidth: CGFloat = 120
    private let itemSpacing: CGFloat = 20
    private let gridItemHeight: CGFloat = 100

    @ViewBuilder
    private func emptyGridSpace(itemsCount: Int, columnCount: Int) -> some View {
        let rowHeight = gridItemHeight + itemSpacing
        let currentRows = Int(ceil(Double(itemsCount) / Double(columnCount)))
        let currentHeight = CGFloat(currentRows) * rowHeight

        if currentHeight < scrollViewHeight {
            let neededHeight = scrollViewHeight - currentHeight
            let emptyRows = Int(neededHeight / rowHeight)

            ForEach(0 ..< emptyRows, id: \.self) { _ in
                HStack(spacing: itemSpacing) {
                    ForEach(0 ..< columnCount, id: \.self) { _ in
                        Color.clear
                            .frame(width: itemMaxWidth, height: gridItemHeight)
                            .allowsHitTesting(false)
                    }
                }
            }
        }
    }

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: itemMinWidth, maximum: itemMaxWidth), spacing: itemSpacing)]
    }

    var body: some View {
        let fsStore = store.scope(state: \.fsItems, action: \.fsItems)

        GeometryReader { geometry in
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
                                if fsStore.groupKey == .none {
                                    let selectedIds = fsStore.selectedIds
                                    let clipboardItems = fsStore.clipboardItems
                                    let thumbnailsReady = fsStore.thumbnailsReady

                                    LazyVGrid(columns: columns, spacing: 16) {
                                        ForEach(fsStore.items) { item in
                                            FSItemGridView(
                                                item: item,
                                                isSelected: selectedIds.contains(item.id),
                                                isCut: clipboardItems.contains(item.fullPath) && fsStore
                                                    .clipboardOperation == .cut,
                                                isRenaming: fsStore.renamingItemId == item.id,
                                                renamingText: fsStore.renamingText,
                                                isThumbnailReady: thumbnailsReady.contains(item.fullPath),
                                                onSelect: {
                                                    let isCommandPressed = NSEvent.modifierFlags.contains(.command)
                                                    let isShiftPressed = NSEvent.modifierFlags.contains(.shift)
                                                    fsStore.send(.selectItem(
                                                        id: item.id,
                                                        isCommandPressed: isCommandPressed,
                                                        isShiftPressed: isShiftPressed
                                                    ))
                                                },
                                                onOpen: {
                                                    fsStore.send(.selectItem(
                                                        id: item.id,
                                                        isCommandPressed: false,
                                                        isShiftPressed: false
                                                    ))
                                                    saveScrollPositionBeforeOpen()
                                                    store.send(.openSelectedItem)
                                                },
                                                onRenameUpdate: { text in
                                                    fsStore.send(.updateRenamingText(text))
                                                },
                                                onRenameCommit: {
                                                    fsStore.send(.commitRename)
                                                },
                                                onRenameCancel: {
                                                    fsStore.send(.cancelRename)
                                                },
                                                onStartDrag: {
                                                    let dragPaths = selectedIds.isEmpty
                                                        ? [item.fullPath]
                                                        : fsStore.items.filter { selectedIds.contains($0.id) }
                                                        .map { $0.fullPath }
                                                    fsStore.send(.startDrag(paths: dragPaths))
                                                },
                                                onDrop: { providers, folderPath in
                                                    fsStore.send(.handleDrop(
                                                        providers: providers,
                                                        destinationPath: folderPath
                                                    ))
                                                },
                                                draggingPaths: fsStore.draggingPaths
                                            )
                                            .background(
                                                GeometryReader { itemGeometry in
                                                    Color.clear
                                                        .preference(
                                                            key: VisibleTopItemKey.self,
                                                            value: isNearTop(itemGeometry) ? item.id : ""
                                                        )
                                                        .preference(
                                                            key: GridItemPositionKey.self,
                                                            value: [
                                                                item.id: itemGeometry
                                                                    .frame(in: .named("gridContainer")),
                                                            ]
                                                        )
                                                }
                                            )
                                            .id(item.id)
                                        }
                                    }

                                    emptyGridSpace(
                                        itemsCount: fsStore.items.count,
                                        columnCount: fsStore.gridColumnCount
                                    )
                                } else {
                                    let selectedIds = fsStore.selectedIds
                                    let clipboardItems = fsStore.clipboardItems
                                    let thumbnailsReady = fsStore.thumbnailsReady

                                    ForEach(Array(fsStore.groupedItems.enumerated()),
                                            id: \.element.groupName)
                                    { index, group in
                                        if index > 0 {
                                            Spacer()
                                                .frame(height: 16)
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

                                        LazyVGrid(columns: columns, spacing: 16) {
                                            ForEach(group.items) { item in
                                                FSItemGridView(
                                                    item: item,
                                                    isSelected: selectedIds.contains(item.id),
                                                    isCut: clipboardItems.contains(item.fullPath) && fsStore
                                                        .clipboardOperation == .cut,
                                                    isRenaming: fsStore.renamingItemId == item.id,
                                                    renamingText: fsStore.renamingText,
                                                    isThumbnailReady: thumbnailsReady.contains(item.fullPath),
                                                    onSelect: {
                                                        let isCommandPressed = NSEvent.modifierFlags.contains(.command)
                                                        let isShiftPressed = NSEvent.modifierFlags.contains(.shift)
                                                        fsStore.send(.selectItem(
                                                            id: item.id,
                                                            isCommandPressed: isCommandPressed,
                                                            isShiftPressed: isShiftPressed
                                                        ))
                                                    },
                                                    onOpen: {
                                                        fsStore.send(.selectItem(
                                                            id: item.id,
                                                            isCommandPressed: false,
                                                            isShiftPressed: false
                                                        ))
                                                        saveScrollPositionBeforeOpen()
                                                        store.send(.openSelectedItem)
                                                    },
                                                    onRenameUpdate: { text in
                                                        fsStore.send(.updateRenamingText(text))
                                                    },
                                                    onRenameCommit: {
                                                        fsStore.send(.commitRename)
                                                    },
                                                    onRenameCancel: {
                                                        fsStore.send(.cancelRename)
                                                    },
                                                    onStartDrag: {
                                                        let dragPaths = selectedIds.isEmpty
                                                            ? [item.fullPath]
                                                            : fsStore.items.filter { selectedIds.contains($0.id) }
                                                            .map { $0.fullPath }
                                                        fsStore.send(.startDrag(paths: dragPaths))
                                                    },
                                                    onDrop: { providers, folderPath in
                                                        fsStore.send(.handleDrop(
                                                            providers: providers,
                                                            destinationPath: folderPath
                                                        ))
                                                    },
                                                    draggingPaths: fsStore.draggingPaths
                                                )
                                                .background(
                                                    GeometryReader { itemGeometry in
                                                        Color.clear
                                                            .preference(
                                                                key: VisibleTopItemKey.self,
                                                                value: isNearTop(itemGeometry) ? item.id : ""
                                                            )
                                                            .preference(
                                                                key: GridItemPositionKey.self,
                                                                value: [
                                                                    item.id: itemGeometry
                                                                        .frame(in: .named("gridContainer")),
                                                                ]
                                                            )
                                                    }
                                                )
                                                .id(item.id)
                                            }
                                        }
                                    }

                                    emptyGridSpace(
                                        itemsCount: fsStore.items.count,
                                        columnCount: fsStore.gridColumnCount
                                    )
                                }
                            }
                        }
                        .padding([.horizontal, .bottom], 16)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    }
                    .coordinateSpace(name: "scrollView")
                    .coordinateSpace(name: "contentPane")
                    .coordinateSpace(name: "gridContainer")
                    .onPreferenceChange(VisibleTopItemKey.self) { topItemId in
                        guard !topItemId.isEmpty, topItemId != savedTopItemId else { return }
                        savedTopItemId = topItemId
                    }
                    .onPreferenceChange(GridItemPositionKey.self) { positions in
                        updateGridColumnCount(positions: positions)
                    }
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
                }
                .simultaneousGesture(
                    DragGesture(minimumDistance: 10, coordinateSpace: .named("contentPane"))
                        .onChanged { value in
                            guard !fsStore.itemPositions.isEmpty else { return }

                            if fsStore.lassoSelection != nil {
                                fsStore.send(.updateLassoSelection(currentPoint: value.location))
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
                                    let scrollViewBounds = CGRect(x: 0, y: 0, width: 1000, height: 1000)

                                    fsStore.send(.startLassoSelection(
                                        startPoint: value.startLocation,
                                        scrollViewBounds: scrollViewBounds,
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
                .onChange(of: fsStore.lastSelectedId) { newId in
                    if fsStore.shouldScrollToSelection, let id = newId {
                        proxy.scrollTo(id, anchor: nil)
                        fsStore.send(.resetScrollFlag)
                    }
                }
                .onChange(of: store.currentPath) { _ in
                    proxy.scrollTo("scrollTop", anchor: .top)
                    savedTopItemId = nil
                }
            }
            .onAppear {
                scrollViewHeight = geometry.size.height
            }
            .onChange(of: geometry.size) { newSize in
                scrollViewHeight = newSize.height
            }
        }
        .border(fsStore.isDropTargeted ? Color.accentColor : Color.clear, width: 2)
        .onDrop(
            of: [UTType.fileURL],
            delegate: FileDropDelegate(store: store, fsStore: fsStore)
        )
    }
}

// swiftlint:enable type_body_length
