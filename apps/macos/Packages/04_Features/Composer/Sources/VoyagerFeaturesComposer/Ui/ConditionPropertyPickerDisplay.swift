import Foundation

enum ConditionPropertyPickerDisplay {
    struct NativeMenuConfiguration {
        let properties: [String]
        let existingKeys: Set<String>
        let editingKey: String?
        let defaults: Set<String>
        let categories: [String: String]
        let labels: [String: String]
        let selectedKey: String?
    }

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

    static func nativeMenuItems(
        configuration: NativeMenuConfiguration,
        onSelect: @escaping (String) -> Void,
    ) -> [ComposerNativeMenuItem] {
        let filtered = filteredProperties(
            properties: configuration.properties,
            existingKeys: configuration.existingKeys,
            editingKey: configuration.editingKey,
            searchText: "",
            labels: configuration.labels,
        )
        let recommended = recommendedProperties(from: filtered, defaults: configuration.defaults)
        let recommendedKeys = Set(recommended)
        let grouped = groupedByCategory(filtered, categories: configuration.categories)
            .mapValues { $0.filter { !recommendedKeys.contains($0) } }
            .filter { !$0.value.isEmpty }

        let recommendedItems = recommended.map { propertyMenuItem(
            key: $0,
            labels: configuration.labels,
            selectedKey: configuration.selectedKey,
            onSelect: onSelect,
        )
        }
        let categoryItems = grouped.keys.sorted().map { categoryKey in
            ComposerNativeMenuItem.submenu(
                title: categoryTitle(for: categoryKey),
                items: (grouped[categoryKey] ?? []).map { propertyMenuItem(
                    key: $0,
                    labels: configuration.labels,
                    selectedKey: configuration.selectedKey,
                    onSelect: onSelect,
                )
                },
            )
        }

        return recommendedItems + (recommendedItems.isEmpty || categoryItems.isEmpty ? [] : [.separator()]) +
            categoryItems
    }

    private static func propertyMenuItem(
        key: String,
        labels: [String: String],
        selectedKey: String?,
        onSelect: @escaping (String) -> Void,
    ) -> ComposerNativeMenuItem {
        .init(
            title: labels[key] ?? key,
            isSelected: key == selectedKey,
            isEnabled: true,
            action: { onSelect(key) },
        )
    }
}
