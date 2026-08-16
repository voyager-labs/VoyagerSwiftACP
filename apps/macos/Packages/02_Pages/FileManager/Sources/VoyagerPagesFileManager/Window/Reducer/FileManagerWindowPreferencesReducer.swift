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
                    guard var content = state.tabContentStates[tabID] else { continue }
                    applyContentPreferences(preferences, to: &content)
                    state.tabContentStates[tabID] = content
                }

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
    content.entryViewLayout.entryArrangements.updateSortKey(preferences.sortKey)
    content.entryViewLayout.entryArrangements.updateSortOrder(preferences.sortOrder)
    content.entryViewLayout.entryArrangements.updateGroupKey(preferences.groupKey)
    content.syncComposerCollectionState()
}
