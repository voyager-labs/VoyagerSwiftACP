import ComposableArchitecture

@Reducer
struct EntryViewLayoutFeature {
    @ObservableState
    struct State {}

    enum Action {}

    var body: some Reducer<State, Action> {
        Reduce { _, _ in
            .none
        }
    }
}
