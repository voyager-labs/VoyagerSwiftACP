import ComposableArchitecture
import SwiftUI

struct ContentPaneContextMenu: View {
    let store: StoreOf<FileManagerFeature>

    @Dependency(\.entryClient)
    private var entryClient

    var body: some View {
        if isTrashFolder {
            Button("Empty Trash") {
                store.send(.entries(.emptyTrash))
            }
        } else {
            Button("New Folder") {
                store.send(.entries(.createNewFolder(currentPath: store.currentPath)))
            }
            .keyboardShortcut("n", modifiers: [.command, .shift])
        }

        Divider()

        Menu("View") {
            viewLayoutToggle("as List", layout: .list)
            viewLayoutToggle("as Icon", layout: .grid)
        }

        Menu("Sort By") {
            sortKeyToggle("Name", key: .name)
            sortKeyToggle("Kind", key: .kind)
            sortKeyToggle("Application", key: .application)
            sortKeyToggle("Date Last Opened", key: .dateLastOpened)
            sortKeyToggle("Date Added", key: .dateAdded)
            sortKeyToggle("Date Modified", key: .dateModified)
            sortKeyToggle("Date Created", key: .dateCreated)
            sortKeyToggle("Size", key: .size)
            sortKeyToggle("Tags", key: .tags)

            Divider()

            sortOrderToggle("Ascending", order: .ascending)
            sortOrderToggle("Descending", order: .descending)
        }

        Menu("Group By") {
            groupKeyToggle("None", key: .none)

            Divider()

            groupKeyToggle("Name", key: .name)
            groupKeyToggle("Kind", key: .kind)
            groupKeyToggle("Application", key: .application)
            groupKeyToggle("Date Last Opened", key: .dateLastOpened)
            groupKeyToggle("Date Added", key: .dateAdded)
            groupKeyToggle("Date Modified", key: .dateModified)
            groupKeyToggle("Date Created", key: .dateCreated)
            groupKeyToggle("Size", key: .size)
            groupKeyToggle("Tags", key: .tags)
        }
    }

    private var isTrashFolder: Bool {
        guard case let .folder(path) = store.navigationState,
              let trashPath = entryClient.trashDirectoryPath()
        else {
            return false
        }
        return path == trashPath || path.hasPrefix(trashPath + "/")
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
                get: { store.sortKey == key },
                set: { isOn in
                    if isOn {
                        store.send(.changeSortKey(key))
                    }
                },
            ),
        )
    }

    private func sortOrderToggle(_ title: String, order: SortOrder) -> some View {
        Toggle(
            title,
            isOn: Binding(
                get: { store.sortOrder == order },
                set: { isOn in
                    if isOn {
                        store.send(.changeSortOrder(order))
                    }
                },
            ),
        )
    }

    private func groupKeyToggle(_ title: String, key: GroupKey) -> some View {
        Toggle(
            title,
            isOn: Binding(
                get: { store.entries.groupKey == key },
                set: { isOn in
                    if isOn {
                        store.send(.changeGroupKey(key))
                    }
                },
            ),
        )
    }
}
