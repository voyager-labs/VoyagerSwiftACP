import ComposableArchitecture
import SwiftUI

struct ContentPaneGridCollectionView: NSViewControllerRepresentable {
    let store: StoreOf<FileManagerFeature>

    func makeNSViewController(context _: Context) -> EntryGridCollectionViewController {
        EntryGridCollectionViewController(store: store)
    }

    func updateNSViewController(_: EntryGridCollectionViewController, context _: Context) {
        // Store는 reference-backed; 컨트롤러가 퍼블리셔를 구독한다.
    }
}
