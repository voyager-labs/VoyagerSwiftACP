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
                if event.keyCode == 49 && event.modifierFlags.isDisjoint(with: [.command, .option, .control, .shift]) {
                    if store.canQuickLookSelectedItem {
                        store.send(.quickLookSelectedItem)
                    }
                    return
                }

                if event.modifierFlags.isDisjoint(with: [.command, .option, .control]) {
                    let isShiftPressed = event.modifierFlags.contains(.shift)

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
                    case 126: move(-1) // ↑
                    case 125: move(+1) // ↓
                    default: break
                    }
                    return
                }

                guard event.modifierFlags.contains(.command) else { return }

                if event.characters == "a" {
                    store.send(.fsItems(.selectAll))
                } else if event.characters == "c" {
                    store.send(.fsItems(.copySelectedItems))
                } else if event.characters == "x" {
                    store.send(.fsItems(.cutSelectedItems))
                } else if event.characters == "v" {
                    store.send(.fsItems(.pasteItems(destinationPath: store.currentPath)))
                } else if event.characters == "." && event.modifierFlags.contains(.shift) {
                    store.send(.toggleShowHiddenFiles)
                } else if let number = Int(event.characters ?? ""), (1 ... 9).contains(number) {
                    AppDelegate.shared?.selectTab(at: number - 1)
                } else if event.characters == "0" {
                    AppDelegate.shared?.selectTab(at: 9)
                }
            }

            NavigationSplitView(columnVisibility: $columnVisibility) {
                SidebarView(store: store)
            } detail: {
                VStack(spacing: 0) {
                    HStack {
                        PathBreadcrumbView(
                            pathComponents: store.pathComponents,
                            selectedItem: store.fsItems.selectedIds.count == 1
                                ? store.fsItems.items.first(where: { $0.id == store.fsItems.selectedIds.first })
                                : nil,
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
            .frame(minWidth: 600, minHeight: 350)
            .navigationTitle(store.windowTitle)
        }
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                Menu {
                    if store.backHistory.isEmpty {
                        Text("No history")
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(0 ..< store.backHistory.count, id: \.self) { index in
                            let reversedIndex = store.backHistory.count - 1 - index
                            Button(
                                action: {
                                    store.send(.goToHistoryIndex(index, isBackHistory: true))
                                },
                                label: {
                                    Text(FileManager.default.displayName(atPath: store.backHistory[reversedIndex]))
                                }
                            )
                        }
                    }
                } label: {
                    Image(systemName: "chevron.left")
                } primaryAction: {
                    store.send(.goBack)
                }
                .menuIndicator(.hidden)
                .disabled(!store.canGoBack)

                Menu {
                    if store.forwardHistory.isEmpty {
                        Text("No history")
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(0 ..< store.forwardHistory.count, id: \.self) { index in
                            let reversedIndex = store.forwardHistory.count - 1 - index
                            Button(
                                action: {
                                    store.send(.goToHistoryIndex(index, isBackHistory: false))
                                },
                                label: {
                                    Text(FileManager.default.displayName(atPath: store.forwardHistory[reversedIndex]))
                                }
                            )
                        }
                    }
                } label: {
                    Image(systemName: "chevron.right")
                } primaryAction: {
                    store.send(.goForward)
                }
                .menuIndicator(.hidden)
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

                ToolbarMenuView(store: store)
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

            store.send(.loadLocations)
        }
    }
}
