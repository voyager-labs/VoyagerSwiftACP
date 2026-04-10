import ComposableArchitecture

@Reducer
struct CollectionFeature {
    typealias State = CollectionState
    typealias Action = CollectionAction

    var body: some Reducer<State, Action> {
        CollectionSavePipelineReducer()
    }
}
