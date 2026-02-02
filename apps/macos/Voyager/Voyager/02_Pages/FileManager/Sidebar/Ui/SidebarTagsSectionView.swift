import ComposableArchitecture
import SwiftUI

struct SidebarTagsSectionView: View {
    @Binding var contextMenuTargetId: String?
    @Binding var contextMenuTargetWasSelected: Bool

    let store: StoreOf<FileManagerSidebarFeature>

    var body: some View {
        Group {
            if !store.tags.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    SidebarSectionHeader(
                        title: "Tags",
                        isCollapsed: store.isTagsCollapsed,
                        onToggle: {
                            store.send(.toggleTagsSection)
                        },
                    )
                    .padding(.top, 8)

                    if !store.isTagsCollapsed {
                        ForEach(store.tags, id: \.name) { tag in
                            SidebarTagItemView(
                                tag: tag,
                                isSelected: store.selectedSidebarItem == tag.name,
                                isContextMenuTarget: contextMenuTargetId == tag.name,
                                contextMenuTargetWasSelected: contextMenuTargetId == tag.name
                                    ? contextMenuTargetWasSelected : false,
                                action: {
                                    store.send(.showTag(tag))
                                },
                                onDrop: { providers, tagName in
                                    store.send(.dropItemsToTag(providers: providers, tagName: tagName))
                                },
                                onContextMenuOpen: nil,
                            )
                        }
                    }
                }
            }
        }
    }
}
