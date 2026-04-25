import ComposableArchitecture
import Foundation

@Reducer
struct EntryOperationsMetricsReducer {
    typealias State = EntryOperationsState
    typealias Action = EntryOperationsAction

    var body: some Reducer<State, Action> {
        EmptyReducer()
    }
}
