import Foundation
import Logging
import VoyagerShared

struct GatewayQueryConverter {
    private let logger: Logger
    private let conditionRegistry: PropertyConditionRegistry?
    private let conditionSanitizer: SearchConditionSanitizer?

    let resourceBundle: Bundle
    let homeDir: String
    let systemPropertyMap: [String: SystemPropertyDefinition]

    init(
        bundle: Bundle = .main,
        logger: Logger = Logger(label: "VoyagerHelper.GatewayQueryConverter"),
    ) {
        self.logger = logger
        resourceBundle = bundle
        homeDir = NSHomeDirectory()

        do {
            let loadedConditionRegistry: PropertyConditionRegistry = try RegistryLoader.load(
                resourceName: "property_condition_registry",
                bundle: bundle,
            )
            let systemRegistry: SystemPropertyRegistry = try RegistryLoader.load(
                resourceName: "system_property_registry",
                bundle: bundle,
            )
            let conditionBuilder = SearchConditionBuilder(
                registry: loadedConditionRegistry,
                systemRegistry: systemRegistry,
            )
            conditionRegistry = loadedConditionRegistry
            conditionSanitizer = SearchConditionSanitizer(conditionBuilder: conditionBuilder)
            systemPropertyMap = GatewayQueryConverter.buildSystemPropertyMap(systemRegistry: systemRegistry)
        } catch {
            conditionRegistry = nil
            conditionSanitizer = nil
            systemPropertyMap = [:]
            logger.error("Query converter registry load failed: \(error)")
        }
    }

    func convert(
        query: String,
        existingFilters: SearchFiltersPayload,
    ) async -> GatewayQueryResult {
        do {
            guard let conditionRegistry,
                  let conditionSanitizer
            else {
                throw GatewayQueryError.registryUnavailable
            }

            let visibleExistingConditions = existingFilters.conditions.filter {
                conditionSanitizer.isVisiblePropertyKey($0.propertyKey)
            }
            let userPrompt = buildUserPrompt(
                query: query,
                existingConditions: visibleExistingConditions,
                existingScopes: existingFilters.scopes,
                conditionRegistry: conditionRegistry,
            )
            let systemPrompt = try buildSystemPrompt()

            let content = try await requestGateway(systemPrompt: systemPrompt, userPrompt: userPrompt)
            let output = try decodeGatewayOutput(from: content)

            if let outputError = output.error,
               outputError.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            {
                logger.error("[GatewayQueryConverter] \(outputError)")
                return GatewayQueryResult(conditions: [], scopes: nil, error: outputError)
            }

            return resolveGatewayQueryResult(
                output: output,
                existingFilters: existingFilters,
                visibleExistingConditions: visibleExistingConditions,
                conditionSanitizer: conditionSanitizer,
            )
        } catch {
            logger.error("[GatewayQueryConverter] conversion failed: \(error)")
            return GatewayQueryResult(conditions: [], scopes: nil, error: String(describing: error))
        }
    }
}
