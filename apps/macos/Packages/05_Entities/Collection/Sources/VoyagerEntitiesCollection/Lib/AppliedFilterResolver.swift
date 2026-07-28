import VoyagerShared

public enum AppliedFilterResolver {
    public struct ResolutionResult: Equatable {
        public let scopes: [String]
        public let excludedScopes: [String]
        public let conditions: [Condition]
        public let unknownKeys: [String]

        public init(scopes: [String], conditions: [Condition], unknownKeys: [String], excludedScopes: [String] = []) {
            self.scopes = scopes
            self.excludedScopes = excludedScopes
            self.conditions = conditions
            self.unknownKeys = unknownKeys
        }
    }

    public static func resolveDetailed(
        _ appliedFilters: AppliedFiltersPayload?,
        fallbackScopes: [String],
        fallbackConditions: [Condition],
        registryClient: RegistryClient,
        fallbackExcludedScopes: [String] = [],
    ) -> ResolutionResult {
        guard let appliedFilters else {
            return .init(
                scopes: fallbackScopes,
                conditions: fallbackConditions,
                unknownKeys: [],
                excludedScopes: fallbackExcludedScopes,
            )
        }
        let scopes = appliedFilters.scopes ?? fallbackScopes
        let excludedScopes = appliedFilters.excludedScopes
        guard let payloads = appliedFilters.conditions else {
            return .init(
                scopes: scopes,
                conditions: fallbackConditions,
                unknownKeys: [],
                excludedScopes: excludedScopes.isEmpty ? fallbackExcludedScopes : excludedScopes,
            )
        }
        let resolved = payloads.map { resolve($0, registryClient: registryClient) }
        return .init(
            scopes: scopes,
            conditions: resolved.map(\.condition),
            unknownKeys: Array(Set(resolved.compactMap(\.unknownKey))).sorted(),
            excludedScopes: excludedScopes.isEmpty ? fallbackExcludedScopes : excludedScopes,
        )
    }

    public static func resolve(
        _ appliedFilters: AppliedFiltersPayload?,
        fallbackScopes: [String],
        fallbackConditions: [Condition],
        registryClient: RegistryClient,
        fallbackExcludedScopes: [String] = [],
    ) -> (scopes: [String], conditions: [Condition]) {
        let result = resolveDetailed(
            appliedFilters,
            fallbackScopes: fallbackScopes,
            fallbackConditions: fallbackConditions,
            registryClient: registryClient,
            fallbackExcludedScopes: fallbackExcludedScopes,
        )
        return (result.scopes, result.conditions)
    }

    private static func resolve(
        _ payload: SearchConditionPayload,
        registryClient: RegistryClient,
    ) -> (condition: Condition, unknownKey: String?) {
        let source = CollectionCondition(
            propertyKey: payload.propertyKey,
            operatorCode: payload.operator,
            value: payload.value,
        )
        let unknownKey: String? = switch registryClient.resolveKey(payload.propertyKey) {
        case let .unknown(key): key
        case .canonical, .legacy: nil
        }
        do {
            let preliminary = try registryClient.resolveCondition(
                propertyKey: payload.propertyKey,
                operatorCode: payload.operator,
                values: nil,
                sourcePayload: nil,
            )
            guard preliminary.availability == .available, let operation = preliminary.operation else {
                return try (registryClient.resolveCondition(
                    propertyKey: payload.propertyKey,
                    operatorCode: payload.operator,
                    values: nil,
                    sourcePayload: source,
                ), unknownKey)
            }
            guard let values = ConditionCodec.decode(payload.value, contract: operation.valueContract) else {
                return (
                    RegistryClient.opaqueCondition(
                        key: payload.propertyKey,
                        source: source,
                        availability: .invalidPersistedValue,
                    ),
                    unknownKey,
                )
            }
            return try (registryClient.resolveCondition(
                propertyKey: payload.propertyKey,
                operatorCode: payload.operator,
                values: values,
                sourcePayload: source,
            ), unknownKey)
        } catch {
            return (
                RegistryClient
                    .opaqueCondition(key: payload.propertyKey, source: source, availability: .invalidPersistedValue),
                unknownKey,
            )
        }
    }
}
