import ComposableArchitecture
import Foundation
import IdentifiedCollections

@Reducer
struct EntryOperationsLoadingReducer {
    typealias State = EntryOperationsState
    typealias Action = EntryOperationsAction

    @Dependency(\.entryLoadingClient)
    private var entryLoadingClient
    @Dependency(\.workspaceClient)
    private var workspaceClient

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case let .loadItems(path, showHidden):
                state.isLoading = true
                return .run { send in
                    let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
                    do {
                        let items = try await entryLoadingClient.loadItems(url, showHidden)
                        await send(.itemsLoaded(items))
                    } catch {
                        await send(.itemsLoaded([]))
                    }
                }

            case let .loadRecentItems(showHidden):
                state.isLoading = true
                return .run { [entryLoadingClient, workspaceClient] send in
                    let recentItems = await entryLoadingClient.loadRecentItems(showHidden, workspaceClient)
                    await send(.itemsLoaded(recentItems))
                }

            case let .loadTagItems(tagName, showHidden):
                state.isLoading = true
                return .run { [entryLoadingClient, workspaceClient] send in
                    let taggedItems = await entryLoadingClient.loadFilesWithTag(tagName, showHidden, workspaceClient)
                    await send(.itemsLoaded(taggedItems))
                }

            case .loadComputerItems:
                state.isLoading = true
                return .run { [entryLoadingClient] send in
                    do {
                        let computerItems = try await entryLoadingClient.loadComputerItems()
                        await send(.itemsLoaded(computerItems))
                    } catch {
                        await send(.itemsLoaded([]))
                    }
                }

            case let .itemsLoaded(items):
                state.loadingContext.items = IdentifiedArray(uniqueElements: items)
                state.isLoading = false
                state.isReloading = false
                return .none

            case let .collectionItemsLoadedFromSearch(items, showHidden):
                let converted = EntryCollectionItemsConverter.convert(
                    items,
                    showHidden: showHidden,
                    entryLoadingClient: entryLoadingClient,
                    workspaceClient: workspaceClient,
                )
                state.loadingContext.collectionItems = IdentifiedArray(uniqueElements: converted)
                return .none

            case let .setCollectionMode(isCollectionMode):
                state.loadingContext.isCollectionMode = isCollectionMode
                return .none

            case .clearCollectionItems:
                state.loadingContext.collectionItems = []
                return .none

            default:
                return .none
            }
        }
    }
}
