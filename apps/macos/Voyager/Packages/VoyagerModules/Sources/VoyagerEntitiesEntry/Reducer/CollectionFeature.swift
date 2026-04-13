import ComposableArchitecture

@Reducer
public struct CollectionFeature {
    public typealias State = CollectionState
    public typealias Action = CollectionAction

    public init() {}

    public var body: some Reducer<State, Action> {
        EmptyReducer()
    }
}
