import ComposableArchitecture

/// 직접 탐색(direct navigation) route 전이의 공통 수행 경계.
/// View 요청의 즉시 수행(DirectReducer)과 unsaved alert를 통과한 지연 수행
/// (`performNavigation`의 pending direct case)이 같은 전이를 공유한다.
enum ContentPageNavigationDirectTransition {
    /// pending direct case를 실제 route 전이로 수행한다.
    static func perform(
        _ pending: ContentPageNavigationPending,
        state: inout ContentPageNavigationState,
    ) -> Effect<ContentPageNavigationAction> {
        switch pending {
        case let .navigateToPath(path):
            navigateToPath(path, state: &state)
        case .showRecents:
            show(.recents, state: &state)
        case .showComputer:
            show(.computer, state: &state)
        case let .showTag(tagName):
            show(.tags(tagName), state: &state)
        case let .showAiChat(sessionID):
            show(.aiChat(sessionID), state: &state)
        case let .showAiChatSessions(sessionID):
            show(.aiChatSessions(sessionID), state: &state)
        case .back, .forward, .history, .enclosingDirectory, .openCollectionFile:
            .none
        }
    }

    private static func navigateToPath(
        _ path: String,
        state: inout ContentPageNavigationState,
    ) -> Effect<ContentPageNavigationAction> {
        let currentSnapshot = state.makeContentPageNavigationHistorySnapshot()
        let previousNavigationState = state.navigationState
        let shouldRecordHistory = path != state.currentPath

        if shouldRecordHistory {
            state.appendBackHistory(currentSnapshot)
            state.forwardHistory = []
        }

        state.navigationState = .folder(path)

        return directNavigationEffect(
            previousNavigationState: previousNavigationState,
            nextNavigationState: state.navigationState,
            shouldResetComposer: shouldRecordHistory,
        )
    }

    private static func show(
        _ route: ContentPageNavigationRoute,
        state: inout ContentPageNavigationState,
    ) -> Effect<ContentPageNavigationAction> {
        if state.navigationState == route {
            return .none
        }

        let currentSnapshot = state.makeContentPageNavigationHistorySnapshot()
        let previousNavigationState = state.navigationState
        state.appendBackHistory(currentSnapshot)
        state.forwardHistory = []
        state.navigationState = route

        return directNavigationEffect(
            previousNavigationState: previousNavigationState,
            nextNavigationState: state.navigationState,
            shouldResetComposer: true,
        )
    }

    private static func directNavigationEffect(
        previousNavigationState: ContentPageNavigationRoute,
        nextNavigationState: ContentPageNavigationRoute,
        shouldResetComposer: Bool,
    ) -> Effect<ContentPageNavigationAction> {
        var effects: [Effect<ContentPageNavigationAction>] = []

        if shouldResetComposer {
            effects.append(.send(.delegate(.resetComposer)))
        }

        effects.append(
            .send(.delegate(.logDAUNavigation(previous: previousNavigationState, next: nextNavigationState))),
        )
        effects.append(.send(.delegate(.navigateToState(nextNavigationState))))

        return .concatenate(effects)
    }
}
