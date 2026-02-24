import ComposableArchitecture
import Foundation

enum ContentPageNavigationDelegate: Equatable, Sendable {
    case navigateToState(ContentPageNavigationRoute)
    case logDAUNavigation(
        previous: ContentPageNavigationRoute,
        next: ContentPageNavigationRoute,
    )
    case resetComposer
}

struct ContentPageNavigationErrorFingerprint: Equatable, Sendable {
    let domain: String
    let code: Int
    let message: String

    init(error: Error) {
        let nsError = error as NSError
        domain = nsError.domain
        code = nsError.code
        message = nsError.localizedDescription
    }
}

enum ContentPageCollectionFileLoadResult: Equatable, Sendable {
    case success(VoyagerCollectionFile)
    case failure(ContentPageNavigationErrorFingerprint)
}

@CasePathable
enum ContentPageNavigationAction: Equatable, Sendable {
    case goBack
    case goForward
    case goToHistoryIndex(Int, isBackHistory: Bool)
    case goToEnclosingDirectory
    case navigateToPath(String)
    case showRecents
    case showComputer
    case showTag(String)
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
    case openCollectionFile(URL)
    case collectionFileLoaded(ContentPageCollectionFileLoadResult)
    case navigateToCollection(ContentPageCollectionNavigation)
    case performNavigation(ContentPageNavigationPending)
    case showUnsavedNavigationAlert(ContentPageNavigationPending)
    case unsavedNavigationAlertResponse(ContentPageNavigationPending, CollectionNavigationChoice)
    case delegate(ContentPageNavigationDelegate)
}
