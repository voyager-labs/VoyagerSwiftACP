import Foundation
import VoyagerEntitiesCollection
import VoyagerEntitiesEntry
import VoyagerEntitiesTag

enum ConditionTagSuggestions {
    static func normalizedTokenKey(_ raw: String) -> String {
        raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive], locale: .current)
    }

    static func deduplicatedTagsByName(_ tags: [Tag]) -> [Tag] {
        var seen: Set<String> = []
        var result: [Tag] = []

        for tag in tags {
            let name = tag.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { continue }
            let normalized = normalizedTokenKey(name)
            if seen.insert(normalized).inserted {
                result.append(tag)
            }
        }

        return result
    }

    static func filteredFinderTags(selectedTokens: [String], finderTagOptions: [Tag], query: String) -> [Tag] {
        let selected = Set(selectedTokens.map(normalizedTokenKey))
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)

        return finderTagOptions.filter { tag in
            let normalizedName = normalizedTokenKey(tag.name)
            guard !selected.contains(normalizedName) else { return false }
            guard !trimmedQuery.isEmpty else { return true }

            let displayName = tag.name.trimmingCharacters(in: .whitespacesAndNewlines)
            return displayName.localizedCaseInsensitiveContains(trimmedQuery)
        }
    }
}
