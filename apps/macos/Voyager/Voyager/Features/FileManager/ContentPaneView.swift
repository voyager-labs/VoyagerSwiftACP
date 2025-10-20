import ComposableArchitecture
import SwiftUI

struct ContentPaneView: View {
    let store: StoreOf<FileManagerFeature>

    var body: some View {
        ContentPaneListView(store: store)
    }
}
