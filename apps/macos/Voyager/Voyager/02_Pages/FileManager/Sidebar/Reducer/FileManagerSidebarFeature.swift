import AppKit
import ComposableArchitecture
import Foundation
import UniformTypeIdentifiers
import VoyagerShared

@Reducer
struct FileManagerSidebarFeature {
    typealias State = FileManagerSidebarState
    typealias Action = FileManagerSidebarAction

    fileprivate enum CancelID {
        static let systemNotifications = "FileManagerSidebarFeature.systemNotifications"
    }

    var body: some Reducer<State, Action> {
        let visibility = SidebarVisibilityReducer()
        let favorites = SidebarFavoritesReducer()
        let locations = SidebarLocationsReducer()
        let tags = SidebarTagsReducer()
        let sectionCollapse = SidebarSectionCollapseReducer()
        let width = SidebarWidthReducer()
        let contextMenu = SidebarContextMenuReducer()

        Reduce { state, action in
            .merge(
                visibility.reduce(into: &state, action: action),
                favorites.reduce(into: &state, action: action),
                locations.reduce(into: &state, action: action),
                tags.reduce(into: &state, action: action),
                sectionCollapse.reduce(into: &state, action: action),
                width.reduce(into: &state, action: action),
                contextMenu.reduce(into: &state, action: action),
            )
        }
    }
}

private struct SidebarVisibilityReducer {
    @Dependency(\.userDefaultsClient)
    private var userDefaultsClient

    func reduce(into state: inout FileManagerSidebarState, action: FileManagerSidebarAction)
        -> Effect<FileManagerSidebarAction>
    {
        switch action {
        case let .setSidebarVisible(visible):
            state.sidebarVisible = visible
            userDefaultsClient.setObject(visible, SettingsKeys.sidebarVisible)
            return .none

        case .restoreSidebarSelection:
            if let restoreSelection = state.pendingSidebarSelectionRestore {
                state.selectedSidebarItem = restoreSelection
            }
            state.pendingSidebarSelectionRestore = nil
            return .none

        default:
            return .none
        }
    }
}

private struct SidebarFavoritesReducer {
    private let loading: SidebarFavoritesLoadingReducer
    private let insertion: SidebarFavoritesInsertionReducer
    private let editing: SidebarFavoritesEditingReducer

    init(
        loading: SidebarFavoritesLoadingReducer = .init(),
        insertion: SidebarFavoritesInsertionReducer = .init(),
        editing: SidebarFavoritesEditingReducer = .init(),
    ) {
        self.loading = loading
        self.insertion = insertion
        self.editing = editing
    }

    func reduce(into state: inout FileManagerSidebarState, action: FileManagerSidebarAction)
        -> Effect<FileManagerSidebarAction>
    {
        .merge(
            loading.reduce(into: &state, action: action),
            insertion.reduce(into: &state, action: action),
            editing.reduce(into: &state, action: action),
        )
    }
}

private struct SidebarFavoritesLoadingReducer {
    @Dependency(\.entryLoadingClient)
    private var entryLoadingClient
    @Dependency(\.userDefaultsClient)
    private var userDefaultsClient
    @Dependency(\.fileManagerFavoritesClient)
    private var favoritesClient

    func reduce(into state: inout FileManagerSidebarState, action: FileManagerSidebarAction)
        -> Effect<FileManagerSidebarAction>
    {
        switch action {
        case .loadFavorites:
            return .run { send in
                let favorites = await favoritesClient.loadFavorites(entryLoadingClient, userDefaultsClient)
                await send(.favoritesLoaded(favorites))
            }

        case let .favoritesLoaded(favorites):
            state.favorites = favorites
            return .none

        default:
            return .none
        }
    }
}

private struct SidebarFavoritesInsertionReducer {
    @Dependency(\.entryLoadingClient)
    private var entryLoadingClient
    @Dependency(\.userDefaultsClient)
    private var userDefaultsClient
    @Dependency(\.fileManagerFavoritesClient)
    private var favoritesClient
    @Dependency(\.fileManagerIconClient)
    private var iconClient

    func reduce(into state: inout FileManagerSidebarState, action: FileManagerSidebarAction)
        -> Effect<FileManagerSidebarAction>
    {
        switch action {
        case let .insertFavoriteFromDrop(providers, index):
            insertFavoriteFromDropEffect(providers: providers, index: index)

        case let .insertFavorite(url, index):
            insertFavorite(url: url, index: index, state: &state)

        default:
            .none
        }
    }

    private func insertFavoriteFromDropEffect(providers: [NSItemProvider], index: Int)
        -> Effect<FileManagerSidebarAction>
    {
        .run { @MainActor send in
            for provider in providers
                where provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier)
            {
                let resolvedURL: URL? = await resolveURL(from: provider)
                if let resolvedURL {
                    await send(.insertFavorite(url: resolvedURL, at: index))
                    return
                }
            }
        }
    }

    private func resolveURL(from provider: NSItemProvider) async -> URL? {
        await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                if let url = item as? URL {
                    continuation.resume(returning: url)
                    return
                }

                if let data = item as? Data {
                    if let urlString = String(data: data, encoding: .utf8),
                       let url = URL(string: urlString)
                    {
                        continuation.resume(returning: url)
                        return
                    }
                    continuation.resume(returning: URL(dataRepresentation: data, relativeTo: nil))
                    return
                }

                continuation.resume(returning: nil)
            }
        }
    }

    private func insertFavorite(
        url: URL,
        index: Int,
        state: inout FileManagerSidebarState,
    ) -> Effect<FileManagerSidebarAction> {
        if let existingIndex = state.favorites.firstIndex(where: { $0.url.path == url.path }) {
            if existingIndex != index {
                return .send(.reorderFavorites(from: IndexSet(integer: existingIndex), to: index))
            }
            return .none
        }

        var isDirectory: ObjCBool = false
        guard entryLoadingClient.fileExistsAtPath(url.path, &isDirectory) else {
            return .none
        }

        let isCollection = CollectionFileUtils.isCollectionFile(url)
        guard isDirectory.boolValue || isCollection else {
            return .none
        }

        let name = CollectionFileUtils.displayName(url, fallback: entryLoadingClient.displayName(url.path))
        let iconName = iconClient.iconNameForURL(url, isDirectory.boolValue, entryLoadingClient)
        let newFavorite = SidebarItems.FavoriteItem(name: name, url: url, iconName: iconName)

        let insertIndex = max(0, min(index, state.favorites.count))
        state.favorites.insert(newFavorite, at: insertIndex)
        favoritesClient.saveFavorites(state.favorites, userDefaultsClient)
        return .none
    }
}

private struct SidebarFavoritesEditingReducer {
    @Dependency(\.userDefaultsClient)
    private var userDefaultsClient
    @Dependency(\.fileManagerFavoritesClient)
    private var favoritesClient

    func reduce(into state: inout FileManagerSidebarState, action: FileManagerSidebarAction)
        -> Effect<FileManagerSidebarAction>
    {
        switch action {
        case let .removeFavorite(favorite):
            state.favorites.removeAll { $0.url.path == favorite.url.path }
            favoritesClient.saveFavorites(state.favorites, userDefaultsClient)
            return .none

        case let .reorderFavorites(source, destination):
            state.favorites = reorderedFavorites(current: state.favorites, source: source, destination: destination)
            favoritesClient.saveFavorites(state.favorites, userDefaultsClient)
            return .none

        default:
            return .none
        }
    }

    private func reorderedFavorites(
        current: [SidebarItems.FavoriteItem],
        source: IndexSet,
        destination: Int,
    ) -> [SidebarItems.FavoriteItem] {
        var reordered = current
        let sortedIndices = source.sorted(by: >)
        var itemsToMove: [SidebarItems.FavoriteItem] = []
        for index in sortedIndices {
            itemsToMove.insert(reordered.remove(at: index), at: 0)
        }
        let maxSourceIndex = source.max() ?? 0
        let adjustedDestination = destination > maxSourceIndex
            ? destination - itemsToMove.count
            : destination
        let insertIndex = max(0, min(adjustedDestination, reordered.count))
        reordered.insert(contentsOf: itemsToMove, at: insertIndex)
        return reordered
    }
}

private struct SidebarLocationsReducer {
    @Dependency(\.entryLoadingClient)
    private var entryLoadingClient
    @Dependency(\.fileManagerLocationsClient)
    private var locationsClient

    func reduce(into state: inout FileManagerSidebarState, action: FileManagerSidebarAction)
        -> Effect<FileManagerSidebarAction>
    {
        switch action {
        case .loadLocations:
            return .run { send in
                let locations = await locationsClient.loadLocations(entryLoadingClient)
                await send(.locationsLoaded(locations))
            }

        case let .locationsLoaded(locations):
            state.locations = locations
            return .none

        default:
            return .none
        }
    }
}

private struct SidebarTagsReducer {
    @Dependency(\.finderFavoritesTagClient)
    private var finderFavoritesTagClient

    func reduce(into state: inout FileManagerSidebarState, action: FileManagerSidebarAction)
        -> Effect<FileManagerSidebarAction>
    {
        switch action {
        case .loadTags:
            return .send(.tagsLoaded(finderFavoritesTagClient.favoriteTags()))

        case let .tagsLoaded(tags):
            state.tags = tags
            return .none

        default:
            return .none
        }
    }
}

private struct SidebarSectionCollapseReducer {
    func reduce(into state: inout FileManagerSidebarState, action: FileManagerSidebarAction)
        -> Effect<FileManagerSidebarAction>
    {
        switch action {
        case .toggleFavoritesSection:
            state.isFavoritesCollapsed.toggle()
            return .none

        case .toggleLocationsSection:
            state.isLocationsCollapsed.toggle()
            return .none

        case .toggleTagsSection:
            state.isTagsCollapsed.toggle()
            return .none

        default:
            return .none
        }
    }
}

private struct SidebarWidthReducer {
    @Dependency(\.userDefaultsClient)
    private var userDefaultsClient

    func reduce(into state: inout FileManagerSidebarState, action: FileManagerSidebarAction)
        -> Effect<FileManagerSidebarAction>
    {
        switch action {
        case let .setSidebarWidth(width):
            let clampedWidth = max(150, min(400, width))
            if abs(state.sidebarWidth - clampedWidth) < 0.5 {
                return .none
            }
            state.sidebarWidth = clampedWidth
            userDefaultsClient.setDouble(clampedWidth, SettingsKeys.sidebarWidth)
            return .none

        default:
            return .none
        }
    }
}

private struct SidebarContextMenuReducer {
    @Dependency(\.notificationCenterClient)
    private var notificationCenterClient

    func reduce(into state: inout FileManagerSidebarState, action: FileManagerSidebarAction)
        -> Effect<FileManagerSidebarAction>
    {
        switch action {
        case .startObservingSystemNotifications:
            return .run { send in
                for await _ in await notificationCenterClient.notifications(
                    NSMenu.didEndTrackingNotification,
                    nil,
                ) {
                    await send(.systemMenuDidEndTracking)
                }
            }
            .cancellable(id: FileManagerSidebarFeature.CancelID.systemNotifications, cancelInFlight: true)

        case .stopObservingSystemNotifications:
            return .cancel(id: FileManagerSidebarFeature.CancelID.systemNotifications)

        case .systemMenuDidEndTracking:
            state.contextMenuTargetId = nil
            state.contextMenuTargetWasSelected = false
            return .none

        case let .setContextMenuTarget(id, wasSelected):
            state.contextMenuTargetId = id
            state.contextMenuTargetWasSelected = wasSelected
            return .none

        default:
            return .none
        }
    }
}
