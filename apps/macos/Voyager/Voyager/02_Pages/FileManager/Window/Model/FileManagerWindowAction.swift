import ComposableArchitecture
import Foundation

@CasePathable
enum FileManagerWindowAction: CasePathable, Sendable {
    case content(FileManagerContentFeature.Action)
    case sidebar(FileManagerSidebarFeature.Action)
    case inspector(FileManagerInspectorFeature.Action)
    case navigation(ContentPageNavigationFeature.Action)

    case onAppear
    case onDisappear
    case closeWindow
}
