import ComposableArchitecture
import Foundation

// TODO(voy-142): 타입명과 맞추기 위해 파일명을 EntryUndoReducer.swift로 변경 필요.
@Reducer
struct EntryUndoReducer {
    typealias State = EntryState
    typealias Action = EntryAction

    @Dependency(\.entryLoadingClient)
    var entryLoadingClient
    @Dependency(\.entryFileOpsClient)
    var entryFileOpsClient
    @Dependency(\.workspaceClient)
    var workspaceClient

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case let .operationFinished(filePath, kind, result):
                switch (kind, result) {
                case (.createFolder, .success):
                    let createdURL = URL(fileURLWithPath: filePath)
                    if let createdItem = EntryLoadUtils.convertURLToEntry(
                        createdURL,
                        entryLoadingClient: entryLoadingClient,
                        workspaceClient: workspaceClient,
                    ) {
                        if let creatingId = state.creatingNewFolderId,
                           let index = state.items.index(id: creatingId)
                        {
                            state.items.remove(id: creatingId)
                            state.items.insert(createdItem, at: index)
                        } else {
                            state.items.insert(createdItem, at: 0)
                        }
                        state.creatingNewFolderId = createdItem.id
                        state.selectedIds = [createdItem.id]
                        state.lastSelectedId = createdItem.id
                        state.rangeAnchorId = nil
                        state.renamingItemId = createdItem.id
                        state.renamingText = createdItem.name
                        state.shouldScrollToSelection = true
                        state.selectAfterLoadFileNames = [createdItem.name]
                    }

                    return .run { _ in
                        await entryFileOpsClient.postFileSystemChanged([filePath])
                    }

                case (.createFolder, .failure):
                    state.clearCreatingFolder()
                    return .none

                case (.pasteFile, .success):
                    if state.isDragDropOperation {
                        state.isDragDropOperation = false
                    }

                    return .merge(
                        .send(.reloadCurrentFolder),
                        .run { _ in
                            await entryFileOpsClient.postFileSystemChanged([filePath])
                        },
                    )

                case (.rename, .success):
                    return .run { _ in
                        await entryFileOpsClient.postFileSystemChanged([filePath])
                    }

                case (.moveToTrash, .success),
                     (.putBack, .success):
                    return .send(.reloadCurrentFolder)

                case (.deleteImmediately, .success):
                    return .send(.reloadCurrentFolder)

                case (.compress, .success),
                     (.extract, .success),
                     (.setTags, .success):
                    return .send(.reloadCurrentFolder)

                case (.pasteFile, .failure):
                    if state.isDragDropOperation {
                        state.isDragDropOperation = false
                        return .send(.reloadCurrentFolder)
                    }
                    return .none

                default:
                    return .none
                }

            default:
                return .none
            }
        }
    }
}
