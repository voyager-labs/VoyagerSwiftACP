import AppKit
import ComposableArchitecture
import SwiftUI

struct ViewMenuCommands: Commands {
    var body: some Commands {
        CommandGroup(replacing: .sidebar) {
            Button(
                AppDelegate.shared?.currentFileManagerStore?.sidebarVisible == true
                    ? "Hide Sidebar"
                    : "Show Sidebar"
            ) {
                let newValue = !(AppDelegate.shared?.currentFileManagerStore?.sidebarVisible ?? true)
                AppDelegate.shared?.currentFileManagerStore?.send(.setSidebarVisible(newValue))
            }
            .keyboardShortcut("s", modifiers: .command)
            .disabled(AppDelegate.shared?.currentFileManagerStore == nil)
        }

        CommandGroup(after: .sidebar) {
            Button("as List") {
                AppDelegate.shared?.currentFileManagerStore?.send(.changeLayout(.list))
            }
            .disabled(AppDelegate.shared?.currentFileManagerStore?.viewLayout == .list)

            Button("as Icons") {
                AppDelegate.shared?.currentFileManagerStore?.send(.changeLayout(.grid))
            }
            .disabled(AppDelegate.shared?.currentFileManagerStore?.viewLayout == .grid)

            Divider()

            Button(
                AppDelegate.shared?.currentFileManagerStore?.showHiddenFiles == true
                    ? "Hide Hidden Files"
                    : "Show Hidden Files"
            ) {
                AppDelegate.shared?.currentFileManagerStore?.send(.toggleShowHiddenFiles)
            }
            .keyboardShortcut(".", modifiers: [.command, .shift])

            Divider()

            Menu("Group By") {
                Button(
                    action: { AppDelegate.shared?.currentFileManagerStore?.send(.changeGroupKey(.none)) },
                    label: {
                        HStack {
                            Text("None")
                            if AppDelegate.shared?.currentFileManagerStore?.fsItems.groupKey == GroupKey.none {
                                Image(systemName: "checkmark")
                            }
                        }
                    },
                )

                Divider()

                Button(
                    action: { AppDelegate.shared?.currentFileManagerStore?.send(.changeGroupKey(.name)) },
                    label: {
                        HStack {
                            Text("Name")
                            if AppDelegate.shared?.currentFileManagerStore?.fsItems.groupKey == .name {
                                Image(systemName: "checkmark")
                            }
                        }
                    },
                )

                Button(
                    action: { AppDelegate.shared?.currentFileManagerStore?.send(.changeGroupKey(.kind)) },
                    label: {
                        HStack {
                            Text("Kind")
                            if AppDelegate.shared?.currentFileManagerStore?.fsItems.groupKey == .kind {
                                Image(systemName: "checkmark")
                            }
                        }
                    },
                )

                Button(
                    action: { AppDelegate.shared?.currentFileManagerStore?.send(.changeGroupKey(.application)) },
                    label: {
                        HStack {
                            Text("Application")
                            if AppDelegate.shared?.currentFileManagerStore?.fsItems.groupKey == .application {
                                Image(systemName: "checkmark")
                            }
                        }
                    },
                )

                Button(
                    action: { AppDelegate.shared?.currentFileManagerStore?.send(.changeGroupKey(.dateLastOpened)) },
                    label: {
                        HStack {
                            Text("Date Last Opened")
                            if AppDelegate.shared?.currentFileManagerStore?.fsItems.groupKey == .dateLastOpened {
                                Image(systemName: "checkmark")
                            }
                        }
                    },
                )

                Button(
                    action: { AppDelegate.shared?.currentFileManagerStore?.send(.changeGroupKey(.dateAdded)) },
                    label: {
                        HStack {
                            Text("Date Added")
                            if AppDelegate.shared?.currentFileManagerStore?.fsItems.groupKey == .dateAdded {
                                Image(systemName: "checkmark")
                            }
                        }
                    },
                )

                Button(
                    action: { AppDelegate.shared?.currentFileManagerStore?.send(.changeGroupKey(.dateModified)) },
                    label: {
                        HStack {
                            Text("Date Modified")
                            if AppDelegate.shared?.currentFileManagerStore?.fsItems.groupKey == .dateModified {
                                Image(systemName: "checkmark")
                            }
                        }
                    },
                )

                Button(
                    action: { AppDelegate.shared?.currentFileManagerStore?.send(.changeGroupKey(.dateCreated)) },
                    label: {
                        HStack {
                            Text("Date Created")
                            if AppDelegate.shared?.currentFileManagerStore?.fsItems.groupKey == .dateCreated {
                                Image(systemName: "checkmark")
                            }
                        }
                    },
                )

                Button(
                    action: { AppDelegate.shared?.currentFileManagerStore?.send(.changeGroupKey(.size)) },
                    label: {
                        HStack {
                            Text("Size")
                            if AppDelegate.shared?.currentFileManagerStore?.fsItems.groupKey == .size {
                                Image(systemName: "checkmark")
                            }
                        }
                    },
                )
                Button(
                    action: { AppDelegate.shared?.currentFileManagerStore?.send(.changeGroupKey(.tags)) },
                    label: {
                        HStack {
                            Text("Tags")
                            if AppDelegate.shared?.currentFileManagerStore?.fsItems.groupKey == .tags {
                                Image(systemName: "checkmark")
                            }
                        }
                    },
                )
            }

            Divider()

            Menu("Sort By") {
                Button(
                    action: { AppDelegate.shared?.currentFileManagerStore?.send(.changeSortKey(.name)) },
                    label: {
                        HStack {
                            Text("Name")
                            if AppDelegate.shared?.currentFileManagerStore?.sortKey == .name {
                                Image(systemName: "checkmark")
                            }
                        }
                    },
                )

                Button(
                    action: { AppDelegate.shared?.currentFileManagerStore?.send(.changeSortKey(.kind)) },
                    label: {
                        HStack {
                            Text("Kind")
                            if AppDelegate.shared?.currentFileManagerStore?.sortKey == .kind {
                                Image(systemName: "checkmark")
                            }
                        }
                    },
                )

                Button(
                    action: { AppDelegate.shared?.currentFileManagerStore?.send(.changeSortKey(.application)) },
                    label: {
                        HStack {
                            Text("Application")
                            if AppDelegate.shared?.currentFileManagerStore?.sortKey == .application {
                                Image(systemName: "checkmark")
                            }
                        }
                    },
                )

                Button(
                    action: { AppDelegate.shared?.currentFileManagerStore?.send(.changeSortKey(.dateLastOpened)) },
                    label: {
                        HStack {
                            Text("Date Last Opened")
                            if AppDelegate.shared?.currentFileManagerStore?.sortKey == .dateLastOpened {
                                Image(systemName: "checkmark")
                            }
                        }
                    },
                )

                Button(
                    action: { AppDelegate.shared?.currentFileManagerStore?.send(.changeSortKey(.dateAdded)) },
                    label: {
                        HStack {
                            Text("Date Added")
                            if AppDelegate.shared?.currentFileManagerStore?.sortKey == .dateAdded {
                                Image(systemName: "checkmark")
                            }
                        }
                    },
                )

                Button(
                    action: { AppDelegate.shared?.currentFileManagerStore?.send(.changeSortKey(.dateModified)) },
                    label: {
                        HStack {
                            Text("Date Modified")
                            if AppDelegate.shared?.currentFileManagerStore?.sortKey == .dateModified {
                                Image(systemName: "checkmark")
                            }
                        }
                    },
                )

                Button(
                    action: { AppDelegate.shared?.currentFileManagerStore?.send(.changeSortKey(.dateCreated)) },
                    label: {
                        HStack {
                            Text("Date Created")
                            if AppDelegate.shared?.currentFileManagerStore?.sortKey == .dateCreated {
                                Image(systemName: "checkmark")
                            }
                        }
                    },
                )

                Button(
                    action: { AppDelegate.shared?.currentFileManagerStore?.send(.changeSortKey(.size)) },
                    label: {
                        HStack {
                            Text("Size")
                            if AppDelegate.shared?.currentFileManagerStore?.sortKey == .size {
                                Image(systemName: "checkmark")
                            }
                        }
                    },
                )
                Button(
                    action: { AppDelegate.shared?.currentFileManagerStore?.send(.changeSortKey(.tags)) },
                    label: {
                        HStack {
                            Text("Tags")
                            if AppDelegate.shared?.currentFileManagerStore?.sortKey == .tags {
                                Image(systemName: "checkmark")
                            }
                        }
                    },
                )

                Divider()

                Button(
                    action: { AppDelegate.shared?.currentFileManagerStore?.send(.changeSortOrder(.ascending)) },
                    label: {
                        HStack {
                            Text("Ascending")
                            if AppDelegate.shared?.currentFileManagerStore?.sortOrder == .ascending {
                                Image(systemName: "checkmark")
                            }
                        }
                    },
                )

                Button(
                    action: { AppDelegate.shared?.currentFileManagerStore?.send(.changeSortOrder(.descending)) },
                    label: {
                        HStack {
                            Text("Descending")
                            if AppDelegate.shared?.currentFileManagerStore?.sortOrder == .descending {
                                Image(systemName: "checkmark")
                            }
                        }
                    },
                )
            }
            .disabled(AppDelegate.shared?.currentFileManagerStore?.fsItems.groupKey != GroupKey.none)
        }
    }
}
