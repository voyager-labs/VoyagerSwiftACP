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
    let legacyKeyMap: [String: String]

    init(bundle: Bundle = .main) throws {
        registry = try RegistryLoader.load(resourceName: "property_condition_registry", bundle: bundle)
        let systemRegistry: SystemPropertyRegistry = try RegistryLoader.load(
            resourceName: "system_property_registry",
            bundle: bundle,
        )
        propertyMap = SearchConditionBuilder.buildPropertyMap(systemRegistry: systemRegistry)
        legacyKeyMap = SearchConditionBuilder.buildLegacyKeyMap(systemRegistry: systemRegistry)
    }

    init(registry: PropertyConditionRegistry, systemRegistry: SystemPropertyRegistry) {
        self.registry = registry
        propertyMap = SearchConditionBuilder.buildPropertyMap(systemRegistry: systemRegistry)
        legacyKeyMap = SearchConditionBuilder.buildLegacyKeyMap(systemRegistry: systemRegistry)
    }
}
