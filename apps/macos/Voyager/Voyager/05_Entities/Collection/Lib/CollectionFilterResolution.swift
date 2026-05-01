import Foundation
import VoyagerShared

enum CollectionFilterResolution {
    static func resolve(
        file: VoyagerCollectionFile,
        registryClient: RegistryClient,
    ) -> AppliedFiltersUtils.ResolutionResult {
        let conditionPayloads = file.conditions.map { condition in
            VoyagerShared.SearchConditionPayload(
                propertyKey: condition.propertyKey,
                operator: condition.operatorCode,
                value: condition.value,
            )
        }
        let appliedFilters = VoyagerShared.AppliedFiltersPayload(
            scopes: file.scopes,
            excludedScopes: file.excludedScopes,
            includeSubfolders: file.includeSubfolders,
            conditions: conditionPayloads,
        )
        return AppliedFiltersUtils.resolveDetailed(
            appliedFilters,
            fallbackScopes: file.scopes,
            fallbackConditions: [],
            registryClient: registryClient,
            fallbackExcludedScopes: file.excludedScopes,
        )
    }
}
