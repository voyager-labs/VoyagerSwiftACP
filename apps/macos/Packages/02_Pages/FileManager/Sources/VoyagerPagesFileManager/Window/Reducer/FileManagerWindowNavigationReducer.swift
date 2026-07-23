import ComposableArchitecture
import Foundation
import VoyagerEntitiesCollection
import VoyagerEntitiesTag
import VoyagerFeaturesComposer
import VoyagerFeaturesContentPageNavigation
import VoyagerShared

@Reducer
struct FileManagerWindowNavigationReducer {
    typealias State = FileManagerWindowState
    typealias Action = FileManagerWindowAction

    var body: some Reducer<State, Action> {
        FileManagerNavigationBridgeReducer()
        FileManagerNavigationActionReducer()
    }
}

@Reducer
private struct FileManagerNavigationBridgeReducer {
    typealias State = FileManagerWindowState
    typealias Action = FileManagerWindowAction

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case let .content(.internal(.requestNavigation(navigationAction))):
                .send(.navigation(navigationAction))

            case let .performBatchCloseContentAction(
                operationID,
                tabID,
                .internal(.requestNavigation(navigationAction)),
            ):
                .send(.performBatchCloseNavigationAction(
                    operationID: operationID,
                    tabID: tabID,
                    action: navigationAction,
                ))

            case let .content(.internal(.applyNavigationState(navigationState))):
                syncActiveContentTabEffect(
                    navigationState,
                    state: state,
                    computerName: state.content.navigation.currentPath,
                )

            case let .content(.internal(.performPendingNavigation(pending))):
                .send(.navigation(.internal(.performNavigation(pending))))

            case .content(.delegate(.composerCollectionSearchSucceeded)):
                syncActiveContentTabEffect(
                    state.content.navigation.navigationState,
                    state: state,
                    computerName: state.content.navigation.currentPath,
                )

            case .content(.delegate(.collectionChangesDiscarded)):
                .none

            case .content(.delegate(.composerCollectionSearchFailed)):
                .none

            default:
                .none
            }
        }
    }
}

func handleNavigateToState(
    _ navigationState: ContentPageNavigationRoute,
    state _: inout FileManagerWindowState,
) -> Effect<FileManagerWindowAction> {
    switch navigationState {
    case let .collection(navigation):
        .concatenate(
            .send(.content(.internal(.applyNavigationState(.collection(navigation))))),
            .send(.navigation(.internal(.navigateToCollection(navigation)))),
        )

    default:
        .send(.content(.internal(.applyNavigationState(navigationState))))
    }
}
