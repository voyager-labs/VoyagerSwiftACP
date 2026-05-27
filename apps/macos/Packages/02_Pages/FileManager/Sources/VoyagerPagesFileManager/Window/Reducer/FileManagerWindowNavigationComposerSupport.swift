import ComposableArchitecture
import Foundation
import VoyagerFeaturesComposer
import VoyagerFeaturesContentPageNavigation

func handleNavigationDelegate(
    _ delegateAction: ContentPageNavigationAction.Delegate,
    state: inout FileManagerWindowState,
    computerName: String,
    metricsClient: MetricsClient,
) -> Effect<FileManagerWindowAction> {
    switch delegateAction {
    case let .navigateToState(navigationState):
        syncSidebarSelection(state: &state, computerName: computerName)
        return handleNavigateToState(navigationState, state: &state)

    case let .logDAUNavigation(previous, next):
        guard previous != next else { return .none }
        if next.isCollection {
            metricsClient.logDAUNavigation(.collection)
        } else {
            metricsClient.logDAUNavigation(.folder)
        }
        return .none

    case .resetComposer:
        return .concatenate(
            .send(.content(.internal(.resetComposer))),
            .send(.content(.internal(.exitCollectionMode))),
        )
    }
}
