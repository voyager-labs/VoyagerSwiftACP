import ComposableArchitecture
import Foundation
import VoyagerEntitiesCollection
import VoyagerEntitiesTag
import VoyagerFeaturesComposer
import VoyagerFeaturesContentPageNavigation
import VoyagerShared

@Reducer
struct FileManagerWindowNavigationReducer {
    typealias State = FileManagerWindowState
    typealias Action = FileManagerWindowAction

    var body: some Reducer<State, Action> {
        FileManagerNavigationBridgeReducer()
        FileManagerNavigationActionReducer()
    }
}

@Reducer
private struct FileManagerNavigationBridgeReducer {
    typealias State = FileManagerWindowState
    typealias Action = FileManagerWindowAction

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .sidebar(.internal(.favoritesLoaded)),
                 .sidebar(.internal(.locationsLoaded)),
                 .sidebar(.internal(.tagsLoaded)):
                let computerName = state.sidebar.locations.first(where: { $0.isComputer })?.name
                syncSidebarSelection(state: &state, computerName: computerName)
                state.syncContentTabSidebarItems()
                return .none

            case let .sidebar(.delegate(.openFavorite(favorite))):
                if favorite.url.pathExtension.lowercased() == CollectionConstants.fileExtension {
                    state.sidebar.pendingSidebarSelectionRestore = state.sidebar.selectedSidebarItem
                    state.sidebar.selectedSidebarItem = favorite.displayName
                    return .send(.navigation(.view(.openCollectionFile(favorite.url))))
                }
                return .send(.navigation(.view(.navigateToPath(favorite.url.path))))

            case let .sidebar(.delegate(.openLocation(location))):
                return .send(.navigation(.view(.navigateToPath(location.url.path))))

            case let .sidebar(.delegate(.showTag(tagName))):
                return .send(.navigation(.view(.showTag(tagName))))

            case .sidebar(.delegate(.showRecents)):
                return .send(.navigation(.view(.showRecents)))

            case .sidebar(.delegate(.showComputer)):
                return .send(.navigation(.view(.showComputer)))

            case let .content(.internal(.requestNavigation(navigationAction))):
                return .send(.navigation(navigationAction))

            case let .content(.internal(.applyNavigationState(navigationState))):
                let computerName = state.sidebar.locations.first(where: { $0.isComputer })?.name
                    ?? state.content.navigation.currentPath
                syncSidebarSelection(state: &state, computerName: computerName)
                return syncActiveContentTabEffect(
                    navigationState,
                    state: state,
                    computerName: computerName,
                )

            case let .content(.internal(.performPendingNavigation(pending))):
                return .send(.navigation(.internal(.performNavigation(pending))))

            case .content(.delegate(.composerCollectionSearchSucceeded)),
                 .content(.delegate(.collectionChangesDiscarded)):
                let computerName = state.sidebar.locations.first(where: { $0.isComputer })?.name
                syncSidebarSelection(state: &state, computerName: computerName)
                return .none

            case .content(.delegate(.composerCollectionSearchFailed)):
                if state.sidebar.pendingSidebarSelectionRestore != nil {
                    return .send(.sidebar(.internal(.restoreSidebarSelection)))
                }
                return .none

            default:
                return .none
            }
        }
    }
}

func syncSidebarSelection(
    state: inout FileManagerWindowState,
    computerName: String?,
) {
    switch state.content.navigation.navigationState {
    case .home:
        state.sidebar.selectedSidebarItem = nil
    case .collection:
        if let url = state.content.collection.collectionSession.document?.url {
            state.sidebar.selectedSidebarItem = state.sidebar.favorites
                .first(where: { $0.url.path == url.path })
                .map(\.displayName) ?? state.content.collection.collectionSession.document?.name
        } else {
            state.sidebar.selectedSidebarItem = nil
        }
    case .recents:
        state.sidebar.selectedSidebarItem = "Recents"
    case let .tags(tagName):
        state.sidebar.selectedSidebarItem = tagName
    case .computer:
        state.sidebar.selectedSidebarItem = computerName ?? state.content.navigation.currentPath
    case .folder:
        state.sidebar.selectedSidebarItem = matchedSidebarItemName(
            path: state.content.navigation.currentPath,
            favorites: state.sidebar.favorites,
            locations: state.sidebar.locations,
            computerName: computerName,
        )
    }
}

func matchedSidebarItemName(
    path: String,
    favorites: [SidebarItems.FavoriteItem],
    locations: [SidebarItems.LocationItem],
    computerName: String?,
) -> String? {
    if let computerName, path == computerName {
        return locations.first(where: { $0.isComputer })?.name ?? path
    }
    if !path.hasPrefix("/") {
        return path
    }

    let standardizedPath = standardizedFilePath(path)
    return favorites.first(where: { standardizedFilePath($0.url.path) == standardizedPath })?.name
        ?? locations.first(where: { standardizedFilePath($0.url.path) == standardizedPath })?.name
}

private func standardizedFilePath(_ path: String) -> String {
    URL(fileURLWithPath: path).standardizedFileURL.path
}

func handleNavigateToState(
    _ navigationState: ContentPageNavigationRoute,
    state _: inout FileManagerWindowState,
) -> Effect<FileManagerWindowAction> {
    switch navigationState {
    case let .collection(navigation):
        .concatenate(
            .send(.content(.internal(.applyNavigationState(.collection(navigation))))),
            .send(.navigation(.internal(.navigateToCollection(navigation)))),
        )

    default:
        .send(.content(.internal(.applyNavigationState(navigationState))))
    }
}
