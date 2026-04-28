import ComposableArchitecture
import Foundation
import VoyagerShared

@CasePathable
enum CollectionAction: CasePathable, Sendable {
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
    enum Delegate: Sendable {
        case draftRestorePrepared(CollectionDraftRestorePayload)
        case searchResultPrepared(CollectionSearchResultPayload)
        case writeBackNavigationPrepared(CollectionWriteBackNavigationPayload)
    }
}

struct SaveRequestPayload: Equatable, Sendable {
    let context: CollectionContext?
    let isSearchLoading: Bool
    let isFiltersLoading: Bool
    let snapshotItems: [VoyagerShared.JSONValue]?
    let definitionFingerprint: String
    let capturedAt: Date
    let relevanceRoots: [String]
    let openedCompatibility: CollectionFileCompatibilityMetadata?
}

struct CollectionSaveCompletion: Equatable, Sendable {
    let url: URL
    let file: VoyagerCollectionFile
}
