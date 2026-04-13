import AppKit
import ComposableArchitecture
import Foundation
import UniformTypeIdentifiers
import VoyagerEntitiesEntry
import VoyagerShared

@Reducer
public struct FileManagerSidebarFeature {
    public typealias State = FileManagerSidebarState
    public typealias Action = FileManagerSidebarAction

    public enum CancelID {
        public static let systemNotifications = "FileManagerSidebarFeature.systemNotifications"
    }

    @Dependency(\.entryLoadingClient)
    private var entryLoadingClient
    @Dependency(\.userDefaultsClient)
    private var userDefaultsClient
    @Dependency(\.fileManagerFavoritesClient)
    private var favoritesClient
    @Dependency(\.fileManagerLocationsClient)
    private var locationsClient
    @Dependency(\.finderFavoritesTagClient)
    private var finderFavoritesTagClient
    @Dependency(\.notificationCenterClient)
    private var notificationCenterClient
    @Dependency(\.fileManagerIconClient)
    private var iconClient

    public var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case let .view(.setSidebarVisible(visible)):
                state.sidebarVisible = visible
                userDefaultsClient.setObject(visible, SettingsKeys.sidebarVisible)
                return .none

            case .view(.toggleFavoritesSection):
                state.isFavoritesCollapsed.toggle()
                return .none

            case .view(.toggleLocationsSection):
                state.isLocationsCollapsed.toggle()
                return .none

            case .view(.toggleTagsSection):
                state.isTagsCollapsed.toggle()
                return .none

            case let .view(.setSidebarWidth(width)):
                let clampedWidth = max(150, min(400, width))
                if abs(state.sidebarWidth - clampedWidth) < 0.5 {
                    return .none
                }
                state.sidebarWidth = clampedWidth
                userDefaultsClient.setDouble(clampedWidth, SettingsKeys.sidebarWidth)
                return .none

            case let .view(.setContextMenuTarget(id, wasSelected)):
                state.contextMenuTargetId = id
                state.contextMenuTargetWasSelected = wasSelected
                return .none

            case .internal(.restoreSidebarSelection):
                if let restoreSelection = state.pendingSidebarSelectionRestore {
                    state.selectedSidebarItem = restoreSelection
                }
                state.pendingSidebarSelectionRestore = nil
                return .none

            case .internal(.loadFavorites):
                let favoritesClient = favoritesClient
                let entryLoadingClient = entryLoadingClient
                let userDefaultsClient = userDefaultsClient
                return .run { send in
                    let favorites = await favoritesClient.loadFavorites(entryLoadingClient, userDefaultsClient)
                    await send(.internal(.favoritesLoaded(favorites)))
                }

            case let .internal(.favoritesLoaded(favorites)):
                state.favorites = favorites
                return .none

            case let .internal(.insertFavoriteFromDrop(providers, index)):
                return insertFavoriteFromDropEffect(providers: providers, index: index)

            case let .internal(.insertFavorite(url, index)):
                return insertFavorite(url: url, index: index, state: &state)

            case let .internal(.removeFavorite(favorite)):
                state.favorites.removeAll { $0.url.path == favorite.url.path }
                favoritesClient.saveFavorites(state.favorites, userDefaultsClient)
                return .none

            case let .internal(.reorderFavorites(source, destination)):
                state.favorites = reorderedFavorites(
                    current: state.favorites,
                    source: source,
                    destination: destination,
                )
                favoritesClient.saveFavorites(state.favorites, userDefaultsClient)
                return .none

            case .internal(.loadLocations):
                let locationsClient = locationsClient
                let entryLoadingClient = entryLoadingClient
                return .run { send in
                    let locations = await locationsClient.loadLocations(entryLoadingClient)
                    await send(.internal(.locationsLoaded(locations)))
                }

            case let .internal(.locationsLoaded(locations)):
                state.locations = locations
                return .none

            case .internal(.loadTags):
                return .send(.internal(.tagsLoaded(finderFavoritesTagClient.favoriteTags())))

            case let .internal(.tagsLoaded(tags)):
                state.tags = tags
                return .none

            case .internal(.startObservingSystemNotifications):
                let notificationCenterClient = notificationCenterClient
                return .run { send in
                    for await _ in await notificationCenterClient.notifications(
                        NSMenu.didEndTrackingNotification,
                        nil,
                    ) {
                        await send(.internal(.systemMenuDidEndTracking))
                    }
                }
                .cancellable(id: CancelID.systemNotifications, cancelInFlight: true)

            case .internal(.stopObservingSystemNotifications):
                return .cancel(id: CancelID.systemNotifications)

            case .internal(.systemMenuDidEndTracking):
                state.contextMenuTargetId = nil
                state.contextMenuTargetWasSelected = false
                return .none

            case .delegate:
                return .none
            }
        }
    }

    private func insertFavoriteFromDropEffect(providers: [NSItemProvider], index: Int)
        -> Effect<FileManagerSidebarAction>
    {
        nonisolated(unsafe) let safeProviders = providers
        return .run { @MainActor send in
            for provider in safeProviders
                where provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier)
            {
                let resolvedURL = await Self.resolveURL(from: provider)
                if let resolvedURL {
                    await send(.internal(.insertFavorite(url: resolvedURL, at: index)))
                    return
                }
            }
        }
    }

    private static func resolveURL(from provider: NSItemProvider) async -> URL? {
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
                return .send(.internal(.reorderFavorites(from: IndexSet(integer: existingIndex), to: index)))
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
