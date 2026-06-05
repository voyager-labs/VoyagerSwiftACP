import ComposableArchitecture
import Foundation
import VoyagerShared

@CasePathable
public enum CollectionAction: CasePathable, Sendable {
    case delegate(Delegate)

    case openRequested(URL, reopenContext: CollectionContext?, isAlreadyStale: Bool)
    case draftDiscardRequested
    case refreshRequested
    case openSearchPresentationCancelled
    case temporaryContextResetRequested(rootScopePath: String)
    case navigationStateApplied(CollectionNavigationStatePayload)
    case refreshResponseReceived(VoyagerShared.SearchResponsePayload, wasDirtyBeforeApplyingResponse: Bool)
    case refreshFailed
    case externalPathsChanged([String])
    case searchSucceeded(
        context: CollectionContext,
        items: [VoyagerShared.JSONValue],
        previousNavigationIsCollection: Bool,
        nextNavigationDiffers: Bool,
    )
    case searchFailed
    case sessionResetRequested
    case writeBackCompleted(CollectionSaveCompletion)
    case writeBackFailed

    case saveRequested(SaveRequestPayload)
    case saveToExisting(SaveRequestPayload, URL)
    case savePanelResponse(URL?)
    case saveCompleted(Result<CollectionSaveCompletion, Error>)

    @CasePathable
    public enum Delegate: Sendable {
        case draftRestorePrepared(CollectionDraftRestorePayload)
        case searchResultPrepared(CollectionSearchResultPayload)
        case writeBackNavigationPrepared(CollectionWriteBackNavigationPayload)
    }
}

public struct SaveRequestPayload: Equatable, Sendable {
    public let context: CollectionContext?
    public let isSearchLoading: Bool
    public let isFiltersLoading: Bool
    public let snapshotItems: [VoyagerShared.JSONValue]?
    public let definitionFingerprint: String
    public let capturedAt: Date
    public let relevanceRoots: [String]
    public let openedCompatibility: CollectionFileCompatibilityMetadata?

    public init(
        context: CollectionContext?,
        isSearchLoading: Bool,
        isFiltersLoading: Bool,
        snapshotItems: [VoyagerShared.JSONValue]?,
        definitionFingerprint: String,
        capturedAt: Date,
        relevanceRoots: [String],
        openedCompatibility: CollectionFileCompatibilityMetadata?,
    ) {
        self.context = context
        self.isSearchLoading = isSearchLoading
        self.isFiltersLoading = isFiltersLoading
        self.snapshotItems = snapshotItems
        self.definitionFingerprint = definitionFingerprint
        self.capturedAt = capturedAt
        self.relevanceRoots = relevanceRoots
        self.openedCompatibility = openedCompatibility
    }
}

public struct CollectionSaveCompletion: Equatable, Sendable {
    public let url: URL
    public let file: VoyagerCollectionFile

    public init(url: URL, file: VoyagerCollectionFile) {
        self.url = url
        self.file = file
    }
}
