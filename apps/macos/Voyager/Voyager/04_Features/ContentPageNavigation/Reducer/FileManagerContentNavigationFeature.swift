// TODO(ContentPageNavigation): 2차 네이밍 정리
// - 파일명 변경: FileManagerContentNavigationFeature.swift -> ContentPageNavigationFeature.swift
// - 타입명 변경:
//   - FileManagerContentNavigationFeature -> ContentPageNavigationFeature
// - 주의:
//   - 이 단계에서는 동작 변경 금지(로직 수정 금지). 네이밍만 정리한다.

import ComposableArchitecture
import Foundation
import SwiftUI

@Reducer
struct FileManagerContentNavigationFeature {
    typealias State = FileManagerContentNavigationState
    typealias Action = FileManagerContentNavigationAction

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
        _ pending: ContentPendingNavigation,
        currentSnapshot: ContentPageHistory,
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
        currentSnapshot: ContentPageHistory,
        state: inout State,
    ) -> Effect<Action> {
        guard let entry = state.backHistory.popLast() else { return .none }
        state.appendForwardHistory(currentSnapshot)
        let previousNavigationState = applyContentPageHistory(state: &state, entry: entry)
        return .merge(
            .send(.delegate(.applyContentPageHistory(entry))),
            .send(.delegate(.logDAUNavigation(previous: previousNavigationState, next: state.navigationState))),
            .send(.delegate(.navigateToState(state.navigationState))),
        )
    }

    private func performForwardNavigation(
        currentSnapshot: ContentPageHistory,
        state: inout State,
    ) -> Effect<Action> {
        guard let entry = state.forwardHistory.popLast() else { return .none }
        state.appendBackHistory(currentSnapshot)
        let previousNavigationState = applyContentPageHistory(state: &state, entry: entry)
        return .merge(
            .send(.delegate(.applyContentPageHistory(entry))),
            .send(.delegate(.logDAUNavigation(previous: previousNavigationState, next: state.navigationState))),
            .send(.delegate(.navigateToState(state.navigationState))),
        )
    }

    private func performHistoryNavigation(
        index: Int,
        isBackHistory: Bool,
        currentSnapshot: ContentPageHistory,
        state: inout State,
    ) -> Effect<Action> {
        if isBackHistory {
            let backCount = state.backHistory.count
            guard index >= 0, index < backCount else { return .none }
            let offset = backCount - index - 1
            var entry = state.backHistory.removeLast()
            var newForwardHistory: [ContentPageHistory] = []
            for _ in 0 ..< offset {
                newForwardHistory.append(entry)
                entry = state.backHistory.removeLast()
            }
            state.appendForwardHistory(currentSnapshot)
            newForwardHistory.reversed().forEach { state.appendForwardHistory($0) }
            let previousNavigationState = applyContentPageHistory(state: &state, entry: entry)
            return .merge(
                .send(.delegate(.applyContentPageHistory(entry))),
                .send(.delegate(.logDAUNavigation(previous: previousNavigationState, next: state.navigationState))),
                .send(.delegate(.navigateToState(state.navigationState))),
            )
        }

        let forwardCount = state.forwardHistory.count
        guard index >= 0, index < forwardCount else { return .none }
        let offset = forwardCount - index - 1
        var entry = state.forwardHistory.removeLast()
        var newBackHistory: [ContentPageHistory] = []
        for _ in 0 ..< offset {
            newBackHistory.append(entry)
            entry = state.forwardHistory.removeLast()
        }
        state.appendBackHistory(currentSnapshot)
        newBackHistory.reversed().forEach { state.appendBackHistory($0) }
        let previousNavigationState = applyContentPageHistory(state: &state, entry: entry)
        return .merge(
            .send(.delegate(.applyContentPageHistory(entry))),
            .send(.delegate(.logDAUNavigation(previous: previousNavigationState, next: state.navigationState))),
            .send(.delegate(.navigateToState(state.navigationState))),
        )
    }

    private func performEnclosingDirectoryNavigation(
        currentSnapshot: ContentPageHistory,
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

    private func applyContentPageHistory(
        state: inout State,
        entry: ContentPageHistory,
    ) -> FileManagerNavigationUtils.NavigationState {
        let previousNavigationState = state.navigationState
        state.navigationState = entry.navigationState
        return previousNavigationState
    }
}
