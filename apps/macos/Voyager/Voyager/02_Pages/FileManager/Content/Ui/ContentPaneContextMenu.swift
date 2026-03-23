import ComposableArchitecture
import Foundation
import SwiftUI

struct ContentPaneContextMenu: View {
    let store: StoreOf<FileManagerContentFeature>

    @Dependency(\.fileManagerClient) private var fileManagerClient

    private var isTrashFolder: Bool {
        guard case let .folder(path) = store.navigation.navigationState,
              let trashPath = fileManagerClient.urlsForDirectory(.trashDirectory, .userDomainMask).first?.path
        else {
            return false
        }
        return path == trashPath || path.hasPrefix(trashPath + "/")
    }

    private var defaultNewFolderName: String {
        var folderName = "untitled folder"
        var counter = 2
        while store.entryViewLayout.entries.contains(where: { $0.name == folderName }) {
            folderName = "untitled folder \(counter)"
            counter += 1
        }
        return folderName
    }

    var body: some View {
        if isTrashFolder {
            Button("Empty Trash") {
                store
                    .send(.entryViewLayout(.entryOperations(.trash(.emptyTrash(paths: store.entryViewLayout.entries
                            .map(\.fullPath))))))
            }
        } else {
            Button("New Folder") {
                store.send(.entryViewLayout(.entryOperations(.edit(.createNewFolder(
                    name: defaultNewFolderName,
                    parentPath: store.navigation.currentPath,
                )))))
            }
            .keyboardShortcut("n", modifiers: [.command, .shift])
        }

        Divider()

        Menu("View") {
            viewLayoutToggle("as List", layout: .list)
            viewLayoutToggle("as Icon", layout: .grid)
        }

        Menu("Sort By") {
            ForEach(EntryArrangementMenuItems.sortItems) { item in
                sortKeyToggle(item.title, key: item.key)
            }

            Divider()

            sortOrderToggle("Ascending", order: .ascending)
            sortOrderToggle("Descending", order: .descending)
        }

        Menu("Group By") {
            groupKeyToggle("None", key: .none)

            Divider()

            ForEach(EntryArrangementMenuItems.groupItems) { item in
                groupKeyToggle(item.title, key: item.key)
            }
        }
    }

    private func viewLayoutToggle(_ title: String, layout: EntryViewLayoutState.Mode) -> some View {
        Toggle(
            title,
            isOn: Binding(
                get: { store.entryViewLayout.mode == layout },
                set: { isOn in
                    if isOn {
                        store.send(.view(.changeLayout(layout)))
                    }
                },
            ),
        )
    }

    private func sortKeyToggle(_ title: String, key: SortKey) -> some View {
        Toggle(
            title,
            isOn: Binding(
                get: { store.entryViewLayout.entryArrangements.sortKey == key },
                set: { isOn in
                    if isOn {
                        store.send(.entryViewLayout(.entryArrangements(.setSortKey(key))))
                    }
                },
            ),
        )
    }

    private func sortOrderToggle(_ title: String, order: SortOrder) -> some View {
        Toggle(
            title,
            isOn: Binding(
                get: { store.entryViewLayout.entryArrangements.sortOrder == order },
                set: { isOn in
                    if isOn {
                        store.send(.entryViewLayout(.entryArrangements(.setSortOrder(order))))
                    }
                },
            ),
        )
    }

    private func groupKeyToggle(_ title: String, key: GroupKey) -> some View {
        Toggle(
            title,
            isOn: Binding(
                get: { store.entryViewLayout.entryArrangements.groupKey == key },
                set: { isOn in
                    if isOn {
                        store.send(.entryViewLayout(.entryArrangements(.setGroupKey(key))))
                    }
                },
            ),
        )
    }
}
