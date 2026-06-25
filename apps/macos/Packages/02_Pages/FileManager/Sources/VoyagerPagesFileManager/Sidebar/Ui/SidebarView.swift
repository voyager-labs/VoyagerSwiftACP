import AppKit
import ComposableArchitecture
import SwiftUI
import VoyagerShared

struct SidebarView: View {
    let store: StoreOf<FileManagerSidebarFeature>

    var body: some View {
        VStack(spacing: 0) {
            Color.clear
                .frame(height: 50)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if !store.contentTabSidebarItems.isEmpty {
                        SidebarSectionHeader(
                            title: "Tabs",
                            isCollapsed: false,
                            onToggle: {},
                        )

                        ForEach(Array(store.contentTabSidebarItems.enumerated()), id: \.element.id) { index, item in
                            SidebarItemView(
                                iconName: item.iconName ?? "doc",
                                title: item.title ?? "Untitled",
                                isSelected: item.isActive,
                                isContextMenuTarget: false,
                                contextMenuTargetWasSelected: false,
                                isFavorite: false,
                                iconColor: item.isPinned ? VoyagerDS.BrandSecondaryColor.c600 : nil,
                                targetURL: nil,
                                action: {
                                    store.send(.delegate(.selectContentTab(item.id)))
                                },
                                onDrop: nil,
                                onContextMenuOpen: nil,
                            )

                            if index < store.contentTabSidebarItems.count - 1 {
                                Spacer()
                                    .frame(height: 4)
                            }
                        }

                        Spacer()
                            .frame(height: 8)
                    }

                    SidebarItemView(
                        iconName: "clock",
                        title: "Recents",
                        isSelected: store.selectedSidebarItem == "Recents",
                        isContextMenuTarget: store.contextMenuTargetId == "Recents",
                        contextMenuTargetWasSelected: store.contextMenuTargetId == "Recents"
                            ? store.contextMenuTargetWasSelected : false,
                        isFavorite: true,
                        iconColor: nil,
                        targetURL: nil,
                        action: {
                            store.send(.delegate(.showRecents))
                        },
                        onDrop: nil,
                        onContextMenuOpen: nil,
                    )
                    .padding(.top, 8)

                    Spacer()
                        .frame(height: 8)

                    if !store.favorites.isEmpty {
                        SidebarFavoritesSectionView(store: store)
                    }

                    Spacer()
                        .frame(height: 8)

                    if !store.locations.isEmpty {
                        SidebarLocationsSectionView(store: store)
                    }

                    Spacer()
                        .frame(height: 8)

                    if !store.tags.isEmpty {
                        SidebarTagsSectionView(store: store)
                    }

                    Spacer()
                }
            }
            .clipped()
        }
        .background(Color.clear)
        .onAppear {
            store.send(.internal(.startObservingSystemNotifications))
        }
        .onDisappear {
            store.send(.internal(.stopObservingSystemNotifications))
        }
        .navigationSplitViewColumnWidth(ideal: store.sidebarWidth)
    }
}
