// TODO(ContentPageNavigation): 2차 네이밍 정리
// - 파일명 변경: FileManagerContentNavigationAction.swift -> ContentPageNavigationAction.swift
// - 타입명 변경:
//   - FileManagerContentNavigationAction -> ContentPageNavigationAction
//   - FileManagerContentNavigationDelegate -> ContentPageNavigationDelegate
// - 주의:
//   - 이 단계에서는 동작 변경 금지(로직 수정 금지). 네이밍만 정리한다.
import ComposableArchitecture
import Foundation

enum FileManagerContentNavigationDelegate: Equatable, Sendable {
    case applyContentPageHistory(ContentPageHistory)
    case navigateToState(FileManagerNavigationUtils.NavigationState)
    case logDAUNavigation(
        previous: FileManagerNavigationUtils.NavigationState,
        next: FileManagerNavigationUtils.NavigationState,
    )
    case resetComposer
}

@CasePathable
enum FileManagerContentNavigationAction: Equatable, Sendable {
    case goBack
    case goForward
    case goToHistoryIndex(Int, isBackHistory: Bool)
    case goToEnclosingDirectory
    case navigateToPath(String)
    case showRecents
    case showComputer
    case showTag(String)
    case openCollectionFile(URL)
    case collectionFileLoaded(Result<VoyagerCollectionFile, Error>)
    case navigateToCollection(FileManagerNavigationUtils.CollectionNavigation)
    case performNavigation(ContentPendingNavigation, currentSnapshot: ContentPageHistory)
    case showUnsavedNavigationAlert(ContentPendingNavigation)
    case unsavedNavigationAlertResponse(ContentPendingNavigation, CollectionNavigationChoice)
    case delegate(FileManagerContentNavigationDelegate)
}

extension FileManagerContentNavigationAction {
    static func == (
        lhs: FileManagerContentNavigationAction,
        rhs: FileManagerContentNavigationAction,
    ) -> Bool {
        switch (lhs, rhs) {
        case (.goBack, .goBack),
             (.goForward, .goForward),
             (.goToEnclosingDirectory, .goToEnclosingDirectory),
             (.showRecents, .showRecents),
             (.showComputer, .showComputer):
            return true

        case let (.goToHistoryIndex(lhsIndex, lhsIsBack), .goToHistoryIndex(rhsIndex, rhsIsBack)):
            return lhsIndex == rhsIndex && lhsIsBack == rhsIsBack

        case let (.navigateToPath(lhsPath), .navigateToPath(rhsPath)):
            return lhsPath == rhsPath

        case let (.showTag(lhsTag), .showTag(rhsTag)):
            return lhsTag == rhsTag

        case let (.openCollectionFile(lhsURL), .openCollectionFile(rhsURL)):
            return lhsURL == rhsURL

        case let (.collectionFileLoaded(lhsResult), .collectionFileLoaded(rhsResult)):
            switch (lhsResult, rhsResult) {
            case let (.success(lhsFile), .success(rhsFile)):
                return lhsFile == rhsFile
            case let (.failure(lhsError), .failure(rhsError)):
                let lhsNSError = lhsError as NSError
                let rhsNSError = rhsError as NSError
                return lhsNSError.domain == rhsNSError.domain
                    && lhsNSError.code == rhsNSError.code
            default:
                return false
            }

        case let (.navigateToCollection(lhsCollection), .navigateToCollection(rhsCollection)):
            return lhsCollection == rhsCollection

        case let (.performNavigation(lhsNavigation, lhsSnapshot), .performNavigation(rhsNavigation, rhsSnapshot)):
            return lhsNavigation == rhsNavigation && lhsSnapshot == rhsSnapshot

        case let (.showUnsavedNavigationAlert(lhsNavigation), .showUnsavedNavigationAlert(rhsNavigation)):
            return lhsNavigation == rhsNavigation

        case let (
            .unsavedNavigationAlertResponse(lhsNavigation, lhsChoice),
            .unsavedNavigationAlertResponse(rhsNavigation, rhsChoice),
        ):
            return lhsNavigation == rhsNavigation && lhsChoice == rhsChoice

        case let (.delegate(lhsDelegate), .delegate(rhsDelegate)):
            return lhsDelegate == rhsDelegate

        default:
            return false
        }
    }
}
