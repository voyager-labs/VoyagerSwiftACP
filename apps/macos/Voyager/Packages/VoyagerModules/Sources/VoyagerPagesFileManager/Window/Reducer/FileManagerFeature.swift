import ComposableArchitecture
import Foundation

import VoyagerFeaturesContentPageNavigation
import VoyagerFeaturesEntryOperations
@_exported import VoyagerWidgetsEntryViewLayout

@Reducer
public struct FileManagerFeature {
    public typealias State = FileManagerWindowState
    public typealias Action = FileManagerWindowAction

    public init() {}

    public var body: some Reducer<State, Action> {
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
