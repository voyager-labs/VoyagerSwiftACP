import ComposableArchitecture

extension FileManagerWindowCommandRoutingReducer {
    func handlePresentContentTabSwitcher(
        source: FileManagerContentTabSwitcherPresentation.Source,
        state: inout State,
    ) -> Effect<Action> {
        guard canRouteRecentContentTabInteraction(state) else { return .none }
        state.contentTabSwitcherPresentation = .init(source: source, contentTabs: state.contentTabs)
        return .none
    }

    func handleMoveContentTabSwitcherFocus(
        direction: ContentTabSwitcherFocusDirection,
        state: inout State,
    ) -> Effect<Action> {
        guard canRouteRecentContentTabInteraction(state),
              let presentation = state.contentTabSwitcherPresentation,
              presentation.source.isInteractive,
              case let .candidates(candidates) = ContentTabSwitcherProjection.project(from: state.contentTabs),
              candidates.count > 1
        else { return .none }

        let liveIDs = candidates.map(\.id)
        if let focusedID = presentation.focusedCandidateID,
           !liveIDs.contains(focusedID),
           let oldIndex = presentation.candidateIDs.firstIndex(of: focusedID)
        {
            let neighborID: ContentTabID? = if direction == .next {
                presentation.candidateIDs.dropFirst(oldIndex + 1).first(where: liveIDs.contains)
            } else {
                presentation.candidateIDs[..<oldIndex].last(where: liveIDs.contains)
            }
            let wrappedID = neighborID ?? (direction == .next ? liveIDs.first : liveIDs.last)
            state.contentTabSwitcherPresentation = .init(
                source: presentation.source,
                candidateIDs: liveIDs,
                focusedCandidateID: wrappedID,
            )
            return .none
        }

        let currentIndex = presentation.focusedCandidateID
            .flatMap { liveIDs.firstIndex(of: $0) }
            ?? state.contentTabs.activeTabID.flatMap { liveIDs.firstIndex(of: $0) }
            ?? 0
        let offset = direction == .next ? 1 : -1
        let nextIndex = (currentIndex + offset + liveIDs.count) % liveIDs.count
        state.contentTabSwitcherPresentation = .init(
            source: presentation.source,
            candidateIDs: liveIDs,
            focusedCandidateID: liveIDs[nextIndex],
        )
        return .none
    }

    func handleContentTabSwitcherFocusChanged(
        _ id: ContentTabID,
        state: inout State,
    ) -> Effect<Action> {
        guard canRouteRecentContentTabInteraction(state),
              let presentation = state.contentTabSwitcherPresentation,
              presentation.source.isInteractive,
              case let .candidates(candidates) = ContentTabSwitcherProjection.project(from: state.contentTabs)
        else { return .none }

        let liveIDs = candidates.map(\.id)
        guard liveIDs.contains(id), presentation.focusedCandidateID != id else { return .none }
        state.contentTabSwitcherPresentation = .init(
            source: presentation.source,
            candidateIDs: liveIDs,
            focusedCandidateID: id,
        )
        return .none
    }

    func handleDismissContentTabSwitcher(state: inout State) -> Effect<Action> {
        state.contentTabSwitcherPresentation = nil
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
