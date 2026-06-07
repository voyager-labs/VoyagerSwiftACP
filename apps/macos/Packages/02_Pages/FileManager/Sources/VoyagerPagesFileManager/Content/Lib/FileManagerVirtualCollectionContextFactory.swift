import Foundation
import VoyagerEntitiesCollection
import VoyagerFeaturesContentPageNavigation
import VoyagerShared

enum FileManagerVirtualCollectionContextFactory {
    static let recentsSinceAnyOpenedLiteral = AppliedFilterValueUtils.recentsSinceAnyOpenedLiteral
    private static let allIndexedScopes: [String] = []
    private static let rootScopePath = "/"

    static func collectionContext(
        for route: ContentPageNavigationRoute,
        registryClient: RegistryClient,
    ) -> CollectionContext? {
        let conditionPayloads: [SearchConditionPayload] = switch route {
        case let .tags(tagName):
            [makeTagConditionPayload(tagName: tagName)]
        case .recents:
            makeRecentsConditionPayloads()
        case .folder, .computer, .collection:
            []
        }

        guard conditionPayloads.isEmpty == false else {
            return nil
        }

        let appliedFilters = AppliedFiltersPayload(
            scopes: allIndexedScopes,
            excludedScopes: [],
            includeSubfolders: true,
            conditions: conditionPayloads,
        )
        let resolved = AppliedFiltersUtils.resolveDetailed(
            appliedFilters,
            fallbackScopes: allIndexedScopes,
            fallbackConditions: [],
            registryClient: registryClient,
        )

        return CollectionContext(
            query: "",
            scopes: resolved.scopes,
            excludedScopes: resolved.excludedScopes,
            includeSubfolders: appliedFilters.includeSubfolders ?? true,
            includeDirectories: route.includesDirectoriesInVirtualCollection,
            conditions: resolved.conditions,
        )
    }

    static func isVirtualRouteSeedConditionSet(_ conditions: [Condition]) -> Bool {
        isRecentsVirtualRouteSeedConditionSet(conditions) || isTagVirtualRouteSeedConditionSet(conditions)
    }

    private static func makeTagConditionPayload(tagName: String) -> SearchConditionPayload {
        SearchConditionPayload(
            propertyKey: "tag_names",
            operator: "any",
            value: .array([.string(tagName)]),
        )
    }

    private static func isRecentsVirtualRouteSeedConditionSet(_ conditions: [Condition]) -> Bool {
        guard conditions.count == 2 else { return false }
        let keys = conditions.map(\.propertyKey)
        return keys == ["last_used_date", "content_type_tree"]
            && conditions[0].operatorCode == "gt"
            && conditions[0].values == [recentsSinceAnyOpenedLiteral]
            && conditions[1].operatorCode == "neq"
            && conditions[1].values == ["public.folder"]
    }

    private static func isTagVirtualRouteSeedConditionSet(_ conditions: [Condition]) -> Bool {
        guard conditions.count == 1, let condition = conditions.first else { return false }
        return condition.propertyKey == "tag_names"
            && condition.operatorCode == "any"
            && condition.values?.count == 1
    }

    private static func makeRecentsConditionPayloads() -> [SearchConditionPayload] {
        [
            SearchConditionPayload(
                propertyKey: "last_used_date",
                operator: "gt",
                value: .string(recentsSinceAnyOpenedLiteral),
            ),
            SearchConditionPayload(
                propertyKey: "content_type_tree",
                operator: "neq",
                value: .string("public.folder"),
            ),
        ]
    }
}

private extension ContentPageNavigationRoute {
    var includesDirectoriesInVirtualCollection: Bool {
        if case .tags = self {
            return true
        }
        return false
    }
}
