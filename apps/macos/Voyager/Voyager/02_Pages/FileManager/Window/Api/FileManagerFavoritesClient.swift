import ComposableArchitecture
import Foundation

@preconcurrency import ObjectiveC

struct FileManagerFavoritesClient: Sendable {
    var loadFavorites: @Sendable (EntryLoadingClient, UserDefaultsClient) async -> [SidebarItems.FavoriteItem]
    var saveFavorites: @Sendable ([SidebarItems.FavoriteItem], UserDefaultsClient) -> Void

    nonisolated init(
        loadFavorites: @escaping @Sendable (EntryLoadingClient, UserDefaultsClient) async
            -> [SidebarItems.FavoriteItem],
        saveFavorites: @escaping @Sendable ([SidebarItems.FavoriteItem], UserDefaultsClient) -> Void,
    ) {
        self.loadFavorites = loadFavorites
        self.saveFavorites = saveFavorites
    }
}

extension FileManagerFavoritesClient: DependencyKey {
    nonisolated static var liveValue: FileManagerFavoritesClient {
        FileManagerFavoritesClient(
            loadFavorites: { entryLoadingClient, userDefaultsClient in
                let defaultFavorites = await Self.initializeDefaultFavorites(entryLoadingClient: entryLoadingClient)
                return await MainActor.run {
                    if let data = userDefaultsClient.object("favorites") as? Data,
                       let favorites = try? JSONDecoder().decode([SidebarItems.FavoriteItem].self, from: data),
                       !favorites.isEmpty
                    {
                        let updatedFavorites = favorites.map { favorite in
                            if favorite.url.path == "/Applications" {
                                return SidebarItems.FavoriteItem(
                                    name: favorite.name,
                                    url: favorite.url,
                                    iconName: "appstore",
                                )
                            }

                            var isDirectory: ObjCBool = false
                            if entryLoadingClient.fileExistsAtPath(favorite.url.path, &isDirectory) {
                                let iconName = FileManagerIconClient.resolveIconName(
                                    for: favorite.url,
                                    isDirectory: isDirectory.boolValue,
                                    entryLoadingClient: entryLoadingClient,
                                )
                                return SidebarItems.FavoriteItem(
                                    name: favorite.name,
                                    url: favorite.url,
                                    iconName: iconName,
                                )
                            }

                            return favorite
                        }
                        if updatedFavorites != favorites {
                            let encoded = try? JSONEncoder().encode(updatedFavorites)
                            userDefaultsClient.setObject(encoded, "favorites")
                        }
                        return updatedFavorites
                    }

                    let encoded = try? JSONEncoder().encode(defaultFavorites)
                    userDefaultsClient.setObject(encoded, "favorites")
                    return defaultFavorites
                }
            },
            saveFavorites: { favorites, userDefaultsClient in
                if let encoded = try? JSONEncoder().encode(favorites) {
                    userDefaultsClient.setObject(encoded, "favorites")
                }
            },
        )
    }

    private static func initializeDefaultFavorites(entryLoadingClient: EntryLoadingClient) async
        -> [SidebarItems.FavoriteItem]
    {
        await MainActor.run {
            func makeFavorite(
                name: String,
                directory: FileManager.SearchPathDirectory,
                iconName: String,
                entryLoadingClient: EntryLoadingClient,
                domain: FileManager.SearchPathDomainMask = .userDomainMask,
            ) -> SidebarItems.FavoriteItem? {
                guard let url = entryLoadingClient.urlsForDirectory(directory, domain).first else { return nil }
                return SidebarItems.FavoriteItem(name: name, url: url, iconName: iconName)
            }

            return [
                makeFavorite(
                    name: "Applications",
                    directory: .applicationDirectory,
                    iconName: "appstore",
                    entryLoadingClient: entryLoadingClient,
                    domain: .localDomainMask,
                ),
                makeFavorite(
                    name: "Desktop",
                    directory: .desktopDirectory,
                    iconName: "menubar.dock.rectangle",
                    entryLoadingClient: entryLoadingClient,
                ),
                makeFavorite(
                    name: "Documents",
                    directory: .documentDirectory,
                    iconName: "doc",
                    entryLoadingClient: entryLoadingClient,
                ),
                makeFavorite(
                    name: "Downloads",
                    directory: .downloadsDirectory,
                    iconName: "arrow.down.circle",
                    entryLoadingClient: entryLoadingClient,
                ),
            ].compactMap(\.self)
        }
    }

    nonisolated static var testValue: FileManagerFavoritesClient {
        FileManagerFavoritesClient(
            loadFavorites: { _, _ in [] },
            saveFavorites: { _, _ in },
        )
    }

    nonisolated static var previewValue: FileManagerFavoritesClient {
        testValue
    }
}

extension DependencyValues {
    nonisolated var fileManagerFavoritesClient: FileManagerFavoritesClient {
        get { self[FileManagerFavoritesClient.self] }
        set { self[FileManagerFavoritesClient.self] = newValue }
    }
}
