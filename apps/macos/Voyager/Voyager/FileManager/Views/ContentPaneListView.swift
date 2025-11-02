import ComposableArchitecture
import SwiftUI
import UniformTypeIdentifiers

struct ContentPaneListView: View {
    let store: StoreOf<FileManagerFeature>

    @State private var availableWidth: CGFloat = 0

    private func sendWithSelection(
        _ item: FSItem,
        fsStore: Store<FSItemsFeature.State, FSItemsFeature.Action>,
        action: @escaping () -> Void
    ) {
        fsStore.send(.selectItem(id: item.id, isCommandPressed: false, isShiftPressed: false))
        action()
    }

    // swiftlint:disable function_body_length
    @ViewBuilder
    private func itemRow(
        item: FSItem,
        fsStore: Store<FSItemsFeature.State, FSItemsFeature.Action>,
        geometry: GeometryProxy
    ) -> FSItemListView {
        FSItemListView(
            item: item,
            isSelected: fsStore.selectedIds.contains(item.id),
            isCut: fsStore.clipboardItems.contains(item.fullPath) && fsStore.clipboardOperation == .cut,
            availableWidth: geometry.size.width,
            applications: fsStore.operations.applicationsForItems[item.fullPath],
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
                    fsStore.send(.openSelectedItem)
                })
            },
            onQuickLook: {
                sendWithSelection(item, fsStore: fsStore, action: {
                    fsStore.send(.quickLookSelectedItem)
                })
            },
            onOpenWithApp: { bundleID in
                sendWithSelection(item, fsStore: fsStore, action: {
                    fsStore.send(.openWithSelectedItem(bundleID: bundleID))
                })
            },
            onSetDefaultApp: { bundleID, type in
                sendWithSelection(item, fsStore: fsStore, action: {
                    fsStore.send(.setDefaultAppForSelectedItem(
                        bundleID: bundleID,
                        type: type
                    ))
                })
            },
            onSetDefaultAppWithOther: {
                sendWithSelection(item, fsStore: fsStore, action: {
                    fsStore.send(.setDefaultAppWithOtherForSelectedItem)
                })
            },
            onStartDrag: {
                let dragPaths = fsStore.selectedIds.isEmpty
                    ? [item.fullPath]
                    : fsStore.items.filter { fsStore.selectedIds.contains($0.id) }
                    .map { $0.fullPath }
                fsStore.send(.startDrag(paths: dragPaths))
            },
            onDrop: { folderPath in
                fsStore.send(.dropToFolder(destinationPath: folderPath))
            }
        )
    }

    // swiftlint:enable function_body_length

    var body: some View {
        let fsStore = store.scope(state: \.fsItems, action: \.fsItems)

        if fsStore.isLoading {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
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
                                if fsStore.groupKey == .none {
                                    ForEach(Array(fsStore.items.enumerated()), id: \.element.id) { index, item in
                                        itemRow(item: item, fsStore: fsStore, geometry: geometry)
                                            .background(index % 2 == 0 ? Color.clear : Color.primary.opacity(0.05))
                                            .id(item.id)
                                            .task {
                                                if !item.isDirectory {
                                                    fsStore.send(.operations(.loadApplicationsForFile(file: item)))
                                                }
                                            }
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

                                                let tagColor = FSItemTagUtils.getTagColor(group.groupName)

                                                if let color = tagColor {
                                                    Circle()
                                                        .fill(color)
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
                                            itemRow(item: item, fsStore: fsStore, geometry: geometry)
                                                .background(itemIndex % 2 == 0 ? Color.clear : Color.primary
                                                    .opacity(0.05))
                                                .id(item.id)
                                                .task {
                                                    if !item.isDirectory {
                                                        fsStore.send(.operations(.loadApplicationsForFile(file: item)))
                                                    }
                                                }
                                        }
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                fsStore.send(.clearSelection)
                            }
                        }
                        .contextMenu {
                            Button("New Folder") {
                                store.send(.fsItems(.operations(.createNewFolder(path: store.currentPath))))
                            }
                            .keyboardShortcut("n", modifiers: [.command, .shift])
                        }
                        .onChange(of: fsStore.lastSelectedId) { newId in
                            if fsStore.shouldScrollToSelection, let id = newId {
                                proxy.scrollTo(id, anchor: nil)
                                fsStore.send(.resetScrollFlag)
                            }
                        }
                    }
                    .onDrop(of: [UTType.fileURL.identifier], isTargeted: nil) { _, _ in
                        fsStore.send(.dropToFolder(destinationPath: store.currentPath))
                        return true
                    }
                }
            }
        }
    }
}
