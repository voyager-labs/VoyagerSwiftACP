import ComposableArchitecture
import IdentifiedCollections

@Reducer
struct FileManagerEntryArrangementsBridge {
    typealias State = FileManagerContentState
    typealias Action = FileManagerContentAction

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .entryArrangements(.delegate(.requestApply)):
                return .send(.entryArrangements(.apply(
                    items: Array(state.entryOperations.displayItems),
                    isCollectionMode: state.entryOperations.loadingContext.isCollectionMode,
                )))

            case let .entryArrangements(.delegate(.applied(sortedItems, isCollectionMode))):
                if isCollectionMode {
                    state.entryOperations.loadingContext.collectionItems = IdentifiedArray(uniqueElements: sortedItems)
                } else {
                    state.entryOperations.loadingContext.items = IdentifiedArray(uniqueElements: sortedItems)
                }
                return .none

            default:
                return .none
            }
        }
    }
}
