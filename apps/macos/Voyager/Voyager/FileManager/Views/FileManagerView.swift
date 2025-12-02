import ComposableArchitecture
import SwiftUI

struct FileManagerView: View {
    let store: StoreOf<FileManagerFeature>
    let initialPath: String?

    @FocusState private var isKeyCommandFocused: Bool

    init(store: StoreOf<FileManagerFeature>, initialPath: String? = nil) {
        self.store = store
        self.initialPath = initialPath
    }

    private var columnVisibility: Binding<NavigationSplitViewVisibility> {
        Binding(
            get: { store.sidebarVisible ? .all : .detailOnly },
            set: { newValue in
                store.send(.setSidebarVisible(newValue == .all))
            }
        )
    }

    var body: some View {
        ZStack {
            KeyCommandView { event in
                if event.keyCode == 53 && store.fsItems.isRenaming {
                    store.send(.fsItems(.cancelRename))
                    return
                }

                if event.keyCode == 36 && event.modifierFlags.isDisjoint(with: [.command, .option, .control, .shift]) {
                    if store.fsItems.isRenaming {
                        store.send(.fsItems(.commitRename))
                        return
                    }

                    if store.fsItems.selectedIds.count == 1,
                       let selectedId = store.fsItems.selectedIds.first
                    {
                        store.send(.fsItems(.startRename(id: selectedId)))
                    }
                    return
                }

                if event.keyCode == 49 && event.modifierFlags.isDisjoint(with: [.command, .option, .control, .shift]) {
                    if store.canQuickLookSelectedItem {
                        store.send(.quickLookSelectedItem)
                    }
                    return
                }

                if event.keyCode == 125 && event.modifierFlags.contains(.command) && event.modifierFlags
                    .contains(.option)
                {
                    if store.fsItems.selectedIds.count == 1,
                       let selectedId = store.fsItems.selectedIds.first,
                       let selectedItem = store.fsItems.items.first(where: { $0.id == selectedId }),
                       selectedItem.isDirectory
                    {
                        AppDelegate.shared?.createNewTab(path: selectedItem.fullPath)
                    }
                    return
                }

                if event.keyCode == 51 && event.modifierFlags.contains(.command) && event.modifierFlags
                    .contains(.option)
                {
                    if !store.fsItems.selectedIds.isEmpty {
                        store.send(.deleteSelectedItemsImmediately)
                    }
                    return
                }

                if event.keyCode == 51 && event.modifierFlags.contains(.command) && !event.modifierFlags
                    .contains(.option)
                {
                    if !store.fsItems.selectedIds.isEmpty {
                        store.send(.moveSelectedItemsToTrash)
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
                    case 126 where store.viewLayout == .grid: // ↑ Grid 행 이동
                        let columnCount = store.fsItems.gridColumnCount
                        move(-columnCount)
                    case 125 where store.viewLayout == .grid: // ↓ Grid 행 이동
                        let columnCount = store.fsItems.gridColumnCount
                        move(+columnCount)
                    case 126: move(-1) // ↑ List
                    case 125: move(+1) // ↓ List
                    default: break
                    }
                    return
                }

                guard event.modifierFlags.contains(.command) else { return }

                if event.characters == "." && event.modifierFlags.contains(.shift) {
                    store.send(.toggleShowHiddenFiles)
                } else if let number = Int(event.characters ?? ""), (1 ... 9).contains(number) {
                    AppDelegate.shared?.selectTab(at: number - 1)
                } else if event.characters == "0" {
                    AppDelegate.shared?.selectTab(at: 9)
                }
            }
            .focusable()
            .focused($isKeyCommandFocused)

            NavigationSplitView(columnVisibility: columnVisibility) {
                SidebarView(store: store)
            } detail: {
                VStack(spacing: 0) {
                    GeometryReader { geometry in
                        HStack {
                            PathBreadcrumbView(
                                breadcrumbItems: store.breadcrumbItems,
                                selectedItem: store.selectedBreadcrumbItem,
                                availableWidth: geometry.size.width - 32 - (store.isTrashFolder ? 80 : 0),
                                onNavigate: { path in
                                    store.send(.navigateTo(path))
                                }
                            )
                            Spacer()

                            if store.isTrashFolder {
                                Button("Empty") {
                                    store.send(.emptyTrash)
                                }
                                .controlSize(.small)
                                .buttonStyle(.borderedProminent)
                                .tint(Color(white: 0.3))
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                    }
                    .frame(height: 36)

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
        .onChange(of: store.fsItems.isRenaming) { isRenaming in
            if !isRenaming {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    isKeyCommandFocused = true
                }
            }
        }
        .onAppear {
            store.send(.loadFavorites)
            store.send(.loadLocations)
            store.send(.loadTags)

            if let path = initialPath {
                store.send(.navigateTo(path))
            } else {
                store.send(.onAppear)
            }

            store.send(.fsItems(.onAppear))

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                isKeyCommandFocused = true
            }
        }
    }
}
