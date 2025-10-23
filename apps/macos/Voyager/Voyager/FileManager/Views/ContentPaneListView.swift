import ComposableArchitecture
import SwiftUI

struct ContentPaneListView: View {
    let store: StoreOf<FileManagerFeature>

    @State private var availableWidth: CGFloat = 0

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
                            LazyVStack(alignment: .leading, spacing: 4) {
                                if fsStore.groupKey == .none {
                                    ForEach(fsStore.items) { item in
                                        FSItemListView(
                                            item: item,
                                            isSelected: fsStore.selectedIds.contains(item.id),
                                            availableWidth: geometry.size.width,
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
                                                store.send(.openItem(id: item.id))
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

                                                let tagInfo = FSItemTagUtils.getTagInfo(group.groupName)

                                                if let color = tagInfo.color {
                                                    Circle()
                                                        .fill(color)
                                                        .frame(width: 8, height: 8)
                                                        .overlay(
                                                            Circle()
                                                                .stroke(Color.primary.opacity(0.2), lineWidth: 1)
                                                        )
                                                }

                                                Text(tagInfo.localizedName)
                                                    .font(.headline)
                                                    .foregroundColor(.primary)
                                                Spacer()
                                            }
                                            .padding(.horizontal, 8)
                                            .padding(.bottom, 4)
                                        }

                                        ForEach(group.items) { item in
                                            FSItemListView(
                                                item: item,
                                                isSelected: fsStore.selectedIds.contains(item.id),
                                                availableWidth: geometry.size.width,
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
                                                    store.send(.openItem(id: item.id))
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
                                fsStore.send(.clearSelection)
                            }
                        }
                        .onChange(of: fsStore.lastSelectedId) { newId in
                            if fsStore.shouldScrollToSelection, let id = newId {
                                proxy.scrollTo(id, anchor: nil)
                                fsStore.send(.resetScrollFlag)
                            }
                        }
                    }
                }
            }
        }
    }
}
