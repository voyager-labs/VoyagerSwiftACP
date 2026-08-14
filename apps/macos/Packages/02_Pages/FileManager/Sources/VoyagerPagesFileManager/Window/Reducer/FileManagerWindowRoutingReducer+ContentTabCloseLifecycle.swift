import AppKit
import ComposableArchitecture
import Foundation
import VoyagerEntitiesAi
import VoyagerEntitiesCollection
import VoyagerEntitiesEntry
import VoyagerFeaturesAiChat
import VoyagerFeaturesComposer
import VoyagerFeaturesContentPageNavigation
import VoyagerFeaturesEntryOperations
import VoyagerShared

extension FileManagerWindowRoutingReducer {
    func finalizeContentTabClose(
        tabID: ContentTabID,
        state: inout State,
    ) -> Effect<Action> {
        guard !keepPendingContentTabCloseFocused(state: &state) else { return .none }
        let disposition = contentTabCloseDisposition(tabID: tabID, state: state)
        let isActualRemoval = disposition.isActualRemoval
        let shouldResetLastTabContent = disposition.shouldResetLastTabContent
        state.pendingDirectoryReloadTabIDs.remove(tabID)
        let closedTabLoadingCancellationEffect: Effect<Action> = if isActualRemoval || shouldResetLastTabContent {
            cancelLoadingEffectForClosedTab(
                tabID: tabID,
                wasActive: disposition.shouldRestorePreviousActiveTab,
                state: state,
            )
        } else {
            .none
        }
        if isActualRemoval {
            state.recentlyClosedNavigationRoute = navigationRouteForClosingTab(tabID, state: state)
        }
        let handoffCleanupEffect = prepareClosedTabHandoff(
            tabID: tabID,
            disposition: disposition,
            state: &state,
        )
        applyClosedTabStateMutation(tabID: tabID, disposition: disposition, state: &state)
        syncDashboardProjections(state: &state)
        syncSidebarSelectionForActiveContentTab(state: &state)
        let undoManagerLifecycleEffect = closedTabUndoManagerEffect(
            tabID: tabID,
            disposition: disposition,
            state: state,
        )
        let handoffEffect: Effect<Action> = .merge(
            handoffCleanupEffect,
            activeTabHandoffEffect(
                disposition.shouldResyncContentNavigation,
                state: &state,
                aiConnectionsFileClient: aiConnectionsFileClient,
                skipAiChatCancel: true,
            ),
            closeInspectorForActiveAiChatEffect(state: state),
            undoManagerLifecycleEffect,
            closedTabLoadingCancellationEffect,
        )
        return shouldResetLastTabContent
            ? .merge(handoffEffect, .send(.delegate(.closeWindow)))
            : handoffEffect
    }

    private func prepareClosedTabHandoff(
        tabID _: ContentTabID,
        disposition: ContentTabCloseDisposition,
        state: inout State,
    ) -> Effect<Action> {
        guard disposition.shouldResyncContentNavigation else { return .none }
        let sessionIDs = aiChatLifecycleSessionIDsToPreserve(state.content.aiChat)
        guard !sessionIDs.isEmpty else {
            return prepareContentForActiveTabHandoff(state: &state.content)
        }
        for sessionID in sessionIDs {
            state.addBackgroundAiChatState(sessionID: sessionID, state: state.content)
        }
        return prepareContentForActiveTabHandoff(state: &state.content, skipAiChatCleanup: true)
    }

    private func applyClosedTabStateMutation(
        tabID: ContentTabID,
        disposition: ContentTabCloseDisposition,
        state: inout State,
    ) {
        if disposition.isActualRemoval {
            state.addBackgroundAiChatState(for: tabID)
            state.addBackgroundInspectorAiChatState(for: tabID)
            state.removeContentState(for: tabID)
            state.removeInspectorState(for: tabID)
            guard disposition.shouldRestorePreviousActiveTab else { return }
            state.restoreContentStateForActiveTab()
            removeBackgroundAiChatOwnersPromotedToActiveContent(state: &state)
            state.restoreInspectorStateForActiveTab()
        } else if disposition.shouldResetLastTabContent {
            state.addBackgroundAiChatState(for: tabID)
            state.addBackgroundInspectorAiChatState(for: tabID)
            state.content = contentState(
                for: state.contentTabs.tabs[id: tabID]?.anchor,
                inheritingWindowContextFrom: state.content,
            )
            state.inspector = .init()
            state.syncActiveTabContentState()
            state.syncActiveTabInspectorState()
        }
    }

    private func closedTabUndoManagerEffect(
        tabID: ContentTabID,
        disposition: ContentTabCloseDisposition,
        state: State,
    ) -> Effect<Action> {
        if let homeTabID = disposition.replacementHomeTabID {
            return replaceUndoManagerScopeEffect(closedTabID: tabID, homeTabID: homeTabID, state: state)
        }
        guard disposition.isActualRemoval else { return .none }
        return deactivateUndoManagerScopeEffect(tabID: tabID, state: state)
    }
}
