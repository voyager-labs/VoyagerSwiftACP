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
            EntryOperationsFolderLoadingReducer()
            EntryOperationsMetricsReducer()
            EntryOperationsLifecycleReducer()
            EntryUndoRedoOperationsReducer()
            EntryOperationsExecutionReducer()
        }
    }
}

@Reducer
struct EntryOperationsExecutionReducer {
    typealias State = EntryOperationsState
    typealias Action = EntryOperationsAction

    var body: some Reducer<State, Action> {
        CombineReducers {
            EntryOpenOperationsReducer()
            EntryOpenWithOperationsReducer()
            EntryEditOperationsReducer()
            EntryClipboardOperationsReducer()
            EntryTrashOperationsReducer()
            EntryArchiveOperationsReducer()
            EntryTaggingOperationsReducer()
            EntryExternalDropOperationsReducer()
        }
    }
}
