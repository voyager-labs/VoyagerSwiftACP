import AppKit
import ComposableArchitecture
import SwiftUI
import VoyagerFeaturesEntryArrangements
import VoyagerShared

struct SortGroupButton: View {
    let store: StoreOf<FileManagerContentFeature>

    var body: some View {
        ToolbarMenuButton(
            systemName: "arrow.up.arrow.down",
            isEnabled: true,
            font: IconButtonStyle.toolbar.font,
            menuContent: {
                Menu("Group By") {
                    groupKeyToggle("None", key: .none)

                    Divider()

                    ForEach(EntryArrangementMenuItems.groupItems) { item in
                        groupKeyToggle(item.title, key: item.key)
                    }
                }

                Menu("Sort By") {
                    ForEach(EntryArrangementMenuItems.sortItems) { item in
                        sortKeyToggle(item.title, key: item.key)
                    }

                    Divider()

                    sortOrderToggle("Ascending", order: .ascending)
                    sortOrderToggle("Descending", order: .descending)
                }
                .disabled(store.entryArrangements.groupKey != .none)
            },
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

    private func sortOrderToggle(_ title: String, order: VoyagerShared.SortOrder) -> some View {
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
}
