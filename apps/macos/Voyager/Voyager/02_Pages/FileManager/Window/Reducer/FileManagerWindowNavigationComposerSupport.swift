import ComposableArchitecture
import Foundation

func handleNavigationDelegate(
    _ delegateAction: ContentPageNavigationAction.Delegate,
    state: inout FileManagerWindowState,
    computerName: String,
) -> Effect<FileManagerWindowAction> {
    switch delegateAction {
    case let .navigateToState(navigationState):
        syncSidebarSelection(state: &state, computerName: computerName)
        return handleNavigateToState(navigationState, state: &state)

    case let .logDAUNavigation(previous, next):
        logContentPageNavigationDAUIfNeeded(previous: previous, next: next)
        return .none

    case .resetComposer:
        state.content.resetComposer()
        return .send(.content(.internal(.exitCollectionMode)))
    }
}
