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

            HStack(spacing: 0) {
                if store.sidebarVisible {
                    SidebarView(store: store)
                        .frame(width: 220)
                        .ignoresSafeArea(.all, edges: .top)
                }

                VStack(alignment: .leading, spacing: 0) {
                    CustomToolbarView(store: store)
                    ContentPaneView(store: store)
                }
                .ignoresSafeArea(.all, edges: .top)
            }
            .frame(minWidth: 600, minHeight: 350)
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
