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
                    : "Show Sidebar"
            ) {
                let newValue = !(appDelegate.currentFileManagerStore?.sidebarVisible ?? true)
                appDelegate.currentFileManagerStore?.send(.setSidebarVisible(newValue))
            }
            .keyboardShortcut("s", modifiers: .command)
            .disabled(appDelegate.currentFileManagerStore == nil)
        }

        CommandGroup(after: .sidebar) {
            Button("as List") {
                appDelegate.currentFileManagerStore?.send(.changeLayout(.list))
            }
            .disabled(appDelegate.currentFileManagerStore?.viewLayout == .list)

            Button("as Icons") {
                appDelegate.currentFileManagerStore?.send(.changeLayout(.grid))
            }
            .disabled(appDelegate.currentFileManagerStore?.viewLayout == .grid)

            Divider()

            Button(
                appDelegate.currentFileManagerStore?.showHiddenFiles == true
                    ? "Hide Hidden Files"
                    : "Show Hidden Files"
            ) {
                appDelegate.currentFileManagerStore?.send(.toggleShowHiddenFiles)
            }
            .keyboardShortcut(".", modifiers: [.command, .shift])

            Divider()

            Menu("Group By") {
                Button(
                    action: { appDelegate.currentFileManagerStore?.send(.changeGroupKey(.none)) },
                    label: {
                        HStack {
                            Text("None")
                            if appDelegate.currentFileManagerStore?.fsItems.groupKey == GroupKey.none {
                                Image(systemName: "checkmark")
                            }
                        }
                    },
                )

                Divider()

                Button(
                    action: { appDelegate.currentFileManagerStore?.send(.changeGroupKey(.name)) },
                    label: {
                        HStack {
                            Text("Name")
                            if appDelegate.currentFileManagerStore?.fsItems.groupKey == .name {
                                Image(systemName: "checkmark")
                            }
                        }
                    },
                )

                Button(
                    action: { appDelegate.currentFileManagerStore?.send(.changeGroupKey(.kind)) },
                    label: {
                        HStack {
                            Text("Kind")
                            if appDelegate.currentFileManagerStore?.fsItems.groupKey == .kind {
                                Image(systemName: "checkmark")
                            }
                        }
                    },
                )

                Button(
                    action: { appDelegate.currentFileManagerStore?.send(.changeGroupKey(.application)) },
                    label: {
                        HStack {
                            Text("Application")
                            if appDelegate.currentFileManagerStore?.fsItems.groupKey == .application {
                                Image(systemName: "checkmark")
                            }
                        }
                    },
                )

                Button(
                    action: { appDelegate.currentFileManagerStore?.send(.changeGroupKey(.dateLastOpened)) },
                    label: {
                        HStack {
                            Text("Date Last Opened")
                            if appDelegate.currentFileManagerStore?.fsItems.groupKey == .dateLastOpened {
                                Image(systemName: "checkmark")
                            }
                        }
                    },
                )

                Button(
                    action: { appDelegate.currentFileManagerStore?.send(.changeGroupKey(.dateAdded)) },
                    label: {
                        HStack {
                            Text("Date Added")
                            if appDelegate.currentFileManagerStore?.fsItems.groupKey == .dateAdded {
                                Image(systemName: "checkmark")
                            }
                        }
                    },
                )

                Button(
                    action: { appDelegate.currentFileManagerStore?.send(.changeGroupKey(.dateModified)) },
                    label: {
                        HStack {
                            Text("Date Modified")
                            if appDelegate.currentFileManagerStore?.fsItems.groupKey == .dateModified {
                                Image(systemName: "checkmark")
                            }
                        }
                    },
                )

                Button(
                    action: { appDelegate.currentFileManagerStore?.send(.changeGroupKey(.dateCreated)) },
                    label: {
                        HStack {
                            Text("Date Created")
                            if appDelegate.currentFileManagerStore?.fsItems.groupKey == .dateCreated {
                                Image(systemName: "checkmark")
                            }
                        }
                    },
                )

                Button(
                    action: { appDelegate.currentFileManagerStore?.send(.changeGroupKey(.size)) },
                    label: {
                        HStack {
                            Text("Size")
                            if appDelegate.currentFileManagerStore?.fsItems.groupKey == .size {
                                Image(systemName: "checkmark")
                            }
                        }
                    },
                )
                Button(
                    action: { appDelegate.currentFileManagerStore?.send(.changeGroupKey(.tags)) },
                    label: {
                        HStack {
                            Text("Tags")
                            if appDelegate.currentFileManagerStore?.fsItems.groupKey == .tags {
                                Image(systemName: "checkmark")
                            }
                        }
                    },
                )
            }

            Divider()

            Menu("Sort By") {
                Button(
                    action: { appDelegate.currentFileManagerStore?.send(.changeSortKey(.name)) },
                    label: {
                        HStack {
                            Text("Name")
                            if appDelegate.currentFileManagerStore?.sortKey == .name {
                                Image(systemName: "checkmark")
                            }
                        }
                    },
                )

                Button(
                    action: { appDelegate.currentFileManagerStore?.send(.changeSortKey(.kind)) },
                    label: {
                        HStack {
                            Text("Kind")
                            if appDelegate.currentFileManagerStore?.sortKey == .kind {
                                Image(systemName: "checkmark")
                            }
                        }
                    },
                )

                Button(
                    action: { appDelegate.currentFileManagerStore?.send(.changeSortKey(.application)) },
                    label: {
                        HStack {
                            Text("Application")
                            if appDelegate.currentFileManagerStore?.sortKey == .application {
                                Image(systemName: "checkmark")
                            }
                        }
                    },
                )

                Button(
                    action: { appDelegate.currentFileManagerStore?.send(.changeSortKey(.dateLastOpened)) },
                    label: {
                        HStack {
                            Text("Date Last Opened")
                            if appDelegate.currentFileManagerStore?.sortKey == .dateLastOpened {
                                Image(systemName: "checkmark")
                            }
                        }
                    },
                )

                Button(
                    action: { appDelegate.currentFileManagerStore?.send(.changeSortKey(.dateAdded)) },
                    label: {
                        HStack {
                            Text("Date Added")
                            if appDelegate.currentFileManagerStore?.sortKey == .dateAdded {
                                Image(systemName: "checkmark")
                            }
                        }
                    },
                )

                Button(
                    action: { appDelegate.currentFileManagerStore?.send(.changeSortKey(.dateModified)) },
                    label: {
                        HStack {
                            Text("Date Modified")
                            if appDelegate.currentFileManagerStore?.sortKey == .dateModified {
                                Image(systemName: "checkmark")
                            }
                        }
                    },
                )

                Button(
                    action: { appDelegate.currentFileManagerStore?.send(.changeSortKey(.dateCreated)) },
                    label: {
                        HStack {
                            Text("Date Created")
                            if appDelegate.currentFileManagerStore?.sortKey == .dateCreated {
                                Image(systemName: "checkmark")
                            }
                        }
                    },
                )

                Button(
                    action: { appDelegate.currentFileManagerStore?.send(.changeSortKey(.size)) },
                    label: {
                        HStack {
                            Text("Size")
                            if appDelegate.currentFileManagerStore?.sortKey == .size {
                                Image(systemName: "checkmark")
                            }
                        }
                    },
                )
                Button(
                    action: { appDelegate.currentFileManagerStore?.send(.changeSortKey(.tags)) },
                    label: {
                        HStack {
                            Text("Tags")
                            if appDelegate.currentFileManagerStore?.sortKey == .tags {
                                Image(systemName: "checkmark")
                            }
                        }
                    },
                )

                Divider()

                Button(
                    action: { appDelegate.currentFileManagerStore?.send(.changeSortOrder(.ascending)) },
                    label: {
                        HStack {
                            Text("Ascending")
                            if appDelegate.currentFileManagerStore?.sortOrder == .ascending {
                                Image(systemName: "checkmark")
                            }
                        }
                    },
                )

                Button(
                    action: { appDelegate.currentFileManagerStore?.send(.changeSortOrder(.descending)) },
                    label: {
                        HStack {
                            Text("Descending")
                            if appDelegate.currentFileManagerStore?.sortOrder == .descending {
                                Image(systemName: "checkmark")
                            }
                        }
                    },
                )
            }
            .disabled(appDelegate.currentFileManagerStore?.fsItems.groupKey != GroupKey.none)
        }
    }
}
