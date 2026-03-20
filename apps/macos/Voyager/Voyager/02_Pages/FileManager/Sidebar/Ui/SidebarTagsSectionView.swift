import ComposableArchitecture
import SwiftUI

struct SidebarTagsSectionView: View {
    let store: StoreOf<FileManagerSidebarFeature>

    var body: some View {
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
                        isContextMenuTarget: store.contextMenuTargetId == tag.name,
                        contextMenuTargetWasSelected: store.contextMenuTargetId == tag.name
                            ? store.contextMenuTargetWasSelected : false,
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
