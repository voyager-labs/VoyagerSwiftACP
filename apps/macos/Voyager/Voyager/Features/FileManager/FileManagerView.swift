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
                if event.modifierFlags.isDisjoint(with: [.command, .option, .control]) {
                    let isShiftPressed = event.modifierFlags.contains(.shift)
                    if event.keyCode == 125 {
                        store.send(.fsItems(.selectNextItem(isShiftPressed: isShiftPressed)))
                        return
                    } else if event.keyCode == 126 {
                        store.send(.fsItems(.selectPreviousItem(isShiftPressed: isShiftPressed)))
                        return
                    }
                }

                guard event.modifierFlags.contains(.command) else { return }

                if event.characters == "a" {
                    store.send(.fsItems(.selectAll))
                } else if let number = Int(event.characters ?? ""), (1 ... 9).contains(number) {
                    AppDelegate.shared?.selectTab(at: number - 1)
                } else if event.characters == "0" {
                    AppDelegate.shared?.selectTab(at: 9)
                }
            }

            NavigationSplitView(columnVisibility: $columnVisibility) {
                SidebarView()
            } detail: {
                VStack(spacing: 0) {
                    HStack {
                        PathBreadcrumbView(
                            pathComponents: store.pathComponents,
                            onNavigate: { path in
                                store.send(.navigateTo(path))
                            }
                        )
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)

                    ContentPaneView(store: store)
                }
            }
            .navigationSplitViewStyle(.balanced)
            .frame(minWidth: 800, minHeight: 600)
            .navigationTitle(store.windowTitle)
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

            ToolbarItemGroup(placement: .primaryAction) {
                Picker("Layout", selection: Binding(
                    get: { store.viewLayout },
                    set: { store.send(.changeLayout($0)) }
                )) {
                    Label("List", systemImage: "list.bullet")
                        .tag(FileManagerFeature.ViewLayout.list)
                    Label("Grid", systemImage: "square.grid.2x2")
                        .tag(FileManagerFeature.ViewLayout.grid)
                }
                .pickerStyle(.segmented)
                .fixedSize()
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
