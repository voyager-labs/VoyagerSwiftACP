import ComposableArchitecture
import SwiftUI

struct ContentPaneGridView: View {
    let store: StoreOf<FileManagerFeature>

    private let columns = [
        GridItem(.adaptive(minimum: 100, maximum: 120), spacing: 16),
    ]

    var body: some View {
        let fsStore = store.scope(state: \.fsItems, action: \.fsItems)

        if fsStore.isLoading {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(fsStore.items) { item in
                            FSItemGridCell(
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
                    .padding(16)
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
