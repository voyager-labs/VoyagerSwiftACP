import ComposableArchitecture

extension FileManagerWindowCommandRoutingReducer {
    func handlePresentContentTabSwitcher(
        source: FileManagerContentTabSwitcherPresentation.Source,
        state: inout State,
    ) -> Effect<Action> {
        guard canRouteRecentContentTabInteraction(state) else { return .none }
        state.contentTabSwitcherPresentation = .init(source: source)
        return .none
    }

    func canRouteRecentContentTabInteraction(_ state: State) -> Bool {
        guard !state.isClosing,
              state.pendingSelectedContentTabClose == nil,
              state.pendingContentTabClose == nil,
              state.pendingContentTabTeardown == nil,
              state.pendingSelectedContentTabPinMutation == nil,
              state.pendingContentTabMove == nil,
              state.contentTabMoveParticipantRequestID == nil,
              state.pendingTopNavigationIntents.isEmpty,
              state.contentTabs.pendingPinnedRecordIDs.isEmpty
        else { return false }
        if case .tearingDownTab = state.undoRedoPhase { return false }
        return true
    }
}
