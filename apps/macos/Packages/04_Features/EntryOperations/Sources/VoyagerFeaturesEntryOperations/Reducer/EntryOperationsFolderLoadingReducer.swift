import ComposableArchitecture
import Foundation
import VoyagerEntitiesEntry

@Reducer
public struct EntryOperationsFolderLoadingReducer {
    public typealias State = EntryOperationsState
    public typealias Action = EntryOperationsAction

    private struct CancelID: Hashable {
        let requestID: EntryFolderLoadRequest.RequestID
        let windowID: UUID?
    }

    @Dependency(\.entryLoadingClient)
    private var entryLoadingClient

    public init() {}

    public var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case let .loading(.loadFolderItems(request)):
                state.folderLoadingContexts[request.id] = .init(request: request)
                let cancelID = CancelID(requestID: request.id, windowID: state.windowID)
                return .run { [entryLoadingClient] send in
                    do {
                        let url = URL(fileURLWithPath: request.path)
                        for try await event in entryLoadingClient.loadItems(url, request.showHidden, request.priority) {
                            await send(.loading(.folderStreamEvent(request: request, event: event)))
                        }
                        try Task.checkCancellation()
                        await send(.loading(.folderStreamFinished(request: request)))
                    } catch is CancellationError {
                        return
                    } catch {
                        guard !Task.isCancelled else { return }
                        await send(.loading(.folderStreamFailed(request: request, failure: Self.failure(from: error))))
                    }
                }
                .cancellable(id: cancelID, cancelInFlight: true)

            case let .loading(.cancelFolderItems(requestID)):
                state.folderLoadingContexts[requestID] = nil
                return .cancel(id: CancelID(requestID: requestID, windowID: state.windowID))

            case let .loading(.folderStreamEvent(request, event)):
                guard var context = state.folderLoadingContexts[request.id],
                      context.request == request,
                      !context.terminal,
                      accepts(event, context: &context)
                else { return .none }
                state.folderLoadingContexts[request.id] = context
                return .send(.delegate(.folderLoadEvent(request: request, event: event)))

            case let .loading(.folderStreamFinished(request)):
                guard var context = state.folderLoadingContexts[request.id],
                      context.request == request,
                      context.coreFinished,
                      !context.terminal
                else { return .none }
                context.terminal = true
                state.folderLoadingContexts[request.id] = context
                return .send(.delegate(.folderLoadFinished(request: request)))

            case let .loading(.folderStreamFailed(request, failure)):
                guard var context = state.folderLoadingContexts[request.id],
                      context.request == request,
                      !context.terminal
                else { return .none }
                context.terminal = true
                state.folderLoadingContexts[request.id] = context
                return .send(.delegate(.folderLoadFailed(request: request, failure: failure)))

            default:
                return .none
            }
        }
    }

    private func accepts(_ event: EntryLoadEvent, context: inout EntryFolderLoadingContext) -> Bool {
        switch event {
        case let .coreBatch(_, batchIndex):
            guard !context.coreFinished, batchIndex == context.expectedCoreBatchIndex else { return false }
            context.expectedCoreBatchIndex += 1
        case let .coreFinished(batchCount):
            guard !context.coreFinished, batchCount == context.expectedCoreBatchIndex else { return false }
            context.coreFinished = true
        case .metadataPatches:
            guard context.coreFinished else { return false }
        }
        return true
    }

    private static func failure(from error: Error) -> EntryFolderLoadFailure {
        let nsError = error as NSError
        if nsError.code == NSFileReadNoPermissionError {
            return .permissionDenied
        }
        return .unavailable(description: nsError.localizedDescription)
    }
}
