import ComposableArchitecture
import Foundation
import SwiftUI
import UniformTypeIdentifiers
import VoyagerShared

struct SidebarFavoritesSectionView: View {
    @State private var dropTargetIndex: Int?

    let store: StoreOf<FileManagerSidebarFeature>

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SidebarSectionHeader(
                title: "Favorites",
                isCollapsed: store.isFavoritesCollapsed,
                onToggle: {
                    store.send(.view(.toggleFavoritesSection))
                },
            )
            .padding(.top, 8)

            if !store.isFavoritesCollapsed {
                favoriteDropIndicator(at: 0)

                ForEach(Array(store.favorites.enumerated()), id: \.element.url) { index, favorite in
                    SidebarItemView(
                        iconName: favorite.iconName,
                        title: favorite.displayName,
                        isSelected: store.selectedSidebarItem == favorite.displayName,
                        isContextMenuTarget: store.contextMenuTargetId == favorite.displayName,
                        contextMenuTargetWasSelected: store.contextMenuTargetId == favorite.displayName
                            ? store.contextMenuTargetWasSelected : false,
                        isFavorite: true,
                        iconColor: favorite.url.pathExtension.lowercased() == CollectionConstants.fileExtension
                            ? VoyagerDS.BrandSecondaryColor.c600
                            : nil,
                        targetURL: favorite.url,
                        action: {
                            store.send(.delegate(.openFavorite(favorite)))
                        },
                        onDrop: { providers, targetURL in
                            store.send(.delegate(.dropItemsToSidebarFolder(
                                providers: providers,
                                targetURL: targetURL,
                            )))
                        },
                        onContextMenuOpen: {
                            store.send(.view(.setContextMenuTarget(
                                id: favorite.displayName,
                                wasSelected: store.selectedSidebarItem == favorite.displayName,
                            )))
                        },
                    )
                    .contextMenu {
                        Button("Remove from Sidebar") {
                            store.send(.internal(.removeFavorite(favorite)))
                        }
                    }
                    .onDrag {
                        NSItemProvider(object: favorite.url as NSURL)
                    }

                    favoriteDropIndicator(at: index + 1)
                }
            }
        }
    }

    @ViewBuilder
    private func favoriteDropIndicator(at index: Int) -> some View {
        let isActive = dropTargetIndex == index

        Rectangle()
            .fill(Color.clear)
            .frame(height: 4)
            .frame(maxWidth: .infinity)
            .overlay(
                Group {
                    if isActive {
                        Rectangle()
                            .fill(Color.accentColor)
                            .frame(height: 2)
                    }
                },
            )
            .padding(.horizontal, 8)
            .contentShape(Rectangle())
            .onDrop(
                of: [UTType.fileURL],
                delegate: FileManagerFavoriteDropDelegate(
                    dropTargetIndex: $dropTargetIndex,
                    index: index,
                    onDrop: handleFavoriteInsert(providers:at:),
                ),
            )
    }

    private func handleFavoriteInsert(providers: [NSItemProvider], at index: Int) -> Bool {
        dropTargetIndex = nil

        let fileURLProviders = providers.filter {
            $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier)
        }
        guard !fileURLProviders.isEmpty else {
            return false
        }

        store.send(.internal(.insertFavoriteFromDrop(providers: fileURLProviders, at: index)))
        return true
    }
}
