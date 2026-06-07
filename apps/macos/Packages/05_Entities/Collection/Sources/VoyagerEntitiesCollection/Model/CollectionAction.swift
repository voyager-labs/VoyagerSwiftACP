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
        case saveFeedback(CollectionSaveFeedback)
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
    public let savedContext: CollectionContext?

    public init(
        url: URL,
        file: VoyagerCollectionFile,
        savedContext: CollectionContext? = nil,
    ) {
        self.url = url
        self.file = file
        self.savedContext = savedContext
    }
}

public struct CollectionSaveFeedback: Equatable, Sendable {
    public enum Stage: Equatable, Sendable {
        case saveBlocked
        case saveFailed
    }

    public enum Category: Equatable, Sendable {
        case emptyContent
        case incompleteCondition
        case invalidConditionValue
        case futureMinorReadOnly
        case saveFailed
    }

    public let stage: Stage
    public let category: Category
    public let title: String
    public let message: String
    public let recoveryHint: String?
    public let propertyLabel: String?
    public let isRetryable: Bool

    public init(
        stage: Stage,
        category: Category,
        title: String,
        message: String,
        recoveryHint: String? = nil,
        propertyLabel: String? = nil,
        isRetryable: Bool,
    ) {
        self.stage = stage
        self.category = category
        self.title = title
        self.message = message
        self.recoveryHint = recoveryHint
        self.propertyLabel = propertyLabel
        self.isRetryable = isRetryable
    }
}
