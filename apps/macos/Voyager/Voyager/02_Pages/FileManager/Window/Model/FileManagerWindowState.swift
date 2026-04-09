import ComposableArchitecture
import Foundation

import VoyagerFeaturesEntryOperations

@ObservableState
struct FileManagerWindowState: Equatable {
    var content: FileManagerContentFeature.State = .init()
    var sidebar: FileManagerSidebarFeature.State = .init()
    var inspector: FileManagerInspectorFeature.State = .init()

    static func makeInitial(windowID: UUID, path: String?) -> Self {
        var state = Self()
        state.content.entryViewLayout.entryOperations.windowID = windowID

        if let path {
            state.content.navigation.seedInitialFolderPath(path)
        }

        return state
    }
}
