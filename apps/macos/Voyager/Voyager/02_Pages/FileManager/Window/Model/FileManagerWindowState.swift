import ComposableArchitecture
import Foundation

@ObservableState
struct FileManagerWindowState: Equatable {
    var content: FileManagerContentFeature.State = .init()
    var sidebar: FileManagerSidebarFeature.State = .init()
    var inspector: FileManagerInspectorFeature.State = .init()
}
