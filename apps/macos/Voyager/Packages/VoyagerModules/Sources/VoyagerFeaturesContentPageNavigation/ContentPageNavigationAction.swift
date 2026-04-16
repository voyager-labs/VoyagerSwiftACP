import ComposableArchitecture
import Foundation
import VoyagerEntitiesEntry

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
    case success(VoyagerCollectionFile)
    case failure(ContentPageNavigationErrorFingerprint)
}

@CasePathable
public enum ContentPageNavigationAction: ViewAction, Equatable, Sendable {
    case view(View)
    case delegate(Delegate)
    case `internal`(Internal)

    public enum View: Equatable, Sendable {
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

    public enum Internal: Equatable, Sendable {
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

    public enum Delegate: Equatable, Sendable {
        case navigateToState(ContentPageNavigationRoute)
        case logDAUNavigation(
            previous: ContentPageNavigationRoute,
            next: ContentPageNavigationRoute,
        )
        case resetComposer
    }
}
