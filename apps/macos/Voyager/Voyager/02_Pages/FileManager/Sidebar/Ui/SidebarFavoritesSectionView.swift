import AppKit
import ComposableArchitecture
import SwiftUI
import UniformTypeIdentifiers

struct SidebarFavoritesSectionView: View {
    @Dependency(\.entryClient)
    private var entryClient

    @Binding var dropTargetIndex: Int?
    @Binding var draggingFavoriteURL: URL?
    @Binding var contextMenuTargetId: String?
    @Binding var contextMenuTargetWasSelected: Bool

    let store: StoreOf<FileManagerSidebarFeature>

    var body: some View {
        Group {
            if !store.favorites.isEmpty {
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
                                draggingFavoriteURL = favorite.url
                                return NSItemProvider(object: favorite.url as NSURL)
                            }

                            favoriteDropIndicator(at: index + 1)
                        }
                    }
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
                    entryClient: entryClient,
                    resolveURL: { providers, completion in
                        resolveFirstDropURL(from: providers, completion: completion)
                    },
                    onDrop: handleFavoriteInsert(providers:at:),
                ),
            )
    }

    private func handleFavoriteInsert(providers: [NSItemProvider], at index: Int) -> Bool {
        dropTargetIndex = nil

        var hasProvider = false
        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            hasProvider = true
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { data, _ in
                if let data = data as? Data,
                   let urlString = String(data: data, encoding: .utf8),
                   let url = URL(string: urlString)
                {
                    Task { @MainActor in
                        let entryClient = entryClient
                        if let existingIndex = store.favorites.firstIndex(where: { $0.url.path == url.path }) {
                            if existingIndex != index {
                                store.send(.reorderFavorites(from: IndexSet(integer: existingIndex), to: index))
                            }
                            draggingFavoriteURL = nil
                            return
                        }
                        var isDirectory: ObjCBool = false
                        guard entryClient.fileExistsAtPath(url.path, &isDirectory),
                              isDirectory.boolValue || url.pathExtension.lowercased() == "voycoll"
                        else {
                            return
                        }
                        store.send(.insertFavorite(url: url, at: index))
                        draggingFavoriteURL = nil
                    }
                }
            }
        }
        return hasProvider
    }

    private func resolveFirstDropURL(
        from providers: [NSItemProvider],
        completion: @escaping @Sendable (URL?) -> Void,
    ) {
        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { data, _ in
                guard let data = data as? Data,
                      let urlString = String(data: data, encoding: .utf8),
                      let url = URL(string: urlString)
                else {
                    completion(nil)
                    return
                }
                completion(url)
            }
            return
        }
        completion(nil)
    }
}
