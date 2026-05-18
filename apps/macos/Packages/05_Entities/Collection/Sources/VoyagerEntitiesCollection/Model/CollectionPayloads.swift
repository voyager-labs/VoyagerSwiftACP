import Foundation
import VoyagerShared

public struct CollectionDraftRestorePayload: Equatable, Sendable {
    public let context: CollectionContext
    public let openedURL: URL?

    public init(context: CollectionContext, openedURL: URL?) {
        self.context = context
        self.openedURL = openedURL
    }
}

public enum CollectionNavigationKindPayload: Equatable, Sendable {
    case temporary
    case file(url: URL, name: String)
}

public struct CollectionNavigationPresentationPayload: Equatable, Sendable {
    public let kind: CollectionNavigationKindPayload
    public let context: CollectionContext
    public let compatibility: CollectionFileCompatibilityMetadata?
}

public struct CollectionOpenRestorationPayload: Equatable, Sendable {
    public let context: CollectionContext
    public let compatibility: CollectionFileCompatibilityMetadata?
    public let navigation: CollectionNavigationPresentationPayload?
    public let shouldRestoreStaleNavigation: Bool
    public let queryTrigger: CollectionRefreshTriggerPayload?
    public let hydratedOpenPayload: CollectionHydratedOpenPayload?
    public let isEmptyDefinition: Bool
    public let unsupportedFilterKeys: [String]
}

public struct CollectionNavigationStatePayload: Equatable, Sendable {
    public let context: CollectionContext
    public let includeSubfolders: Bool
    public let document: CollectionOpenedDocumentState?
    public let baseline: CollectionBaseline?
    public let composerText: String
    public let scopes: [String]
    public let excludedScopes: [String]
    public let conditions: [Condition]

    public init(
        context: CollectionContext,
        includeSubfolders: Bool? = nil,
        document: CollectionOpenedDocumentState?,
        baseline: CollectionBaseline?,
        composerText: String,
        scopes: [String],
        excludedScopes: [String]? = nil,
        conditions: [Condition]
    ) {
        self.context = context
        self.includeSubfolders = includeSubfolders ?? context.includeSubfolders
        self.document = document
        self.baseline = baseline
        self.composerText = composerText
        self.scopes = scopes
        self.excludedScopes = excludedScopes ?? context.excludedScopes
        self.conditions = conditions
    }
}

public struct CollectionHydratedOpenPayload: Equatable, Sendable {
    public let lastFiltersResponse: VoyagerShared.SearchResponsePayload
    public let lastSearchResponse: VoyagerShared.SearchResponsePayload?
    public let snapshotPaths: [String]
}

public enum CollectionRefreshTriggerPayload: Equatable, Sendable {
    case applyFilters
    case submit
}

public struct CollectionSearchResultPayload: Equatable, Sendable {
    public let navigation: CollectionNavigationPresentationPayload
    public let shouldAppendHistory: Bool
    public let shouldLogDAU: Bool
}

public struct CollectionWriteBackNavigationPayload: Equatable, Sendable {
    public let nextNavigation: CollectionNavigationPresentationPayload
    public let previousHistoryNavigation: CollectionNavigationPresentationPayload?
    public let shouldAppendHistory: Bool
}
