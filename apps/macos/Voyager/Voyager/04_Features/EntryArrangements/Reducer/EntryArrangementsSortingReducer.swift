import ComposableArchitecture
import Foundation
import VoyagerShared
import VoyagerWidgetsEntryViewLayout

@Reducer
struct EntryArrangementsSortingReducer {
    typealias State = EntryArrangementsState
    typealias Action = EntryArrangementsAction

    @Dependency(\.userDefaultsClient)
    private var userDefaultsClient

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case let .setSortKey(key):
                state.updateSortKey(key)
                userDefaultsClient.setString(key.rawValue, EntryArrangementsPersistenceKey.sortKey)
                return .send(.delegate(.requestApply))

            case let .setSortOrder(order):
                state.updateSortOrder(order)
                userDefaultsClient.setString(order.rawValue, EntryArrangementsPersistenceKey.sortOrder)
                return .send(.delegate(.requestApply))

            case .reapply:
                return .send(.delegate(.requestApply))

            case .setGroupKey,
                 .toggleCollapsedGroup,
                 .delegate,
                 .apply:
                return .none
            }
        }
    }
}
