import Foundation
import VoyagerEntitiesCollection
import VoyagerFeaturesContentPageNavigation
import VoyagerShared

enum FileManagerVirtualCollectionContextFactory {
    static let recentsSinceAnyOpenedLiteral = AppliedFilterValueUtils.recentsSinceAnyOpenedLiteral
    private static let allIndexedScopes: [String] = []

    static func collectionContext(
        for route: ContentPageNavigationRoute,
        registryClient: RegistryClient,
    ) -> CollectionContext? {
        switch route {
        case let .tags(tagName):
            makeCollectionContext(
                conditionPayloads: [makeTagConditionPayload(tagNames: [tagName])],
                includeDirectories: true,
                registryClient: registryClient,
            )
        case .recents:
            recentsCollectionContext(registryClient: registryClient)
        case .home, .folder, .computer, .collection, .aiChat, .aiChatSessions:
            nil
        }
    }

    static func recentsCollectionContext(
        registryClient: RegistryClient,
    ) -> CollectionContext {
        makeCollectionContext(
            conditionPayloads: makeRecentsConditionPayloads(),
            includeDirectories: false,
            registryClient: registryClient,
        )
    }

    static func allTagsCollectionContext(
        tagNames: [String],
        registryClient: RegistryClient,
    ) -> CollectionContext {
        makeCollectionContext(
            conditionPayloads: [makeTagConditionPayload(tagNames: normalizeTagNames(tagNames))],
            includeDirectories: true,
            registryClient: registryClient,
        )
    }

    static func normalizeTagNames(_ tagNames: [String]) -> [String] {
        let normalizedNames = tagNames
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return Array(Set(normalizedNames)).sorted()
    }

    static func isVirtualRouteSeedConditionSet(_ conditions: [Condition]) -> Bool {
        isRecentsVirtualRouteSeedConditionSet(conditions) || isTagVirtualRouteSeedConditionSet(conditions)
    }

    private static func makeCollectionContext(
        conditionPayloads: [SearchConditionPayload],
        includeDirectories: Bool,
        registryClient: RegistryClient,
    ) -> CollectionContext {
        let appliedFilters = AppliedFiltersPayload(
            scopes: allIndexedScopes,
            excludedScopes: [],
            includeSubfolders: true,
            conditions: conditionPayloads,
        )
        let resolved = AppliedFilterResolver.resolveDetailed(
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
            includeDirectories: includeDirectories,
            conditions: resolved.conditions,
        )
    }

    private static func makeTagConditionPayload(tagNames: [String]) -> SearchConditionPayload {
        SearchConditionPayload(
            propertyKey: "tag_names",
            operator: "any",
            value: .array(tagNames.map(JSONValue.string)),
        )
    }

    private static func isRecentsVirtualRouteSeedConditionSet(_ conditions: [Condition]) -> Bool {
        guard conditions.count == 2 else { return false }
        let keys = conditions.map(\.property.key)
        return keys == ["last_used_date", "content_type_tree"]
            && conditions[0].operation?.code == "gt"
            && conditions[0].values == [recentsSinceAnyOpenedLiteral]
            && conditions[1].operation?.code == "neq"
            && conditions[1].values == ["public.folder"]
    }

    private static func isTagVirtualRouteSeedConditionSet(_ conditions: [Condition]) -> Bool {
        guard conditions.count == 1, let condition = conditions.first else { return false }
        return condition.property.key == "tag_names"
            && condition.operation?.code == "any"
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
