import ComposableArchitecture

@Reducer
struct FileManagerProductContentTabActionReducer {
    typealias State = FileManagerFeature.State
    typealias Action = FileManagerFeature.Action

    @Dependency(\.fileManagerProductMetricsClient)
    var productMetricsClient

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case let .closeContentTabRequested(tabID):
                guard state.canStartSelectedContentTabClose,
                      state.productContentTabCloseMetric == nil,
                      state.pendingTopNavigationIntents.contains(where: { $0.intent == .close(tabID) })
                else { return .none }
                state.productContentTabCloseMetric = ProductContentTabCloseMetric(
                    tabID: tabID,
                    context: ProductContentTabActionMetricContext(
                        operationID: productMetricsClient.makeOperationID(),
                        source: .contentTabBar,
                    ),
                )
                return .none

            case let .closeContentTabRequestedWithSource(tabID, source):
                guard state.canStartSelectedContentTabClose else { return .none }
                if state.contentTabs.tabs[id: tabID]?.isPinned == true,
                   !state.contentTabs.pendingPinnedRecordIDs.contains(tabID)
                {
                    state.productContentTabCloseMetric = ProductContentTabCloseMetric(
                        tabID: tabID,
                        context: ProductContentTabActionMetricContext(
                            operationID: productMetricsClient.makeOperationID(),
                            source: source,
                        ),
                    )
                }
                return FileManagerFeature().requestTopNavigationClose(tabID: tabID, state: &state)

            case let .contentTabActionRequested(contentTabAction, source):
                guard state.contentTabMoveParticipantRequestID == nil,
                      state.pendingSelectedContentTabClose == nil,
                      state.pendingSelectedContentTabPinMutation == nil
                else { return .none }
                return FileManagerFeature().reduceContentTabAction(
                    contentTabAction,
                    state: &state,
                    source: source,
                )

            default:
                return .none
            }
        }
    }
}
