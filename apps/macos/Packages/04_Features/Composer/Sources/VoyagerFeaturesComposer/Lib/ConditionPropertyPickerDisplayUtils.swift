import Foundation

enum ConditionPropertyPickerDisplayUtils {
    static func recommendedProperties(
        from filtered: [String],
        defaults: Set<String>,
    ) -> [String] {
        filtered.filter { defaults.contains($0) }
    }

    static func groupedByCategory(
        _ filtered: [String],
        categories: [String: String],
    ) -> [String: [String]] {
        Dictionary(grouping: filtered) { key in
            categories[key] ?? "misc"
        }
    }

    static func filteredProperties(
        properties: [String],
        existingKeys: Set<String>,
        editingKey: String?,
        searchText: String,
        labels: [String: String],
    ) -> [String] {
        let available = properties.filter { key in
            !(existingKeys.contains(key) && key != editingKey)
        }

        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return available }

        return available.filter { key in
            let label = labels[key] ?? key
            return label.localizedCaseInsensitiveContains(query)
        }
    }

    static func categoryTitle(for key: String) -> String {
        let spaced = key
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "([a-z])([A-Z])", with: "$1 $2", options: .regularExpression)
        return spaced.prefix(1).uppercased() + spaced.dropFirst()
    }
}
