import ComposableArchitecture
import SwiftUI

struct ContentPaneView: View {
    let store: StoreOf<FileManagerFeature>

    private var statusText: String {
        let total = store.fsItems.items.count
        let selected = store.fsItems.selectedIds.count

        if selected == 0 {
            return "\(total) items"
        } else {
            return "\(selected) of \(total) selected"
        }
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            switch store.viewLayout {
            case .list:
                ContentPaneListView(store: store)
            case .grid:
                ContentPaneGridView(store: store)
            }

            if !store.inspectorPaneExists {
                StatusBarButton(
                    text: statusText,
                    action: { store.send(.toggleInspector) }
                )
                .padding(.trailing, 24)
                .padding(.bottom, 20)
            }
        }
    }
}
