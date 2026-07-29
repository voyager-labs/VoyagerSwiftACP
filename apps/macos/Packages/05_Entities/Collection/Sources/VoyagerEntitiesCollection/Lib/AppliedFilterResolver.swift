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
        let source = sourceCondition(for: payload)
        let keyResolution = resolvePropertyKey(payload.propertyKey, registryClient: registryClient)
        let operatorCode = keyResolution.canonical.map {
            resolveOperatorCode(payload.operator, propertyKey: $0, registryClient: registryClient)
        } ?? payload.operator
        do {
            let preliminary = try registryClient.resolveCondition(
                propertyKey: payload.propertyKey,
                operatorCode: operatorCode,
                values: nil,
                sourcePayload: nil,
            )
            guard preliminary.availability == .available, let operation = preliminary.operation else {
                return try unavailableConditionResult(
                    payload: payload,
                    source: source,
                    operatorCode: operatorCode,
                    keyResolution: keyResolution,
                    registryClient: registryClient,
                )
            }
            guard let values = ConditionCodec.decode(payload.value, contract: operation.valueContract) else {
                return invalidValueResult(
                    payload: payload,
                    source: source,
                    keyResolution: keyResolution,
                    registryClient: registryClient,
                )
            }
            return try (registryClient.resolveCondition(
                propertyKey: payload.propertyKey,
                operatorCode: operatorCode,
                values: values,
                sourcePayload: source,
            ), keyResolution.unknown)
        } catch {
            if let historical = historicalCondition(
                payload,
                canonicalPropertyKey: keyResolution.canonical,
                registryClient: registryClient,
            ) {
                return (historical, nil)
            }
            return (
                RegistryClient
                    .opaqueCondition(key: payload.propertyKey, source: source, availability: .invalidPersistedValue),
                keyResolution.unknown,
            )
        }
    }

    private static func sourceCondition(for payload: SearchConditionPayload) -> CollectionCondition {
        CollectionCondition(
            propertyKey: payload.propertyKey,
            operatorCode: payload.operator,
            value: payload.value,
        )
    }

    private static func unavailableConditionResult(
        payload: SearchConditionPayload,
        source: CollectionCondition,
        operatorCode: String,
        keyResolution: (canonical: String?, unknown: String?),
        registryClient: RegistryClient,
    ) throws -> (condition: Condition, unknownKey: String?) {
        if let historical = historicalCondition(
            payload,
            canonicalPropertyKey: keyResolution.canonical,
            registryClient: registryClient,
        ) {
            return (historical, nil)
        }
        return try (registryClient.resolveCondition(
            propertyKey: payload.propertyKey,
            operatorCode: operatorCode,
            values: nil,
            sourcePayload: source,
        ), keyResolution.unknown)
    }

    private static func invalidValueResult(
        payload: SearchConditionPayload,
        source: CollectionCondition,
        keyResolution: (canonical: String?, unknown: String?),
        registryClient: RegistryClient,
    ) -> (condition: Condition, unknownKey: String?) {
        if let historical = historicalCondition(
            payload,
            canonicalPropertyKey: keyResolution.canonical,
            registryClient: registryClient,
        ) {
            return (historical, nil)
        }
        return (
            RegistryClient.opaqueCondition(
                key: payload.propertyKey,
                source: source,
                availability: .invalidPersistedValue,
            ),
            keyResolution.unknown,
        )
    }

    private static func historicalCondition(
        _ payload: SearchConditionPayload,
        canonicalPropertyKey: String?,
        registryClient: RegistryClient,
    ) -> Condition? {
        let currentPropertyType = canonicalPropertyKey.map {
            SystemPropertyTypeKey(rawType: registryClient.propertyTypeString(for: $0))
        }
        return HistoricalConditionCompatibility.restoredCondition(
            from: payload,
            canonicalPropertyKey: canonicalPropertyKey,
            currentPropertyType: currentPropertyType,
            registryClient: registryClient,
        )
    }

    private static func resolvePropertyKey(
        _ key: String,
        registryClient: RegistryClient,
    ) -> (canonical: String?, unknown: String?) {
        switch registryClient.resolveKey(key) {
        case let .canonical(canonical): (canonical, nil)
        case let .legacy(_, normalized): (normalized, nil)
        case let .unknown(unknown): (nil, unknown)
        }
    }

    private static func resolveOperatorCode(
        _ code: String,
        propertyKey: String,
        registryClient: RegistryClient,
    ) -> String {
        let availableCodes = registryClient.operatorCodes(for: propertyKey)
        if availableCodes.contains(code) { return code }
        if isHistoricalAlphaListOperator(code, propertyKey: propertyKey, registryClient: registryClient) {
            return code
        }

        if let aliasMatch = availableCodes.first(where: { availableCode in
            let definition = registryClient.operatorDefinition(availableCode)
            return ([availableCode] + (definition.aliases ?? [])).contains {
                operatorAlias($0, matches: code)
            }
        }) {
            return aliasMatch
        }

        let normalized = normalizedOperatorAlias(code)
        if ["eq", "equals", "is"].contains(normalized), availableCodes.contains("any") {
            return "any"
        }
        if ["neq", "none", "isnot"].contains(normalized), availableCodes.contains("none") {
            return "none"
        }
        return code
    }

    private static func isHistoricalAlphaListOperator(
        _ code: String,
        propertyKey: String,
        registryClient: RegistryClient,
    ) -> Bool {
        let operators = ["contains_any", "contains_all", "not_contains_any", "not_contains_all"]
        return operators.contains(code)
            && registryClient.propertyTypeString(for: propertyKey) == SystemPropertyTypeKey.categorical.rawValue
    }

    private static func operatorAlias(_ candidate: String, matches code: String) -> Bool {
        guard candidate != code else { return true }
        let normalizedCandidate = normalizedOperatorAlias(candidate)
        return !normalizedCandidate.isEmpty && normalizedCandidate == normalizedOperatorAlias(code)
    }

    private static func normalizedOperatorAlias(_ value: String) -> String {
        value.lowercased().filter(\.isLetter)
    }
}
