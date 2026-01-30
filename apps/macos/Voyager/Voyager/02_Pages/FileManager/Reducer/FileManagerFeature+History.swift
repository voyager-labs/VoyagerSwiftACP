import ComposableArchitecture
import Foundation

extension FileManagerFeature {
    func performBackNavigation(state: inout State) -> Effect<Action> {
        guard let entry = state.backHistory.popLast() else { return .none }
        let currentSnapshot = state.makeHistoryEntry()
        state.appendForwardHistory(currentSnapshot)
        applyHistoryEntry(
            state: &state,
            entry: entry,
            favorites: state.favorites,
            locations: state.locations,
        )
        Self.resetComposerAfterAlertNavigation(state: &state)
        let exitEffect = Self.clearCollectionMode(state: &state)
        return .concatenate(
            exitEffect,
            navigateToState(
                state.navigationState,
                showHidden: state.showHiddenFiles,
            ),
        )
    }

    func performForwardNavigation(state: inout State) -> Effect<Action> {
        guard let entry = state.forwardHistory.popLast() else { return .none }
        let currentSnapshot = state.makeHistoryEntry()
        state.appendBackHistory(currentSnapshot)
        applyHistoryEntry(
            state: &state,
            entry: entry,
            favorites: state.favorites,
            locations: state.locations,
        )
        Self.resetComposerAfterAlertNavigation(state: &state)
        let exitEffect = Self.clearCollectionMode(state: &state)
        return .concatenate(
            exitEffect,
            navigateToState(
                state.navigationState,
                showHidden: state.showHiddenFiles,
            ),
        )
    }

    func performHistoryNavigation(
        index: Int,
        isBackHistory: Bool,
        state: inout State,
    ) -> Effect<Action> {
        if isBackHistory {
            guard index < state.backHistory.count else { return .none }
            let targetIndex = state.backHistory.count - 1 - index
            let targetEntry = state.backHistory[targetIndex]
            let trailing = Array(state.backHistory[(targetIndex + 1)...])

            state.backHistory.removeLast(state.backHistory.count - targetIndex)

            let currentSnapshot = state.makeHistoryEntry()
            state.appendForwardHistory(currentSnapshot)
            state.forwardHistory.append(contentsOf: trailing.reversed())
            state.trimHistory()

            applyHistoryEntry(
                state: &state,
                entry: targetEntry,
                favorites: state.favorites,
                locations: state.locations,
            )
            Self.resetComposerAfterAlertNavigation(state: &state)
            let exitEffect = Self.clearCollectionMode(state: &state)
            return .concatenate(
                exitEffect,
                navigateToState(
                    state.navigationState,
                    showHidden: state.showHiddenFiles,
                ),
            )
        }

        guard index < state.forwardHistory.count else { return .none }
        let targetIndex = state.forwardHistory.count - 1 - index
        let targetEntry = state.forwardHistory[targetIndex]
        let trailing = Array(state.forwardHistory[(targetIndex + 1)...])

        state.forwardHistory.removeLast(state.forwardHistory.count - targetIndex)

        let currentSnapshot = state.makeHistoryEntry()
        state.appendBackHistory(currentSnapshot)
        state.backHistory.append(contentsOf: trailing.reversed())
        state.trimHistory()

        applyHistoryEntry(
            state: &state,
            entry: targetEntry,
            favorites: state.favorites,
            locations: state.locations,
        )
        Self.resetComposerAfterAlertNavigation(state: &state)
        let exitEffect = Self.clearCollectionMode(state: &state)
        return .concatenate(
            exitEffect,
            navigateToState(
                state.navigationState,
                showHidden: state.showHiddenFiles,
            ),
        )
    }

    static func resetComposerAfterAlertNavigation(state: inout State) {
        if state.resetComposerOnNextDirectoryNavigation,
           !state.navigationState.isCollection
        {
            state.resetComposer()
            state.resetComposerOnNextDirectoryNavigation = false
        }
    }

    func applyHistoryEntry(
        state: inout State,
        entry: HistoryEntry,
        favorites: [SidebarUtils.FavoriteItem],
        locations: [SidebarUtils.LocationItem],
    ) {
        let previousNavigationState = state.navigationState
        state.navigationState = entry.navigationState
        logDAUNavigationIfNeeded(previous: previousNavigationState, next: state.navigationState)
        switch entry.navigationState {
        case .collection:
            state.selectedSidebarItem = nil
        default:
            state.selectedSidebarItem = entry.sidebarItemName
            matchSidebarToPath(
                state: &state,
                path: state.currentPath,
                favorites: favorites,
                locations: locations,
            )
        }
        state.composer = entry.composerState
        state.composer.isPresented = false
    }
}
