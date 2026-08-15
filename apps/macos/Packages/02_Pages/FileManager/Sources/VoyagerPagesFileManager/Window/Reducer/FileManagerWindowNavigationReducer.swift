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
            case let .tabContent(tabID, .internal(.requestNavigation(navigationAction))):
                guard tabID == state.contentTabs.activeTabID else { return .none }
                return .send(.navigation(navigationAction))

            case let .performBatchCloseContentAction(
                operationID,
                tabID,
                .internal(.requestNavigation(navigationAction)),
            ):
                return .send(.performBatchCloseNavigationAction(
                    operationID: operationID,
                    tabID: tabID,
                    action: navigationAction,
                ))

            case let .tabContent(tabID, .internal(.applyNavigationState(navigationState))):
                guard let originContent = fileManagerContentState(for: tabID, state: state) else { return .none }
                return syncContentTabEffect(
                    navigationState,
                    tabID: tabID,
                    state: state,
                    computerName: originContent.navigation.currentPath,
                )

            case let .tabContent(tabID, .internal(.performPendingNavigation(pending))):
                guard tabID == state.contentTabs.activeTabID else { return .none }
                return .send(.navigation(.internal(.performNavigation(pending))))

            case let .tabContent(tabID, .delegate(.composerCollectionSearchSucceeded)):
                guard let originContent = fileManagerContentState(for: tabID, state: state) else { return .none }
                return syncContentTabEffect(
                    originContent.navigation.navigationState,
                    tabID: tabID,
                    state: state,
                    computerName: originContent.navigation.currentPath,
                )

            default:
                return .none
            }
        }
    }
}

func handleNavigateToState(
    _ navigationState: ContentPageNavigationRoute,
    state: inout FileManagerWindowState,
) -> Effect<FileManagerWindowAction> {
    guard let activeTabID = state.contentTabs.activeTabID else { return .none }
    let applyNavigationStateEffect: Effect<FileManagerWindowAction> = .send(.tabContent(
        tabID: activeTabID,
        action: .internal(.applyNavigationState(navigationState)),
    ))
    guard case let .collection(navigation) = navigationState else {
        return applyNavigationStateEffect
    }
    return .concatenate(
        applyNavigationStateEffect,
        .send(.navigation(.internal(.navigateToCollection(navigation)))),
    )
}
