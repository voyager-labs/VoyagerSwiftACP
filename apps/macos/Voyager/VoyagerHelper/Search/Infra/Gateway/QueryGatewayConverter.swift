import Foundation
import Logging

struct QueryGatewayConverter: Sendable {
    private let logger: Logger
    let homeDir: String
    private let conditionRegistry: PropertyConditionRegistry?
    let propertyMap: [String: SystemPropertyDefinition]

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
            conditionRegistry = loadedConditionRegistry
            propertyMap = QueryGatewayConverter.buildPropertyMap(systemRegistry: systemRegistry)
        } catch {
            conditionRegistry = nil
            propertyMap = [:]
            logger.error("Query converter registry load failed: \(error)")
        }
    }

    func convert(
        query: String,
        existingFilters: SearchFiltersPayload,
    ) async -> QueryGatewayConversionResult {
        do {
            guard let conditionRegistry else {
                throw QueryGatewayError.registryUnavailable
            }

            let visibleExistingConditions = existingFilters.conditions.filter { isVisibleKey($0.propertyKey) }
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

            let normalizedConditions = normalizeAndValidateConditions(
                output.conditions ?? [],
                conditionRegistry: conditionRegistry,
            )
            let fallbackConditions = normalizeAndValidateConditions(
                visibleExistingConditions,
                conditionRegistry: conditionRegistry,
            )
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
