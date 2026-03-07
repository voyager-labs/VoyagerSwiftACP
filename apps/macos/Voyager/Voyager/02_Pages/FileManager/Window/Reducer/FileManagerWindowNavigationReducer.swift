import ComposableArchitecture
import Foundation

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
            case .sidebar(.favoritesLoaded),
                 .sidebar(.locationsLoaded),
                 .sidebar(.tagsLoaded):
                syncSidebarSelection(state: &state)
                return .none

            case let .sidebar(.openFavorite(favorite)):
                if favorite.url.pathExtension.lowercased() == CollectionConstants.fileExtension {
                    state.sidebar.pendingSidebarSelectionRestore = state.sidebar.selectedSidebarItem
                    state.sidebar.selectedSidebarItem = favorite.displayName
                    return .send(.navigation(.view(.openCollectionFile(favorite.url))))
                }
                return .send(.navigation(.view(.navigateToPath(favorite.url.path))))

            case let .sidebar(.openLocation(location)):
                return .send(.navigation(.view(.navigateToPath(location.url.path))))

            case let .sidebar(.showTag(tag)):
                return .send(.navigation(.view(.showTag(tag.name))))

            case .sidebar(.showRecents):
                return .send(.navigation(.view(.showRecents)))

            case .sidebar(.showComputer):
                return .send(.navigation(.view(.showComputer)))

            case let .content(.entries(.navigateFolder(id: id))):
                guard let entry = state.content.entryOperations.displayItems[id: id] else {
                    return .none
                }
                return .send(.navigation(.view(.navigateToPath(entry.fullPath))))

            case let .content(.entries(.openCollectionFile(url))):
                return .send(.navigation(.view(.openCollectionFile(url))))

            case let .content(.requestNavigation(navigationAction)):
                return .send(.navigation(navigationAction))

            case let .content(.performPendingNavigation(pending)):
                return .send(.navigation(.internal(.performNavigation(pending))))

            case .content(.composer(.internal(.searchResponse(.success)))),
                 .content(.composer(.internal(.filtersResponse(.success)))),
                 .content(.discardCollectionChanges):
                syncSidebarSelection(state: &state)
                return .none

            case .content(.composer(.internal(.searchResponse(.failure)))),
                 .content(.composer(.internal(.filtersResponse(.failure)))):
                if state.sidebar.pendingSidebarSelectionRestore != nil {
                    return .send(.sidebar(.restoreSidebarSelection))
                }
                return .none

            default:
                return .none
            }
        }
    }

    private func syncSidebarSelection(state: inout State) {
        let computerName = state.sidebar.locations.first(where: { $0.isComputer })?.name
            ?? state.content.navigation.currentPath
        switch state.content.navigation.navigationState {
        case .collection:
            if let url = state.content.collectionSession.openedURL {
                state.sidebar.selectedSidebarItem = state.sidebar.favorites
                    .first(where: { $0.url.path == url.path })
                    .map(\.displayName) ?? state.content.collectionSession.openedName
            } else {
                state.sidebar.selectedSidebarItem = nil
            }
        case .recents:
            state.sidebar.selectedSidebarItem = "Recents"
        case let .tags(tagName):
            state.sidebar.selectedSidebarItem = tagName
        case .computer:
            state.sidebar.selectedSidebarItem = computerName
        case .folder:
            state.sidebar.selectedSidebarItem = matchedSidebarItemName(
                path: state.content.navigation.currentPath,
                favorites: state.sidebar.favorites,
                locations: state.sidebar.locations,
                computerName: computerName,
            )
        }
    }

    private func matchedSidebarItemName(
        path: String,
        favorites: [SidebarItems.FavoriteItem],
        locations: [SidebarItems.LocationItem],
        computerName: String,
    ) -> String? {
        if path == computerName {
            return locations.first(where: { $0.isComputer })?.name ?? path
        }
        if !path.hasPrefix("/") {
            return path
        }
        return favorites.first(where: { $0.url.path == path })?.name
            ?? locations.first(where: { $0.url.path == path })?.name
    }
}

func syncSidebarSelection(
    state: inout FileManagerWindowState,
    computerName: String,
) {
    switch state.content.navigation.navigationState {
    case .collection:
        if let url = state.content.collectionSession.openedURL {
            state.sidebar.selectedSidebarItem = state.sidebar.favorites
                .first(where: { $0.url.path == url.path })
                .map(\.displayName) ?? state.content.collectionSession.openedName
        } else {
            state.sidebar.selectedSidebarItem = nil
        }
    case .recents:
        state.sidebar.selectedSidebarItem = "Recents"
    case let .tags(tagName):
        state.sidebar.selectedSidebarItem = tagName
    case .computer:
        state.sidebar.selectedSidebarItem = computerName
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
    computerName: String,
) -> String? {
    if path == computerName {
        return locations.first(where: { $0.isComputer })?.name ?? path
    }
    if !path.hasPrefix("/") {
        return path
    }
    return favorites.first(where: { $0.url.path == path })?.name
        ?? locations.first(where: { $0.url.path == path })?.name
}

func handleNavigateToState(
    _ navigationState: ContentPageNavigationRoute,
    state: inout FileManagerWindowState,
) -> Effect<FileManagerWindowAction> {
    switch navigationState {
    case let .folder(path):
        .concatenate(
            .send(.content(.entries(.setCollectionMode(false)))),
            .send(.content(.entries(.loadItems(path: path)))),
        )
    case .recents:
        .concatenate(
            .send(.content(.entries(.setCollectionMode(false)))),
            .send(.content(.entries(.loadRecentItems(showHidden: state.content.entryViewLayout.showHiddenFiles)))),
        )
    case let .tags(tagName):
        .concatenate(
            .send(.content(.entries(.setCollectionMode(false)))),
            .send(.content(.entries(.loadTagItems(
                tagName: tagName,
                showHidden: state.content.entryViewLayout.showHiddenFiles,
            )))),
        )
    case .computer:
        .concatenate(
            .send(.content(.entries(.setCollectionMode(false)))),
            .send(.content(.entries(.loadComputerItems))),
        )
    case let .collection(navigation):
        .concatenate(
            .send(.content(.entries(.setCollectionMode(true)))),
            .send(.navigation(.internal(.navigateToCollection(navigation)))),
        )
    }
}
