import Foundation
import Logging
import VoyagerShared

struct QueryConversionInterpreter {
    private let logger: Logger
    private let conditionRegistry: PropertyConditionRegistry?
    private let conditionSanitizer: SearchConditionSanitizer?

    let resourceBundle: Bundle
    let homeDir: String
    let systemPropertyMap: [String: SystemPropertyDefinition]

    init(
        bundle: Bundle = .main,
        logger: Logger = Logger(label: "VoyagerHelper.QueryConversionInterpreter"),
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
            systemPropertyMap = QueryConversionInterpreter.buildSystemPropertyMap(systemRegistry: systemRegistry)
        } catch {
            conditionRegistry = nil
            conditionSanitizer = nil
            systemPropertyMap = [:]
            logger.error("Query converter registry load failed: \(error)")
        }
    }

    func buildPrompt(
        query: String,
        existingFilters: SearchFiltersPayload,
    ) throws -> QueryConversionPromptPayload {
        let conditionRegistry = try requireConditionRegistry()
        guard let conditionSanitizer else {
            throw QueryConversionError.registryUnavailable
        }

        let visibleExistingConditions = existingFilters.conditions.filter {
            conditionSanitizer.isVisiblePropertyKey($0.propertyKey)
        }
        let systemPrompt = try buildSystemPrompt()
        let userPrompt = buildUserPrompt(
            query: query,
            existingConditions: visibleExistingConditions,
            existingScopes: existingFilters.scopes,
            conditionRegistry: conditionRegistry,
        )
        return QueryConversionPromptPayload(systemPrompt: systemPrompt, userPrompt: userPrompt)
    }

    func decodeAndNormalize(
        content: String,
        existingFilters: SearchFiltersPayload,
    ) throws -> QueryConversionResult {
        guard let conditionSanitizer else {
            throw QueryConversionError.registryUnavailable
        }

        let output = try decodeQueryConversionOutput(from: content)

        if let outputError = output.error,
           outputError.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        {
            logger.error("[QueryConversionInterpreter] \(outputError)")
            return QueryConversionResult(
                conditions: [],
                scopes: nil,
                error: outputError,
                outcome: .conversionFailure,
            )
        }

        let visibleExistingConditions = existingFilters.conditions.filter {
            conditionSanitizer.isVisiblePropertyKey($0.propertyKey)
        }
        let outputConditions = output.conditions ?? []
        let normalizedConditions = conditionSanitizer.normalizeAndValidate(outputConditions)
        let fallbackConditions = conditionSanitizer.normalizeAndValidate(visibleExistingConditions)
        let cleanedExistingScopes = cleanScopes(existingFilters.scopes)
        let cleanedOutputScopes = cleanScopes(output.scopes ?? existingFilters.scopes)

        if outputConditions.isEmpty == false, normalizedConditions.isEmpty {
            let error = "Generated filters could not be validated."
            logger.error("[QueryConversionInterpreter] \(error)")
            return QueryConversionResult(
                conditions: [],
                scopes: nil,
                error: error,
                outcome: .conversionFailure,
            )
        }

        let finalConditions = normalizedConditions.isEmpty ? fallbackConditions : normalizedConditions
        let outcome: QueryConversionResultOutcome = if normalizedConditions.isEmpty {
            cleanedOutputScopes == cleanedExistingScopes ? .fallbackReuse : .generatedChangeSet
        } else if normalizedConditions == fallbackConditions, cleanedOutputScopes == cleanedExistingScopes {
            .unchangedResult
        } else {
            .generatedChangeSet
        }

        return QueryConversionResult(
            conditions: finalConditions,
            scopes: output.scopes,
            error: nil,
            outcome: outcome,
        )
    }

    private func failureResult(error: any Error) -> QueryConversionResult {
        QueryConversionResult(
            conditions: [],
            scopes: nil,
            error: String(describing: error),
            outcome: .conversionFailure,
        )
    }

    private func requireConditionRegistry() throws -> PropertyConditionRegistry {
        guard let conditionRegistry else {
            throw QueryConversionError.registryUnavailable
        }
        return conditionRegistry
    }

    private func cleanScopes(_ scopes: [String]) -> [String] {
        scopes
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.isEmpty == false }
    }
}
