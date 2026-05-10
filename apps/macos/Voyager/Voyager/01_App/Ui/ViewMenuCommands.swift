import AppKit
import ComposableArchitecture
import SwiftUI
import VoyagerFeaturesEntryArrangements
import VoyagerShared

@ViewAction(for: MenuCommandsFeature.self)
struct ViewMenuCommands: Commands {
    let store: StoreOf<MenuCommandsFeature>

    @ObservedObject private var viewStore: ViewStore<MenuCommandsState, MenuCommandsAction>

    init(appRootStore: StoreOf<AppRootFeature>) {
        let menuStore = appRootStore.scope(state: \.menuCommands, action: \.menuCommands)
        store = menuStore
        viewStore = ViewStore(
            menuStore,
            observe: { $0 },
        )
    }

    var body: some Commands {
        CommandGroup(replacing: .sidebar) {
            Button(viewStore.sidebarVisible ? "Hide Sidebar" : "Show Sidebar") {
                sendViewCommand(.toggleSidebar)
            }
            .keyboardShortcut("s", modifiers: [.command, .control])
            .disabled(!viewStore.hasFocusedWindow)

            Button(viewStore.showHiddenFiles ? "Hide Hidden Files" : "Show Hidden Files") {
                sendViewCommand(.toggleShowHiddenFiles)
            }
            .keyboardShortcut(".", modifiers: [.command, .shift])
            .disabled(!viewStore.hasFocusedWindow)

            Divider()
        }

        CommandGroup(after: .toolbar) {
            Divider()
            Toggle(isOn: viewLayoutToggleBinding(.list)) {
                Label("as List", systemImage: "list.bullet")
            }
            Toggle(isOn: viewLayoutToggleBinding(.grid)) {
                Label("as Icon", systemImage: "square.grid.2x2")
            }

            Divider()

            Menu("Group By") {
                Toggle("None", isOn: groupKeyToggleBinding(.none))

                Divider()

                ForEach(EntryArrangementMenuItems.groupItems) { item in
                    Toggle(item.title, isOn: groupKeyToggleBinding(item.key))
                }
            }

            Menu("Sort By") {
                ForEach(EntryArrangementMenuItems.sortItems) { item in
                    Toggle(item.title, isOn: sortKeyToggleBinding(item.key))
                }

                Divider()

                Toggle("Ascending", isOn: sortOrderToggleBinding(.ascending))
                Toggle("Descending", isOn: sortOrderToggleBinding(.descending))
            }
            .disabled(viewStore.groupKey != GroupKey.none)
        }
    }

    private func viewLayoutToggleBinding(_ layout: EntryViewLayoutState.Mode) -> Binding<Bool> {
        Binding(
            get: { viewStore.viewLayout == layout },
            set: { isOn in
                guard isOn else { return }
                sendViewCommand(.setViewLayout(layout))
            },
        )
    }

    private func groupKeyToggleBinding(_ key: GroupKey) -> Binding<Bool> {
        Binding(
            get: { viewStore.groupKey == key },
            set: { isOn in
                guard isOn else { return }
                sendViewCommand(.setGroupKey(key))
            },
        )
    }

    private func sortKeyToggleBinding(_ key: SortKey) -> Binding<Bool> {
        Binding(
            get: { viewStore.sortKey == key },
            set: { isOn in
                guard isOn else { return }
                sendViewCommand(.setSortKey(key))
            },
        )
    }

    private func sortOrderToggleBinding(_ order: VoyagerShared.SortOrder) -> Binding<Bool> {
        Binding(
            get: { viewStore.sortOrder == order },
            set: { isOn in
                guard isOn else { return }
                sendViewCommand(.setSortOrder(order))
            },
        )
    }

    private func sendViewCommand(_ command: MenuCommandItem.ViewCommand) {
        send(.viewCommand(command))
    }
}
