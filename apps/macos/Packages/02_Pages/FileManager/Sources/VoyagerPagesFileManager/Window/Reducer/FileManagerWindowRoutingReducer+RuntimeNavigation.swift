import ComposableArchitecture
import Foundation
import VoyagerEntitiesAi
import VoyagerFeaturesContentPageNavigation

extension FileManagerWindowRoutingReducer {
    func applyPinnedContentTabRuntimeNavigation(
        tabID: ContentTabID,
        navigationState: ContentPageNavigationRoute,
        state: inout State,
    ) -> Effect<Action> {
        guard let tab = state.contentTabs.tabs[id: tabID],
              tab.isPinned,
              let anchor = contentTabAnchor(
                  for: navigationState,
                  computerName: fileManagerClient.displayName("/"),
              )
        else { return .none }

        let isActiveTab = state.contentTabs.activeTabID == tabID
        let targetContentState: FileManagerContentState? = isActiveTab
            ? state.content
            : state.tabContentStates[tabID]
        guard targetContentState?.hasUnsavedCollectionChanges != true else { return .none }

        let shouldResetCollectionMode = targetContentState?.isCollectionMode == true
            && !navigationState.isCollection

        let cancelCollectionOpenEffect = isActiveTab ? cancelPendingCollectionOpen(state: &state) : .none
        let resetCollectionModeEffect = if isActiveTab, shouldResetCollectionMode {
            resetComposerAndClearCollectionModeEffect()
        } else {
            Effect<Action>.none
        }
        let currentNavigationState = targetContentState?.navigation.navigationState
        if isActiveTab, currentNavigationState == navigationState {
            return .concatenate(cancelCollectionOpenEffect, resetCollectionModeEffect)
        }
        guard currentNavigationState != navigationState || shouldResetCollectionMode else { return .none }

        guard isActiveTab else {
            return applyInactivePinnedContentTabRuntimeNavigation(
                tabID: tabID,
                anchor: anchor,
                navigationState: navigationState,
                shouldResetCollectionMode: shouldResetCollectionMode,
                state: &state,
            )
        }

        return .concatenate(
            cancelCollectionOpenEffect,
            resetCollectionModeEffect,
            tab.anchor == anchor
                ? .none
                : .send(.contentTabs(.updateRuntimePageAnchor(tabID, anchor))),
            .send(.navigation(.internal(.applyPinnedPeerNavigationState(navigationState)))),
            handleNavigateToState(navigationState, state: &state),
        )
    }

    private func applyInactivePinnedContentTabRuntimeNavigation(
        tabID: ContentTabID,
        anchor: ContentTabPageAnchor,
        navigationState: ContentPageNavigationRoute,
        shouldResetCollectionMode: Bool,
        state: inout State,
    ) -> Effect<Action> {
        var contentState = state.tabContentStates[tabID]
            ?? FileManagerContentFeature.State.initialContent(
                for: anchor,
                inheritingWindowContextFrom: state.content,
            )
        if shouldResetCollectionMode {
            contentState.resetComposerAndClearCollectionMode()
        }
        contentState.navigation.navigationState = navigationState
        switch navigationState {
        case let .aiChat(sessionID):
            let aiChatSessionID = AiChatSessionID(rawValue: UUID(uuidString: sessionID) ?? UUID())
            if !contentState.aiChat.prepareChatPresentation(for: aiChatSessionID) {
                contentState.aiChat.prepareDeferredChatSessionRestore(for: aiChatSessionID)
            }
        case let .aiChatSessions(sessionID):
            let aiChatSessionID = AiChatSessionID(rawValue: UUID(uuidString: sessionID) ?? UUID())
            contentState.aiChat.prepareInactiveSessionsPresentation(for: aiChatSessionID)
        default:
            break
        }
        state.tabContentStates[tabID] = contentState
        return state.contentTabs.tabs[id: tabID]?.anchor == anchor
            ? .none
            : .send(.contentTabs(.updateRuntimePageAnchor(tabID, anchor)))
    }
}
