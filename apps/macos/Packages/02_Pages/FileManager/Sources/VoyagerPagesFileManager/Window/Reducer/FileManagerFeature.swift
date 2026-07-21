import ComposableArchitecture
import Foundation
import VoyagerFeaturesContentPageNavigation
import VoyagerFeaturesEntryOperations

@Reducer
public struct FileManagerFeature {
    public typealias State = FileManagerWindowState
    public typealias Action = FileManagerWindowAction

    public init() {}

    public var body: some Reducer<State, Action> {
        Scope(state: \.content, action: \.content) {
            FileManagerContentFeature()
        }

        Scope(state: \.content.navigation, action: \.navigation) {
            ContentPageNavigationFeature()
        }

        Scope(state: \.sidebarEntryDropOperations, action: \.internal.sidebarEntryDrop) {
            EntryOperationsFeature()
        }

        Scope(state: \.sidebar, action: \.sidebar) {
            FileManagerSidebarFeature()
        }

        Scope(state: \.inspector, action: \.inspector) {
            FileManagerInspectorFeature()
        }

        Reduce { state, action in
            switch action {
            case let .contentTabs(.duplicate(sourceID, duplicateID)):
                .send(.internal(.duplicateContentTabReduced(
                    sourceID: sourceID,
                    duplicateID: duplicateID,
                    duplicateIDWasPreexisting: state.contentTabs.tabs[id: duplicateID] != nil,
                )))

            case let .contentTabs(.duplicateSelected(requests)):
                .send(.internal(.duplicateSelectedContentTabsReduced(
                    requests: requests,
                    preexistingTabIDs: Set(state.contentTabs.tabs.ids),
                )))

            default:
                .none
            }
        }

        Scope(state: \.contentTabs, action: \.contentTabs) {
            ContentTabFeature()
        }

        FileManagerWindowNavigationReducer()
        FileManagerWindowLifecycleReducer()
        FileManagerWindowPreferencesReducer()
        FileManagerWindowRoutingReducer()
        FileManagerWindowCommandRoutingReducer()
    }
}
