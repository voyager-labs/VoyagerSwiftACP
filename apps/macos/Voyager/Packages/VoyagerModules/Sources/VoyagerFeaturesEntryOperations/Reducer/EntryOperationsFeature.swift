import ComposableArchitecture

@Reducer
public struct EntryOperationsFeature {
    public typealias State = EntryOperationsState
    public typealias Action = EntryOperationsAction

    public init() {}

    public var body: some Reducer<State, Action> {
        CombineReducers {
            EntryOperationsCommandRoutingReducer()
            EntryOperationsLoadingReducer()
            EntryOperationsMetricsReducer()
            EntryOperationsLifecycleReducer()
            EntryUndoRedoOperationsReducer()
            EntryOpenOperationsReducer()
            EntryOpenWithOperationsReducer()
            EntryEditOperationsReducer()
            EntryClipboardOperationsReducer()
            EntryTrashOperationsReducer()
            EntryArchiveOperationsReducer()
            EntryTaggingOperationsReducer()
        }
    }
}
