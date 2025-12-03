import ComposableArchitecture
import SwiftUI

struct ToolbarMenuView: View {
    let store: StoreOf<FileManagerFeature>

    var body: some View {
        Menu {
            Button(
                action: { store.send(.changeLayout(.list)) },
                label: {
                    HStack {
                        Image(systemName: "list.bullet")
                        Text("List")
                    }
                }
            )

            Button(
                action: { store.send(.changeLayout(.grid)) },
                label: {
                    HStack {
                        Image(systemName: "square.grid.2x2")
                        Text("Grid")
                    }
                }
            )

            Divider()

            Button("New Folder") {
                store.send(.fsItems(.createNewFolder(currentPath: store.currentPath)))
            }
            .keyboardShortcut("n", modifiers: [.command, .shift])

            Divider()

            Menu("Group By") {
                Button(
                    action: { store.send(.changeGroupKey(.none)) },
                    label: {
                        HStack {
                            Text("None")
                            if store.fsItems.groupKey == .none {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                )

                Divider()

                Button(
                    action: { store.send(.changeGroupKey(.name)) },
                    label: {
                        HStack {
                            Text("Name")
                            if store.fsItems.groupKey == .name {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                )

                Button(
                    action: { store.send(.changeGroupKey(.kind)) },
                    label: {
                        HStack {
                            Text("Kind")
                            if store.fsItems.groupKey == .kind {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                )

                Button(
                    action: { store.send(.changeGroupKey(.application)) },
                    label: {
                        HStack {
                            Text("Application")
                            if store.fsItems.groupKey == .application {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                )

                Button(
                    action: { store.send(.changeGroupKey(.dateLastOpened)) },
                    label: {
                        HStack {
                            Text("Date Last Opened")
                            if store.fsItems.groupKey == .dateLastOpened {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                )

                Button(
                    action: { store.send(.changeGroupKey(.dateAdded)) },
                    label: {
                        HStack {
                            Text("Date Added")
                            if store.fsItems.groupKey == .dateAdded {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                )

                Button(
                    action: { store.send(.changeGroupKey(.dateModified)) },
                    label: {
                        HStack {
                            Text("Date Modified")
                            if store.fsItems.groupKey == .dateModified {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                )

                Button(
                    action: { store.send(.changeGroupKey(.dateCreated)) },
                    label: {
                        HStack {
                            Text("Date Created")
                            if store.fsItems.groupKey == .dateCreated {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                )

                Button(
                    action: { store.send(.changeGroupKey(.size)) },
                    label: {
                        HStack {
                            Text("Size")
                            if store.fsItems.groupKey == .size {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                )
                Button(
                    action: { store.send(.changeGroupKey(.tags)) },
                    label: {
                        HStack {
                            Text("Tags")
                            if store.fsItems.groupKey == .tags {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                )
            }

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
                    action: { store.send(.changeSortKey(.kind)) },
                    label: {
                        HStack {
                            Text("Kind")
                            if store.sortKey == .kind {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                )
                Button(
                    action: { store.send(.changeSortKey(.application)) },
                    label: {
                        HStack {
                            Text("Application")
                            if store.sortKey == .application {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                )
                Button(
                    action: { store.send(.changeSortKey(.dateLastOpened)) },
                    label: {
                        HStack {
                            Text("Date Last Opened")
                            if store.sortKey == .dateLastOpened {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                )
                Button(
                    action: { store.send(.changeSortKey(.dateAdded)) },
                    label: {
                        HStack {
                            Text("Date Added")
                            if store.sortKey == .dateAdded {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                )
                Button(
                    action: { store.send(.changeSortKey(.dateModified)) },
                    label: {
                        HStack {
                            Text("Date Modified")
                            if store.sortKey == .dateModified {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                )
                Button(
                    action: { store.send(.changeSortKey(.dateCreated)) },
                    label: {
                        HStack {
                            Text("Date Created")
                            if store.sortKey == .dateCreated {
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
                    action: { store.send(.changeSortKey(.tags)) },
                    label: {
                        HStack {
                            Text("Tags")
                            if store.sortKey == .tags {
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
            .disabled(store.fsItems.groupKey != .none)
        } label: {
            Image(systemName: "chevron.down")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .frame(width: 32, height: 32)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(Color(nsColor: .controlBackgroundColor))
                )
        }
        .menuIndicator(.hidden)
        .buttonStyle(.plain)
    }
}
