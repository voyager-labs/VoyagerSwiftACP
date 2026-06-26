import AppKit
import ComposableArchitecture
import SwiftUI
import VoyagerEntitiesTag
import VoyagerShared

struct SidebarView: View {
    let store: StoreOf<FileManagerSidebarFeature>

    @Environment(\.colorScheme)
    private var colorScheme

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
                            contentTabRow(item)

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

    @ViewBuilder
    private func contentTabRow(_ item: ContentTabProjection.ContentTabSidebarItem) -> some View {
        if let tagColorCode = item.tagColorCode {
            HStack(spacing: 8) {
                ColorDotView(nsColor: TagColor(colorCode: tagColorCode).nsColor, size: 8)
                Text(item.title ?? "Untitled")
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(item.isActive ? VoyagerDS.Surface.sidebarSelectionBackground(for: colorScheme) : Color.clear),
            )
            .padding(.horizontal, 4)
            .contentShape(Rectangle())
            .onTapGesture {
                store.send(.delegate(.selectContentTab(item.id)))
            }
        } else {
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
        }
    }
}
