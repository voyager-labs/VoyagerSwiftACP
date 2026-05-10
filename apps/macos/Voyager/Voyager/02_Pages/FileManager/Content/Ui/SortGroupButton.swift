import AppKit
import ComposableArchitecture
import SwiftUI
import VoyagerFeaturesEntryArrangements

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
                .disabled(store.entryViewLayout.entryArrangements.groupKey != .none)
            },
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

    private func sortOrderToggle(_ title: String, order: VoyagerFeaturesEntryArrangements.SortOrder) -> some View {
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
}
