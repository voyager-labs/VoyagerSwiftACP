import ComposableArchitecture
import Foundation

@Reducer
struct FileManagerWindowPreferencesReducer {
    typealias State = FileManagerWindowState
    typealias Action = FileManagerWindowAction

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case let .applyAppPreferences(preferences):
                state.sidebar.sidebarVisible = preferences.sidebarVisible
                state.sidebar.sidebarWidth = preferences.sidebarWidth

                state.content.viewLayout = preferences.viewLayout
                state.content.listIconSize = preferences.listIconSize
                state.content.gridIconSize = preferences.gridIconSize
                state.content.listTextSize = preferences.listTextSize
                state.content.gridTextSize = preferences.gridTextSize

                state.content.entryViewLayout.showHiddenFiles = preferences.showHiddenFiles
                state.content.entryArrangements.updateSortKey(preferences.sortKey)
                state.content.entryArrangements.updateSortOrder(preferences.sortOrder)
                state.content.entryArrangements.updateGroupKey(preferences.groupKey)
                state.content.syncComposerCollectionState()

                return .merge(
                    .send(.content(.entryArrangements(.setSortKey(preferences.sortKey)))),
                    .send(.content(.entryArrangements(.setSortOrder(preferences.sortOrder)))),
                    .send(.content(.entryArrangements(.setGroupKey(preferences.groupKey)))),
                )

            default:
                return .none
            }
        }
    }
}
