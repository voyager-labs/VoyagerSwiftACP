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
                    let row = (store.viewLayout == .grid && store.gridColumnCount > 1) ? store.gridColumnCount : 1

                    @MainActor
                    func move(_ offset: Int) {
                        if offset == 1 {
                            store.send(.fsItems(.selectNextItem(isShiftPressed: isShiftPressed)))
                        } else if offset == -1 {
                            store.send(.fsItems(.selectPreviousItem(isShiftPressed: isShiftPressed)))
                        } else {
                            store.send(.fsItems(.selectByOffset(offset: offset, isShiftPressed: isShiftPressed)))
                        }
                    }

                    switch event.keyCode {
                    case 123 where store.viewLayout == .grid: move(-1) // ←
                    case 124 where store.viewLayout == .grid: move(+1) // →
                    case 126: move(-row) // ↑
                    case 125: move(+row) // ↓
                    default: break
                    }
                    return
                }

                guard event.modifierFlags.contains(.command) else { return }

                if event.characters == "a" {
                    store.send(.fsItems(.selectAll))
                } else if event.characters == "." && event.modifierFlags.contains(.shift) {
                    store.send(.toggleShowHiddenFiles)
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

                Menu {
                    Menu("Sort By") {
                        Button(
                            action: { store.send(.changeSortKey(.name)) },
                            label: {
                                HStack {
                                    Text("Name")
                                    if store.sortKey == .name {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        )
                        Button(
                            action: { store.send(.changeSortKey(.size)) },
                            label: {
                                HStack {
                                    Text("Size")
                                    if store.sortKey == .size {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        )
                        Button(
                            action: { store.send(.changeSortKey(.modified)) },
                            label: {
                                HStack {
                                    Text("Date Modified")
                                    if store.sortKey == .modified {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        )
                        Button(
                            action: { store.send(.changeSortKey(.type)) },
                            label: {
                                HStack {
                                    Text("Type")
                                    if store.sortKey == .type {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        )

                        Divider()

                        Button(
                            action: { store.send(.changeSortOrder(.ascending)) },
                            label: {
                                HStack {
                                    Text("Ascending")
                                    if store.sortOrder == .ascending {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        )

                        Button(
                            action: { store.send(.changeSortOrder(.descending)) },
                            label: {
                                HStack {
                                    Text("Descending")
                                    if store.sortOrder == .descending {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        )
                    }
                } label: {
                    Image(systemName: "ellipsis")
                }
                .menuIndicator(.hidden)
                .frame(minWidth: 32)
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
