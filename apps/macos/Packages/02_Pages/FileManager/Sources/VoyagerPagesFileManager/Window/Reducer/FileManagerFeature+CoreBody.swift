import ComposableArchitecture
import VoyagerFeaturesContentPageNavigation
import VoyagerFeaturesEntryOperations

extension FileManagerFeature {
    @ReducerBuilder<State, Action> var coreBody: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case let .content(contentAction):
                guard state.pendingSelectedContentTabClose == nil
                    || !isComposerSaveRequest(contentAction)
                else { return .none }
                guard let activeTabID = state.contentTabs.activeTabID,
                      state.contentTabs.tabs[id: activeTabID] != nil
                else { return .none }
                let generation = undoManagerGeneration(tabID: activeTabID, state: state)
                let effect = FileManagerContentFeature().reduce(
                    into: &state.content,
                    action: contentAction,
                )
                return effect.map {
                    Self.routeContentEffectAction(
                        $0,
                        tabID: activeTabID,
                        undoManagerGeneration: generation,
                    )
                }

            case let .tabContent(tabID, contentAction):
                guard state.contentTabs.tabs[id: tabID] != nil else { return .none }

                let generation = undoManagerGeneration(tabID: tabID, state: state)
                let isActiveTab = state.contentTabs.activeTabID == tabID
                guard var contentState = isActiveTab ? state.content : state.tabContentStates[tabID] else {
                    return .none
                }
                let effect = FileManagerContentFeature().reduce(
                    into: &contentState,
                    action: contentAction,
                )
                if isActiveTab {
                    state.content = contentState
                }
                state.tabContentStates[tabID] = contentState
                return effect.map {
                    Self.routeContentEffectAction(
                        $0,
                        tabID: tabID,
                        undoManagerGeneration: generation,
                    )
                }

            case let .performSelectedContentTabCloseMutation(operationID, tabID, .close):
                guard state.pendingSelectedContentTabClose?.operationID == operationID else { return .none }
                return requestTopNavigationClose(tabID: tabID, state: &state)

            case let .performSelectedContentTabPinMutation(operationID, tabID, .pin(requestedTabID, placement)):
                guard requestedTabID == tabID,
                      state.pendingSelectedContentTabPinMutation?.operationID == operationID,
                      state.pendingSelectedContentTabPinMutation?.currentTabID == tabID
                else { return .none }
                guard requestTopNavigationPin(tabID: tabID, placement: placement, state: &state) else {
                    return .send(.selectedPinMutationItemCompleted(
                        operationID: operationID,
                        tabID: tabID,
                        outcome: .remaining,
                    ))
                }
                return .none

            case let .performSelectedContentTabPinMutation(operationID, tabID, .unpin(requestedTabID, placement)):
                guard requestedTabID == tabID,
                      state.pendingSelectedContentTabPinMutation?.operationID == operationID,
                      state.pendingSelectedContentTabPinMutation?.currentTabID == tabID
                else { return .none }
                guard prepareTopNavigationUnpin(tabID: tabID, placement: placement, state: &state) else {
                    return .send(.selectedPinMutationItemCompleted(
                        operationID: operationID,
                        tabID: tabID,
                        outcome: .remaining,
                    ))
                }
                return .none

            case let .performSelectedContentTabPinMutation(
                operationID, tabID, .delegate(.persistPinnedRecord(request)),
            ):
                guard !state.isClosing,
                      let pending = state.pendingSelectedContentTabPinMutation,
                      pending.operationID == operationID,
                      pending.currentTabID == tabID,
                      let rollback = pending.currentItemRollbackSnapshot
                else { return .none }
                let rebasedRequest = ContentTabPinnedRecordPersistenceRequest(
                    tabID: request.tabID,
                    context: request.context,
                    rollback: rollback,
                    mutation: request.mutation,
                    persistenceScopeID: request.persistenceScopeID,
                )
                return forwardPinnedRecordPersistence(
                    rebasedRequest,
                    source: .selectedPin(operationID: operationID),
                    state: &state,
                )

            case let .performSelectedContentTabCloseMutation(
                operationID, _, .delegate(.persistPinnedRecord(request)),
            ):
                return forwardPinnedRecordPersistence(
                    request,
                    source: .selectedClose(operationID: operationID),
                    state: &state,
                )

            case let .performSelectedContentTabCloseMutation(
                _, tabID, .pinnedRecordSaveSucceeded(_, context),
            ):
                return completeTopNavigationLifecycleIfNeeded(
                    tabID: tabID, context: context, terminal: nil, state: &state,
                )

            case let .performSelectedContentTabCloseMutation(
                _, tabID, .pinnedRecordSaveFailed(_, context, _),
            ):
                return completeTopNavigationLifecycleIfNeeded(
                    tabID: tabID, context: context, terminal: .failed(.save), state: &state,
                )

            case let .performSelectedContentTabCloseMutation(
                _, tabID, .pinnedRecordStoreUnavailable(_, context, failure, _),
            ):
                return completeTopNavigationLifecycleIfNeeded(
                    tabID: tabID,
                    context: context,
                    terminal: .failed(.storeUnavailable(failure)),
                    state: &state,
                )

            case let .performSelectedContentTabCloseMutation(
                _, tabID, .pinnedRecordSaveNotApplied(_, context, reason, _),
            ):
                let failure: FileManagerTopNavigationIntentFailure = switch reason {
                case .superseded: .superseded
                case .cancelled: .cancelled
                }
                return completeTopNavigationLifecycleIfNeeded(
                    tabID: tabID, context: context, terminal: .failed(failure), state: &state,
                )

            case let .closeContentTabRequested(tabID):
                guard state.contentTabMoveParticipantRequestID == nil,
                      state.pendingSelectedContentTabClose == nil
                else { return .none }
                return requestTopNavigationClose(tabID: tabID, state: &state)

            case let .contentTabs(.delegate(.persistPinnedRecord(request))):
                guard state.contentTabMoveParticipantRequestID == nil else { return .none }
                return forwardPinnedRecordPersistence(
                    request,
                    source: .contentTab,
                    state: &state,
                )

            case let .contentTabs(.pin(tabID, placement)):
                guard state.contentTabMoveParticipantRequestID == nil,
                      state.pendingSelectedContentTabClose == nil,
                      state.pendingSelectedContentTabPinMutation == nil
                else { return .none }
                _ = requestTopNavigationPin(tabID: tabID, placement: placement, state: &state)
                return .none

            case let .contentTabs(.unpin(tabID, placement)):
                guard state.contentTabMoveParticipantRequestID == nil,
                      state.pendingSelectedContentTabClose == nil,
                      state.pendingSelectedContentTabPinMutation == nil
                else { return .none }
                _ = prepareTopNavigationUnpin(tabID: tabID, placement: placement, state: &state)
                return .none

            case let .contentTabs(.updateActivePageAnchor(tabID, anchor)):
                guard state.contentTabMoveParticipantRequestID == nil else { return .none }
                prepareTopNavigationUpdate(tabID: tabID, anchor: anchor, state: &state)
                return .none

            case let .contentTabs(.commitClose(tabID)):
                guard state.contentTabMoveParticipantRequestID == nil,
                      state.pendingSelectedContentTabClose == nil
                else { return .none }
                guard !state.contentTabs.pendingPinnedRecordIDs.contains(tabID) else { return .none }
                state.dormantContentTabSlots.removeAll { $0.id == tabID }
                state.pendingTopNavigationIntents.removeAll { pending in
                    switch pending.intent {
                    case let .pin(id, _), let .unpin(id), let .close(id), let .update(id):
                        id == tabID
                    case .move, .movePinnedGroup:
                        false
                    }
                }
                state.replayTopNavigationOverlays()
                return .none

            case let .contentTabs(contentTabAction) where isPinnedRecordPersistenceTerminal(contentTabAction):
                return completeContentTabPinnedRecordPersistence(
                    action: contentTabAction,
                    state: &state,
                )

            case let .topNavigationMoveRequested(source, destination):
                guard state.contentTabMoveParticipantRequestID == nil else { return .none }
                return requestTopNavigationMove(
                    source: source,
                    destination: destination,
                    state: &state,
                )

            case let .internal(.topNavigationIntentCompleted(token, terminal)):
                return completeTopNavigationIntent(token: token, terminal: terminal, state: &state)

            case let .internal(.pinnedRecordPersistenceCompleted(token, source, request, terminal)):
                return completePinnedRecordPersistence(
                    token: token,
                    source: source,
                    request: request,
                    terminal: terminal,
                    state: &state,
                )

            case let .applyBootstrap(bootstrap):
                state.applyBootstrap(bootstrap)
                return .none

            case let .applyExternalCommittedTopNavigationOrder(order, revision):
                if let revision,
                   state.lastConfirmedTopNavigationCommitRevision.map({ revision < $0 }) == true
                {
                    return .none
                }
                state.lastConfirmedTopNavigationOrder = order
                state.lastConfirmedTopNavigationCommitRevision = revision
                state.topNavigationArrangementAvailability = .available
                state.topNavigationArrangementPresentation = nil
                state.replayTopNavigationOverlays()
                return .none

            case let .applyCommittedTopNavigationSnapshot(order, revision, pinnedContentTabs):
                guard state.lastConfirmedTopNavigationCommitRevision.map({ revision >= $0 }) != false else {
                    return .none
                }
                if let pinnedContentTabs {
                    state.applyPinnedContentTabs(pinnedContentTabs, mode: .authoritative)
                }
                state.lastConfirmedTopNavigationOrder = order
                state.lastConfirmedTopNavigationCommitRevision = revision
                state.topNavigationArrangementAvailability = .available
                state.topNavigationArrangementPresentation = nil
                state.replayTopNavigationOverlays()
                return .none

            case let .applyFixedLocationItems(items):
                state.applyFixedLocationItems(
                    items,
                    hiddenLocationIDs: state.sidebar.hiddenFixedLocationItemIDs,
                )
                return .none

            case let .applyUnavailableTopNavigationArrangement(failure):
                state.topNavigationArrangementAvailability = .unavailable(failure)
                state.topNavigationArrangementPresentation = .loadUnavailable
                return .none

            case let .internal(.entryActionCompleted(tabID, record, expectedGeneration)):
                guard record.operationKind.isUndoable,
                      let expectedGeneration,
                      undoManagerGeneration(tabID: tabID, state: state) == expectedGeneration,
                      state.contentTabs.tabs[id: tabID] != nil,
                      let windowID = state.windowID
                else { return .none }

                let scope = UndoManagerScope(windowID: windowID, contentTabID: tabID.rawValue)
                let isActiveTab = state.contentTabs.activeTabID == tabID
                guard var contentState = isActiveTab ? state.content : state.tabContentStates[tabID] else {
                    return .none
                }
                let ownerID = contentState.entryViewLayout.entryOperations.undoOwnerID
                guard fileOperationUndoManagerClient.registerUndoWithOwner(
                    scope,
                    expectedGeneration,
                    ownerID,
                    record,
                ) else {
                    clearLogicalUndoHistory(tabID: tabID, state: &state)
                    return .none
                }
                let effect = FileManagerContentFeature().reduce(
                    into: &contentState,
                    action: .entryViewLayout(.entryOperations(.lifecycle(.entryActionCompleted(record)))),
                )
                if isActiveTab {
                    state.content = contentState
                }
                state.tabContentStates[tabID] = contentState
                return effect.map { .tabContent(tabID: tabID, action: $0) }

            default:
                return .none
            }
        }

        Scope(state: \.content.navigation, action: \.navigation) {
            ContentPageNavigationFeature()
        }

        Scope(state: \.sidebarEntryDropOperations, action: \.internal.sidebarEntryDrop) {
            EntryOperationsFeature()
        }

        Scope(state: \.sidebar, action: \.sidebar) {
            FileManagerSidebarFeature()
        }

        Scope(state: \.inspector, action: \.inspector) {
            FileManagerInspectorFeature()
        }

        Reduce { state, action in
            switch action {
            case let .performBatchCloseContentAction(operationID, tabID, contentAction):
                guard state.isCurrentSelectedContentTabClose(operationID: operationID, tabID: tabID) else {
                    return .none
                }
                return FileManagerContentFeature()
                    .reduce(into: &state.content, action: contentAction)
                    .map {
                        .performBatchCloseContentAction(
                            operationID: operationID,
                            tabID: tabID,
                            action: $0,
                        )
                    }
                    .cancellable(id: SelectedContentTabCloseOperationCancelID(operationID: operationID))

            case let .performBatchCloseNavigationAction(operationID, tabID, navigationAction):
                guard state.isCurrentSelectedContentTabClose(operationID: operationID, tabID: tabID) else {
                    return .none
                }
                return ContentPageNavigationFeature()
                    .reduce(into: &state.content.navigation, action: navigationAction)
                    .map {
                        .performBatchCloseNavigationAction(
                            operationID: operationID,
                            tabID: tabID,
                            action: $0,
                        )
                    }
                    .cancellable(id: SelectedContentTabCloseOperationCancelID(operationID: operationID))

            case let .contentTabs(contentTabAction):
                guard state.contentTabMoveParticipantRequestID == nil else { return .none }
                if let pending = state.pendingSelectedContentTabPinMutation,
                   let currentTabID = pending.currentTabID,
                   isSelectedContentTabPinMutationPersistenceReplacement(contentTabAction, for: currentTabID)
                {
                    return .send(.performSelectedContentTabPinMutation(
                        operationID: pending.operationID,
                        tabID: currentTabID,
                        action: contentTabAction,
                    ))
                }
                guard state.pendingSelectedContentTabClose == nil
                    || isSelectionAllowedDuringBatchClose(contentTabAction)
                else { return .none }
                guard state.pendingSelectedContentTabPinMutation == nil
                    || (!isDirectPinMutation(contentTabAction) && !isDirectCloseMutation(contentTabAction))
                else { return .none }
                return reduceContentTabAction(contentTabAction, state: &state)

            case let .performSelectedContentTabPinMutation(operationID, tabID, contentTabAction):
                guard !state.isClosing,
                      let pending = state.pendingSelectedContentTabPinMutation,
                      pending.operationID == operationID,
                      pending.currentTabID == tabID,
                      !isDirectPinMutation(contentTabAction)
                      || pending.currentTopNavigationToken != nil,
                      !isStalePinnedRecordPersistenceResult(contentTabAction, in: state.contentTabs),
                      isCorrelatedSelectedContentTabPinMutation(
                          contentTabAction,
                          for: tabID,
                          target: pending.target,
                      )
                else { return .none }
                let previousActiveTabID = state.contentTabs.previousActiveTabID
                let childEffect = withDependencies {
                    $0.contentTabPinnedRecordPersistenceRouting = pinnedRecordPersistenceRouting(
                        state: state,
                    )
                } operation: {
                    ContentTabFeature().reduce(
                        into: &state.contentTabs,
                        action: contentTabAction,
                    )
                }
                state.contentTabs.previousActiveTabID = previousActiveTabID
                state.syncContentTabSidebarItems()
                let rollback = pending.currentItemRollbackSnapshot
                return childEffect.map {
                    .performSelectedContentTabPinMutation(
                        operationID: operationID,
                        tabID: tabID,
                        action: rebasingPinnedRecordRollback($0, to: rollback),
                    )
                }
                .cancellable(id: SelectedContentTabPinMutationOperationCancelID(operationID: operationID))

            case let .performSelectedContentTabCloseMutation(operationID, tabID, contentTabAction):
                guard !state.isClosing,
                      let pending = state.pendingSelectedContentTabClose,
                      pending.operationID == operationID,
                      pending.currentTabID == tabID,
                      !isStalePinnedRecordPersistenceResult(contentTabAction, in: state.contentTabs),
                      isCorrelatedSelectedContentTabCloseMutation(contentTabAction, for: tabID)
                else { return .none }
                let childEffect = withDependencies {
                    $0.contentTabPinnedRecordPersistenceRouting = pinnedRecordPersistenceRouting(
                        state: state,
                    )
                } operation: {
                    ContentTabFeature().reduce(
                        into: &state.contentTabs,
                        action: contentTabAction,
                    )
                }
                return childEffect.map {
                    .performSelectedContentTabCloseMutation(
                        operationID: operationID,
                        tabID: tabID,
                        action: $0,
                    )
                }
                .cancellable(id: SelectedContentTabCloseOperationCancelID(operationID: operationID))

            default:
                return .none
            }
        }

        FileManagerWindowAiChatSelectionReducer()

        FileManagerWindowNavigationReducer()
        FileManagerWindowLifecycleReducer()
        FileManagerWindowPreferencesReducer()
        FileManagerWindowContentTabMoveReducer()
        FileManagerWindowRoutingReducer()
        FileManagerWindowUndoRoutingReducer()
        Reduce { state, action in
            if state.contentTabMoveParticipantRequestID != nil,
               case .request(.restoreLastClosedContentTab) = action
            {
                return .none
            }
            return FileManagerWindowCommandRoutingReducer().reduce(into: &state, action: action)
        }

        Reduce { state, action in
            switch action {
            case let .contentTabs(.updateActivePageAnchor(tabID, _))
                where state.contentTabs.activeTabID == tabID:
                state.syncActiveTabInspectorState()
            case .inspector:
                state.syncActiveTabInspectorState()
            default:
                break
            }
            return .none
        }
    }
}
