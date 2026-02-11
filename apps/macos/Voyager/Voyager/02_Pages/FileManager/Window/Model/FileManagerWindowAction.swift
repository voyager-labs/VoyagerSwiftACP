import ComposableArchitecture
import Foundation

@CasePathable
enum FileManagerWindowAction: CasePathable, Sendable {
    case content(FileManagerContentFeature.Action)
    case sidebar(FileManagerSidebarFeature.Action)
    case inspector(FileManagerInspectorFeature.Action)

    case navigation(FileManagerContentNavigationAction)
    case navigateTo(String)
    case openCollectionFile(URL)
    case collectionFileLoaded(Result<VoyagerCollectionFile, Error>)
    case navigateToCollection(FileManagerNavigationUtils.CollectionNavigation)
    case showRecents
    case showComputer
    case showTag(String)

    case onAppear
    case closeWindow
}
