import ComposableArchitecture
import Foundation
import SwiftUI

@Reducer
struct ContentPageNavigationFeature {
    typealias State = ContentPageNavigationState
    typealias Action = ContentPageNavigationAction

    var body: some Reducer<State, Action> {
        ContentPageNavigationDirectReducer()
        ContentPageNavigationHistoryReducer()
        ContentPageNavigationStateReducer()
    }
}

@Reducer
private struct ContentPageNavigationDirectReducer {
    typealias State = ContentPageNavigationState
    typealias Action = ContentPageNavigationAction

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case let .performNavigateToPath(path, currentSnapshot):
                performNavigateToPath(path, currentSnapshot: currentSnapshot, state: &state)

            case let .performShowRecents(currentSnapshot):
                performShowRecents(currentSnapshot: currentSnapshot, state: &state)

            case let .performShowComputer(currentSnapshot):
                performShowComputer(currentSnapshot: currentSnapshot, state: &state)

            case let .performShowTag(tagName, currentSnapshot):
                performShowTag(tagName, currentSnapshot: currentSnapshot, state: &state)

            case let .prepareCollectionFileOpen(url, currentSnapshot):
                performPrepareCollectionFileOpen(url, currentSnapshot: currentSnapshot, state: &state)

            default:
                .none
            }
        }
    }

    private func performNavigateToPath(
        _ path: String,
        currentSnapshot: ContentPageNavigationHistorySnapshot,
        state: inout State,
    ) -> Effect<Action> {
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

    private func performShowRecents(
        currentSnapshot: ContentPageNavigationHistorySnapshot,
        state: inout State,
    ) -> Effect<Action> {
        if case .recents = state.navigationState {
            return .none
        }

        let previousNavigationState = state.navigationState
        state.appendBackHistory(currentSnapshot)
        state.forwardHistory = []
        state.navigationState = .recents

        return directNavigationEffect(
            previousNavigationState: previousNavigationState,
            nextNavigationState: state.navigationState,
            shouldResetComposer: true,
        )
    }

    private func performShowComputer(
        currentSnapshot: ContentPageNavigationHistorySnapshot,
        state: inout State,
    ) -> Effect<Action> {
        if case .computer = state.navigationState {
            return .none
        }

        let previousNavigationState = state.navigationState
        state.appendBackHistory(currentSnapshot)
        state.forwardHistory = []
        state.navigationState = .computer

        return directNavigationEffect(
            previousNavigationState: previousNavigationState,
            nextNavigationState: state.navigationState,
            shouldResetComposer: true,
        )
    }

    private func performShowTag(
        _ tagName: String,
        currentSnapshot: ContentPageNavigationHistorySnapshot,
        state: inout State,
    ) -> Effect<Action> {
        if case let .tags(currentTagName) = state.navigationState,
           currentTagName == tagName
        {
            return .none
        }

        let previousNavigationState = state.navigationState
        state.appendBackHistory(currentSnapshot)
        state.forwardHistory = []
        state.navigationState = .tags(tagName)

        return directNavigationEffect(
            previousNavigationState: previousNavigationState,
            nextNavigationState: state.navigationState,
            shouldResetComposer: true,
        )
    }

    private func performPrepareCollectionFileOpen(
        _ url: URL,
        currentSnapshot: ContentPageNavigationHistorySnapshot,
        state: inout State,
    ) -> Effect<Action> {
        if case .collection = state.navigationState {
            return .none
        }

        let directoryPath = url.deletingLastPathComponent().path
        let previousSnapshot = ContentPageNavigationHistorySnapshot(
            navigationState: .folder(directoryPath),
            composerSnapshot: currentSnapshot.composerSnapshot,
        )
        state.appendBackHistory(previousSnapshot)
        state.forwardHistory = []
        return .none
    }

    private func directNavigationEffect(
        previousNavigationState: ContentPageNavigationRoute,
        nextNavigationState: ContentPageNavigationRoute,
        shouldResetComposer: Bool,
    ) -> Effect<Action> {
        var effects: [Effect<Action>] = []

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

@Reducer
private struct ContentPageNavigationHistoryReducer {
    typealias State = ContentPageNavigationState
    typealias Action = ContentPageNavigationAction

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case let .performNavigation(pending, currentSnapshot):
                performNavigation(pending, currentSnapshot: currentSnapshot, state: &state)

            default:
                .none
            }
        }
    }

    private func performNavigation(
        _ pending: ContentPageNavigationPending,
        currentSnapshot: ContentPageNavigationHistorySnapshot,
        state: inout State,
    ) -> Effect<Action> {
        switch pending {
        case .back:
            performBackNavigation(currentSnapshot: currentSnapshot, state: &state)
        case .forward:
            performForwardNavigation(currentSnapshot: currentSnapshot, state: &state)
        case let .history(index, isBackHistory):
            performHistoryNavigation(
                index: index,
                isBackHistory: isBackHistory,
                currentSnapshot: currentSnapshot,
                state: &state,
            )
        case .enclosingDirectory:
            performEnclosingDirectoryNavigation(currentSnapshot: currentSnapshot, state: &state)
        }
    }

    private func performBackNavigation(
        currentSnapshot: ContentPageNavigationHistorySnapshot,
        state: inout State,
    ) -> Effect<Action> {
        guard let entry = state.backHistory.popLast() else { return .none }
        state.appendForwardHistory(currentSnapshot)
        let previousNavigationState = applyContentPageNavigationHistorySnapshot(state: &state, entry: entry)
        return .merge(
            .send(.delegate(.applyContentPageNavigationHistorySnapshot(entry))),
            .send(.delegate(.logDAUNavigation(previous: previousNavigationState, next: state.navigationState))),
            .send(.delegate(.navigateToState(state.navigationState))),
        )
    }

    private func performForwardNavigation(
        currentSnapshot: ContentPageNavigationHistorySnapshot,
        state: inout State,
    ) -> Effect<Action> {
        guard let entry = state.forwardHistory.popLast() else { return .none }
        state.appendBackHistory(currentSnapshot)
        let previousNavigationState = applyContentPageNavigationHistorySnapshot(state: &state, entry: entry)
        return .merge(
            .send(.delegate(.applyContentPageNavigationHistorySnapshot(entry))),
            .send(.delegate(.logDAUNavigation(previous: previousNavigationState, next: state.navigationState))),
            .send(.delegate(.navigateToState(state.navigationState))),
        )
    }

    private func performHistoryNavigation(
        index: Int,
        isBackHistory: Bool,
        currentSnapshot: ContentPageNavigationHistorySnapshot,
        state: inout State,
    ) -> Effect<Action> {
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
            return .merge(
                .send(.delegate(.applyContentPageNavigationHistorySnapshot(entry))),
                .send(.delegate(.logDAUNavigation(previous: previousNavigationState, next: state.navigationState))),
                .send(.delegate(.navigateToState(state.navigationState))),
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
        return .merge(
            .send(.delegate(.applyContentPageNavigationHistorySnapshot(entry))),
            .send(.delegate(.logDAUNavigation(previous: previousNavigationState, next: state.navigationState))),
            .send(.delegate(.navigateToState(state.navigationState))),
        )
    }

    private func performEnclosingDirectoryNavigation(
        currentSnapshot: ContentPageNavigationHistorySnapshot,
        state: inout State,
    ) -> Effect<Action> {
        guard let path = state.enclosingDirectoryPath else { return .none }
        state.appendBackHistory(currentSnapshot)
        state.forwardHistory = []
        let previousNavigationState = state.navigationState
        state.navigationState = .folder(path)
        return .merge(
            .send(.delegate(.resetComposer)),
            .send(.delegate(.logDAUNavigation(previous: previousNavigationState, next: state.navigationState))),
            .send(.delegate(.navigateToState(state.navigationState))),
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

@Reducer
private struct ContentPageNavigationStateReducer {
    typealias State = ContentPageNavigationState
    typealias Action = ContentPageNavigationAction

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .rollbackBackHistoryOnce:
                rollbackBackHistoryOnce(state: &state)

            case let .appendBackHistory(entry):
                appendBackHistory(entry, state: &state)

            case .clearForwardHistory:
                clearForwardHistory(state: &state)

            case let .setNavigationState(navigationState):
                setNavigationState(navigationState, state: &state)

            case let .setPendingNavigation(pending):
                setPendingNavigation(pending, state: &state)

            default:
                .none
            }
        }
    }

    private func rollbackBackHistoryOnce(
        state: inout State,
    ) -> Effect<Action> {
        if !state.backHistory.isEmpty {
            state.backHistory.removeLast()
        }
        return .none
    }

    private func appendBackHistory(
        _ entry: ContentPageNavigationHistorySnapshot,
        state: inout State,
    ) -> Effect<Action> {
        state.appendBackHistory(entry)
        return .none
    }

    private func clearForwardHistory(
        state: inout State,
    ) -> Effect<Action> {
        state.forwardHistory = []
        return .none
    }

    private func setNavigationState(
        _ navigationState: ContentPageNavigationRoute,
        state: inout State,
    ) -> Effect<Action> {
        state.navigationState = navigationState
        return .none
    }

    private func setPendingNavigation(
        _ pending: ContentPageNavigationPending?,
        state: inout State,
    ) -> Effect<Action> {
        state.pendingNavigation = pending
        return .none
    }
}
