import ComposableArchitecture
import Foundation

@Reducer
struct ContentPageNavigationHistoryReducer {
    typealias State = ContentPageNavigationState
    typealias Action = ContentPageNavigationAction

    init() {}

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case let .internal(.performNavigation(pending)):
                performNavigation(pending, state: &state)

            default:
                .none
            }
        }
    }

    private func performNavigation(
        _ pending: ContentPageNavigationPending,
        state: inout State,
    ) -> Effect<Action> {
        switch pending {
        case .back:
            performBackNavigation(state: &state)
        case .forward:
            performForwardNavigation(state: &state)
        case let .history(index, isBackHistory):
            performHistoryNavigation(
                index: index,
                isBackHistory: isBackHistory,
                state: &state,
            )
        case .enclosingDirectory:
            performEnclosingDirectoryNavigation(state: &state)
        case .navigateToPath, .showRecents, .showComputer, .showTag, .showAiChat, .showAiChatSessions:
            ContentPageNavigationDirectTransition.perform(pending, state: &state)
        case .openCollectionFile:
            // Collection file loading belongs to the FileManager window boundary.
            .none
        }
    }

    private func performBackNavigation(
        state: inout State,
    ) -> Effect<Action> {
        let currentSnapshot = state.makeContentPageNavigationHistorySnapshot()
        guard let entry = state.backHistory.popLast() else { return .none }
        state.appendForwardHistory(currentSnapshot)
        let previousNavigationState = applyContentPageNavigationHistorySnapshot(state: &state, entry: entry)
        return historyNavigationEffects(
            previousNavigationState: previousNavigationState,
            nextNavigationState: state.navigationState,
            identity: .back,
            shouldRevealEntry: true,
        )
    }

    private func performForwardNavigation(
        state: inout State,
    ) -> Effect<Action> {
        let currentSnapshot = state.makeContentPageNavigationHistorySnapshot()
        guard let entry = state.forwardHistory.popLast() else { return .none }
        state.appendBackHistory(currentSnapshot)
        let previousNavigationState = applyContentPageNavigationHistorySnapshot(state: &state, entry: entry)
        return historyNavigationEffects(
            previousNavigationState: previousNavigationState,
            nextNavigationState: state.navigationState,
            identity: .forward,
            shouldRevealEntry: false,
        )
    }

    private func performHistoryNavigation(
        index: Int,
        isBackHistory: Bool,
        state: inout State,
    ) -> Effect<Action> {
        let currentSnapshot = state.makeContentPageNavigationHistorySnapshot()
        if isBackHistory {
            let backCount = state.backHistory.count
            guard index >= 0, index < backCount else { return .none }
            let offset = backCount - index - 1
            var entry = state.backHistory.removeLast()
            var newForwardHistory: [ContentPageNavigationHistorySnapshot] = []
            for _ in 0 ..< offset {
                newForwardHistory.append(entry)
                entry = state.backHistory.removeLast()
            }
            state.appendForwardHistory(currentSnapshot)
            newForwardHistory.reversed().forEach { state.appendForwardHistory($0) }
            let previousNavigationState = applyContentPageNavigationHistorySnapshot(state: &state, entry: entry)
            return historyNavigationEffects(
                previousNavigationState: previousNavigationState,
                nextNavigationState: state.navigationState,
                identity: .back,
                shouldRevealEntry: false,
            )
        }

        let forwardCount = state.forwardHistory.count
        guard index >= 0, index < forwardCount else { return .none }
        let offset = forwardCount - index - 1
        var entry = state.forwardHistory.removeLast()
        var newBackHistory: [ContentPageNavigationHistorySnapshot] = []
        for _ in 0 ..< offset {
            newBackHistory.append(entry)
            entry = state.forwardHistory.removeLast()
        }
        state.appendBackHistory(currentSnapshot)
        newBackHistory.reversed().forEach { state.appendBackHistory($0) }
        let previousNavigationState = applyContentPageNavigationHistorySnapshot(state: &state, entry: entry)
        return historyNavigationEffects(
            previousNavigationState: previousNavigationState,
            nextNavigationState: state.navigationState,
            identity: .forward,
            shouldRevealEntry: false,
        )
    }

    private func performEnclosingDirectoryNavigation(
        state: inout State,
    ) -> Effect<Action> {
        let currentSnapshot = state.makeContentPageNavigationHistorySnapshot()
        guard let path = state.enclosingDirectoryPath else { return .none }
        state.appendBackHistory(currentSnapshot)
        state.forwardHistory = []
        let previousNavigationState = state.navigationState
        state.navigationState = .folder(path)
        return historyNavigationEffects(
            previousNavigationState: previousNavigationState,
            nextNavigationState: state.navigationState,
            identity: .enclosingDirectory,
            shouldRevealEntry: true,
        )
    }

    private func historyNavigationEffects(
        previousNavigationState: ContentPageNavigationRoute,
        nextNavigationState: ContentPageNavigationRoute,
        identity: ContentPageNavigationInteractionIdentity,
        shouldRevealEntry: Bool,
    ) -> Effect<Action> {
        var effects: [Effect<Action>] = []

        let shouldResetComposer = !nextNavigationState.isCollection
        if shouldResetComposer {
            effects.append(.send(.delegate(.resetComposer)))
        }

        effects.append(
            .send(.delegate(.logDAUNavigation(
                previous: previousNavigationState,
                next: nextNavigationState,
                identity: identity,
            ))),
        )
        if shouldRevealEntry,
           let revealEffect = revealEffect(
               previousNavigationState: previousNavigationState,
               nextNavigationState: nextNavigationState,
           )
        {
            effects.append(revealEffect)
        }
        effects.append(.send(.delegate(.navigateToState(nextNavigationState))))

        return .concatenate(effects)
    }

    private func revealEffect(
        previousNavigationState: ContentPageNavigationRoute,
        nextNavigationState: ContentPageNavigationRoute,
    ) -> Effect<Action>? {
        guard
            case let .folder(previousPath) = previousNavigationState,
            case let .folder(nextPath) = nextNavigationState
        else { return nil }

        let previousURL = URL(fileURLWithPath: previousPath).standardizedFileURL
        let nextURL = URL(fileURLWithPath: nextPath).standardizedFileURL
        guard
            previousURL.path != nextURL.path,
            nextURL.path == previousURL.deletingLastPathComponent().path
        else { return nil }

        return .send(
            .delegate(
                .revealEntryAfterNavigation(
                    destinationPath: nextPath,
                    entryPath: previousPath,
                ),
            ),
        )
    }

    private func applyContentPageNavigationHistorySnapshot(
        state: inout State,
        entry: ContentPageNavigationHistorySnapshot,
    ) -> ContentPageNavigationRoute {
        let previousNavigationState = state.navigationState
        state.navigationState = entry.navigationState
        return previousNavigationState
    }
}
