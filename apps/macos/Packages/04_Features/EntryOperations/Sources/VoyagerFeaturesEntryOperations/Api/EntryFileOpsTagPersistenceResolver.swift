import Foundation
import VoyagerEntitiesEntry
import VoyagerEntitiesTag

public enum EntryFileOpsTagPersistenceResolver {
    nonisolated public static func makeTags(
        tagNames: [String],
        existingTags: [Tag],
        favoriteTags: [Tag],
    ) -> [Tag] {
        let existingTagsByName = Dictionary(uniqueKeysWithValues: existingTags.map { ($0.name, $0) })
        let favoriteColorCodeByName = Dictionary(uniqueKeysWithValues: favoriteTags.map { ($0.name, $0.colorCode) })

        return tagNames.map { name in
            if let existingTag = existingTagsByName[name] {
                return existingTag
            }

            if let favoriteColorCode = favoriteColorCodeByName[name] {
                return Tag(name: name, colorCode: favoriteColorCode)
            }

            return Tag(name: name, colorCode: 0)
        }
    }
}
