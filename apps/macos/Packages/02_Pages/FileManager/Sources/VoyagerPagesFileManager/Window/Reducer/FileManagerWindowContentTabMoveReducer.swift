import ComposableArchitecture
import Foundation

@Reducer
struct FileManagerWindowContentTabMoveReducer {
    typealias State = FileManagerWindowState
    typealias Action = FileManagerWindowAction

    @Dependency(\.fileManagerProductMetricsClient)
    var fileManagerProductMetricsClient

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case let .sidebar(.view(.moveContentTab(tabID, targetWindowID))):
                guard state.pendingSelectedContentTabPinMutation == nil else { return .none }
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
                guard state.pendingSelectedContentTabPinMutation == nil else { return .none }
                prepareMenuBatchRequest(
                    initiatingTabID: initiatingTabID,
                    orderedTabIDs: orderedTabIDs,
                    targetWindowID: targetWindowID,
                    state: &state,
                )
                return .none

            case let .sidebar(.view(.moveContentTabs(payload, targetWindowID, _, _))):
                guard state.pendingSelectedContentTabPinMutation == nil else { return .none }
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
                guard state.pendingSelectedContentTabPinMutation == nil else { return .none }
                return .send(.delegate(.receiveContentTabDrag(payload)))

            case let .sidebar(.delegate(.receiveContentTabExplicitDomainDrag(payload, targetDomain, placement))):
                // 외부 창 explicit domain 경계 drop 의도를 window manager로 동일하게 통과시킨다.
                // window manager가 source 창의 canonical moveContentTabs로 route한다.
                guard state.pendingSelectedContentTabPinMutation == nil else { return .none }
                return .send(.delegate(.receiveContentTabExplicitDomainDrag(
                    payload: payload,
                    targetDomain: targetDomain,
                    placement: placement,
                )))

            case let .contentTabMoveSucceeded(request):
                guard isMatchingInFlightRequest(request, state: state) else {
                    return .none
                }
                recordMoveTerminalMetric(result: .success, request: request, state: state)
                clearPendingRequest(request, state: &state)
                return .none

            case let .contentTabMoveRejected(request, category):
                guard isMatchingInFlightRequest(request, state: state) else {
                    return .none
                }
                recordMoveTerminalMetric(
                    result: Self.metricResult(for: category),
                    request: request,
                    state: state,
                )
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
        state.pendingContentTabMove = FileManagerWindowContentTabMovePending(
            request: request,
            metricSource: .dragAndDrop,
        )
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

    /// 매칭된 in-flight 터미널에 한해 이동 메트릭을 한 건 기록한다.
    /// prepared 거절과 stale/duplicate 터미널은 이벤트를 만들지 않는다.
    private func recordMoveTerminalMetric(
        result: ContentTabActionResult,
        request: ContentTabMoveRequest,
        state: State,
    ) {
        guard let metricSource = state.pendingContentTabMove?.metricSource else { return }
        fileManagerProductMetricsClient.record(FileManagerProductMetricsProducer.contentTabTerminal(
            operationID: request.operationID,
            action: .move,
            source: metricSource,
            result: result,
        ))
    }

    /// 실패 presentation category를 제품 메트릭 결과로 매핑한다. unavailable만 unavailable이고 나머지는 failure다.
    private static func metricResult(
        for category: ContentTabMoveFailurePresentation.Category,
    ) -> ContentTabActionResult {
        switch category {
        case .unavailable:
            .unavailable
        case .busy, .capacity, .generic:
            .failure
        }
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
