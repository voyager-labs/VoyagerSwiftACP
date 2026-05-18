import ComposableArchitecture

@Reducer
public struct EntryThumbnailFeature {
    public typealias State = EntryThumbnailState
    public typealias Action = EntryThumbnailAction

    public init() {}

    public var body: some Reducer<State, Action> {
        CombineReducers {
            EntryThumbnailRequestReducer()
        }
    }
}
