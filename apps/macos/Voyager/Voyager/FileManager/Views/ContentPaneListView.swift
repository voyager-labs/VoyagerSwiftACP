import ComposableArchitecture
import SwiftUI

struct ContentPaneListView: View {
    let store: StoreOf<FileManagerFeature>

    var body: some View {
        let fsStore = store.scope(state: \.fsItems, action: \.fsItems)

        if fsStore.isLoading {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(fsStore.items) { item in
                            FSItemListView(
                                item: item,
                                isSelected: fsStore.selectedIds.contains(item.id),
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
                    .padding(8)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        fsStore.send(.clearSelection)
                    }
                }
                .onChange(of: fsStore.lastSelectedId) { newId in
                    if let id = newId {
                        withAnimation {
                            proxy.scrollTo(id, anchor: .center)
                        }
                    }
                }
            }
        }
    }
}
