import Foundation
import Logging

struct QueryGatewayConverter: Sendable {
    private let logger: Logger
    let homeDir: String
    private let conditionRegistry: PropertyConditionRegistry?
    private let conditionSanitizer: FilterSearchConditionSanitizer?
    let systemPropertyMap: [String: SystemPropertyDefinition]

    init(
        bundle: Bundle = .main,
        logger: Logger = Logger(label: "VoyagerHelper.QueryGatewayConverter"),
    ) {
        self.logger = logger
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
            let conditionBuilder = FilterSearchConditionBuilder(
                registry: loadedConditionRegistry,
                systemRegistry: systemRegistry,
            )
            conditionRegistry = loadedConditionRegistry
            conditionSanitizer = FilterSearchConditionSanitizer(conditionBuilder: conditionBuilder)
            systemPropertyMap = QueryGatewayConverter.buildSystemPropertyMap(systemRegistry: systemRegistry)
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
    ) async -> QueryGatewayConversionResult {
        do {
            guard let conditionRegistry,
                  let conditionSanitizer
            else {
                throw QueryGatewayError.registryUnavailable
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
            let systemPrompt = buildSystemPrompt()

            let content = try await requestGateway(systemPrompt: systemPrompt, userPrompt: userPrompt)
            let output = try decodeGatewayOutput(from: content)

            if let outputError = output.error,
               outputError.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            {
                logger.error("[QueryGatewayConverter] \(outputError)")
                return QueryGatewayConversionResult(conditions: [], scopes: nil, error: outputError)
            }

            let normalizedConditions = conditionSanitizer.normalizeAndValidate(output.conditions ?? [])
            let fallbackConditions = conditionSanitizer.normalizeAndValidate(visibleExistingConditions)
            let finalConditions = normalizedConditions.isEmpty ? fallbackConditions : normalizedConditions

            return QueryGatewayConversionResult(
                conditions: finalConditions,
                scopes: output.scopes,
                error: nil,
            )
        } catch {
            logger.error("[QueryGatewayConverter] conversion failed: \(error)")
            return QueryGatewayConversionResult(conditions: [], scopes: nil, error: String(describing: error))
        }
    }
}
