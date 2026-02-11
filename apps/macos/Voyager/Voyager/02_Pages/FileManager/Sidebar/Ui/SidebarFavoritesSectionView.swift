import ComposableArchitecture
import Foundation
import SwiftUI
import UniformTypeIdentifiers

struct SidebarFavoritesSectionView: View {
    @Binding var contextMenuTargetId: String?
    @Binding var contextMenuTargetWasSelected: Bool

    @State private var dropTargetIndex: Int?

    let store: StoreOf<FileManagerSidebarFeature>

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SidebarSectionHeader(
                title: "Favorites",
                isCollapsed: store.isFavoritesCollapsed,
                onToggle: {
                    store.send(.toggleFavoritesSection)
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
                        isContextMenuTarget: contextMenuTargetId == favorite.displayName,
                        contextMenuTargetWasSelected: contextMenuTargetId == favorite.displayName
                            ? contextMenuTargetWasSelected : false,
                        isFavorite: true,
                        // TODO(Collection): Collection 관련 상수 이관
                        iconColor: favorite.url.pathExtension.lowercased() == "voycoll"
                            ? VoyagerDS.BrandSecondaryColor.c600
                            : nil,
                        targetURL: favorite.url,
                        action: {
                            store.send(.openFavorite(favorite))
                        },
                        onDrop: { providers, targetURL in
                            store.send(.dropItemsToSidebarFolder(
                                providers: providers,
                                targetURL: targetURL,
                            ))
                        },
                        onContextMenuOpen: {
                            contextMenuTargetId = favorite.displayName
                            contextMenuTargetWasSelected = store.selectedSidebarItem == favorite.displayName
                        },
                    )
                    .contextMenu {
                        Button("Remove from Sidebar") {
                            store.send(.removeFavorite(favorite))
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
                    index: index,
                    dropTargetIndex: $dropTargetIndex,
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

        store.send(.insertFavoriteFromDrop(providers: fileURLProviders, at: index))
        return true
    }
}
