import ComposableArchitecture
import Foundation

@Reducer
struct FileManagerFeature {
    typealias State = FileManagerWindowState
    typealias Action = FileManagerWindowAction

    var body: some Reducer<State, Action> {
        Scope(state: \.content, action: \.content) {
            FileManagerContentFeature()
            FileManagerContentSyncReducer()
        }

        Scope(state: \.content.navigation, action: \.navigation) {
            ContentPageNavigationFeature()
        }

        Scope(state: \.sidebar, action: \.sidebar) {
            FileManagerSidebarFeature()
        }

        Scope(state: \.inspector, action: \.inspector) {
            FileManagerInspectorFeature()
        }

        FileManagerWindowNavigationReducer()
        FileManagerWindowLifecycleReducer()
        FileManagerWindowPreferencesReducer()
        FileManagerWindowRoutingReducer()
        FileManagerWindowCommandRoutingReducer()

        Reduce { _, action in
            switch action {
            case let .content(.delegate(.openPathInNewWindow(path))):
                .send(.delegate(.openPathInNewWindow(path)))

            case let .content(.delegate(.openPathInNewTab(path))):
                .send(.delegate(.openPathInNewTab(path)))

            default:
                .none
            }
        }
    }
}
