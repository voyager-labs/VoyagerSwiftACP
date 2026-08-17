import Foundation
import VoyagerShared

public extension VoyagerCollectionFile {
    func resolveCollectionFilters(
        registryClient: RegistryClient,
    ) -> AppliedFilterResolver.ResolutionResult {
        let conditionPayloads = conditions.map { condition in
            VoyagerShared.SearchConditionPayload(
                propertyKey: condition.propertyKey,
                operator: condition.operatorCode,
                value: condition.value,
            )
        }
        let appliedFilters = VoyagerShared.AppliedFiltersPayload(
            scopes: scopes,
            excludedScopes: excludedScopes,
            includeSubfolders: includeSubfolders,
            conditions: conditionPayloads,
        )
        return AppliedFilterResolver.resolveDetailed(
            appliedFilters,
            fallbackScopes: scopes,
            fallbackConditions: [],
            registryClient: registryClient,
            fallbackExcludedScopes: excludedScopes,
        )
    }
}
