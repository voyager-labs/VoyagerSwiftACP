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
    var routingBody: some ReducerOf<Self> {
        Reduce<Self.State, Self.Action> { state, action in
            if case .request(.moveContentTabSwitcherFocus) = action {
                // stale focus는 방향 정보를 보존해야 하므로 command handler가 직접 reconcile한다.
            } else if case .request(.activateContentTabSwitcherSelection) = action {
                // focused window command는 stale focus 보존을 위해 command handler가 직접 처리한다.
            } else if case .view(.activateContentTabSwitcherCandidate) = action {
            } else {
                reconcileContentTabSwitcherPresentation(state: &state)
            }
            switch action {
            case let .applyPinnedContentTabRuntimeNavigation(tabID, navigationState, pendingSelectEntryID):
                return applyPinnedContentTabRuntimeNavigation(
                    tabID: tabID,
                    navigationState: navigationState,
                    pendingSelectEntryID: pendingSelectEntryID,
                    state: &state,
                )

            case let .requestSelectedContentTabPinMutation(target, source):
                return handleRequestSelectedContentTabPinMutation(target: target, source: source, state: &state)

            case let .requestContentTabDomainTransition(request):
                return handleRequestContentTabDomainTransition(request, state: &state)

            case let .processNextSelectedContentTabPinMutation(operationID):
                return processNextSelectedContentTabPinMutation(operationID: operationID, state: &state)

            case let .selectedPinMutationItemCompleted(operationID, tabID, outcome):
                return completeSelectedContentTabPinMutationItem(
                    operationID: operationID,
                    tabID: tabID,
                    outcome: outcome,
                    state: &state,
                )

            case let .selectedPinMutationBatchCompleted(result):
                recordSelectedPinMutationBatchMetric(result)
                let replayAction = takeDeferredPinnedContentTabsAction(state: &state)
                let replaySnapshot: Effect<Action> = if case .applyAuthoritativePinnedContentTabs = replayAction,
                                                        let revision = state.lastConfirmedTopNavigationCommitRevision
                {
                    .send(.applyCommittedTopNavigationSnapshot(
                        order: state.lastConfirmedTopNavigationOrder,
                        revision: revision,
                        authoritativePinnedContentTabs: nil,
                    ))
                } else {
                    .none
                }
                return .concatenate(
                    replaySnapshot,
                    replayAction.map(Effect.send) ?? .none,
                    selectedContentTabPinMutationFeedbackEffect(result),
                )

            case let .performSelectedContentTabPinMutation(operationID, tabID, contentTabAction):
                return handleSelectedContentTabPinMutation(
                    operationID: operationID,
                    tabID: tabID,
                    action: contentTabAction,
                    state: &state,
                )

            case .requestCloseSelectedContentTabs:
                return handleRequestCloseSelectedContentTabs(source: .contentTabBar, state: &state)

            case let .requestCloseSelectedTabs(source):
                return handleRequestCloseSelectedContentTabs(source: source, state: &state)

            case .onAppear:
                state.isClosing = false
                return .none

            case .onDisappear:
                return handleWindowDisappear(state: &state)

            case let .processNextSelectedContentTabClose(operationID):
                return processNextSelectedContentTabClose(operationID: operationID, state: &state)

            case let .selectedContentTabCloseItemCompleted(operationID, tabID, outcome):
                return completeSelectedContentTabCloseItem(
                    operationID: operationID,
                    tabID: tabID,
                    outcome: outcome,
                    state: &state,
                )

            case let .performSelectedContentTabCloseMutation(operationID, tabID, contentTabAction):
                guard !state.isClosing,
                      let pending = state.pendingSelectedContentTabClose,
                      pending.operationID == operationID,
                      pending.currentTabID == tabID,
                      isCorrelatedSelectedContentTabCloseMutation(contentTabAction, for: tabID)
                else { return .none }
                return handleSelectedContentTabCloseMutation(
                    operationID: operationID,
                    tabID: tabID,
                    action: contentTabAction,
                    state: &state,
                )

            case let .contentTabs(contentTabAction)
                where state.pendingSelectedContentTabPinMutation != nil
                && isDirectCloseMutation(contentTabAction):
                return .none

            case let .contentTabs(contentTabAction)
                where state.pendingSelectedContentTabClose != nil
                && !isSelectionAllowedDuringBatchClose(contentTabAction):
                return .none

            case let .reserveExternalContentTabs(reservations):
                guard state.pendingSelectedContentTabClose == nil,
                      let activeReservation = reservations.last,
                      state.reserveExternalContentTabs(reservations)
                else { return .none }
                return .send(.contentTabs(.setCurrent(activeReservation.id)))

            case let .activateExternalContentTabUndoScopes(tabIDs):
                guard Set(tabIDs).count == tabIDs.count,
                      tabIDs.allSatisfy({ state.contentTabs.tabs[id: $0] != nil })
                else { return .none }
                for tabID in tabIDs {
                    _ = activateUndoManagerScopeEffect(tabID: tabID, state: state)
                }
                return .none

            case .resyncActiveCollectionNavigation:
                guard let activeTabID = state.contentTabs.activeTabID,
                      case .collectionFile = state.contentTabs.tabs[id: activeTabID]?.anchor
                else { return .none }
                return resyncContentNavigationEffect(state: state)

            case let .sidebar(.delegate(.selectContentTab(tabID))):
                guard state.pendingSelectedContentTabClose == nil,
                      state.contentTabs.tabs[id: tabID] != nil
                else { return .none }
                return .send(.selectContentTab(tabID))

            case let .selectContentTab(tabID):
                guard state.pendingSelectedContentTabClose == nil,
                      state.contentTabs.tabs[id: tabID] != nil
                else { return .none }
                return selectContentTabEffect(tabID: tabID, state: &state)

            case let .sidebar(.delegate(.returnContentTabToPinnedLocation(tabID))):
                guard state.pendingSelectedContentTabClose == nil,
                      state.contentTabs.tabs[id: tabID] != nil
                else { return .none }
                return .send(.returnContentTabToPinnedLocation(tabID))

            case let .returnContentTabToPinnedLocation(tabID, pendingSelectEntryID, activateIfNeeded):
                guard state.pendingSelectedContentTabClose == nil,
                      state.contentTabs.tabs[id: tabID] != nil
                else { return .none }
                return returnContentTabToPinnedLocationEffect(
                    tabID: tabID,
                    pendingSelectEntryID: pendingSelectEntryID,
                    activateIfNeeded: activateIfNeeded,
                    state: &state,
                )

            case let .sidebar(.delegate(.closeContentTab(tabID))):
                guard state.contentTabRowInteractionSurface.isCloseEnabled else { return .none }
                return .send(.closeContentTabRequestedWithSource(tabID, .contextMenu))

            case let .sidebar(.delegate(.closeContentTabFromTrailingControl(tabID))):
                guard state.contentTabRowInteractionSurface.isCloseEnabled else { return .none }
                return .send(.closeContentTabRequestedWithSource(tabID, .contentTabBar))

            case .sidebar(.delegate(.closeSelectedContentTabs)):
                guard state.contentTabRowInteractionSurface.isCloseEnabled else { return .none }
                return .send(.request(.contentTabAction(.closeSelected, source: .contextMenu)))

            case let .sidebar(.delegate(.pinContentTab(tabID))):
                guard state.pendingSelectedContentTabClose == nil,
                      state.pendingSelectedContentTabPinMutation == nil,
                      state.pendingContentTabClose == nil,
                      state.pendingContentTabTeardown == nil
                else { return .none }
                guard state.canPinContentTab(tabID) else {
                    return cannotPinCollectionFeedbackEffect()
                }
                return .send(.contentTabActionRequested(.pin(tabID), source: .contextMenu))

            case let .sidebar(.delegate(.unpinContentTab(tabID))):
                guard state.pendingSelectedContentTabPinMutation == nil,
                      state.contentTabRowInteractionSurface.isCloseEnabled
                else { return .none }
                return .send(.contentTabActionRequested(.unpin(tabID), source: .contextMenu))

            case let .sidebar(.delegate(.unpinContentTabFromTrailingControl(tabID))):
                guard state.pendingSelectedContentTabPinMutation == nil,
                      state.contentTabRowInteractionSurface.isCloseEnabled
                else { return .none }
                return .send(.contentTabActionRequested(.unpin(tabID), source: .contentTabBar))

            case let .sidebar(.delegate(.setSelectedContentTabsPinned(target))):
                return .send(.requestSelectedContentTabPinMutation(target: target, source: .contextMenu))

            case let .sidebar(.delegate(.contentTabDomainTransitionRequested(request))):
                return .send(.requestContentTabDomainTransition(request))

            case .sidebar(.delegate(.openContentTab)):
                guard state.contentTabMoveParticipantRequestID == nil,
                      state.pendingSelectedContentTabClose == nil,
                      state.contentTabs.tabs.count < ContentTabConstants.maxTabs
                else { return .none }
                return .send(.request(.openNewContentTab(source: .contentTabBar)))

            case let .sidebar(.delegate(.duplicateContentTab(sourceID))):
                guard state.pendingSelectedContentTabClose == nil else { return .none }
                return .send(.request(.contentTabAction(.duplicate(sourceID), source: .contextMenu)))

            case let .tabContent(tabID, .delegate(.closeWindow)):
                guard tabID == state.contentTabs.activeTabID else { return .none }
                return .send(.delegate(.closeWindow))

            case .sidebar(.delegate(.duplicateSelectedContentTabs)):
                guard state.pendingSelectedContentTabClose == nil else { return .none }
                return .send(.request(.contentTabAction(.duplicateSelected, source: .contextMenu)))

            case let .sidebar(.delegate(.toggleContentTabSelection(id))):
                return .send(.contentTabs(.toggleSelection(id)))

            case let .sidebar(.delegate(.selectContentTabRange(to: id))):
                return .send(.contentTabs(.selectRange(
                    to: id,
                    orderedIDs: state.contentTabSelectionOrderedIDs,
                )))

            case .sidebar(.delegate(.collapseContentTabSelectionToActive)):
                return .send(.contentTabs(.collapseSelectionToActive))

            case .sidebar(.delegate(.dismissTopNavigationPresentation)):
                state.sidebar.topNavigationArrangementPresentation = nil
                return .none

            case let .sidebar(.delegate(.fileManagerTopNavigationReorderRequested(
                sourceID,
                anchorID,
                placement,
                actionSource,
            ))):
                return sidebarReorderRequested(
                    sourceID: sourceID,
                    anchorID: anchorID,
                    placement: placement,
                    actionSource: actionSource,
                    state: &state,
                )

            case .content(.delegate(.requestDuplicate)):
                let command: Action.WindowCommand = state.contentTabs.orderedValidSelectedTabIDs.count > 1
                    ? .duplicateSelectedContentTabs
                    : .duplicate
                return .send(.request(command))

            case .content(.delegate(.closeWindow)):
                return .send(.delegate(.closeWindow))

            case let .contentTabs(.setCurrent(targetID)):
                return contentTabsSetCurrent(targetID: targetID, state: &state)

            case .contentTabs(.open):
                return contentTabsOpen(state: &state)

            case .contentTabActionRequested(.open, source: _):
                return contentTabsOpen(state: &state)

            case let .contentTabs(.requestClose(tabID)):
                guard state.contentTabMoveParticipantRequestID == nil,
                      !state.contentTabs.pendingPinnedRecordIDs.contains(tabID)
                else { return .none }
                guard let tab = state.contentTabs.tabs[id: tabID] else { return .none }
                if tab.isPinned {
                    return .send(.contentTabs(.close(tabID)))
                }
                return prepareContentTabTeardown(tabID: tabID, state: &state)

            case let .contentTabs(.close(tabID)):
                guard state.contentTabMoveParticipantRequestID == nil,
                      state.contentTabs.tabs[id: tabID] == nil
                else { return .none }
                return finalizeContentTabClose(tabID: tabID, state: &state)

            case let .contentTabs(.commitClose(tabID)):
                guard state.contentTabMoveParticipantRequestID == nil,
                      !state.contentTabs.pendingPinnedRecordIDs.contains(tabID)
                else { return .none }
                return finalizeContentTabClose(tabID: tabID, state: &state)

            case .contentTabs(.restore):
                return contentTabsRestore(state: &state)

            case let .applyPinnedContentTabs(contentTabs),
                 let .applyAuthoritativePinnedContentTabs(contentTabs):
                return applyPinnedContentTabs(
                    contentTabs,
                    mode: pinnedContentTabsApplicationMode(for: action),
                    state: &state,
                )

            case .contentTabs(.duplicateSelected):
                // Pre-scope reducer가 captured identity를 internal action으로 전달한 뒤 owner handoff를 수행한다.
                return .none

            case let .internal(.duplicateSelectedContentTabsReduced(requests, preexistingTabIDs)):
                return duplicateSelectedContentTabsReduced(
                    requests: requests,
                    preexistingTabIDs: preexistingTabIDs,
                    state: &state,
                )

            case .contentTabs(.duplicate):
                // Pre-scope reducer가 기존 identity를 캡처한 internal action에서 post-reduce 처리를 수행한다.
                return .none

            case let .internal(.duplicateContentTabReduced(
                sourceID,
                duplicateID,
                duplicateIDWasPreexisting,
            )):
                return duplicateContentTabReduced(
                    sourceID: sourceID,
                    duplicateID: duplicateID,
                    duplicateIDWasPreexisting: duplicateIDWasPreexisting,
                    state: &state,
                )

            case .contentTabs(.reorder):
                state.syncContentTabSidebarItems()
                return .none

            // MARK: - CTM-001-select_content_tabs

            // Child selection mutation은 보존하고 unrelated Window projection/cleanup은 실행하지 않는다.
            case .contentTabs(.toggleSelection),
                 .contentTabs(.selectRange),
                 .contentTabs(.collapseSelectionToActive):
                return .none

            case .contentTabs:
                cleanPendingDirectoryReloadTabIDs(state: &state)
                syncDashboardProjections(state: &state)
                return .none

            case let .content(.entryViewLayout(.entryOperations(.outcome(.entriesMutated(impact))))):
                return handleEntriesMutated(impact, state: &state)

            case let .tabContent(
                tabID,
                .entryViewLayout(.entryOperations(.outcome(.entriesMutated(impact)))),
            ):
                guard fileManagerContentState(for: tabID, state: state) != nil else { return .none }
                return handleEntriesMutated(impact, state: &state)

            case let .content(
                .entryViewLayout(.entryOperations(.outcome(.undoManagerAvailabilityChanged(availability)))),
            ):
                state.undoManagerAvailability = availability
                return .none

            case let .tabContent(
                tabID,
                .entryViewLayout(.entryOperations(.outcome(.undoManagerAvailabilityChanged(availability)))),
            ):
                guard fileManagerContentState(for: tabID, state: state) != nil else { return .none }
                state.undoManagerAvailability = availability
                return .none

            case let .content(
                .entryViewLayout(.entryOperations(.outcome(.entryActionReplayFinished(direction, terminal)))),
            ):
                return handleEntryActionReplayTerminal(
                    direction: direction,
                    terminal: terminal,
                    ownerID: state.content.entryViewLayout.entryOperations.undoOwnerID,
                    context: EntryActionReplayContext(
                        makeFallbackRequestID: { uuid() },
                        undoManagerClient: undoManagerClient,
                    ),
                    state: &state,
                )

            case let .tabContent(
                tabID,
                .entryViewLayout(.entryOperations(.outcome(.entryActionReplayFinished(direction, terminal)))),
            ):
                guard let ownerID = fileManagerContentState(for: tabID, state: state)?
                    .entryViewLayout.entryOperations.undoOwnerID
                else {
                    state.undoRedoPhase = .desynchronized
                    state.undoManagerAvailability = .init()
                    return .none
                }
                return handleEntryActionReplayTerminal(
                    direction: direction,
                    terminal: terminal,
                    ownerID: ownerID,
                    context: EntryActionReplayContext(
                        makeFallbackRequestID: { uuid() },
                        undoManagerClient: undoManagerClient,
                    ),
                    state: &state,
                )

            case let .internal(.sidebarEntryDrop(.outcome(.entriesMutated(impact)))):
                return handleEntriesMutated(impact, state: &state)

            case let .internal(.sidebarEntryDrop(.lifecycle(.entryActionCompleted(record)))):
                if let command = record.command {
                    guard state.recordedSidebarEntryCommandIDs.insert(command.id).inserted else {
                        return .none
                    }
                    if let metric = FileManagerProductMetricsProducer.entryTerminal(for: record) {
                        productMetricsClient.record(metric)
                    }
                    state.pendingSidebarEntryCommands.removeValue(forKey: command.id)
                }
                guard record.operationKind == .moveToTrash else { return .none }
                return handleAffectedDirectoryRefresh(
                    paths: parentDirectoryPaths(for: record.targets),
                    state: &state,
                )

            case let .internal(.sidebarEntryDrop(.outcome(.undoManagerAvailabilityChanged(availability)))):
                state.undoManagerAvailability = availability
                return .none

            case let .internal(.sidebarEntryDrop(.outcome(.entryActionReplayFinished(direction, terminal)))):
                return .merge(
                    handleEntryActionReplayTerminal(
                        direction: direction,
                        terminal: terminal,
                        ownerID: state.sidebarEntryDropOperations.undoOwnerID,
                        context: EntryActionReplayContext(
                            makeFallbackRequestID: { uuid() },
                            undoManagerClient: undoManagerClient,
                        ),
                        state: &state,
                    ),
                    handleSidebarEntryActionReplayTerminal(terminal, state: &state),
                )

            case let .internal(.undoManagerOwnerInvalidationFinished(requestID, ownerID, result)):
                guard allowsSelectedContentTabCloseLifecycleMutation(state: state) else { return .none }
                return handleUndoManagerOwnerInvalidationFinished(
                    requestID: requestID,
                    ownerID: ownerID,
                    result: result,
                    makeUndoOwnerID: { uuid() },
                    state: &state,
                )

            case let .internal(.undoManagerEventReceived(event)):
                return routeUndoManagerEvent(event, state: &state)

            case let .internal(.routeContent(tabID, contentAction)):
                return routeContentAction(
                    contentAction,
                    tabID: tabID,
                    makeFallbackRequestID: { uuid() },
                    undoManagerClient: undoManagerClient,
                    state: &state,
                )

            case let .closeContentTabRequested(tabID):
                guard state.canStartSelectedContentTabClose else { return .none }
                return handleCloseContentTabRequested(tabID: tabID, state: &state)

            case let .closeContentTabRequestedWithSource(tabID, source):
                guard state.canStartSelectedContentTabClose else { return .none }
                return handleCloseContentTabRequested(tabID: tabID, state: &state, source: source)

            case let .contentTabCloseAlertResponse(choice):
                guard state.pendingSelectedContentTabClose == nil else { return .none }
                return handleContentTabCloseAlertResponse(choice: choice, state: &state)

            case let .selectedContentTabCloseAlertResponse(operationID, tabID, choice):
                guard isCurrentSelectedContentTabClose(
                    operationID: operationID,
                    tabID: tabID,
                    state: state,
                ) else { return .none }
                return handleContentTabCloseAlertResponse(choice: choice, state: &state)

            case let .tabContent(tabID, .collection(.saveCompleted(.success))):
                guard state.pendingSelectedContentTabClose == nil,
                      state.pendingContentTabClose?.tabID == tabID,
                      state.contentTabs.activeTabID == tabID
                else { return .none }
                return .none

            case let .tabContent(tabID, .composer(.internal(.syncCollectionState))):
                guard state.pendingSelectedContentTabClose == nil,
                      state.pendingContentTabClose?.tabID == tabID,
                      state.contentTabs.activeTabID == tabID
                else { return .none }
                state.pendingContentTabClose?.didReceiveWriteBackComposerSync = true
                return finalizePendingContentTabCloseIfWriteBackEffectsCompleted(state: &state)

            case let .performBatchCloseContentAction(
                operationID,
                tabID,
                .collection(.saveCompleted(.success)),
            ):
                guard isCurrentSelectedContentTabClose(
                    operationID: operationID,
                    tabID: tabID,
                    state: state,
                ) else { return .none }
                return .none

            case let .performBatchCloseContentAction(
                operationID,
                tabID,
                .composer(.internal(.syncCollectionState)),
            ):
                guard isCurrentSelectedContentTabClose(
                    operationID: operationID,
                    tabID: tabID,
                    state: state,
                ) else { return .none }
                state.pendingContentTabClose?.didReceiveWriteBackComposerSync = true
                return finalizePendingContentTabCloseIfWriteBackEffectsCompleted(state: &state)

            case let .navigation(.internal(.setNavigationState(navigationState))):
                let pendingCloseEffect: Effect<Action>
                if let pendingTabID = state.pendingContentTabClose?.tabID,
                   state.contentTabs.activeTabID == pendingTabID
                {
                    state.pendingContentTabClose?.didReceiveWriteBackNavigationState = true
                    pendingCloseEffect = finalizePendingContentTabCloseIfWriteBackEffectsCompleted(state: &state)
                } else {
                    pendingCloseEffect = .none
                }

                let pinnedCollectionFanOutEffect: Effect<Action> = if case let .collection(collectionNavigation) =
                    navigationState,
                    case .file = collectionNavigation.kind
                {
                    syncPinnedContentTabRuntimeNavigationEffect(
                        navigationState,
                        state: state,
                        computerName: fileManagerClient.displayName("/"),
                    )
                } else {
                    .none
                }
                return .merge(pendingCloseEffect, pinnedCollectionFanOutEffect)

            case let .performBatchCloseNavigationAction(
                operationID,
                tabID,
                .internal(.setNavigationState),
            ):
                guard isCurrentSelectedContentTabClose(
                    operationID: operationID,
                    tabID: tabID,
                    state: state,
                ) else { return .none }
                state.pendingContentTabClose?.didReceiveWriteBackNavigationState = true
                return finalizePendingContentTabCloseIfWriteBackEffectsCompleted(state: &state)

            // Delete/rename 결과는 동일 session의 모든 tab/background owner에 적용되는 session-global event다.
            case let .tabContent(tabID, .aiChat(.deleteSessionTapped(sessionID))):
                guard fileManagerContentState(for: tabID, state: state) != nil else { return .none }
                return cancelAndRemoveBackgroundAiChatOwners(sessionID: sessionID, state: &state)

            case let .inspector(.aiChat(.deleteSessionTapped(sessionID))):
                return cancelAndRemoveBackgroundAiChatOwners(sessionID: sessionID, state: &state)

            case let .tabContent(tabID, .aiChat(.sessionDeleteSucceeded(sessionID))):
                guard fileManagerContentState(for: tabID, state: state) != nil else { return .none }
                propagateAiChatSessionDeleteSucceeded(sessionID: sessionID, state: &state)
                return .none

            case let .inspector(.aiChat(.sessionDeleteSucceeded(sessionID))):
                propagateAiChatSessionDeleteSucceeded(sessionID: sessionID, state: &state)
                return .none

            case let .tabContent(tabID, .aiChat(.sessionDeleteFailed(sessionID, _))):
                guard fileManagerContentState(for: tabID, state: state) != nil else { return .none }
                state.removeBackgroundAiChatState(sessionID: sessionID)
                state.removeBackgroundInspectorAiChatState(sessionID: sessionID)
                return .none

            case let .inspector(.aiChat(.sessionDeleteFailed(sessionID, _))):
                state.removeBackgroundAiChatState(sessionID: sessionID)
                state.removeBackgroundInspectorAiChatState(sessionID: sessionID)
                return .none

            case let .tabContent(tabID, .aiChat(.sessionRenameSucceeded(summary, customTitle))):
                guard fileManagerContentState(for: tabID, state: state) != nil else { return .none }
                refreshAiChatCustomTitle(summary: summary, customTitle: customTitle, state: &state)
                state.updateAiChatTabTitle(sessionID: summary.sessionID, title: summary.title)
                return .none

            case let .inspector(.aiChat(.sessionRenameSucceeded(summary, customTitle))):
                refreshAiChatCustomTitle(summary: summary, customTitle: customTitle, state: &state)
                state.updateAiChatTabTitle(sessionID: summary.sessionID, title: summary.title)
                return .none

            case let .content(.aiChat(aiChatAction)):
                guard let activeTabID = state.contentTabs.activeTabID else { return .none }
                return routeOriginAiChatAction(
                    tabID: activeTabID,
                    aiChatAction: aiChatAction,
                    originContent: state.content,
                    state: &state,
                )

            case let .tabContent(tabID, .aiChat(aiChatAction)):
                guard let originContent = fileManagerContentState(for: tabID, state: state) else { return .none }
                return routeOriginAiChatAction(
                    tabID: tabID,
                    aiChatAction: aiChatAction,
                    originContent: originContent,
                    state: &state,
                )

            case let .backgroundAiChat(aiChatAction):
                let snapshotSessionID = sessionSnapshotSavedSummary(from: aiChatAction)?.sessionID
                let effect = routeBackgroundAiChatAction(aiChatAction, state: &state)
                if let snapshotSessionID {
                    state.refreshAiChatTabTitleFromCanonicalSummary(sessionID: snapshotSessionID)
                }
                return effect

            case let .backgroundAiChatSnapshotPersisted(snapshot):
                handleBackgroundAiChatSnapshotPersisted(snapshot, state: &state)
                return .none

            case let .inspector(.aiChat(aiChatAction)):
                let snapshotSessionID = sessionSnapshotSavedSummary(from: aiChatAction)?.sessionID
                let effect = routeInactiveInspectorAiChatAction(aiChatAction, state: &state)
                refreshAiChatFollowUpFromBackgroundIfNeeded(
                    aiChatAction,
                    backgroundAiChat: state.inspector.aiChat,
                    state: &state,
                    skipsActiveInspector: true,
                )
                if let snapshotSessionID {
                    state.refreshAiChatTabTitleFromCanonicalSummary(sessionID: snapshotSessionID)
                }
                return effect

            case let .backgroundInspectorAiChat(aiChatAction):
                let snapshotSessionID = sessionSnapshotSavedSummary(from: aiChatAction)?.sessionID
                let effect = routeInactiveInspectorAiChatAction(aiChatAction, state: &state)
                if let snapshotSessionID {
                    state.refreshAiChatTabTitleFromCanonicalSummary(sessionID: snapshotSessionID)
                }
                return effect

            case let .backgroundInspectorSnapshotPersisted(snapshot):
                handleBackgroundInspectorAiChatSnapshotPersisted(snapshot, state: &state)
                return .none

            case let .tabContent(tabID, .collection(.saveCompleted(.failure))):
                guard state.pendingSelectedContentTabClose == nil,
                      state.pendingContentTabClose?.tabID == tabID,
                      state.contentTabs.activeTabID == tabID
                else { return .none }
                state.pendingContentTabClose?.didReceiveSaveCompletedFailure = true
                return finalizePendingContentTabCloseFailureIfReady(state: &state)

            case let .tabContent(tabID, .collection(.savePanelResponse(nil))):
                guard state.pendingSelectedContentTabClose == nil,
                      state.pendingContentTabClose?.tabID == tabID,
                      state.contentTabs.activeTabID == tabID
                else { return .none }
                return finishPendingContentTabCloseWithoutClosing(outcome: .cancelled, state: &state)

            case let .tabContent(tabID, .collection(.writeBackFailed)):
                guard state.pendingSelectedContentTabClose == nil,
                      state.pendingContentTabClose?.tabID == tabID,
                      state.contentTabs.activeTabID == tabID
                else { return .none }
                state.pendingContentTabClose?.didReceiveWriteBackFailure = true
                return finalizePendingContentTabCloseFailureIfReady(state: &state)

            case let .tabContent(tabID, .collection(.delegate(.saveFeedback(feedback)))):
                guard state.pendingSelectedContentTabClose == nil,
                      state.pendingContentTabClose?.tabID == tabID,
                      state.contentTabs.activeTabID == tabID
                else { return .none }
                recordPendingContentTabCloseSaveFeedback(feedback, state: &state)
                return finalizePendingContentTabCloseFailureIfReady(state: &state)

            case let .performBatchCloseContentAction(
                operationID,
                tabID,
                .collection(.saveCompleted(.failure)),
            ):
                guard isCurrentSelectedContentTabClose(
                    operationID: operationID,
                    tabID: tabID,
                    state: state,
                ) else { return .none }
                state.pendingContentTabClose?.didReceiveSaveCompletedFailure = true
                return finalizePendingContentTabCloseFailureIfReady(state: &state)

            case let .performBatchCloseContentAction(
                operationID,
                tabID,
                .collection(.savePanelResponse(nil)),
            ):
                guard isCurrentSelectedContentTabClose(
                    operationID: operationID,
                    tabID: tabID,
                    state: state,
                ) else { return .none }
                return finishPendingContentTabCloseWithoutClosing(outcome: .cancelled, state: &state)

            case let .performBatchCloseContentAction(
                operationID,
                tabID,
                .collection(.writeBackFailed),
            ):
                guard isCurrentSelectedContentTabClose(
                    operationID: operationID,
                    tabID: tabID,
                    state: state,
                ) else { return .none }
                state.pendingContentTabClose?.didReceiveWriteBackFailure = true
                return finalizePendingContentTabCloseFailureIfReady(state: &state)

            case let .performBatchCloseContentAction(
                operationID,
                tabID,
                .collection(.delegate(.saveFeedback(feedback))),
            ):
                guard isCurrentSelectedContentTabClose(
                    operationID: operationID,
                    tabID: tabID,
                    state: state,
                ) else { return .none }
                recordPendingContentTabCloseSaveFeedback(feedback, state: &state)
                return finalizePendingContentTabCloseFailureIfReady(state: &state)

            default:
                return .none
            }
        }
    }
}
