import Foundation
import VoyagerEntitiesCollection
import VoyagerFeaturesContentPageNavigation
import VoyagerShared

enum FileManagerVirtualCollectionContextFactory {
    static let recentsSinceAnyOpenedLiteral = "$time.today(-1000000)"
    private static let rootScopePath = "/"

    static func collectionContext(
        for route: ContentPageNavigationRoute,
        registryClient: RegistryClient,
    ) -> CollectionContext? {
        let conditionPayload: SearchConditionPayload? = switch route {
        case let .tags(tagName):
            makeTagConditionPayload(tagName: tagName)
        case .recents:
            makeRecentsConditionPayload()
        case .folder, .computer, .collection:
            nil
        }

        guard let conditionPayload else {
            return nil
        }

        let appliedFilters = AppliedFiltersPayload(
            scopes: [rootScopePath],
            excludedScopes: [],
            includeSubfolders: true,
            conditions: [conditionPayload],
        )
        let resolved = AppliedFiltersUtils.resolveDetailed(
            appliedFilters,
            fallbackScopes: [rootScopePath],
            fallbackConditions: [],
            registryClient: registryClient,
        )

        return CollectionContext(
            query: "",
            scopes: resolved.scopes,
            excludedScopes: resolved.excludedScopes,
            includeSubfolders: appliedFilters.includeSubfolders ?? true,
            conditions: resolved.conditions,
        )
    }

    private static func makeTagConditionPayload(tagName: String) -> SearchConditionPayload {
        SearchConditionPayload(
            propertyKey: "tag_names",
            operator: "any",
            value: .array([.string(tagName)]),
        )
    }

    private static func makeRecentsConditionPayload() -> SearchConditionPayload {
        SearchConditionPayload(
            propertyKey: "last_used_date",
            operator: "gt",
            value: .string(recentsSinceAnyOpenedLiteral),
        )
    }
}
