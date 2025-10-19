import ComposableArchitecture
import SwiftUI

struct ContentPaneView: View {
    let store: StoreOf<FileManagerFeature>

    var body: some View {
        let store = store.scope(state: \.fsItems, action: \.fsItems)

        if store.isLoading {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(store.items) { item in
                            FSItemRowView(
                                item: item,
                                isSelected: store.selectedIds.contains(item.id),
                                onSelect: {
                                    let isCommandPressed = NSEvent.modifierFlags.contains(.command)
                                    let isShiftPressed = NSEvent.modifierFlags.contains(.shift)
                                    store.send(.selectItem(
                                        id: item.id,
                                        isCommandPressed: isCommandPressed,
                                        isShiftPressed: isShiftPressed
                                    ))
                                },
                                onOpen: {
                                    self.store.send(.openItem(id: item.id))
                                }
                            )
                            .id(item.id)
                        }
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        store.send(.clearSelection)
                    }
                }
                .onChange(of: store.lastSelectedId) { newId in
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
