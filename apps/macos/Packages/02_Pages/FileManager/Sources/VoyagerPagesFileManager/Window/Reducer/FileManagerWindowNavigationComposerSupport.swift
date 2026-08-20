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
            syncPinnedContentTabRuntimeNavigationEffect(
                navigationState,
                state: state,
                computerName: computerName,
            ),
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
        return resetComposerAndExitCollectionModeEffect()
    }
}

func resetComposerAndExitCollectionModeEffect() -> Effect<FileManagerWindowAction> {
    .concatenate(
        .send(.content(.internal(.resetComposer))),
        .send(.content(.internal(.exitCollectionMode))),
    )
}

func resetComposerAndClearCollectionModeEffect() -> Effect<FileManagerWindowAction> {
    .concatenate(
        .send(.content(.internal(.resetComposer))),
        .send(.content(.internal(.clearCollectionMode))),
    )
}

func syncPinnedContentTabRuntimeNavigationEffect(
    _ navigationState: ContentPageNavigationRoute,
    state: FileManagerWindowState,
    computerName: String,
) -> Effect<FileManagerWindowAction> {
    guard let activeTabID = state.contentTabs.activeTabID,
          let activeTab = state.contentTabs.tabs[id: activeTabID],
          activeTab.isPinned,
          contentTabAnchor(for: navigationState, computerName: computerName) != nil
    else { return .none }

    return .send(.delegate(.pinnedContentTabRuntimeNavigationChanged(
        tabID: activeTabID,
        navigationState: navigationState,
    )))
}

func syncActiveContentTabEffect(
    _ navigationState: ContentPageNavigationRoute,
    state: FileManagerWindowState,
    computerName: String,
) -> Effect<FileManagerWindowAction> {
    guard let activeTabID = state.contentTabs.activeTabID else { return .none }
    return syncContentTabEffect(
        navigationState,
        tabID: activeTabID,
        state: state,
        computerName: computerName,
    )
}

func syncContentTabEffect(
    _ navigationState: ContentPageNavigationRoute,
    tabID: ContentTabID,
    state: FileManagerWindowState,
    computerName: String,
) -> Effect<FileManagerWindowAction> {
    guard let anchor = contentTabAnchor(for: navigationState, computerName: computerName),
          state.contentTabs.tabs[id: tabID]?.anchor != anchor
    else { return .none }

    let updateTabAnchorEffect = updateContentTabPageAnchorEffect(
        tabID: tabID,
        anchor: anchor,
        state: state,
    )
    guard tabID == state.contentTabs.activeTabID,
          case .aiChat = anchor,
          state.inspector.inspectorVisible,
          state.inspector.activeMode == .chat
    else {
        return updateTabAnchorEffect
    }
    return .concatenate(
        .send(.inspector(.closeChat)),
        updateTabAnchorEffect,
    )
}

func updateContentTabPageAnchorEffect(
    tabID: ContentTabID,
    anchor: ContentTabPageAnchor,
    state: FileManagerWindowState,
) -> Effect<FileManagerWindowAction> {
    let action: ContentTabAction = if state.contentTabs.tabs[id: tabID]?.isPinned == true {
        .updateRuntimePageAnchor(tabID, anchor)
    } else {
        .updateActivePageAnchor(tabID, anchor)
    }
    return .send(.contentTabs(action))
}

func contentTabAnchor(
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
