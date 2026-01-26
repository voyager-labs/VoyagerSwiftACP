import ComposableArchitecture
import SwiftUI

struct ContentPaneListTableView: NSViewControllerRepresentable {
    let store: StoreOf<FileManagerFeature>

    func makeNSViewController(context _: Context) -> EntryListTableViewController {
        EntryListTableViewController(store: store)
    }

    func updateNSViewController(_: EntryListTableViewController, context _: Context) {
        // Store is reference-backed; controller subscribes to publishers.
    }
}
