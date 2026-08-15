import Foundation
import VoyagerEntitiesCollection

public enum FileManagerSidebarTopNavigationItem: Equatable, Sendable, Identifiable {
    case location(FileManagerFixedLocationItem)
    case contentTab(ContentTabProjection.ContentTabSidebarItem)

    public var id: FileManagerTopNavigationItemID {
        switch self {
        case let .location(item):
            .location(item.id)
        case let .contentTab(item):
            .contentTab(item.id)
        }
    }
}

public enum SidebarItems {
    public enum Kind: Equatable, Sendable {
        case directory
        case trash
    }

    public struct LocationItem: Equatable, Sendable {
        public typealias Kind = SidebarItems.Kind

        public let name: String
        public let url: URL
        public let iconName: String
        public let kind: Kind

        nonisolated public init(
            name: String,
            url: URL,
            iconName: String,
            kind: Kind = .directory,
        ) {
            self.name = name
            self.url = url
            self.iconName = iconName
            self.kind = kind
        }

        nonisolated public var isComputer: Bool {
            url.scheme == "computer"
        }
    }

    public struct FavoriteItem: Equatable, Codable, Sendable {
        public let name: String
        public let url: URL
        public let iconName: String

        nonisolated public init(name: String, url: URL, iconName: String) {
            self.name = name
            self.url = url
            self.iconName = iconName
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: FavoriteItemCodingKeys.self)
            name = try container.decode(String.self, forKey: .name)
            let urlString = try container.decode(String.self, forKey: .url)
            guard let decodedURL = URL(string: urlString) else {
                throw DecodingError.dataCorruptedError(
                    forKey: .url,
                    in: container,
                    debugDescription: "Invalid URL string",
                )
            }
            url = decodedURL

            // 과거 favorites 데이터와의 호환을 위해 legacy iconName을 읽고, 없으면 기본 아이콘을 사용한다.
            let legacyContainer = try decoder.container(keyedBy: FavoriteItemLegacyCodingKeys.self)
            iconName = try legacyContainer.decodeIfPresent(String.self, forKey: .iconName) ?? "folder"
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: FavoriteItemCodingKeys.self)
            try container.encode(name, forKey: .name)
            try container.encode(url.absoluteString, forKey: .url)
        }

        nonisolated public var displayName: String {
            CollectionFileUtils.displayName(url, fallback: name)
        }
    }

    private enum FavoriteItemCodingKeys: String, CodingKey {
        case name
        case url
    }

    private enum FavoriteItemLegacyCodingKeys: String, CodingKey {
        case iconName
    }
}
