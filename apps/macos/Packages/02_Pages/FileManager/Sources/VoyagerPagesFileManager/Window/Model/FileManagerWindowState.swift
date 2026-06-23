import ComposableArchitecture
import Foundation
import VoyagerFeaturesContentPageNavigation
import VoyagerFeaturesEntryOperations

@ObservableState
public struct FileManagerWindowState: Equatable {
    public var content: FileManagerContentFeature.State = .init()
    public var sidebar: FileManagerSidebarFeature.State = .init()
    public var inspector: FileManagerInspectorFeature.State = .init()
    public var contentTabs: ContentTabState = .withHomeTab()

    public static func makeInitial(path: String?) -> Self {
        var state = Self()

        if let path {
            state.content.navigation.seedInitialFolderPath(path)
        }

        return state
    }

    public static func makeInitial(
        path: String?,
        contentTabs: ContentTabState?,
    ) -> Self {
        var state = Self()
        state.contentTabs = contentTabs.map { ContentTabState.bootstrapping(
            restoredTabs: $0.tabs,
            activeTabID: $0.activeTabID,
        )
        } ?? .withHomeTab()

        if let path {
            state.content.navigation.seedInitialFolderPath(path)
        }

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
