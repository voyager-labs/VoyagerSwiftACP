import ComposableArchitecture

@Reducer
struct EntryOperationsFeature {
    typealias State = EntryOperationsState
    typealias Action = EntryOperationsAction

    var body: some Reducer<State, Action> {
        CombineReducers {
            EntryThumbnailOperationsReducer()
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
