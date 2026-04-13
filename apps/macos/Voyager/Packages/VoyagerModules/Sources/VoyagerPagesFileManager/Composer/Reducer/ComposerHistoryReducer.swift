import ComposableArchitecture
import VoyagerEntitiesEntry

@Reducer
public struct ComposerHistoryReducer {
    public typealias State = ComposerState
    public typealias Action = ComposerAction

    @Dependency(\.searchClient)
    public var searchClient
    @Dependency(\.registryClient)
    public var registryClient

    public var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .view(.undo):
                guard !state.isLoadingSearch else { return .none }
                let before = buildFilters(from: state)
                guard let previous = state.history.popLast() else { return .none }
                let current = FilterSnapshot(
                    scopes: state.scopes,
                    conditions: state.conditions,
                    conditionDisplayByKey: state.conditionDisplayByKey,
                )
                state.redoHistory.append(current)
                state.scopes = previous.scopes
                state.conditions = previous.conditions
                state.conditionDisplayByKey = previous.conditionDisplayByKey
                updateOperatorOptions(state: &state, registryClient: registryClient)
                let after = buildFilters(from: state)
                if before != after {
                    return applyFiltersIfNeeded(state: &state, searchClient: searchClient)
                }
                return .none

            case .view(.redo):
                guard !state.isLoadingSearch else { return .none }
                let before = buildFilters(from: state)
                guard let next = state.redoHistory.popLast() else { return .none }
                let current = FilterSnapshot(
                    scopes: state.scopes,
                    conditions: state.conditions,
                    conditionDisplayByKey: state.conditionDisplayByKey,
                )
                state.history.append(current)
                state.scopes = next.scopes
                state.conditions = next.conditions
                state.conditionDisplayByKey = next.conditionDisplayByKey
                updateOperatorOptions(state: &state, registryClient: registryClient)
                let after = buildFilters(from: state)
                if before != after {
                    return applyFiltersIfNeeded(state: &state, searchClient: searchClient)
                }
                return .none

            default:
                return .none
            }
        }
    }
}
