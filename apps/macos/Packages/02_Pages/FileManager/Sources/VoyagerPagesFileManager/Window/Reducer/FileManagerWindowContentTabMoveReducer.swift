import ComposableArchitecture
import Foundation

@Reducer
struct FileManagerWindowContentTabMoveReducer {
    typealias State = FileManagerWindowState
    typealias Action = FileManagerWindowAction

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case let .sidebar(.view(.moveContentTab(tabID, targetWindowID))):
                prepareSingletonRequest(
                    tabID: tabID,
                    targetWindowID: targetWindowID,
                    state: &state,
                )
                return .none

            case let .sidebar(.view(.moveSelectedContentTabs(
                initiatingTabID,
                orderedTabIDs,
                targetWindowID,
            ))):
                prepareMenuBatchRequest(
                    initiatingTabID: initiatingTabID,
                    orderedTabIDs: orderedTabIDs,
                    targetWindowID: targetWindowID,
                    state: &state,
                )
                return .none

            case let .sidebar(.view(.moveContentTabs(payload, targetWindowID))):
                prepareBatchRequest(
                    payload: payload,
                    targetWindowID: targetWindowID,
                    state: &state,
                )
                return .none

            case let .sidebar(.delegate(.requestContentTabMove(request))):
                guard var pending = state.pendingContentTabMove,
                      pending.lifecycle == .prepared,
                      pending.request == request,
                      requestHasValidIdentity(request, state: state)
                else { return .none }
                guard !state.isContentTabMoveBusy else {
                    rejectPreparedRequest(request, state: &state)
                    return .none
                }

                pending.lifecycle = .inFlight
                state.pendingContentTabMove = pending
                return .send(.delegate(.requestContentTabMove(request)))

            case let .sidebar(.delegate(.receiveContentTabDrag(payload))):
                return .send(.delegate(.receiveContentTabDrag(payload)))

            case let .contentTabMoveSucceeded(request):
                guard isMatchingInFlightRequest(request, state: state) else {
                    return .none
                }
                clearPendingRequest(request, state: &state)
                return .none

            case let .contentTabMoveRejected(request, category):
                guard isMatchingInFlightRequest(request, state: state) else {
                    return .none
                }
                clearPendingRequest(request, state: &state)
                state.contentTabMoveFailurePresentation = ContentTabMoveFailurePresentation(
                    requestID: request.requestID,
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

    private func prepareSingletonRequest(
        tabID: ContentTabID,
        targetWindowID: UUID,
        state: inout State,
    ) {
        guard state.pendingContentTabMove == nil,
              let request = state.sidebar.pendingContentTabMoveRequest,
              request.initiatingTabID == tabID,
              request.orderedTabIDs == [tabID],
              request.targetWindowID == targetWindowID
        else { return }
        state.pendingContentTabMove = FileManagerWindowContentTabMovePending(request: request)
    }

    private func prepareMenuBatchRequest(
        initiatingTabID: ContentTabID,
        orderedTabIDs: [ContentTabID],
        targetWindowID: UUID,
        state: inout State,
    ) {
        let sourceTabIDs = Set(state.sidebar.contentTabSidebarItems.map(\.id))
        let normalizedOrderedTabIDs = orderedTabIDs.filter(sourceTabIDs.contains)
        guard state.pendingContentTabMove == nil,
              !orderedTabIDs.isEmpty,
              Set(orderedTabIDs).count == orderedTabIDs.count,
              orderedTabIDs.contains(initiatingTabID),
              sourceTabIDs.contains(initiatingTabID),
              let request = state.sidebar.pendingContentTabMoveRequest,
              request.operationID == request.requestID,
              request.initiatingTabID == initiatingTabID,
              request.orderedTabIDs == normalizedOrderedTabIDs,
              request.targetWindowID == targetWindowID
        else { return }
        state.pendingContentTabMove = FileManagerWindowContentTabMovePending(request: request)
    }

    private func prepareBatchRequest(
        payload: ContentTabDragPayload,
        targetWindowID: UUID,
        state: inout State,
    ) {
        guard state.pendingContentTabMove == nil,
              let request = state.sidebar.pendingContentTabMoveRequest,
              request.operationID == (payload.operationID ?? request.requestID),
              request.sourceWindowID == payload.sourceWindowID,
              request.initiatingTabID == payload.initiatingTabID,
              request.orderedTabIDs == payload.orderedTabIDs,
              request.targetWindowID == targetWindowID
        else { return }
        state.pendingContentTabMove = FileManagerWindowContentTabMovePending(request: request)
    }

    private func requestHasValidIdentity(_ request: ContentTabMoveRequest, state: State) -> Bool {
        guard request.sourceWindowID != request.targetWindowID,
              !request.orderedTabIDs.isEmpty,
              Set(request.orderedTabIDs).count == request.orderedTabIDs.count,
              request.orderedTabIDs.contains(request.initiatingTabID)
        else { return false }
        if let windowID = state.windowID, windowID != request.sourceWindowID {
            return false
        }
        if let sidebarWindowID = state.sidebar.currentWindowID,
           sidebarWindowID != request.sourceWindowID
        {
            return false
        }
        return state.windowID != nil || state.sidebar.currentWindowID != nil
    }

    private func isMatchingInFlightRequest(_ request: ContentTabMoveRequest, state: State) -> Bool {
        state.pendingContentTabMove?.lifecycle == .inFlight
            && state.pendingContentTabMove?.request == request
    }

    private func rejectPreparedRequest(_ request: ContentTabMoveRequest, state: inout State) {
        clearPendingRequest(request, state: &state)
        state.contentTabMoveFailurePresentation = ContentTabMoveFailurePresentation(
            requestID: request.requestID,
            category: .busy,
        )
    }

    private func clearPendingRequest(_ request: ContentTabMoveRequest, state: inout State) {
        state.pendingContentTabMove = nil
        if state.sidebar.pendingContentTabMoveRequest == request {
            state.sidebar.pendingContentTabMoveRequest = nil
        }
    }
}
