#if canImport(ComposableArchitecture)
import ComposableArchitecture
import Foundation

@Reducer
struct EntryArrangementsGroupingReducer {
    typealias State = EntryArrangementsState
    typealias Action = EntryArrangementsAction

    @Dependency(\.userDefaultsClient)
    private var userDefaultsClient

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case let .setGroupKey(key):
                state.updateGroupKey(key)
                userDefaultsClient.setString(key.rawValue, EntryArrangementsPersistenceKey.groupKey)
                return .send(.delegate(.requestApply))

            case let .toggleCollapsedGroup(groupName):
                if state.collapsedGroups.contains(groupName) {
                    state.collapsedGroups.remove(groupName)
                } else {
                    state.collapsedGroups.insert(groupName)
                }
                return .none

            case .setSortKey,
                 .setSortOrder,
                 .reapply:
                return .none

            case .delegate,
                 .apply:
                return .none
            }
        }
    }
}
#else

import Foundation

struct EntryArrangementsGroupingReducer {}

#endif
