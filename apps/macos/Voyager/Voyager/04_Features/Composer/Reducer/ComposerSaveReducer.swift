import ComposableArchitecture

@Reducer
struct ComposerSaveReducer {
    typealias State = ComposerState
    typealias Action = ComposerAction

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .saveCollection:
                let payload = makeSavePayload(from: state)
                if let url = state.openedCollectionURL {
                    return .send(.collection(.saveToExisting(payload, url)))
                }
                return .send(.collection(.saveRequested(payload)))

            case .saveCollectionAs:
                return .send(.collection(.saveRequested(makeSavePayload(from: state))))

            case .collection:
                return .none

            default:
                return .none
            }
        }
    }
}

private func makeSavePayload(from state: ComposerState) -> SaveRequestPayload {
    .init(
        context: state.collectionContext,
        isSearchLoading: state.isLoadingSearch,
        isFiltersLoading: state.isLoadingFilters,
    )
}
