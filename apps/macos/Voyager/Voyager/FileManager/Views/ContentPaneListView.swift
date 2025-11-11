import ComposableArchitecture
import SwiftUI
import UniformTypeIdentifiers

// swiftlint:disable type_body_length
struct ContentPaneListView: View {
    let store: StoreOf<FileManagerFeature>

    @State private var availableWidth: CGFloat = 0
    @State private var savedTopItemId: String?

    private func isNearTop(_ geometry: GeometryProxy) -> Bool {
        let frame = geometry.frame(in: .named("scrollView"))
        return frame.minY >= 0 && frame.minY < 30
    }

    private func sendWithSelection(
        _ item: FSItem,
        fsStore: Store<FSItemsFeature.State, FSItemsFeature.Action>,
        action: @escaping () -> Void
    ) {
        if !fsStore.selectedIds.contains(item.id) {
            fsStore.send(.selectItem(id: item.id, isCommandPressed: false, isShiftPressed: false))
        }
        action()
    }

    private func saveScrollPositionBeforeOpen() {
        if let topId = savedTopItemId {
            store.send(.saveTopVisibleItem(topId, forPath: store.currentPath))
        }
    }

    // swiftlint:disable function_body_length
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
        let containsZipFiles = selectedItems.contains { $0.fileExtension.lowercased() == "zip" }
        let containsNonZipFiles = selectedItems.contains { $0.fileExtension.lowercased() != "zip" }

        let showCompress = !containsZipFiles
        let showExtract = containsZipFiles && !containsNonZipFiles

        FSItemListView(
            item: item,
            isSelected: selectedIds.contains(item.id),
            isCut: clipboardItems.contains(item.fullPath) && fsStore.clipboardOperation == .cut,
            isRenaming: fsStore.renamingItemId == item.id,
            renamingText: fsStore.renamingText,
            availableWidth: geometry.size.width,
            applications: fsStore.operations.applicationsForItems[item.fullPath],
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
                sendWithSelection(item, fsStore: fsStore, action: {
                    saveScrollPositionBeforeOpen()
                    fsStore.send(.openSelectedItem)
                })
            },
            onOpenInNewTab: { shouldOpenInNewWindow in
                if item.isDirectory {
                    if shouldOpenInNewWindow {
                        AppDelegate.shared?.createNewWindow(path: item.fullPath)
                    } else {
                        AppDelegate.shared?.createNewTab(path: item.fullPath)
                    }
                }
            },
            onQuickLook: {
                sendWithSelection(item, fsStore: fsStore, action: {
                    fsStore.send(.quickLookSelectedItem)
                })
            },
            onOpenWithApp: { bundleID, shouldSetAsDefault in
                sendWithSelection(item, fsStore: fsStore, action: {
                    fsStore.send(.openWithSelectedItem(bundleID: bundleID, shouldSetAsDefault: shouldSetAsDefault))
                })
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
                let dragPaths = fsStore.selectedIds.isEmpty
                    ? [item.fullPath]
                    : fsStore.items.filter { fsStore.selectedIds.contains($0.id) }
                    .map { $0.fullPath }
                fsStore.send(.startDrag(paths: dragPaths))
            },
            onDrop: { providers, folderPath in
                fsStore.send(.handleDrop(providers: providers, destinationPath: folderPath))
            },
            onLoadApplications: {
                fsStore.send(.operations(.loadApplicationsForFile(file: item)))
            },
            onPutBack: isTrashFolder ? {
                sendWithSelection(item, fsStore: fsStore, action: {
                    fsStore.send(.putBackSelectedItems)
                })
            } : nil,
            onMoveToTrash: {
                sendWithSelection(item, fsStore: fsStore, action: {
                    fsStore.send(.moveSelectedItemsToTrash)
                })
            },
            onDeleteImmediately: {
                sendWithSelection(item, fsStore: fsStore, action: {
                    fsStore.send(.deleteSelectedItemsImmediately)
                })
            },
            onEmptyTrash: {
                store.send(.emptyTrash)
            },
            onRename: {
                sendWithSelection(item, fsStore: fsStore, action: {
                    fsStore.send(.startRename(id: item.id))
                })
            },
            onCompress: {
                sendWithSelection(item, fsStore: fsStore, action: {
                    fsStore.send(.compressSelectedItems)
                })
            },
            onDuplicate: {
                sendWithSelection(item, fsStore: fsStore, action: {
                    fsStore.send(.duplicateSelectedItems)
                })
            },
            onExtract: {
                sendWithSelection(item, fsStore: fsStore, action: {
                    fsStore.send(.extractSelectedItem)
                })
            },
            onCopy: {
                sendWithSelection(item, fsStore: fsStore, action: {
                    fsStore.send(.copySelectedItems)
                })
            },
            onCut: {
                sendWithSelection(item, fsStore: fsStore, action: {
                    fsStore.send(.cutSelectedItems)
                })
            },
            onToggleTag: { tag in
                sendWithSelection(item, fsStore: fsStore, action: {
                    fsStore.send(.toggleTagForSelectedItem(tag: tag))
                })
            },
            selectedCount: fsStore.selectedIds.isEmpty ? 1 : fsStore.selectedIds.count,
            showCompress: showCompress,
            showExtract: showExtract
        )
    }

    // swiftlint:enable function_body_length

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
                            Color.clear.frame(height: 0).id("scrollTop")
                            if fsStore.groupKey == .none {
                                ForEach(Array(fsStore.items.enumerated()), id: \.element.id) { index, item in
                                    itemRow(
                                        item: item,
                                        fsStore: fsStore,
                                        geometry: geometry,
                                        isTrashFolder: store.isTrashFolder
                                    )
                                    .background(index % 2 == 0 ? Color.clear : Color.primary.opacity(0.05))
                                    .background(
                                        GeometryReader { itemGeometry in
                                            Color.clear.preference(
                                                key: VisibleTopItemKey.self,
                                                value: isNearTop(itemGeometry) ? item.id : ""
                                            )
                                        }
                                    )
                                    .id(item.id)
                                }
                            } else {
                                ForEach(Array(fsStore.groupedItems.enumerated()),
                                        id: \.element.groupName)
                                { index, group in
                                    if index > 0 {
                                        Spacer()
                                            .frame(height: 16)
                                    }

                                    if !group.groupName.isEmpty && fsStore.groupKey != .name {
                                        HStack(spacing: 8) {
                                            Spacer()
                                                .frame(width: 28)

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

                                    ForEach(Array(group.items.enumerated()), id: \.element.id) { itemIndex, item in
                                        itemRow(
                                            item: item,
                                            fsStore: fsStore,
                                            geometry: geometry,
                                            isTrashFolder: store.isTrashFolder
                                        )
                                        .background(itemIndex % 2 == 0 ? Color.clear : Color.primary
                                            .opacity(0.05))
                                        .background(
                                            GeometryReader { itemGeometry in
                                                Color.clear.preference(
                                                    key: VisibleTopItemKey.self,
                                                    value: isNearTop(itemGeometry) ? item.id : ""
                                                )
                                            }
                                        )
                                        .id(item.id)
                                    }
                                }
                            }
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
                    .coordinateSpace(name: "scrollView")
                    .onPreferenceChange(VisibleTopItemKey.self) { topItemId in
                        guard !topItemId.isEmpty, topItemId != savedTopItemId else { return }
                        savedTopItemId = topItemId
                    }
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
                    .onChange(of: store.currentPath) { [oldPath = store.currentPath] _ in
                        if let topId = savedTopItemId {
                            store.send(.saveTopVisibleItem(topId, forPath: oldPath))
                        }
                        savedTopItemId = nil
                    }
                    .onChange(of: store.scrollTargetId) { targetId in
                        if let targetId = targetId {
                            proxy.scrollTo(targetId, anchor: .top)
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
