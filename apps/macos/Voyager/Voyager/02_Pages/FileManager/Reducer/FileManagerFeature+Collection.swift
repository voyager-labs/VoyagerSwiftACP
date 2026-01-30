import ComposableArchitecture

extension FileManagerFeature {
    func exitCollectionMode(state: inout State) -> Effect<Action> {
        let wasCollection = if case .collection = state.navigationState { true } else { false }
        let clearEffect = Self.clearCollectionMode(state: &state)

        guard wasCollection else {
            return clearEffect
        }

        state.navigationState = FileManagerNavigationUtils.navigationStateFromPath(
            state.titlePath,
            computerName: sidebarClient.computerName(),
        )
        matchSidebarToPath(
            state: &state,
            path: state.currentPath,
            favorites: state.favorites,
            locations: state.locations,
        )
        return clearEffect
    }

    static func shouldPromptForUnsavedNavigation(state: State) -> Bool {
        state.entries.isCollectionMode && state.canSaveCollection
    }

    static func clearCollectionMode(state: inout State) -> Effect<Action> {
        state.collectionContext = nil
        state.pendingSearchQuery = nil
        state.isOpeningCollectionFile = false
        state.openedCollectionName = nil
        state.openedCollectionURL = nil
        state.openedCollectionBaseline = nil
        state.collectionOriginURL = nil
        state.pendingNavigation = nil
        state.entries.collectionItems = []
        return .merge(
            .cancel(id: CancelID.openCollectionFile),
            .cancel(id: ComposerFeature.CancelID.search),
            .cancel(id: ComposerFeature.CancelID.filters),
            .send(.entries(.setCollectionMode(false))),
        )
    }
}
