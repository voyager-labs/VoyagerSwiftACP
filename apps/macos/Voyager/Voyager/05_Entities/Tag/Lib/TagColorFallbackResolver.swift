import Foundation

import VoyagerEntitiesEntry

enum TagColorFallbackResolver {
    nonisolated static func normalizedTags(_ tags: [Tag]?, favoriteTags: [Tag]) -> [Tag]? {
        guard let tags, !tags.isEmpty else {
            return tags
        }

        let favoriteColorCodeByName = Dictionary(
            uniqueKeysWithValues: favoriteTags.map { (normalizedName($0.name), $0.colorCode) },
        )

        return tags.map { tag in
            guard tag.colorCode == 0,
                  let favoriteColorCode = favoriteColorCodeByName[normalizedName(tag.name)],
                  favoriteColorCode != 0
            else {
                return tag
            }

            return Tag(name: tag.name, colorCode: favoriteColorCode)
        }
    }

    nonisolated static func resolvedColorCode(
        tagName: String,
        preferredColorCodes: [Int],
        favoriteTags: [Tag],
    ) -> Int {
        if let preferredColorCode = preferredColorCodes.first(where: { $0 != 0 }) {
            return preferredColorCode
        }

        if let favoriteColorCode = favoriteTags.first(where: {
            normalizedName($0.name) == normalizedName(tagName)
        })?.colorCode {
            return favoriteColorCode
        }

        return preferredColorCodes.first ?? 0
    }

    private nonisolated static func normalizedName(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
