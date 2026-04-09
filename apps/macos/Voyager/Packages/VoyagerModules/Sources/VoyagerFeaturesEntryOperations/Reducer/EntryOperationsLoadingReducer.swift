import ComposableArchitecture
import Foundation
import IdentifiedCollections

@Reducer
public struct EntryOperationsLoadingReducer {
    public typealias State = EntryOperationsState
    public typealias Action = EntryOperationsAction

    public init() {}

    @Dependency(\.entryLoadingClient)
    private var entryLoadingClient
    @Dependency(\.workspaceClient)
    private var workspaceClient

    public var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case let .loading(.loadItems(path, showHidden)):
                state.isLoading = true
                return .run { [entryLoadingClient] send in
                    let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
                    do {
                        let items = try await entryLoadingClient.loadItems(url, showHidden)
                        await send(.loading(.itemsLoaded(items)))
                    } catch {
                        await send(.loading(.itemsLoaded([])))
                    }
                }

            case let .loading(.loadRecentItems(showHidden)):
                state.isLoading = true
                return .run { [entryLoadingClient, workspaceClient] send in
                    let recentItems = await entryLoadingClient.loadRecentItems(showHidden, workspaceClient)
                    await send(.loading(.itemsLoaded(recentItems)))
                }

            case let .loading(.loadTagItems(tagName, showHidden)):
                state.isLoading = true
                return .run { [entryLoadingClient, workspaceClient] send in
                    let taggedItems = await entryLoadingClient.loadFilesWithTag(tagName, showHidden, workspaceClient)
                    await send(.loading(.itemsLoaded(taggedItems)))
                }

            case .loading(.loadComputerItems):
                state.isLoading = true
                return .run { [entryLoadingClient] send in
                    do {
                        let computerItems = try await entryLoadingClient.loadComputerItems()
                        await send(.loading(.itemsLoaded(computerItems)))
                    } catch {
                        await send(.loading(.itemsLoaded([])))
                    }
                }

            case let .loading(.itemsLoaded(items)):
                state.loadingContext.items = IdentifiedArray(uniqueElements: items)
                state.isLoading = false
                state.isReloading = false

                if let renamingId = state.renamingItemId {
                    let itemIds = Set(items.map(\.id))
                    if !itemIds.contains(renamingId) {
                        return .send(.edit(.cancelRename))
                    }
                }
                return .none

            case let .loading(.collectionItemsLoadedFromSearch(paths, showHidden)):
                let converted = EntryCollectionItemsConverter.convert(
                    paths,
                    showHidden: showHidden,
                    entryLoadingClient: entryLoadingClient,
                    workspaceClient: workspaceClient,
                )
                state.loadingContext.collectionItems = IdentifiedArray(uniqueElements: converted)
                return .none

            case let .loading(.setCollectionMode(isCollectionMode)):
                state.loadingContext.isCollectionMode = isCollectionMode
                return .none

            case .loading(.clearCollectionItems):
                state.loadingContext.collectionItems = []
                return .none

            default:
                return .none
            }
        }
    }
}
