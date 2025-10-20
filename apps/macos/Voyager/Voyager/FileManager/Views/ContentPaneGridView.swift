import ComposableArchitecture
import SwiftUI

struct ContentPaneGridView: View {
    let store: StoreOf<FileManagerFeature>

    private let itemMinWidth: CGFloat = 100
    private let itemMaxWidth: CGFloat = 120
    private let itemSpacing: CGFloat = 16
    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: itemMinWidth, maximum: itemMaxWidth), spacing: itemSpacing)]
    }

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
                            FSItemGridView(
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
                    .background(
                        GeometryReader { geo in
                            Color.clear
                                .onAppear {
                                    let count = max(
                                        1,
                                        Int((geo.size.width - 32 + itemSpacing) / (itemMinWidth + itemSpacing))
                                    )
                                    store.send(.updateGridColumnCount(count))
                                }
                                .onChange(of: geo.size.width) { newWidth in
                                    let count = max(
                                        1,
                                        Int((newWidth - 32 + itemSpacing) / (itemMinWidth + itemSpacing))
                                    )
                                    store.send(.updateGridColumnCount(count))
                                }
                        }
                    )
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
