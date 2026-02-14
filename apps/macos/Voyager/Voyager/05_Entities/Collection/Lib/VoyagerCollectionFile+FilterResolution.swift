import Foundation

extension VoyagerCollectionFile {
    func resolveCollectionFilters(
        registryClient: RegistryClient,
    ) -> AppliedFiltersUtils.ResolutionResult {
        let conditionPayloads = conditions.map { condition in
            SearchConditionPayload(
                propertyKey: condition.propertyKey,
                operator: condition.operatorCode,
                value: condition.value,
            )
        }
        let appliedFilters = AppliedFiltersPayload(
            scopes: scopes,
            conditions: conditionPayloads,
        )
        return AppliedFiltersUtils.resolveDetailed(
            appliedFilters,
            fallbackScopes: scopes,
            fallbackConditions: [],
            registryClient: registryClient,
        )
    }
}
