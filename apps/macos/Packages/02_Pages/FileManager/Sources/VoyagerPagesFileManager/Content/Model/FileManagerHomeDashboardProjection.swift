import Foundation

// MARK: - Home/Favorite Model

// MARK: - Fixed Location Model

public struct FileManagerFixedLocationItem: Equatable, Sendable, Identifiable {
    public let id: String
    public let title: String
    public let path: String
    public let iconName: String
    public let accessibilityLabel: String

    public init(
        id: String,
        title: String,
        path: String,
        iconName: String,
        accessibilityLabel: String,
    ) {
        self.id = id
        self.title = title
        self.path = path
        self.iconName = iconName
        self.accessibilityLabel = accessibilityLabel
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
        filePath: String? = nil,
        anchor: ContentTabPageAnchor,
        page: ContentTabPage,
    ) {
        self.id = id
        self.title = title
        self.iconName = iconName
        self.filePath = filePath
        self.anchor = anchor
        self.page = page
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

// MARK: - Home Favorites (Pinned ContentTab Projection)

public extension FileManagerHomeDashboardProjection {
    static func homeFavorites(from contentTabs: ContentTabState) -> [FileManagerHomeFavoriteItem] {
        contentTabs.tabs
            .filter(\.isPinned)
            .filter { tab in
                switch tab.anchor {
                case .directory, .collectionFile:
                    true
                case .homeDefault, .virtualCollection, .aiChat:
                    false
                }
            }
            .map { tab in
                FileManagerHomeFavoriteItem(
                    id: tab.id,
                    title: tab.title,
                    iconName: tab.iconName,
                    filePath: filePath(for: tab.anchor),
                    anchor: tab.anchor,
                    page: tab.page,
                )
            }
    }

    private static func filePath(for anchor: ContentTabPageAnchor) -> String? {
        switch anchor {
        case let .directory(path):
            path
        case let .collectionFile(url):
            url.path
        case .homeDefault, .virtualCollection, .aiChat:
            nil
        }
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
