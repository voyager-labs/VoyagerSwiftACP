import Combine
import ComposableArchitecture
import SwiftUI

public struct ItemsContainerView: View {
    public let rootURL: URL

    @EnvironmentObject private var selectionModel: FSItemSelectionModel

    @State private var items: [FSItemFeature.State]
    @State private var selection: FSItemFeature.State.ID?

    public init(
        rootURL: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads")
    ) {
        self.rootURL = rootURL
        _items = State(initialValue: Self.loadItems(from: rootURL))
    }

    public var body: some View {
        List(selection: $selection) {
            ForEach(items) { item in
                FSItemView(
                    store: Store(
                        initialState: item,
                        reducer: { FSItemFeature() }
                    )
                )
                .tag(item.id)
            }
        }
        .onAppear {
            items = Self.loadItems(from: rootURL)
            selectionModel.rootURL = rootURL
            if let item = items.first {
                selection = item.id
                selectionModel.selectedItem = item
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .fsItemDirectoryDidChange)) { notification in
            guard let changedURL = notification.object as? URL, changedURL == rootURL else { return }
            items = Self.loadItems(from: rootURL)
            if let selectedID = selection, let updated = items.first(where: { $0.id == selectedID }) {
                selectionModel.selectedItem = updated
            } else if selectionModel.selectedItem == nil {
                selectionModel.selectedItem = items.first
                selection = items.first?.id
            }
        }
        .onChange(of: selection) { newID in
            if let id = newID, let item = items.first(where: { $0.id == id }) {
                selectionModel.selectedItem = item
            } else {
                selectionModel.selectedItem = nil
            }
        }
    }

    private static func loadItems(from directory: URL) -> [FSItemFeature.State] {
        let fileManager = FileManager.default
        guard
            let contents = try? fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )
        else {
            return []
        }

        return contents.map { url in
            let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            return FSItemFeature.State(
                id: UUID(),
                url: url,
                displayName: url.lastPathComponent,
                isDirectory: isDirectory
            )
        }
    }
}

struct ItemsContainerView_Previews: PreviewProvider {
    static var previews: some View {
        ItemsContainerView()
            .frame(width: 480, height: 320)
    }
}
