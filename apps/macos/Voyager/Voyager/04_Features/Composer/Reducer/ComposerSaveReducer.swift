import ComposableArchitecture
import Foundation
import VoyagerShared

@Reducer
struct ComposerSaveReducer {
    typealias State = ComposerState
    typealias Action = ComposerAction

    @Dependency(\.date)
    var date

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .view(.saveCollection):
                let payload = makeSavePayload(from: state, currentDate: date())
                if let url = state.openedCollectionURL {
                    return .send(.collection(.saveToExisting(payload, url)))
                }
                return .send(.collection(.saveRequested(payload)))

            case .view(.saveCollectionAs):
                return .send(.collection(.saveRequested(makeSavePayload(from: state, currentDate: date()))))

            case .collection:
                return .none

            default:
                return .none
            }
        }
    }
}

private func makeSavePayload(from state: ComposerState, currentDate: Date) -> SaveRequestPayload {
    let context = state.collectionContext
    let query = context?.query ?? ""
    let scopes: [String] = context?.scopes ?? []
    let conditions: [Condition] = context?.conditions ?? []
    return SaveRequestPayload(
        context: context,
        isSearchLoading: state.isLoadingSearch,
        isFiltersLoading: state.isLoadingFilters,
        snapshotItems: CollectionSnapshotHydration.snapshotItems(from: state.lastFiltersResponse?.items),
        definitionFingerprint: CollectionSnapshotHydration.definitionFingerprint(
            query: query,
            scopes: scopes,
            conditions: conditions,
        ),
        capturedAt: currentDate,
        relevanceRoots: scopes.map(standardizedPath).sorted(),
    )
}

private func standardizedPath(_ path: String) -> String {
    URL(fileURLWithPath: path).standardizedFileURL.path
}
