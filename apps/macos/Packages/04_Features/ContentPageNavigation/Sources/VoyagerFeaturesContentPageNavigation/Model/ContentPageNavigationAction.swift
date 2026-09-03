import ComposableArchitecture
import Foundation
import VoyagerEntitiesCollection

public enum ContentPageNavigationErrorCategory: String, Equatable, Sendable {
    case unsupportedSchema
    case invalidDefinition
    case malformed
    case access
    case unknown
}

public struct ContentPageNavigationErrorFingerprint: Equatable, Sendable {
    public let domain: String
    public let code: Int
    public let message: String
    public let category: ContentPageNavigationErrorCategory

    public init(error: Error, category: ContentPageNavigationErrorCategory = .unknown) {
        let nsError = error as NSError
        domain = nsError.domain
        code = nsError.code
        message = nsError.localizedDescription
        self.category = category
    }
}

public enum ContentPageCollectionFileLoadResult: Equatable, Sendable {
    case success(CollectionFileLoadResult)
    case failure(ContentPageNavigationErrorFingerprint)
}

public struct ContentPageCollectionOpenRequest: Equatable, Sendable {
    public let id: UUID
    public let url: URL
    public let sourceRoute: ContentPageNavigationRoute
    public let prePrepareBackHistory: [ContentPageNavigationHistorySnapshot]
    public let prePrepareForwardHistory: [ContentPageNavigationHistorySnapshot]

    public init(
        id: UUID,
        url: URL,
        sourceRoute: ContentPageNavigationRoute,
        prePrepareBackHistory: [ContentPageNavigationHistorySnapshot],
        prePrepareForwardHistory: [ContentPageNavigationHistorySnapshot],
    ) {
        self.id = id
        self.url = url
        self.sourceRoute = sourceRoute
        self.prePrepareBackHistory = prePrepareBackHistory
        self.prePrepareForwardHistory = prePrepareForwardHistory
    }
}

@CasePathable
public enum ContentPageNavigationAction: ViewAction, Equatable, Sendable {
    case view(View)
    case delegate(Delegate)
    case `internal`(Internal)

    @CasePathable
    public enum View: CasePathable, Equatable, Sendable {
        case goBack
        case goForward
        case goToHistoryIndex(Int, isBackHistory: Bool)
        case goToEnclosingDirectory
        case navigateToPath(String)
        case showRecents
        case showComputer
        case showTag(String)
        case showAiChat(String)
        case showAiChatSessions(String)
        case openCollectionFile(URL)
    }

    @CasePathable
    public enum Internal: CasePathable, Equatable, Sendable {
        case performNavigateToPath(String)
        case performShowRecents
        case performShowComputer
        case performShowTag(String)
        case performShowAiChat(String)
        case performShowAiChatSessions(String)
        case prepareCollectionFileOpen(URL)
        case rollbackBackHistoryOnce
        case restoreHistory(
            back: [ContentPageNavigationHistorySnapshot],
            forward: [ContentPageNavigationHistorySnapshot],
        )
        case appendBackHistory(ContentPageNavigationHistorySnapshot)
        case clearForwardHistory
        case setNavigationState(ContentPageNavigationRoute)
        case applyPinnedPeerNavigationState(ContentPageNavigationRoute)
        case setPendingNavigation(ContentPageNavigationPending?)
        case collectionFileLoaded(
            request: ContentPageCollectionOpenRequest,
            result: ContentPageCollectionFileLoadResult,
        )
        case navigateToCollection(ContentPageCollectionNavigation)
        case performNavigation(ContentPageNavigationPending)
        case showUnsavedNavigationAlert(ContentPageNavigationPending)
        case unsavedNavigationAlertResponse(ContentPageNavigationPending, CollectionNavigationChoice)
    }

    @CasePathable
    public enum Delegate: CasePathable, Equatable, Sendable {
        case navigateToState(ContentPageNavigationRoute)
        case logDAUNavigation(
            previous: ContentPageNavigationRoute,
            next: ContentPageNavigationRoute,
        )
        case revealEntryAfterNavigation(destinationPath: String, entryPath: String)
        case resetComposer
    }
}
