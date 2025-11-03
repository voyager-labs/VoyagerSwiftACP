import ComposableArchitecture
import SwiftUI
import UniformTypeIdentifiers

struct ContentPaneGridView: View {
    let store: StoreOf<FileManagerFeature>

    private let itemMinWidth: CGFloat = 100
    private let itemMaxWidth: CGFloat = 120
    private let itemSpacing: CGFloat = 20
    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: itemMinWidth, maximum: itemMaxWidth), spacing: itemSpacing)]
    }

    var body: some View {
        let fsStore = store.scope(state: \.fsItems, action: \.fsItems)

        ScrollViewReader { proxy in
            ScrollView {
                ZStack {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if fsStore.isRenaming {
                                fsStore.send(.commitRename)
                            }
                            fsStore.send(.clearSelection)
                        }

                    LazyVStack(alignment: .leading, spacing: 16) {
                        if fsStore.groupKey == .none {
                            LazyVGrid(columns: columns, spacing: 16) {
                                ForEach(fsStore.items) { item in
                                    FSItemGridView(
                                        item: item,
                                        isSelected: fsStore.selectedIds.contains(item.id),
                                        isCut: fsStore.clipboardItems.contains(item.fullPath) && fsStore
                                            .clipboardOperation == .cut,
                                        isRenaming: fsStore.renamingItemId == item.id,
                                        renamingText: fsStore.renamingText,
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
                                    .id(item.id)
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
                                        let tagColor = FSItemTagUtils.getTagColor(group.groupName)
                                        if let color = tagColor {
                                            Circle()
                                                .fill(color)
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
                                            isSelected: fsStore.selectedIds.contains(item.id),
                                            isCut: fsStore.clipboardItems.contains(item.fullPath) && fsStore
                                                .clipboardOperation == .cut,
                                            isRenaming: fsStore.renamingItemId == item.id,
                                            renamingText: fsStore.renamingText,
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
                                        .id(item.id)
                                    }
                                }
                            }
                        }
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
            }
            .animation(.easeInOut(duration: 0.15), value: fsStore.items)
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
