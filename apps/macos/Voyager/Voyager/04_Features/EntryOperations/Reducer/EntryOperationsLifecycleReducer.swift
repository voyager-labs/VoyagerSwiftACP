import ComposableArchitecture
import Foundation
import UniformTypeIdentifiers

@Reducer
struct EntryOperationsLifecycleReducer {
    typealias State = EntryOperationsState
    typealias Action = EntryOperationsAction

    @Dependency(\.entryOpenClient)
    var entryOpenClient
    @Dependency(\.entryOperationsAlertClient)
    var alertClient

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
                switch result {
                case .success:
                    state.itemStates[filePath]?.lastError = nil

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

            case .lifecycle(.entryActionCompleted):
                return .none

            default:
                return .none
            }
        }
    }
}
