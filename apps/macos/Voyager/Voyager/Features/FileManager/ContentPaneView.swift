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
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(store.items) { item in
                        FSItemRowView(
                            item: item,
                            isSelected: store.selectedIds.contains(item.id),
                            onSelect: {
                                let isCommandPressed = NSEvent.modifierFlags.contains(.command)
                                store.send(.selectItem(id: item.id, isCommandPressed: isCommandPressed))
                            },
                            onOpen: {
                                self.store.send(.openItem(id: item.id))
                            }
                        )
                    }
                }
                .padding(8)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .contentShape(Rectangle())
                .onTapGesture {
                    store.send(.clearSelection)
                }
            }
        }
    }
}
