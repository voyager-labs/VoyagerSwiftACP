import ComposableArchitecture
import Foundation
import UniformTypeIdentifiers

import VoyagerEntitiesEntry

@Reducer
struct EntryOperationsLifecycleReducer {
    typealias State = EntryOperationsState
    typealias Action = EntryOperationsAction

    @Dependency(\.entryOpenClient)
    var entryOpenClient
    @Dependency(\.entryOperationsAlertClient)
    var alertClient
    @Dependency(\.entryThumbnailCacheClient)
    var entryThumbnailCacheClient

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case let .lifecycle(.syncSelectedEntryIDs(ids)):
                state.selectedEntryIDs = ids
                return .none

            case let .lifecycle(.clearError(filePath)):
                state.itemStates[filePath]?.lastError = nil
                return .none

            case let .lifecycle(.operationStarted(filePath, kind)):
                state.itemStates[filePath] = ItemOperationState(isBusy: true, lastError: nil)
                return .none

            case let .lifecycle(.operationFinished(filePath, kind, result)):
                state.itemStates[filePath]?.isBusy = false

                if case .rename = kind {
                    state.renamingItemId = nil
                    state.renamingText = ""
                }

                switch result {
                case .success:
                    state.itemStates[filePath]?.lastError = nil

                    if case .createFolder = kind {
                        state.renamingItemId = filePath
                        state.renamingText = URL(fileURLWithPath: filePath).lastPathComponent
                    }

                    if case .setDefaultApp = kind {
                        state.applicationsForItems[filePath] = nil
                        let url = URL(fileURLWithPath: filePath)
                        let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
                        let fileExtension = url.pathExtension
                        guard !isDirectory else { return .none }
                        let fileType = UTType(filenameExtension: fileExtension) ?? .data

                        return EntryOperationsExecutionSupport.loadApplications(
                            for: filePath,
                            url: url,
                            fileType: fileType,
                            entryOpenClient: entryOpenClient,
                        )
                    }

                case let .failure(error):
                    state.itemStates[filePath]?.lastError = error

                    if case .getInfo = kind {
                        return .run { [alertClient] _ in
                            await alertClient.showGetInfoFailureAlert(error.message, error.suggestion)
                        }
                    }
                }

                return .none

            case let .lifecycle(.pathsMutated(paths)):
                let uniquePaths = Array(Set(paths))
                guard !uniquePaths.isEmpty else { return .none }
                return .run { [entryThumbnailCacheClient] _ in
                    await MainActor.run {
                        entryThumbnailCacheClient.removeThumbnails(for: uniquePaths)
                    }
                }

            case .lifecycle(.entryActionCompleted):
                return .none

            default:
                return .none
            }
        }
    }
}
