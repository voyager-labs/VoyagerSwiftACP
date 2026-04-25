import Foundation
import VoyagerShared

struct CollectionDraftRestorePayload: Equatable, Sendable {
    let context: CollectionContext
    let openedURL: URL?
}

enum CollectionNavigationKindPayload: Equatable, Sendable {
    case temporary
    case file(url: URL, name: String)
}

struct CollectionNavigationPresentationPayload: Equatable, Sendable {
    let kind: CollectionNavigationKindPayload
    let context: CollectionContext
    let compatibility: CollectionFileCompatibilityMetadata?
}

struct CollectionOpenRestorationPayload: Equatable, Sendable {
    let context: CollectionContext
    let compatibility: CollectionFileCompatibilityMetadata?
    let navigation: CollectionNavigationPresentationPayload?
    let shouldRestoreStaleNavigation: Bool
    let queryTrigger: CollectionRefreshTriggerPayload?
    let hydratedOpenPayload: CollectionHydratedOpenPayload?
    let isEmptyDefinition: Bool
    let unsupportedFilterKeys: [String]
}

struct CollectionNavigationStatePayload: Equatable, Sendable {
    let context: CollectionContext
    let document: CollectionOpenedDocumentState?
    let baseline: CollectionBaseline?
    let composerText: String
    let scopes: [String]
    let conditions: [Condition]
}

struct CollectionHydratedOpenPayload: Equatable, Sendable {
    let lastFiltersResponse: VoyagerShared.SearchResponsePayload
    let lastSearchResponse: VoyagerShared.SearchResponsePayload?
    let snapshotPaths: [String]
}

enum CollectionRefreshTriggerPayload: Equatable, Sendable {
    case applyFilters
    case submit
}

struct CollectionSearchResultPayload: Equatable, Sendable {
    let navigation: CollectionNavigationPresentationPayload
    let shouldAppendHistory: Bool
    let shouldLogDAU: Bool
}

struct CollectionWriteBackNavigationPayload: Equatable, Sendable {
    let nextNavigation: CollectionNavigationPresentationPayload
    let previousHistoryNavigation: CollectionNavigationPresentationPayload?
    let shouldAppendHistory: Bool
}
