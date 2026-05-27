import Foundation
import VoyagerShared

public enum AppliedFiltersUtils {
    public struct ResolutionResult: Equatable {
        public let scopes: [String]
        public let excludedScopes: [String]
        public let conditions: [Condition]
        public let unknownKeys: [String]

        public init(
            scopes: [String],
            excludedScopes: [String] = [],
            conditions: [Condition],
            unknownKeys: [String]
        ) {
            self.scopes = scopes
            self.excludedScopes = excludedScopes
            self.conditions = conditions
            self.unknownKeys = unknownKeys
        }
    }

    private struct ResolvedCondition {
        let condition: Condition
        let unknownKey: String?
    }

    public static func resolve(
        _ appliedFilters: VoyagerShared.AppliedFiltersPayload?,
        fallbackScopes: [String],
        fallbackConditions: [Condition],
        registryClient: RegistryClient,
        fallbackExcludedScopes: [String] = []
    ) -> (scopes: [String], conditions: [Condition]) {
        let resolved = resolveDetailed(
            appliedFilters,
            fallbackScopes: fallbackScopes,
            fallbackConditions: fallbackConditions,
            registryClient: registryClient,
            fallbackExcludedScopes: fallbackExcludedScopes
        )
        return (resolved.scopes, resolved.conditions)
    }

    public static func resolveDetailed(
        _ appliedFilters: VoyagerShared.AppliedFiltersPayload?,
        fallbackScopes: [String],
        fallbackConditions: [Condition],
        registryClient: RegistryClient,
        fallbackExcludedScopes: [String] = []
    ) -> ResolutionResult {
        let scopes = appliedFilters?.scopes ?? fallbackScopes
        let excludedScopes = resolvedExcludedScopes(
            appliedFilters: appliedFilters,
            fallbackExcludedScopes: fallbackExcludedScopes
        )
        if let appliedConditions = appliedFilters?.conditions {
            let resolved = appliedConditions.map {
                makeResolvedCondition(from: $0, registryClient: registryClient)
            }
            let unknownKeys = Array(
                Set(resolved.compactMap(\.unknownKey))
            ).sorted()
            return ResolutionResult(
                scopes: scopes,
                excludedScopes: excludedScopes,
                conditions: resolved.map(\.condition),
                unknownKeys: unknownKeys
            )
        }
        return ResolutionResult(
            scopes: scopes,
            excludedScopes: excludedScopes,
            conditions: fallbackConditions,
            unknownKeys: []
        )
    }

    private static func resolvedExcludedScopes(
        appliedFilters: VoyagerShared.AppliedFiltersPayload?,
        fallbackExcludedScopes: [String]
    ) -> [String] {
        guard let appliedFilters else {
            return fallbackExcludedScopes
        }
        if appliedFilters.excludedScopes.isEmpty, !fallbackExcludedScopes.isEmpty {
            return fallbackExcludedScopes
        }
        return appliedFilters.excludedScopes
    }

    private static func makeResolvedCondition(
        from payload: VoyagerShared.SearchConditionPayload,
        registryClient: RegistryClient
    ) -> ResolvedCondition {
        switch registryClient.resolveKey(payload.propertyKey) {
        case let .canonical(propertyKey):
            return ResolvedCondition(
                condition: makeCondition(
                    from: payload,
                    propertyKey: propertyKey,
                    registryClient: registryClient
                ),
                unknownKey: nil
            )

        case let .legacy(_, normalized):
            return ResolvedCondition(
                condition: makeCondition(
                    from: payload,
                    propertyKey: normalized,
                    registryClient: registryClient
                ),
                unknownKey: nil
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
                    isActive: false
                ),
                unknownKey: rawKey
            )
        }
    }

    private static func makeCondition(
        from payload: VoyagerShared.SearchConditionPayload,
        propertyKey: String,
        registryClient: RegistryClient
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
            isActive: true
        )
    }
}
