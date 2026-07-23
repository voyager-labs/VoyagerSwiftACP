import ComposableArchitecture
import Foundation
import VoyagerFeaturesComposer
import VoyagerFeaturesEntryArrangements

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
                state.inspector.inspectorWidth = preferences.inspectorWidth

                applyContentPreferences(preferences, to: &state.content)
                for tabID in state.tabContentStates.keys {
                    applyContentPreferences(preferences, to: &state.tabContentStates[tabID]!)
                }

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

private func applyContentPreferences(
    _ preferences: AppPreferencesState,
    to content: inout FileManagerContentFeature.State,
) {
    content.entryViewLayout.mode = .init(rawValue: preferences.viewLayoutMode.rawValue) ?? .list
    content.entryViewLayout.listIconSize = preferences.listIconSize
    content.entryViewLayout.gridIconSize = preferences.gridIconSize
    content.entryViewLayout.listTextSize = preferences.listTextSize
    content.entryViewLayout.gridTextSize = preferences.gridTextSize
    content.entryViewLayout.showHiddenFiles = preferences.showHiddenFiles
    content.entryArrangements.updateSortKey(preferences.sortKey)
    content.entryArrangements.updateSortOrder(preferences.sortOrder)
    content.entryArrangements.updateGroupKey(preferences.groupKey)
    content.syncComposerCollectionState()
}
