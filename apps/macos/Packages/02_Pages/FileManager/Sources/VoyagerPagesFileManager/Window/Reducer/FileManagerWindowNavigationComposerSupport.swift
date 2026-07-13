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
        return .concatenate(
            syncActiveContentTabEffect(navigationState, state: state, computerName: computerName),
            handleNavigateToState(navigationState, state: &state),
        )

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

func syncActiveContentTabEffect(
    _ navigationState: ContentPageNavigationRoute,
    state: FileManagerWindowState,
    computerName: String,
) -> Effect<FileManagerWindowAction> {
    guard let activeTabID = state.contentTabs.activeTabID,
          let anchor = contentTabAnchor(for: navigationState, computerName: computerName),
          state.contentTabs.tabs[id: activeTabID]?.anchor != anchor
    else { return .none }

    let updateActiveTabAnchorEffect: Effect<FileManagerWindowAction> = .send(
        .contentTabs(.updateActivePageAnchor(activeTabID, anchor)),
    )
    guard case .aiChat = anchor,
          state.inspector.inspectorVisible,
          state.inspector.activeMode == .chat
    else {
        return updateActiveTabAnchorEffect
    }
    return .concatenate(
        .send(.inspector(.closeChat)),
        updateActiveTabAnchorEffect,
    )
}

private func contentTabAnchor(
    for navigationState: ContentPageNavigationRoute,
    computerName: String,
) -> ContentTabPageAnchor? {
    switch navigationState {
    case .home:
        .homeDefault

    case let .folder(path):
        .directory(path: path)

    case .recents:
        .virtualCollection(id: "Recents")

    case let .tags(tagName):
        .virtualCollection(id: tagName)

    case .computer:
        .virtualCollection(id: computerName)

    case let .collection(navigation):
        switch navigation.kind {
        case let .file(url, _):
            .collectionFile(url: url)
        case .temporary:
            nil
        }

    case let .aiChat(sessionID):
        .aiChat(sessionID: sessionID)

    case let .aiChatSessions(sessionID):
        .aiChat(sessionID: sessionID)
    }
}
