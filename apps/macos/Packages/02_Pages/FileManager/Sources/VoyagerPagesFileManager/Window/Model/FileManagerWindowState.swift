import ComposableArchitecture
import Foundation
import VoyagerFeaturesContentPageNavigation
import VoyagerFeaturesEntryOperations

@ObservableState
public struct FileManagerWindowState: Equatable {
    public var content: FileManagerContentFeature.State = .init()
    public var sidebar: FileManagerSidebarFeature.State = .init()
    public var inspector: FileManagerInspectorFeature.State = .init()

    public static func makeInitial(path: String?, selectEntryID: String? = nil) -> Self {
        var state = Self()
        if let path {
            state.content.navigation.seedInitialFolderPath(path)
        }
        state.content.pendingSelectEntryID = selectEntryID
        return state
    }
}

public extension FileManagerWindowState {
    func appPreferencesPreservingSidebarState(from preferences: AppPreferencesState) -> AppPreferencesState {
        var result = preferences
        result.sidebarVisible = sidebar.sidebarVisible
        result.sidebarWidth = sidebar.sidebarWidth
        return result
    }
}
