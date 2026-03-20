import ComposableArchitecture
import SwiftUI

struct SidebarLocationsSectionView: View {
    let store: StoreOf<FileManagerSidebarFeature>

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SidebarSectionHeader(
                title: "Locations",
                isCollapsed: store.isLocationsCollapsed,
                onToggle: {
                    store.send(.view(.toggleLocationsSection))
                },
            )
            .padding(.top, 8)

            if !store.isLocationsCollapsed {
                ForEach(store.locations, id: \.url) { location in
                    let isSelected = store.selectedSidebarItem == location.name
                    let isContextMenuTarget = store.contextMenuTargetId == location.name
                    let wasSelected = isContextMenuTarget ? store.contextMenuTargetWasSelected : false

                    SidebarItemView(
                        iconName: location.iconName,
                        title: location.name,
                        isSelected: isSelected,
                        isContextMenuTarget: isContextMenuTarget,
                        contextMenuTargetWasSelected: wasSelected,
                        isFavorite: false,
                        iconColor: nil,
                        targetURL: location.isComputer ? nil : location.url,
                        action: {
                            if location.isComputer {
                                store.send(.view(.showComputer))
                            } else {
                                store.send(.view(.openLocation(location)))
                            }
                        },
                        onDrop: { providers, targetURL in
                            store.send(.view(.dropItemsToSidebarFolder(providers: providers, targetURL: targetURL)))
                        },
                        onContextMenuOpen: nil,
                    )
                }
            }
        }
    }
}
