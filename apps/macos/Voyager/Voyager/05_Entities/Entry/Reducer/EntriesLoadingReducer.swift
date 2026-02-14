import AppKit
import ComposableArchitecture
import Foundation
import IdentifiedCollections
import OSLog

// TODO(voy-142): 타입명과 맞추기 위해 파일명을 EntryLoadingReducer.swift로 변경 필요.
@Reducer
struct EntryLoadingReducer {
    typealias State = EntryState
    typealias Action = EntryAction

    @Dependency(\.entryLoadingClient)
    var entryLoadingClient
    @Dependency(\.entryWatchingClient)
    var entryWatchingClient
    @Dependency(\.workspaceClient)
    var workspaceClient

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .onAppear:
                return .run { send in
                    for await _ in await entryWatchingClient.observeFileSystemChanged() {
                        await send(.reloadCurrentFolder)
                    }
                }
                .cancellable(id: EntryCancelID.fileSystemObserver, cancelInFlight: true)

            case .reloadCurrentFolder:
                if state.isVirtualFolder {
                    if state.currentFolderPath == EntryReducerSupport.computerName(
                        entryLoadingClient: entryLoadingClient,
                    ) {
                        return .send(.loadComputerItems)
                    } else if let tagName = state.currentFolderPath {
                        return .send(.loadTagItems(tagName: tagName, showHidden: state.showHiddenFiles))
                    } else {
                        return .send(.loadRecentItems(showHidden: state.showHiddenFiles))
                    }
                } else {
                    return .send(.reloadItems)
                }

            case let .loadItems(path):
                if state.selectAfterLoadFileNames.isEmpty {
                    state.clearSelection()
                }
                state.currentFolderPath = path
                state.isVirtualFolder = false

                let showHidden = state.showHiddenFiles
                EntryReducerSupport.entryLoadLogger.info(
                    "loadItems path=\(path, privacy: .public) showHidden=\(showHidden)",
                )

                return .merge(
                    .cancel(id: EntryCancelID.fsEventsWatcher),
                    .run { [showHidden = state.showHiddenFiles, path, entryLoadingClient] send in
                        let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
                        do {
                            let items = try await entryLoadingClient.loadItems(url, showHidden)
                            await send(.itemsLoaded(items))
                        } catch {
                            await send(.itemsLoaded([]))
                        }
                    },
                    .run { [path, entryWatchingClient] send in
                        let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
                        let stream = entryWatchingClient.startWatchingDirectory(url)

                        for await changedPaths in stream {
                            await send(.fileSystemChanged(changedPaths))
                        }
                    }
                    .cancellable(id: EntryCancelID.fsEventsWatcher, cancelInFlight: true),
                )

            case .reloadItems:
                guard let path = state.currentFolderPath else { return .none }
                state.isReloading = true

                return .run { [showHidden = state.showHiddenFiles, path] send in
                    let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
                    do {
                        let items = try await entryLoadingClient.loadItems(url, showHidden)
                        await send(.itemsLoaded(items))
                    } catch {
                        await send(.itemsLoaded([]))
                    }
                }

            case let .loadRecentItems(showHidden):
                state.currentFolderPath = nil
                state.isVirtualFolder = true

                return .run { [entryLoadingClient, workspaceClient] send in
                    let recentItems = await entryLoadingClient.loadRecentItems(showHidden, workspaceClient)
                    await send(.itemsLoaded(recentItems))
                }

            case let .loadTagItems(tagName, showHidden):
                state.currentFolderPath = tagName
                state.isVirtualFolder = true

                return .run { [entryLoadingClient, workspaceClient] send in
                    try await Task.sleep(for: .milliseconds(500))
                    let taggedItems = await entryLoadingClient.loadFilesWithTag(tagName, showHidden, workspaceClient)
                    await send(.itemsLoaded(taggedItems))
                }

            case .loadComputerItems:
                state.currentFolderPath = EntryReducerSupport.computerName(entryLoadingClient: entryLoadingClient)
                state.isVirtualFolder = true

                return .run { [entryLoadingClient] send in
                    let computerItems = try await entryLoadingClient.loadComputerItems()
                    await send(.itemsLoaded(computerItems))
                }

            case .fileSystemChanged:
                return .send(.reloadCurrentFolder)

            case .toggleShowHiddenFiles:
                state.showHiddenFiles.toggle()
                return .send(.reloadCurrentFolder)

            case let .applyShowHiddenFiles(show):
                guard state.showHiddenFiles != show else { return .none }
                state.showHiddenFiles = show
                return .send(.reloadCurrentFolder)

            case let .setShowHidden(show):
                state.showHiddenFiles = show
                return .none

            case let .setCollectionMode(isCollectionMode):
                guard state.isCollectionMode != isCollectionMode else { return .none }
                state.isCollectionMode = isCollectionMode
                state.clearSelection()
                return .none

            case let .setDropTargeted(isTargeted):
                let draggedPaths = entryLoadingClient.loadDragPaths()

                if !draggedPaths.isEmpty, let currentFolder = state.currentFolderPath {
                    let sourceParent = URL(fileURLWithPath: draggedPaths[0]).deletingLastPathComponent().path
                    state.isDropTargeted = (sourceParent != currentFolder) && isTargeted
                } else {
                    state.isDropTargeted = isTargeted
                }
                return .none

            case let .itemsLoaded(items):
                let uniqueItems = EntryReducerSupport.deduplicateById(items)
                state.items = IdentifiedArray(uniqueElements: uniqueItems)

                guard !state.isCollectionMode else {
                    state.isReloading = false
                    return .none
                }

                if !state.selectAfterLoadFileNames.isEmpty {
                    let fileNamesToSelect = state.selectAfterLoadFileNames
                    state.selectAfterLoadFileNames = []

                    let itemsToSelect = state.items.filter { fileNamesToSelect.contains($0.name) }
                    if !itemsToSelect.isEmpty {
                        state.selectedIds = Set(itemsToSelect.map(\.id))
                        state.lastSelectedId = itemsToSelect.first?.id
                        state.rangeAnchorId = nil
                        state.shouldScrollToSelection = true
                    }
                } else if state.isReloading {
                    let validIds = Set(state.items.map(\.id))
                    state.selectedIds = state.selectedIds.intersection(validIds)
                    state.isReloading = false
                } else {
                    state.clearSelection()
                }
                return .none

            case let .collectionItemsLoadedFromSearch(items):
                let converted = EntrySearchUtils.convertCollectionItems(items, showHidden: state.showHiddenFiles)
                let uniqueItems = EntryReducerSupport.deduplicateById(converted)
                state.collectionItems = IdentifiedArray(uniqueElements: uniqueItems)

                guard state.isCollectionMode else {
                    return .none
                }

                state.clearSelection()
                return .none

            case let .setSelectAfterLoad(fileNames):
                state.selectAfterLoadFileNames = fileNames
                return .none

            default:
                return .none
            }
        }
    }
}
