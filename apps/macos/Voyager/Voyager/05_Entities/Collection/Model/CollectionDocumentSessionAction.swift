import Foundation
import VoyagerShared

enum CollectionDocumentSessionAction: Equatable, Sendable {
    case openRequested(URL)
    case openLoaded(url: URL, file: VoyagerCollectionFile)
    case openCancelled
    case draftRestoreRequested(
        baseline: CollectionBaseline?,
        isCollectionMode: Bool,
        isDirty: Bool,
        openedURL: URL?,
    )
    case refreshRequested(
        blockingReason: CollectionSessionRefreshBlockingReason?,
        query: String?,
    )

    case delegate(CollectionDocumentSessionDelegate)
}

enum CollectionDocumentSessionDelegate: Equatable, Sendable {
    // Page/Feature 계층이 실제 IO를 수행하도록 요청한다.
    case loadFile(URL)
    case restoreDraft(CollectionDraftRestorePayload)
    case triggerRefresh(CollectionRefreshTriggerPayload)
}

struct CollectionDraftRestorePayload: Equatable, Sendable {
    let context: CollectionContext
    let openedURL: URL?
}

struct CollectionOpenRestorationPayload: Equatable, Sendable {
    let context: CollectionContext
    let compatibility: CollectionFileCompatibilityMetadata?
    let shouldRestoreStaleNavigation: Bool
    let queryTrigger: CollectionQueryTriggerPayload?
    let hydratedOpenPayload: CollectionHydratedOpenPayload?
    let isEmptyDefinition: Bool
    let unsupportedFilterKeys: [String]
}

struct CollectionWriteBackSuccessPayload: Equatable, Sendable {
    let url: URL
    let name: String
    let baseline: CollectionBaseline?
    let compatibility: CollectionFileCompatibilityMetadata?
    let shouldAppendHistory: Bool
}

struct CollectionNavigationStatePayload: Equatable, Sendable {
    let context: CollectionContext
    let compatibility: CollectionFileCompatibilityMetadata?
    let openedURL: URL?
    let openedName: String?
    let originURL: URL?
    let baseline: CollectionBaseline?
    let pendingSearchQuery: String?
    let composerText: String
    let scopes: [String]
    let conditions: [Condition]
}

struct CollectionSearchFailurePayload: Equatable, Sendable {
    let shouldResetSession: Bool
}

struct CollectionExternalInvalidationPayload: Equatable, Sendable {
    let isStale: Bool
    let staleReason: CollectionDocumentSessionState.StaleReason?
    let lastRefreshAt: Date?
}

struct CollectionSessionResetPayload: Equatable, Sendable {
    let shouldReset: Bool
}

struct CollectionOpenCancellationPayload: Equatable, Sendable {
    let pendingSearchQuery: String?
    let isOpening: Bool
    let openedName: String?
}

struct CollectionHydratedOpenPayload: Equatable, Sendable {
    let lastFiltersResponse: VoyagerShared.SearchResponsePayload
    let lastSearchResponse: VoyagerShared.SearchResponsePayload?
    let snapshotPaths: [String]
}

enum CollectionRefreshTriggerPayload: Equatable, Sendable {
    case applyFilters
    case submit(String)
}

typealias CollectionQueryTriggerPayload = CollectionRefreshTriggerPayload

struct CollectionSearchResultPayload: Equatable, Sendable {
    let context: CollectionContext
    let shouldAppendHistory: Bool
    let shouldLogDAU: Bool
}

struct CollectionRefreshResponsePayload: Equatable, Sendable {
    let shouldWriteBack: Bool
    let shouldKeepStale: Bool
}
