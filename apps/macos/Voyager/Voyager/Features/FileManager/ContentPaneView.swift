import ComposableArchitecture
import SwiftUI

struct ContentPaneView: View {
    let store: StoreOf<FileManagerFeature>

    var body: some View {
        switch store.viewLayout {
        case .list:
            ContentPaneListView(store: store)
        case .grid:
            ContentPaneGridView(store: store)
        }
    }
}
