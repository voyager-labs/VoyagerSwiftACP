import Foundation
import VoyagerEntitiesCollection

public enum SidebarItems {
    public struct LocationItem: Equatable {
        public let name: String
        public let url: URL
        public let iconName: String

        public var isComputer: Bool {
            url.scheme == "computer"
        }
    }

    public struct FavoriteItem: Equatable, Codable {
        public let name: String
        public let url: URL
        public let iconName: String

        public nonisolated init(name: String, url: URL, iconName: String) {
            self.name = name
            self.url = url
            self.iconName = iconName
        }

        init(from decoder: Decoder) throws {
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

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: FavoriteItemCodingKeys.self)
            try container.encode(name, forKey: .name)
            try container.encode(url.absoluteString, forKey: .url)
        }

        public nonisolated var displayName: String {
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
