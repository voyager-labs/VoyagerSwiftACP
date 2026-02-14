import ComposableArchitecture

@Reducer
struct EntryThumbnailReducer {
    typealias State = EntryState
    typealias Action = EntryAction

    var body: some Reducer<State, Action> {
        Reduce { _, _ in
            .none
        }
    }
}
