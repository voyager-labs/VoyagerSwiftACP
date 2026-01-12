import AppKit
import ComposableArchitecture
import SwiftUI

struct ViewMenuCommands: Commands {
    @ObservedObject private var appDelegate: AppDelegate

    init() {
        guard let shared = AppDelegate.shared else {
            fatalError("AppDelegate.shared must be initialized before ViewMenuCommands")
        }
        _appDelegate = ObservedObject(wrappedValue: shared)
    }

    var body: some Commands {
        CommandGroup(replacing: .sidebar) {
            Button(
                appDelegate.currentFileManagerStore?.sidebarVisible == true
                    ? "Hide Sidebar"
                    : "Show Sidebar",
            ) {
                let newValue = !(appDelegate.currentFileManagerStore?.sidebarVisible ?? true)
                appDelegate.currentFileManagerStore?.send(.setSidebarVisible(newValue))
            }
            .keyboardShortcut("s", modifiers: [.command, .control])
            .disabled(appDelegate.currentFileManagerStore == nil)
            Button(
                appDelegate.currentFileManagerStore?.showHiddenFiles == true
                    ? "Hide Hidden Files"
                    : "Show Hidden Files",
            ) {
                appDelegate.currentFileManagerStore?.send(.toggleShowHiddenFiles)
            }
            .keyboardShortcut(".", modifiers: [.command, .shift])
            .disabled(appDelegate.currentFileManagerStore == nil)
            Divider()
        }

        CommandGroup(after: .toolbar) {
            Divider()
            Toggle(isOn: viewLayoutToggleBinding(.list)) {
                Label("as List", systemImage: "list.bullet")
            }
            Toggle(isOn: viewLayoutToggleBinding(.grid)) {
                Label("as Grid", systemImage: "square.grid.2x2")
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
            .disabled(appDelegate.currentFileManagerStore?.fsItems.groupKey != GroupKey.none)
        }
    }

    private func viewLayoutToggleBinding(_ layout: FileManagerFeature.ViewLayout) -> Binding<Bool> {
        Binding(
            get: { appDelegate.currentFileManagerStore?.viewLayout == layout },
            set: { isOn in
                guard isOn else { return }
                appDelegate.currentFileManagerStore?.send(.changeLayout(layout))
            },
        )
    }

    private func groupKeyToggleBinding(_ key: GroupKey) -> Binding<Bool> {
        Binding(
            get: { appDelegate.currentFileManagerStore?.fsItems.groupKey == key },
            set: { isOn in
                guard isOn else { return }
                appDelegate.currentFileManagerStore?.send(.changeGroupKey(key))
            },
        )
    }

    private func sortKeyToggleBinding(_ key: SortKey) -> Binding<Bool> {
        Binding(
            get: { appDelegate.currentFileManagerStore?.sortKey == key },
            set: { isOn in
                guard isOn else { return }
                appDelegate.currentFileManagerStore?.send(.changeSortKey(key))
            },
        )
    }

    private func sortOrderToggleBinding(_ order: SortOrder) -> Binding<Bool> {
        Binding(
            get: { appDelegate.currentFileManagerStore?.sortOrder == order },
            set: { isOn in
                guard isOn else { return }
                appDelegate.currentFileManagerStore?.send(.changeSortOrder(order))
            },
        )
    }
}
