import AppKit
import CoreServices
import Foundation
import SwiftUI

@preconcurrency import ObjectiveC

enum SidebarItems {
    struct LocationItem: Equatable {
        let name: String
        let url: URL
        let iconName: String

        var isComputer: Bool {
            url.scheme == "computer"
        }
    }

    struct TagItem: Equatable {
        let name: String
        let color: Color
    }

    struct FavoriteItem: Equatable, Codable {
        let name: String
        let url: URL
        let iconName: String

        // swiftlint:disable:next nesting
        enum CodingKeys: String, CodingKey {
            case name
            case url
            case iconName
        }

        nonisolated init(name: String, url: URL, iconName: String) {
            self.name = name
            self.url = url
            self.iconName = iconName
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
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
            iconName = try container.decode(String.self, forKey: .iconName)
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(name, forKey: .name)
            try container.encode(url.absoluteString, forKey: .url)
            try container.encode(iconName, forKey: .iconName)
        }

        var displayName: String {
            SidebarItems.favoriteDisplayName(for: self)
        }
    }

    static func favoriteDisplayName(for favorite: FavoriteItem) -> String {
        if favorite.url.pathExtension.lowercased() == "voycoll" {
            return favorite.url.deletingPathExtension().lastPathComponent
        }
        return favorite.name
    }
}
