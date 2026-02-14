import Foundation

enum AppliedFiltersUtils {
    struct ResolutionResult: Equatable {
        let scopes: [String]
        let conditions: [Condition]
        let unknownKeys: [String]
    }

    static func resolve(
        _ appliedFilters: AppliedFiltersPayload?,
        fallbackScopes: [String],
        fallbackConditions: [Condition],
        registryClient: RegistryClient,
    ) -> (scopes: [String], conditions: [Condition]) {
        let resolved = resolveDetailed(
            appliedFilters,
            fallbackScopes: fallbackScopes,
            fallbackConditions: fallbackConditions,
            registryClient: registryClient,
        )
        return (resolved.scopes, resolved.conditions)
    }

    static func resolveDetailed(
        _ appliedFilters: AppliedFiltersPayload?,
        fallbackScopes: [String],
        fallbackConditions: [Condition],
        registryClient: RegistryClient,
    ) -> ResolutionResult {
        let scopes = appliedFilters?.scopes ?? fallbackScopes
        if let appliedConditions = appliedFilters?.conditions {
            let resolved = appliedConditions.map {
                makeResolvedCondition(from: $0, registryClient: registryClient)
            }
            let unknownKeys = Array(
                Set(resolved.compactMap(\.unknownKey)),
            ).sorted()
            return ResolutionResult(
                scopes: scopes,
                conditions: resolved.map(\.condition),
                unknownKeys: unknownKeys,
            )
        }
        return ResolutionResult(
            scopes: scopes,
            conditions: fallbackConditions,
            unknownKeys: [],
        )
    }

    private struct ResolvedCondition {
        let condition: Condition
        let unknownKey: String?
    }

    private static func makeResolvedCondition(
        from payload: SearchConditionPayload,
        registryClient: RegistryClient,
    ) -> ResolvedCondition {
        switch registryClient.resolveKey(payload.propertyKey) {
        case let .canonical(propertyKey):
            return ResolvedCondition(
                condition: makeCondition(
                    from: payload,
                    propertyKey: propertyKey,
                    registryClient: registryClient,
                ),
                unknownKey: nil,
            )

        case let .legacy(_, normalized):
            return ResolvedCondition(
                condition: makeCondition(
                    from: payload,
                    propertyKey: normalized,
                    registryClient: registryClient,
                ),
                unknownKey: nil,
            )

        case let .unknown(rawKey):
            let values = AppliedFilterValueUtils.stringValues(from: payload.value, valueUIKind: "singleText")
            return ResolvedCondition(
                condition: Condition(
                    propertyKey: rawKey,
                    propertyLabel: "Unknown (\(rawKey))",
                    propertyType: "unknown",
                    operatorCode: payload.operator,
                    operatorLabel: payload.operator,
                    operatorValueArity: nil,
                    operatorValueUIKind: nil,
                    valueType: "unknown",
                    values: values,
                    isActive: false,
                ),
                unknownKey: rawKey,
            )
        }
    }

    private static func makeCondition(
        from payload: SearchConditionPayload,
        propertyKey: String,
        registryClient: RegistryClient,
    ) -> Condition {
        let propertyLabel = registryClient.label(for: propertyKey)
        let propertyType = registryClient.propertyTypeString(for: propertyKey)
        let typeKey = SystemPropertyTypeKey.operatorKey(from: propertyType)
        let operatorDefinition = registryClient.operatorDefinition(payload.operator)
        let valueUIKind = registryClient.operatorUIKind(for: payload.operator, typeKey: typeKey)
        let operatorLabel = operatorDefinition.uiLabel ?? payload.operator
        let valueType = registryClient.valueType(for: valueUIKind)

        return Condition(
            propertyKey: propertyKey,
            propertyLabel: propertyLabel,
            propertyType: propertyType,
            operatorCode: payload.operator,
            operatorLabel: operatorLabel,
            operatorValueArity: ValueNormalizerUtils.expectedArity(for: valueUIKind),
            operatorValueUIKind: valueUIKind,
            valueType: valueType,
            values: AppliedFilterValueUtils.stringValues(from: payload.value, valueUIKind: valueUIKind),
            isActive: true,
        )
    }
}
