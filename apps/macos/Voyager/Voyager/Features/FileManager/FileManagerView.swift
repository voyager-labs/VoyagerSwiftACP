import ComposableArchitecture
import SwiftUI

struct FileManagerView: View {
    let store: StoreOf<FileManagerFeature>
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    init() {
        store = Store(initialState: FileManagerFeature.State()) {
            FileManagerFeature()
        }
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView()
        } detail: {
            ContentPaneView(store: store)
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 800, minHeight: 600)
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                Button {
                    store.send(.goBack)
                } label: {
                    Image(systemName: "chevron.left")
                }
                .disabled(!store.canGoBack)

                Button {
                    store.send(.goForward)
                } label: {
                    Image(systemName: "chevron.right")
                }
                .disabled(!store.canGoForward)
            }

            ToolbarItem(placement: .principal) {
                Text(store.currentPath)
                    .font(.headline)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .focusedSceneValue(\.fileManagerStore, store)
        .focusedSceneValue(\.columnVisibility, $columnVisibility)
        .onChange(of: columnVisibility) { newValue in
            UserDefaults.standard.set(newValue == .all, forKey: "sidebarVisible")
        }
        .onAppear {
            let savedVisible = UserDefaults.standard.object(forKey: "sidebarVisible") as? Bool ?? true
            columnVisibility = savedVisible ? .all : .detailOnly
            store.send(.onAppear)
        }
    }
}
