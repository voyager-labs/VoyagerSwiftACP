import ComposableArchitecture

@Reducer
struct FileManagerWindowContentTabMoveReducer {
    typealias State = FileManagerWindowState
    typealias Action = FileManagerWindowAction

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case let .sidebar(.delegate(.requestContentTabMove(request))):
                return .send(.delegate(.requestContentTabMove(request)))

            case let .sidebar(.delegate(.receiveContentTabDrag(payload))):
                return .send(.delegate(.receiveContentTabDrag(payload)))

            case let .contentTabMoveSucceeded(requestID):
                guard state.sidebar.pendingContentTabMoveRequest?.requestID == requestID else {
                    return .none
                }
                state.sidebar.pendingContentTabMoveRequest = nil
                return .none

            case let .contentTabMoveRejected(requestID, category):
                guard state.sidebar.pendingContentTabMoveRequest?.requestID == requestID else {
                    return .none
                }
                state.sidebar.pendingContentTabMoveRequest = nil
                state.contentTabMoveFailurePresentation = ContentTabMoveFailurePresentation(
                    requestID: requestID,
                    category: category,
                )
                return .none

            case let .view(.dismissContentTabMoveFailure(requestID)):
                guard state.contentTabMoveFailurePresentation?.requestID == requestID else {
                    return .none
                }
                state.contentTabMoveFailurePresentation = nil
                return .none

            default:
                return .none
            }
        }
    }
}
