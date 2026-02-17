import ComposableArchitecture
import Foundation
import SwiftUI

struct ContentPaneContextMenu: View {
    let store: StoreOf<FileManagerContentFeature>

    var body: some View {
        if isTrashFolder {
            Button("Empty Trash") {
                store.send(.entryOperations(.emptyTrash(items: store.entryOperations.displayOrderItems)))
            }
        } else {
            Button("New Folder") {
                store.send(.entryOperations(.createNewFolder(
                    name: defaultNewFolderName,
                    parentPath: store.navigation.currentPath,
                )))
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

    private var isTrashFolder: Bool {
        guard case let .folder(path) = store.navigation.navigationState,
              let trashPath = FileManager.default.urls(for: .trashDirectory, in: .userDomainMask).first?.path
        else {
            return false
        }
        return path == trashPath || path.hasPrefix(trashPath + "/")
    }

    private var defaultNewFolderName: String {
        var folderName = "untitled folder"
        var counter = 2
        while store.entryOperations.displayItems.contains(where: { $0.name == folderName }) {
            folderName = "untitled folder \(counter)"
            counter += 1
        }
        return folderName
    }

    private func viewLayoutToggle(_ title: String, layout: ContentViewLayout) -> some View {
        Toggle(
            title,
            isOn: Binding(
                get: { store.viewLayout == layout },
                set: { isOn in
                    if isOn {
                        store.send(.changeLayout(layout))
                    }
                },
            ),
        )
    }

    private func sortKeyToggle(_ title: String, key: SortKey) -> some View {
        Toggle(
            title,
            isOn: Binding(
                get: { store.entryArrangements.sortKey == key },
                set: { isOn in
                    if isOn {
                        store.send(.entryArrangements(.setSortKey(key)))
                    }
                },
            ),
        )
    }

    private func sortOrderToggle(_ title: String, order: SortOrder) -> some View {
        Toggle(
            title,
            isOn: Binding(
                get: { store.entryArrangements.sortOrder == order },
                set: { isOn in
                    if isOn {
                        store.send(.entryArrangements(.setSortOrder(order)))
                    }
                },
            ),
        )
    }

    private func groupKeyToggle(_ title: String, key: GroupKey) -> some View {
        Toggle(
            title,
            isOn: Binding(
                get: { store.entryArrangements.groupKey == key },
                set: { isOn in
                    if isOn {
                        store.send(.entryArrangements(.setGroupKey(key)))
                    }
                },
            ),
        )
    }
}
