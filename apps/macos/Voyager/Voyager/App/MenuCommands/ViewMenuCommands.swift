import AppKit
import ComposableArchitecture
import SwiftUI

struct ViewMenuCommands: Commands {
    @FocusedValue(\.fileManagerStore)
    var fileManagerStore: StoreOf<FileManagerFeature>?

    var body: some Commands {
        CommandGroup(replacing: .sidebar) {
            Button(fileManagerStore?.sidebarVisible == true ? "Hide Sidebar" : "Show Sidebar") {
                let newValue = !(fileManagerStore?.sidebarVisible ?? true)
                fileManagerStore?.send(.setSidebarVisible(newValue))
            }
            .keyboardShortcut("s", modifiers: .command)
            .disabled(fileManagerStore == nil)
        }

        CommandGroup(after: .sidebar) {
            Button("as List") {
                fileManagerStore?.send(.changeLayout(.list))
            }
            .disabled(fileManagerStore?.viewLayout == .list)

            Button("as Icons") {
                fileManagerStore?.send(.changeLayout(.grid))
            }
            .disabled(fileManagerStore?.viewLayout == .grid)

            Divider()

            Button(fileManagerStore?.showHiddenFiles == true ? "Hide Hidden Files" : "Show Hidden Files") {
                fileManagerStore?.send(.toggleShowHiddenFiles)
            }
            .keyboardShortcut(".", modifiers: [.command, .shift])

            Divider()

            Menu("Group By") {
                Button(
                    action: { fileManagerStore?.send(.changeGroupKey(.none)) },
                    label: {
                        HStack {
                            Text("None")
                            if fileManagerStore?.fsItems.groupKey == GroupKey.none {
                                Image(systemName: "checkmark")
                            }
                        }
                    },
                )

                Divider()

                Button(
                    action: { fileManagerStore?.send(.changeGroupKey(.name)) },
                    label: {
                        HStack {
                            Text("Name")
                            if fileManagerStore?.fsItems.groupKey == .name {
                                Image(systemName: "checkmark")
                            }
                        }
                    },
                )

                Button(
                    action: { fileManagerStore?.send(.changeGroupKey(.kind)) },
                    label: {
                        HStack {
                            Text("Kind")
                            if fileManagerStore?.fsItems.groupKey == .kind {
                                Image(systemName: "checkmark")
                            }
                        }
                    },
                )

                Button(
                    action: { fileManagerStore?.send(.changeGroupKey(.application)) },
                    label: {
                        HStack {
                            Text("Application")
                            if fileManagerStore?.fsItems.groupKey == .application {
                                Image(systemName: "checkmark")
                            }
                        }
                    },
                )

                Button(
                    action: { fileManagerStore?.send(.changeGroupKey(.dateLastOpened)) },
                    label: {
                        HStack {
                            Text("Date Last Opened")
                            if fileManagerStore?.fsItems.groupKey == .dateLastOpened {
                                Image(systemName: "checkmark")
                            }
                        }
                    },
                )

                Button(
                    action: { fileManagerStore?.send(.changeGroupKey(.dateAdded)) },
                    label: {
                        HStack {
                            Text("Date Added")
                            if fileManagerStore?.fsItems.groupKey == .dateAdded {
                                Image(systemName: "checkmark")
                            }
                        }
                    },
                )

                Button(
                    action: { fileManagerStore?.send(.changeGroupKey(.dateModified)) },
                    label: {
                        HStack {
                            Text("Date Modified")
                            if fileManagerStore?.fsItems.groupKey == .dateModified {
                                Image(systemName: "checkmark")
                            }
                        }
                    },
                )

                Button(
                    action: { fileManagerStore?.send(.changeGroupKey(.dateCreated)) },
                    label: {
                        HStack {
                            Text("Date Created")
                            if fileManagerStore?.fsItems.groupKey == .dateCreated {
                                Image(systemName: "checkmark")
                            }
                        }
                    },
                )

                Button(
                    action: { fileManagerStore?.send(.changeGroupKey(.size)) },
                    label: {
                        HStack {
                            Text("Size")
                            if fileManagerStore?.fsItems.groupKey == .size {
                                Image(systemName: "checkmark")
                            }
                        }
                    },
                )
                Button(
                    action: { fileManagerStore?.send(.changeGroupKey(.tags)) },
                    label: {
                        HStack {
                            Text("Tags")
                            if fileManagerStore?.fsItems.groupKey == .tags {
                                Image(systemName: "checkmark")
                            }
                        }
                    },
                )
            }

            Divider()

            Menu("Sort By") {
                Button(
                    action: { fileManagerStore?.send(.changeSortKey(.name)) },
                    label: {
                        HStack {
                            Text("Name")
                            if fileManagerStore?.sortKey == .name {
                                Image(systemName: "checkmark")
                            }
                        }
                    },
                )

                Button(
                    action: { fileManagerStore?.send(.changeSortKey(.kind)) },
                    label: {
                        HStack {
                            Text("Kind")
                            if fileManagerStore?.sortKey == .kind {
                                Image(systemName: "checkmark")
                            }
                        }
                    },
                )

                Button(
                    action: { fileManagerStore?.send(.changeSortKey(.application)) },
                    label: {
                        HStack {
                            Text("Application")
                            if fileManagerStore?.sortKey == .application {
                                Image(systemName: "checkmark")
                            }
                        }
                    },
                )

                Button(
                    action: { fileManagerStore?.send(.changeSortKey(.dateLastOpened)) },
                    label: {
                        HStack {
                            Text("Date Last Opened")
                            if fileManagerStore?.sortKey == .dateLastOpened {
                                Image(systemName: "checkmark")
                            }
                        }
                    },
                )

                Button(
                    action: { fileManagerStore?.send(.changeSortKey(.dateAdded)) },
                    label: {
                        HStack {
                            Text("Date Added")
                            if fileManagerStore?.sortKey == .dateAdded {
                                Image(systemName: "checkmark")
                            }
                        }
                    },
                )

                Button(
                    action: { fileManagerStore?.send(.changeSortKey(.dateModified)) },
                    label: {
                        HStack {
                            Text("Date Modified")
                            if fileManagerStore?.sortKey == .dateModified {
                                Image(systemName: "checkmark")
                            }
                        }
                    },
                )

                Button(
                    action: { fileManagerStore?.send(.changeSortKey(.dateCreated)) },
                    label: {
                        HStack {
                            Text("Date Created")
                            if fileManagerStore?.sortKey == .dateCreated {
                                Image(systemName: "checkmark")
                            }
                        }
                    },
                )

                Button(
                    action: { fileManagerStore?.send(.changeSortKey(.size)) },
                    label: {
                        HStack {
                            Text("Size")
                            if fileManagerStore?.sortKey == .size {
                                Image(systemName: "checkmark")
                            }
                        }
                    },
                )
                Button(
                    action: { fileManagerStore?.send(.changeSortKey(.tags)) },
                    label: {
                        HStack {
                            Text("Tags")
                            if fileManagerStore?.sortKey == .tags {
                                Image(systemName: "checkmark")
                            }
                        }
                    },
                )

                Divider()

                Button(
                    action: { fileManagerStore?.send(.changeSortOrder(.ascending)) },
                    label: {
                        HStack {
                            Text("Ascending")
                            if fileManagerStore?.sortOrder == .ascending {
                                Image(systemName: "checkmark")
                            }
                        }
                    },
                )

                Button(
                    action: { fileManagerStore?.send(.changeSortOrder(.descending)) },
                    label: {
                        HStack {
                            Text("Descending")
                            if fileManagerStore?.sortOrder == .descending {
                                Image(systemName: "checkmark")
                            }
                        }
                    },
                )
            }
            .disabled(fileManagerStore?.fsItems.groupKey != GroupKey.none)
        }
    }
}
