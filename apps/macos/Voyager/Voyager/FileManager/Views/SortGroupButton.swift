import AppKit
import ComposableArchitecture
import SwiftUI

struct SortGroupButton: View {
    let store: StoreOf<FileManagerFeature>
    @Environment(\.colorScheme)
    var colorScheme
    @State private var isHovered: Bool = false

    var body: some View {
        Menu {
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
            .disabled(store.fsItems.groupKey != .none)
        } label: {
            ZStack {
                Image(systemName: "arrow.up.arrow.down")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .frame(width: 24, height: 24)
                    .background(
                        Group {
                            if isHovered {
                                ZStack {
                                    RoundedRectangle(cornerRadius: VoyagerDS.Radius.toolbarButton)
                                        .fill(VoyagerDS.Surface.toolbarMenuButtonBackground(for: colorScheme))
                                    RoundedRectangle(cornerRadius: VoyagerDS.Radius.toolbarButton)
                                        .fill(VoyagerDS.Interaction.toolbarButtonHoverFill(for: colorScheme))
                                }
                            }
                        }
                        .allowsHitTesting(false),
                    )
            }
            .frame(width: 24, height: 24)
            .contentShape(Rectangle())
            .background(
                HoverTrackingOverlay(isHovered: $isHovered),
            )
        }
        .menuIndicator(.hidden)
        .buttonStyle(.borderless)
    }

    private func groupKeyToggle(_ title: String, key: GroupKey) -> some View {
        Toggle(
            title,
            isOn: Binding(
                get: { store.fsItems.groupKey == key },
                set: { isOn in
                    if isOn {
                        store.send(.changeGroupKey(key))
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
}
