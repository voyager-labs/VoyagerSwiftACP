import ComposableArchitecture
import Foundation
import VoyagerFeaturesComposer
import VoyagerFeaturesContentPageNavigation

func handleNavigationDelegate(
    _ delegateAction: ContentPageNavigationAction.Delegate,
    state: inout FileManagerWindowState,
    computerName: String,
    productMetricsClient: FileManagerProductMetricsClient,
) -> Effect<FileManagerWindowAction> {
    switch delegateAction {
    case let .revealEntryAfterNavigation(destinationPath, entryPath):
        .send(.content(.internal(.setPendingEntrySelection(
            entryID: entryPath,
            destinationPath: destinationPath,
        ))))

    case let .navigateToState(navigationState):
        .concatenate(
            syncActiveContentTabEffect(navigationState, state: state, computerName: computerName),
            handleNavigateToState(navigationState, state: &state),
            syncPinnedContentTabRuntimeNavigationEffect(
                navigationState,
                state: state,
                computerName: computerName,
            ),
        )

    case let .logDAUNavigation(previous, next, identity):
        syncProductBrowsingCorrelation(
            previous: previous,
            next: next,
            identity: identity,
            state: &state,
            productMetricsClient: productMetricsClient,
        )

    case .resetComposer:
        resetComposerAndExitCollectionModeEffect()
    }
}

/// EVM001: 실제 탐색과 콘텐츠 로딩 단말(`voyager_content_browsing_engaged`)을 상관시킨다.
/// entry-loading route만 correlation을 성립시키고, 이미 성립된
/// 콘텐츠 기원 correlation은 덮어쓰지 않으며, 비로딩 route는 미완료 correlation을 정리한다.
private func syncProductBrowsingCorrelation(
    previous: ContentPageNavigationRoute,
    next: ContentPageNavigationRoute,
    identity: ContentPageNavigationInteractionIdentity,
    state: inout FileManagerWindowState,
    productMetricsClient: FileManagerProductMetricsClient,
) -> Effect<FileManagerWindowAction> {
    let source = state.content.pendingProductBrowsingSource ?? .fileManagerSidebar
    state.content.pendingProductBrowsingSource = nil
    guard previous != next else { return .none }
    let content: ContentBrowsingKind? = switch next {
    case .folder:
        .folder
    case .recents, .tags, .computer:
        .collection
    case .home, .collection, .aiChat, .aiChatSessions:
        nil
    }
    guard let content else {
        state.content.productBrowsingOperationID = nil
        state.content.productBrowsingIdentity = nil
        state.content.productBrowsingSource = nil
        state.content.productBrowsingContent = nil
        return .none
    }
    if state.content.productBrowsingOperationID == nil {
        state.content.productBrowsingOperationID = productMetricsClient.makeOperationID()
        state.content.productBrowsingIdentity = identity
        state.content.productBrowsingSource = source
    }
    state.content.productBrowsingContent = content
    return .none
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
