import AppKit
import ComposableArchitecture
import SwiftUI

struct ViewMenuCommands: Commands {
    @ObservedObject private var fileManagerWindowCoordinator: FileManagerWindowCoordinator

    init() {
        fileManagerWindowCoordinator = FileManagerWindowCoordinator.shared
    }

    var body: some Commands {
        CommandGroup(replacing: .sidebar) {
            Button(
                fileManagerWindowCoordinator.currentFileManagerStore?.sidebarVisible == true
                    ? "Hide Sidebar"
                    : "Show Sidebar",
            ) {
                let newValue = !(fileManagerWindowCoordinator.currentFileManagerStore?.sidebarVisible ?? true)
                fileManagerWindowCoordinator.currentFileManagerStore?.send(.setSidebarVisible(newValue))
            }
            .keyboardShortcut("s", modifiers: [.command, .control])
            .disabled(fileManagerWindowCoordinator.currentFileManagerStore == nil)
            Button(
                fileManagerWindowCoordinator.currentFileManagerStore?.showHiddenFiles == true
                    ? "Hide Hidden Files"
                    : "Show Hidden Files",
            ) {
                fileManagerWindowCoordinator.currentFileManagerStore?.send(.toggleShowHiddenFiles)
            }
            .keyboardShortcut(".", modifiers: [.command, .shift])
            .disabled(fileManagerWindowCoordinator.currentFileManagerStore == nil)
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

                Toggle("Name", isOn: groupKeyToggleBinding(.name))
                Toggle("Kind", isOn: groupKeyToggleBinding(.kind))
                Toggle("Application", isOn: groupKeyToggleBinding(.application))
                Toggle("Date Last Opened", isOn: groupKeyToggleBinding(.dateLastOpened))
                Toggle("Date Added", isOn: groupKeyToggleBinding(.dateAdded))
                Toggle("Date Modified", isOn: groupKeyToggleBinding(.dateModified))
                Toggle("Date Created", isOn: groupKeyToggleBinding(.dateCreated))
                Toggle("Size", isOn: groupKeyToggleBinding(.size))
                Toggle("Tags", isOn: groupKeyToggleBinding(.tags))
            }

            Menu("Sort By") {
                Toggle("Name", isOn: sortKeyToggleBinding(.name))
                Toggle("Kind", isOn: sortKeyToggleBinding(.kind))
                Toggle("Application", isOn: sortKeyToggleBinding(.application))
                Toggle("Date Last Opened", isOn: sortKeyToggleBinding(.dateLastOpened))
                Toggle("Date Added", isOn: sortKeyToggleBinding(.dateAdded))
                Toggle("Date Modified", isOn: sortKeyToggleBinding(.dateModified))
                Toggle("Date Created", isOn: sortKeyToggleBinding(.dateCreated))
                Toggle("Size", isOn: sortKeyToggleBinding(.size))
                Toggle("Tags", isOn: sortKeyToggleBinding(.tags))

                Divider()

                Toggle("Ascending", isOn: sortOrderToggleBinding(.ascending))
                Toggle("Descending", isOn: sortOrderToggleBinding(.descending))
            }
            .disabled(fileManagerWindowCoordinator.currentFileManagerStore?.entries.groupKey != GroupKey.none)
        }
    }

    private func viewLayoutToggleBinding(_ layout: ContentViewLayout) -> Binding<Bool> {
        Binding(
            get: { fileManagerWindowCoordinator.currentFileManagerStore?.viewLayout == layout },
            set: { isOn in
                guard isOn else { return }
                fileManagerWindowCoordinator.currentFileManagerStore?.send(.changeLayout(layout))
            },
        )
    }

    private func groupKeyToggleBinding(_ key: GroupKey) -> Binding<Bool> {
        Binding(
            get: { fileManagerWindowCoordinator.currentFileManagerStore?.entries.groupKey == key },
            set: { isOn in
                guard isOn else { return }
                fileManagerWindowCoordinator.currentFileManagerStore?.send(.changeGroupKey(key))
            },
        )
    }

    private func sortKeyToggleBinding(_ key: SortKey) -> Binding<Bool> {
        Binding(
            get: { fileManagerWindowCoordinator.currentFileManagerStore?.sortKey == key },
            set: { isOn in
                guard isOn else { return }
                fileManagerWindowCoordinator.currentFileManagerStore?.send(.changeSortKey(key))
            },
        )
    }

    private func sortOrderToggleBinding(_ order: SortOrder) -> Binding<Bool> {
        Binding(
            get: { fileManagerWindowCoordinator.currentFileManagerStore?.sortOrder == order },
            set: { isOn in
                guard isOn else { return }
                fileManagerWindowCoordinator.currentFileManagerStore?.send(.changeSortOrder(order))
            },
        )
    }
}
