import ComposableArchitecture

@Reducer
struct EntryThumbnailFeature {
    typealias State = EntryThumbnailState
    typealias Action = EntryThumbnailAction

    var body: some Reducer<State, Action> {
        CombineReducers {
            EntryThumbnailRequestReducer()
        }
    }
}
