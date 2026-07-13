import ComposableArchitecture
import Foundation
import VoyagerEntitiesAppPreferences
import VoyagerShared

@Reducer
struct FileManagerSidebarPreferenceReducer {
    typealias State = FileManagerSidebarState
    typealias Action = FileManagerSidebarAction

    @Dependency(\.userDefaultsClient)
    private var userDefaultsClient

    var body: some Reducer<FileManagerSidebarState, FileManagerSidebarAction> {
        Reduce { state, action in
            switch action {
            case let .view(.setSidebarVisible(visible)):
                state.sidebarVisible = visible
                userDefaultsClient.setObject(visible, SettingsKeys.sidebarVisible)
                return .none

            case let .view(.setSidebarWidth(width)):
                guard state.sidebarVisible else { return .none }

                let clampedWidth = max(150, min(400, width))
                if abs(state.sidebarWidth - clampedWidth) < 0.5 {
                    return .none
                }
                state.sidebarWidth = clampedWidth
                userDefaultsClient.setDouble(clampedWidth, SettingsKeys.sidebarWidth)
                return .none

            default:
                return .none
            }
        }
    }
}
