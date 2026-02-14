import AppKit
import ComposableArchitecture
import Foundation
import UniformTypeIdentifiers

@Reducer
struct FileManagerSidebarFeature {
    @Dependency(\.entryLoadingClient)
    var entryLoadingClient
    @Dependency(\.userDefaultsClient)
    var userDefaultsClient
    @Dependency(\.fileManagerFavoritesClient)
    var favoritesClient
    @Dependency(\.fileManagerLocationsClient)
    var locationsClient
    @Dependency(\.fileManagerIconClient)
    var iconClient
    @Dependency(\.finderFavoritesTagClient)
    var finderFavoritesTagClient

    typealias State = FileManagerSidebarState
    typealias Action = FileManagerSidebarAction

    var body: some Reducer<State, Action> {
        Reduce { state, action in
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

            case .loadFavorites:
                return .run { send in
                    let favorites = await favoritesClient.loadFavorites(entryLoadingClient, userDefaultsClient)
                    await send(.favoritesLoaded(favorites))
                }

            case let .favoritesLoaded(favorites):
                state.favorites = favorites
                return .none

            case let .insertFavoriteFromDrop(providers, index):
                return .run { @MainActor send in
                    for provider in providers
                        where provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier)
                    {
                        let resolvedURL: URL? = await withCheckedContinuation { continuation in
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

                        if let resolvedURL {
                            await send(.insertFavorite(url: resolvedURL, at: index))
                            return
                        }
                    }
                }

            case let .insertFavorite(url, index):
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

                // TODO(Collection): Collection 처리 도메인 이동
                let isVoycoll = url.pathExtension.lowercased() == "voycoll"
                guard isDirectory.boolValue || isVoycoll else {
                    return .none
                }

                let name = isVoycoll
                    ? url.deletingPathExtension().lastPathComponent
                    : entryLoadingClient.displayName(url.path)
                let iconName = iconClient.iconNameForURL(url, isDirectory.boolValue, entryLoadingClient)
                let newFavorite = SidebarItems.FavoriteItem(name: name, url: url, iconName: iconName)

                let insertIndex = max(0, min(index, state.favorites.count))
                state.favorites.insert(newFavorite, at: insertIndex)
                favoritesClient.saveFavorites(state.favorites, userDefaultsClient)
                return .none

            case let .removeFavorite(favorite):
                state.favorites.removeAll { $0.url.path == favorite.url.path }
                favoritesClient.saveFavorites(state.favorites, userDefaultsClient)
                return .none

            case let .reorderFavorites(source, destination):
                var reordered = state.favorites
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
                state.favorites = reordered
                favoritesClient.saveFavorites(state.favorites, userDefaultsClient)
                return .none

            case .loadLocations:
                return .run { send in
                    let locations = await locationsClient.loadLocations(entryLoadingClient)
                    await send(.locationsLoaded(locations))
                }

            case let .locationsLoaded(locations):
                state.locations = locations
                return .none

            case .loadTags:
                return .send(.tagsLoaded(finderFavoritesTagClient.favoriteTags()))

            case let .tagsLoaded(tags):
                state.tags = tags
                return .none

            case .toggleFavoritesSection:
                state.isFavoritesCollapsed.toggle()
                return .none

            case .toggleLocationsSection:
                state.isLocationsCollapsed.toggle()
                return .none

            case .toggleTagsSection:
                state.isTagsCollapsed.toggle()
                return .none

            case let .setSidebarWidth(width):
                let clampedWidth = max(150, min(400, width))
                if abs(state.sidebarWidth - clampedWidth) < 0.5 {
                    return .none
                }
                state.sidebarWidth = clampedWidth
                userDefaultsClient.setDouble(clampedWidth, SettingsKeys.sidebarWidth)
                return .none

            case .openFavorite,
                 .openLocation,
                 .showTag,
                 .showRecents,
                 .showComputer,
                 .dropItemsToSidebarFolder,
                 .dropItemsToTag:
                return .none
            }
        }
    }
}
