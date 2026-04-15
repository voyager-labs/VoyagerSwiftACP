import ComposableArchitecture
import Foundation
import VoyagerShared

@Reducer
struct ComposerSaveReducer {
    typealias State = ComposerState
    typealias Action = ComposerAction

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .view(.saveCollection):
                let payload = makeSavePayload(from: state)
                if let url = state.openedCollectionURL {
                    return .send(.collection(.saveToExisting(payload, url)))
                }
                return .send(.collection(.saveRequested(payload)))

            case .view(.saveCollectionAs):
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
    let context = state.collectionContext
    let query = context?.query ?? ""
    let scopes = context?.scopes ?? []
    let conditions = context?.conditions ?? []
    return .init(
        context: context,
        isSearchLoading: state.isLoadingSearch,
        isFiltersLoading: state.isLoadingFilters,
        snapshotItems: CollectionSnapshotHydration.snapshotItems(from: state.lastFiltersResponse?.items),
        definitionFingerprint: CollectionSnapshotHydration.definitionFingerprint(
            query: query,
            scopes: scopes,
            conditions: conditions,
        ),
        capturedAt: Date(),
        relevanceRoots: scopes.map(standardizedPath).sorted(),
    )
}

private func standardizedPath(_ path: String) -> String {
    URL(fileURLWithPath: path).standardizedFileURL.path
}
