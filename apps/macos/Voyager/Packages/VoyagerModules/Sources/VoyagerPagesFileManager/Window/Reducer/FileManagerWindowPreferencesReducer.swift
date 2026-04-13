import ComposableArchitecture
import Foundation

import VoyagerWidgetsEntryViewLayout

@Reducer
public struct FileManagerWindowPreferencesReducer {
    public typealias State = FileManagerWindowState
    public typealias Action = FileManagerWindowAction

    public var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case let .applyAppPreferences(preferences):
                state.sidebar.sidebarVisible = preferences.sidebarVisible
                state.sidebar.sidebarWidth = preferences.sidebarWidth

                state.content.entryViewLayout.mode = preferences.viewLayout
                state.content.entryViewLayout.listIconSize = preferences.listIconSize
                state.content.entryViewLayout.gridIconSize = preferences.gridIconSize
                state.content.entryViewLayout.listTextSize = preferences.listTextSize
                state.content.entryViewLayout.gridTextSize = preferences.gridTextSize
                state.content.entryViewLayout.showHiddenFiles = preferences.showHiddenFiles
                state.content.entryViewLayout.entryArrangements.updateSortKey(preferences.sortKey)
                state.content.entryViewLayout.entryArrangements.updateSortOrder(preferences.sortOrder)
                state.content.entryViewLayout.entryArrangements.updateGroupKey(preferences.groupKey)
                state.content.syncComposerCollectionState()

                return .merge(
                    .send(.content(.entryViewLayout(.entryArrangements(.setSortKey(preferences.sortKey))))),
                    .send(.content(.entryViewLayout(.entryArrangements(.setSortOrder(preferences.sortOrder))))),
                    .send(.content(.entryViewLayout(.entryArrangements(.setGroupKey(preferences.groupKey))))),
                )

            default:
                return .none
            }
        }
    }
}
