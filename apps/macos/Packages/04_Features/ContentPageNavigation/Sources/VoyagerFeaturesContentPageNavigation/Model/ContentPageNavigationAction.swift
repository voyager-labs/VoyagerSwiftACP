import ComposableArchitecture
import Foundation
import VoyagerEntitiesCollection

public struct ContentPageNavigationErrorFingerprint: Equatable, Sendable {
    public let domain: String
    public let code: Int
    public let message: String

    public init(error: Error) {
        let nsError = error as NSError
        domain = nsError.domain
        code = nsError.code
        message = nsError.localizedDescription
    }
}

public enum ContentPageCollectionFileLoadResult: Equatable, Sendable {
    case success(CollectionFileLoadResult)
    case failure(ContentPageNavigationErrorFingerprint)
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
        case openCollectionFile(URL)
    }

    @CasePathable
    public enum Internal: CasePathable, Equatable, Sendable {
        case performNavigateToPath(String)
        case performShowRecents
        case performShowComputer
        case performShowTag(String)
        case prepareCollectionFileOpen(URL)
        case rollbackBackHistoryOnce
        case appendBackHistory(ContentPageNavigationHistorySnapshot)
        case clearForwardHistory
        case setNavigationState(ContentPageNavigationRoute)
        case setPendingNavigation(ContentPageNavigationPending?)
        case collectionFileLoaded(ContentPageCollectionFileLoadResult)
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
        case resetComposer
    }
}
