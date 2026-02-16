import Foundation

enum SidebarItems {
    struct LocationItem: Equatable {
        let name: String
        let url: URL
        let iconName: String

        var isComputer: Bool {
            url.scheme == "computer"
        }
    }

    private enum FavoriteItemCodingKeys: String, CodingKey {
        case name
        case url
    }

    private enum FavoriteItemLegacyCodingKeys: String, CodingKey {
        case iconName
    }

    struct FavoriteItem: Equatable, Codable {
        let name: String
        let url: URL
        let iconName: String

        nonisolated init(name: String, url: URL, iconName: String) {
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

        var displayName: String {
            // TODO(Collection): displayName 구조 변경
            if url.pathExtension.lowercased() == CollectionConstants.fileExtension {
                return url.deletingPathExtension().lastPathComponent
            }
            return name
        }
    }
}
