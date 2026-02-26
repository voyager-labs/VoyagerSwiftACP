import Foundation

struct SearchConditionBuilder: Sendable {
    struct BuilderError: Error, CustomStringConvertible {
        let message: String

        var description: String { message }
    }

    struct PropertyMapping: Sendable {
        let key: String
        let type: String
        let systemKeys: [String]
        let uiHidden: Bool
    }

    let registry: PropertyConditionRegistry
    let propertyMap: [String: PropertyMapping]
    let operatorAliasMap: [String: String]

    init(bundle: Bundle = .main) throws {
        registry = try RegistryLoader.load(resourceName: "property_condition_registry", bundle: bundle)
        let systemRegistry: SystemPropertyRegistry = try RegistryLoader.load(
            resourceName: "system_property_registry",
            bundle: bundle,
        )
        propertyMap = SearchConditionBuilder.buildPropertyMap(systemRegistry: systemRegistry)
        operatorAliasMap = SearchConditionBuilder.buildOperatorAliasMap(registry: registry)
    }

    init(registry: PropertyConditionRegistry, systemRegistry: SystemPropertyRegistry) {
        self.registry = registry
        propertyMap = SearchConditionBuilder.buildPropertyMap(systemRegistry: systemRegistry)
        operatorAliasMap = SearchConditionBuilder.buildOperatorAliasMap(registry: registry)
    }

    func canonicalOperatorCode(for rawOperator: String) -> String? {
        let normalized = rawOperator
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return operatorAliasMap[normalized]
    }
}

private extension SearchConditionBuilder {
    static func buildOperatorAliasMap(registry: PropertyConditionRegistry) -> [String: String] {
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
