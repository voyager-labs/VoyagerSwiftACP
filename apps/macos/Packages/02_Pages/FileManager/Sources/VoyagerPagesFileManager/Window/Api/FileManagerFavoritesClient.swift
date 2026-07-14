import ComposableArchitecture
import Foundation
import VoyagerEntitiesCollection
import VoyagerEntitiesEntry
import VoyagerShared

@preconcurrency import ObjectiveC

public struct FileManagerFavoritesClient: Sendable {
    public var loadFavorites: @Sendable (EntryLoadingClient, UserDefaultsClient) -> [SidebarItems.FavoriteItem]
    public var saveFavorites: @Sendable ([SidebarItems.FavoriteItem], UserDefaultsClient) -> Void

    nonisolated public init(
        loadFavorites: @escaping @Sendable (EntryLoadingClient, UserDefaultsClient) -> [SidebarItems.FavoriteItem],
        saveFavorites: @escaping @Sendable ([SidebarItems.FavoriteItem], UserDefaultsClient) -> Void,
    ) {
        self.loadFavorites = loadFavorites
        self.saveFavorites = saveFavorites
    }
}

extension FileManagerFavoritesClient: DependencyKey {
    nonisolated public static var liveValue: FileManagerFavoritesClient {
        FileManagerFavoritesClient(
            loadFavorites: { entryLoadingClient, userDefaultsClient in
                if let data = userDefaultsClient.object("favorites") as? Data,
                   let favorites = try? JSONDecoder().decode([SidebarItems.FavoriteItem].self, from: data),
                   !favorites.isEmpty
                {
                    let updatedFavorites = favorites.map { favorite in
                        var isDirectory = ObjCBool(false)
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
                        Self.save(updatedFavorites, userDefaultsClient)
                    }
                    return updatedFavorites
                }

                let defaultFavorites = Self.initializeDefaultFavorites(entryLoadingClient: entryLoadingClient)
                Self.save(defaultFavorites, userDefaultsClient)
                return defaultFavorites
            },
            saveFavorites: { favorites, userDefaultsClient in
                Self.save(favorites, userDefaultsClient)
            },
        )
    }

    private static func save(_ favorites: [SidebarItems.FavoriteItem], _ userDefaultsClient: UserDefaultsClient) {
        if let encoded = try? JSONEncoder().encode(favorites) {
            userDefaultsClient.setObject(encoded, "favorites")
        }
    }

    private static func initializeDefaultFavorites(entryLoadingClient: EntryLoadingClient)
        -> [SidebarItems.FavoriteItem]
    {
        func makeFavorite(
            name: String,
            directory: FileManager.SearchPathDirectory,
            iconName: String,
            domain: FileManager.SearchPathDomainMask = .userDomainMask,
        ) -> SidebarItems.FavoriteItem? {
            guard let url = entryLoadingClient.urlsForDirectory(directory, domain).first else { return nil }
            return SidebarItems.FavoriteItem(name: name, url: url, iconName: iconName)
        }

        return [
            makeFavorite(
                name: "Applications",
                directory: .applicationDirectory,
                iconName: "folder.badge.gearshape",
                domain: .localDomainMask,
            ),
            makeFavorite(
                name: "Desktop",
                directory: .desktopDirectory,
                iconName: "menubar.dock.rectangle",
            ),
            makeFavorite(
                name: "Documents",
                directory: .documentDirectory,
                iconName: "doc.text",
            ),
            makeFavorite(
                name: "Downloads",
                directory: .downloadsDirectory,
                iconName: "arrow.down.circle",
            ),
        ].compactMap(\.self)
    }

    nonisolated public static var testValue: FileManagerFavoritesClient {
        FileManagerFavoritesClient(
            loadFavorites: { _, _ in [] },
            saveFavorites: { _, _ in },
        )
    }

    nonisolated public static var previewValue: FileManagerFavoritesClient {
        testValue
    }
}

public enum FileManagerFavoritesPinnedRecordMapper {
    nonisolated public static func pinnedRecords(
        from favorites: [SidebarItems.FavoriteItem],
        pinnedAt: Date,
        fileExistsWithIsDirectory: (String, UnsafeMutablePointer<ObjCBool>?) -> Bool,
    ) -> [ContentTabPinnedRecord] {
        favorites.compactMap { favorite in
            var isDirectory = ObjCBool(false)
            let exists = fileExistsWithIsDirectory(favorite.url.path, &isDirectory)
            guard exists else { return nil }

            if CollectionFileUtils.isCollectionFile(favorite.url) {
                return ContentTabPinnedRecord(
                    id: favoriteRecordID(for: favorite),
                    page: .collection,
                    anchor: .collectionFile(url: favorite.url),
                    title: favorite.displayName,
                    iconName: favorite.iconName,
                    pinnedAt: pinnedAt,
                )
            }

            guard isDirectory.boolValue else { return nil }
            return ContentTabPinnedRecord(
                id: favoriteRecordID(for: favorite),
                page: .directory,
                anchor: .directory(path: favorite.url.path),
                title: favorite.displayName,
                iconName: favorite.iconName,
                pinnedAt: pinnedAt,
            )
        }
    }

    nonisolated private static func favoriteRecordID(for favorite: SidebarItems.FavoriteItem) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let sanitized = favorite.url.absoluteString.unicodeScalars.map { scalar in
            allowed.contains(scalar) ? Character(scalar) : Character("-")
        }
        return "favorite-\(String(sanitized))"
    }
}

public extension DependencyValues {
    nonisolated var fileManagerFavoritesClient: FileManagerFavoritesClient {
        get { self[FileManagerFavoritesClient.self] }
        set { self[FileManagerFavoritesClient.self] = newValue }
    }
}
