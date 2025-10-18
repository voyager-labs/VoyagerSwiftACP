import ComposableArchitecture
import SwiftUI

struct FileManagerView: View {
    let store: StoreOf<FileManagerFeature>
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    let initialPath: String?

    init(store: StoreOf<FileManagerFeature>, initialPath: String? = nil) {
        self.store = store
        self.initialPath = initialPath
    }

    var body: some View {
        ZStack {
            KeyCommandView { event in
                guard event.modifierFlags.contains(.command) else { return }

                if let number = Int(event.characters ?? ""), (1 ... 9).contains(number) {
                    if let window = NSApp.keyWindow,
                       let tabGroup = window.tabGroup,
                       number <= tabGroup.windows.count
                    {
                        tabGroup.windows[number - 1].makeKeyAndOrderFront(nil)
                    }
                }
            }

            NavigationSplitView(columnVisibility: $columnVisibility) {
                SidebarView()
            } detail: {
                ContentPaneView(store: store)
            }
            .navigationSplitViewStyle(.balanced)
            .frame(minWidth: 800, minHeight: 600)
        }
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

            if let path = initialPath {
                store.send(.navigateTo(path))
            } else {
                store.send(.onAppear)
            }
        }
    }
}
