import Foundation

struct FilterSearchConditionBuilder: Sendable {
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

    init(bundle: Bundle = .main) throws {
        registry = try RegistryLoader.load(resourceName: "property_condition_registry", bundle: bundle)
        let systemRegistry: SystemPropertyRegistry = try RegistryLoader.load(
            resourceName: "system_property_registry",
            bundle: bundle,
        )
        propertyMap = FilterSearchConditionBuilder.buildPropertyMap(systemRegistry: systemRegistry)
    }

    init(registry: PropertyConditionRegistry, systemRegistry: SystemPropertyRegistry) {
        self.registry = registry
        propertyMap = FilterSearchConditionBuilder.buildPropertyMap(systemRegistry: systemRegistry)
    }
}
