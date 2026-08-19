import Foundation
import VoyagerEntitiesCollection

// MARK: - Home/Favorite Model

// MARK: - Fixed Location Model

public struct FileManagerFixedLocationItem: Equatable, Sendable, Identifiable {
    public let id: String
    public let title: String
    public let path: String
    public let iconName: String
    public let accessibilityLabel: String
    public let kind: SidebarItems.Kind

    public init(
        id: String,
        title: String,
        path: String,
        iconName: String,
        accessibilityLabel: String,
        kind: SidebarItems.Kind = .directory,
    ) {
        self.id = id
        self.title = title
        self.path = path
        self.iconName = iconName
        self.accessibilityLabel = accessibilityLabel
        self.kind = kind
    }
}

public struct FileManagerHomeFavoriteItem: Equatable, Sendable, Identifiable {
    public let id: ContentTabID
    public let title: String?
    public let iconName: String?
    public let filePath: String?
    public let anchor: ContentTabPageAnchor
    public let page: ContentTabPage

    public init(
        id: ContentTabID,
        title: String?,
        iconName: String?,
        anchor: ContentTabPageAnchor,
        page: ContentTabPage,
        filePath: String? = nil,
    ) {
        self.id = id
        self.title = title
        self.iconName = iconName
        self.anchor = anchor
        self.page = page
        self.filePath = filePath
    }
}

// MARK: - Home/ChatHistory Model

public struct FileManagerHomeChatHistoryItem: Equatable, Sendable {
    public let sessionID: String
    public let title: String?
    public let detail: String?
    public let updatedAtMs: Int64

    public init(
        sessionID: String,
        title: String?,
        detail: String?,
        updatedAtMs: Int64,
    ) {
        self.sessionID = sessionID
        self.title = title
        self.detail = detail
        self.updatedAtMs = updatedAtMs
    }
}

// MARK: - Namespace

public enum FileManagerHomeDashboardProjection {}

// MARK: - Home Favorites (Finder Favorites Projection)

public extension FileManagerHomeDashboardProjection {
    static func homeFavorites(
        from favorites: [SidebarItems.FavoriteItem],
        fileExistsWithIsDirectory: (String, UnsafeMutablePointer<ObjCBool>?) -> Bool,
    ) -> [FileManagerHomeFavoriteItem] {
        favorites.compactMap { favorite -> FileManagerHomeFavoriteItem? in
            var isDirectory = ObjCBool(false)
            guard fileExistsWithIsDirectory(favorite.url.path, &isDirectory) else { return nil }

            let page: ContentTabPage
            let anchor: ContentTabPageAnchor
            if CollectionFileUtils.isCollectionFile(favorite.url) {
                page = .collection
                anchor = .collectionFile(url: favorite.url)
            } else if isDirectory.boolValue {
                page = .directory
                anchor = .directory(path: favorite.url.path)
            } else {
                return nil
            }

            return FileManagerHomeFavoriteItem(
                id: ContentTabID(rawValue: favoriteID(for: favorite)),
                title: favorite.displayName,
                iconName: favorite.iconName,
                anchor: anchor,
                page: page,
                filePath: favorite.url.path,
            )
        }
    }

    private static func favoriteID(for favorite: SidebarItems.FavoriteItem) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let sanitized = favorite.url.absoluteString.unicodeScalars.map { scalar in
            allowed.contains(scalar) ? Character(scalar) : Character("-")
        }
        return "home-favorite-\(String(sanitized))"
    }
}

// MARK: - Fixed Locations

public extension FileManagerHomeDashboardProjection {
    static func makeFixedLocations(from locations: [SidebarItems.LocationItem]) -> [FileManagerFixedLocationItem] {
        locations
            .filter(\.url.isFileURL)
            .map { location in
                FileManagerFixedLocationItem(
                    id: fixedLocationID(for: location),
                    title: location.name,
                    path: location.url.path,
                    iconName: location.iconName,
                    accessibilityLabel: location.name,
                    kind: location.kind,
                )
            }
    }

    private static func fixedLocationID(for location: SidebarItems.LocationItem) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let sanitized = location.url.absoluteString.unicodeScalars.map { scalar in
            allowed.contains(scalar) ? Character(scalar) : Character("-")
        }
        return "fixed-location-\(String(sanitized))"
    }
}
