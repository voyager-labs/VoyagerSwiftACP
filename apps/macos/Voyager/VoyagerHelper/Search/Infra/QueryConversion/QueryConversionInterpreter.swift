import Foundation
import Logging
import VoyagerEntitiesCollection
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
        if let failure = outputFailureResult(from: output) {
            return failure
        }

        let visibleExistingConditions = existingFilters.conditions.filter {
            conditionSanitizer.isVisiblePropertyKey($0.propertyKey)
        }
        let outputConditions = output.conditions ?? []
        let normalizedConditions = conditionSanitizer.normalizeAndValidate(outputConditions)
        let fallbackConditions = conditionSanitizer.normalizeAndValidate(visibleExistingConditions)
        let cleanedExistingScopes = cleanScopes(existingFilters.scopes)
        let cleanedOutputScopes = cleanScopes(output.scopes ?? existingFilters.scopes)

        if let failure = invalidGeneratedConditionsResult(
            outputConditions: outputConditions,
            normalizedConditions: normalizedConditions,
        ) {
            return failure
        }

        let inferredOutcome = inferOutcome(
            normalizedConditions: normalizedConditions,
            fallbackConditions: fallbackConditions,
            cleanedOutputScopes: cleanedOutputScopes,
            cleanedExistingScopes: cleanedExistingScopes,
        )
        let outcome = resolveOutcome(
            outputOutcome: output.outcome,
            inferredOutcome: inferredOutcome,
            hasNormalizedConditions: normalizedConditions.isEmpty == false,
        )
        let finalConditions = resolvedConditions(
            outcome: outcome,
            normalizedConditions: normalizedConditions,
            fallbackConditions: fallbackConditions,
        )

        return QueryConversionResult(
            conditions: finalConditions,
            scopes: output.scopes,
            error: nil,
            outcome: outcome,
        )
    }

    private func outputFailureResult(from output: QueryConversionOutput) -> QueryConversionResult? {
        let outputError = output.error?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard output.outcome == .error || outputError?.isEmpty == false else {
            return nil
        }
        let error = outputError?.isEmpty == false
            ? outputError ?? "Could not generate valid filters."
            : "Could not generate valid filters."
        return conversionFailureResult(error: error)
    }

    private func invalidGeneratedConditionsResult(
        outputConditions: [SearchConditionPayload],
        normalizedConditions: [SearchConditionPayload],
    ) -> QueryConversionResult? {
        guard outputConditions.isEmpty == false, normalizedConditions.isEmpty else {
            return nil
        }
        return conversionFailureResult(error: "Generated filters could not be validated.")
    }

    private func conversionFailureResult(error: String) -> QueryConversionResult {
        logger.error("[QueryConversionInterpreter] \(error)")
        return QueryConversionResult(
            conditions: [],
            scopes: nil,
            error: error,
            outcome: .conversionFailure,
        )
    }

    private func inferOutcome(
        normalizedConditions: [SearchConditionPayload],
        fallbackConditions: [SearchConditionPayload],
        cleanedOutputScopes: [String],
        cleanedExistingScopes: [String],
    ) -> QueryConversionResultOutcome {
        if normalizedConditions.isEmpty {
            return cleanedOutputScopes == cleanedExistingScopes ? .fallbackReuse : .generatedChangeSet
        }
        if normalizedConditions == fallbackConditions, cleanedOutputScopes == cleanedExistingScopes {
            return .unchangedResult
        }
        return .generatedChangeSet
    }

    private func resolvedConditions(
        outcome: QueryConversionResultOutcome,
        normalizedConditions: [SearchConditionPayload],
        fallbackConditions: [SearchConditionPayload],
    ) -> [SearchConditionPayload] {
        if outcome == .fallbackReuse {
            return fallbackConditions
        }
        return normalizedConditions.isEmpty ? fallbackConditions : normalizedConditions
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

    private func resolveOutcome(
        outputOutcome: QueryConversionOutputOutcome?,
        inferredOutcome: QueryConversionResultOutcome,
        hasNormalizedConditions: Bool,
    ) -> QueryConversionResultOutcome {
        guard let outputOutcome else {
            return inferredOutcome
        }

        switch outputOutcome {
        case .generatedChangeSet:
            return .generatedChangeSet
        case .unchangedResult:
            return hasNormalizedConditions ? .unchangedResult : .fallbackReuse
        case .fallbackReuse:
            return .fallbackReuse
        case .error:
            return .conversionFailure
        }
    }
}
