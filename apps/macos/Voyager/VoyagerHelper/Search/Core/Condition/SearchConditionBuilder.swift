import Foundation

nonisolated struct SearchConditionBuilder {
    let registry: PropertyConditionRegistry
    let propertyMap: [String: PropertyMapping]
    let legacyKeyMap: [String: String]
    let operatorAliasMap: [String: String]

    struct BuilderError: Error, CustomStringConvertible {
        let message: String

        var description: String {
            message
        }
    }

    struct PropertyMapping {
        let key: String
        let type: String
        let systemKeys: [String]
        let uiHidden: Bool
    }

    nonisolated init(bundle: Bundle = .main) throws {
        registry = try RegistryLoader.load(resourceName: "property_condition_registry", bundle: bundle)
        let systemRegistry: SystemPropertyRegistry = try RegistryLoader.load(
            resourceName: "system_property_registry",
            bundle: bundle,
        )
        propertyMap = SearchConditionBuilder.buildPropertyMap(systemRegistry: systemRegistry)
        legacyKeyMap = SearchConditionBuilder.buildLegacyKeyMap(systemRegistry: systemRegistry)
        operatorAliasMap = SearchConditionBuilder.buildOperatorAliasMap(registry: registry)
    }

    nonisolated init(registry: PropertyConditionRegistry, systemRegistry: SystemPropertyRegistry) {
        self.registry = registry
        propertyMap = SearchConditionBuilder.buildPropertyMap(systemRegistry: systemRegistry)
        legacyKeyMap = SearchConditionBuilder.buildLegacyKeyMap(systemRegistry: systemRegistry)
        operatorAliasMap = SearchConditionBuilder.buildOperatorAliasMap(registry: registry)
    }

    nonisolated func canonicalOperatorCode(for rawOperator: String) -> String? {
        let normalized = rawOperator
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return operatorAliasMap[normalized]
    }
}

private extension SearchConditionBuilder {
    nonisolated static func buildOperatorAliasMap(registry: PropertyConditionRegistry) -> [String: String] {
        var map: [String: String] = [:]
        for (operatorCode, definition) in registry.operators {
            let normalizedCode = operatorCode.lowercased()
            map[normalizedCode] = operatorCode
            for alias in definition.aliases ?? [] {
                map[alias.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()] = operatorCode
            }
        }
        return map
    }
}
