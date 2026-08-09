import ComposableArchitecture
import Foundation
import VoyagerFeaturesContentPageNavigation
import VoyagerFeaturesEntryOperations

@Reducer
public struct FileManagerFeature {
    public typealias State = FileManagerWindowState
    public typealias Action = FileManagerWindowAction

    public init() {}

    @Dependency(\.fileOperationUndoManagerClient)
    private var fileOperationUndoManagerClient
    @Dependency(\.contentTabPinnedRecordClient)
    private var contentTabPinnedRecordClient
    @Dependency(\.fileManagerPinnedRecordOwner)
    private var pinnedRecordPersistenceOwnership
    @Dependency(\.userDefaultsClient)
    private var userDefaultsClient

    public var body: some Reducer<State, Action> {
        Reduce { state, action in
            guard state.contentTabMoveParticipantRequestID == nil
                || isContentTabMoveParticipantActionAllowed(action)
            else { return .none }
            return coreBody.reduce(into: &state, action: action)
        }
    }

    @ReducerBuilder<State, Action> private var coreBody: some Reducer<State, Action> {
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
                guard fileOperationUndoManagerClient.registerUndo(scope, expectedGeneration, record) else {
                    clearLogicalUndoHistory(tabID: tabID, state: &state)
                    return .none
                }

                let isActiveTab = state.contentTabs.activeTabID == tabID
                guard var contentState = isActiveTab ? state.content : state.tabContentStates[tabID] else {
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

    private func isContentTabMoveParticipantActionAllowed(_ action: Action) -> Bool {
        switch action {
        case .applyCommittedTopNavigationSnapshot,
             .applyExternalCommittedTopNavigationOrder,
             .contentTabMoveSucceeded,
             .contentTabMoveRejected:
            true

        case .tabContent(_, .internal(.applyNavigationState)),
             .tabContent(_, .internal(.startObservingSystemNotifications)),
             .tabContent(_, .internal(.stopObservingSystemNotifications)):
            true

        default:
            false
        }
    }
}

extension FileManagerFeature {
    private func requestTopNavigationPin(
        tabID: ContentTabID,
        placement: ContentTabPlacement?,
        state: inout State,
    ) -> Bool {
        guard case .valid = ContentTabPinMutationPreflight.pin(
            id: tabID,
            placement: placement,
            state: state.contentTabs,
        ) else { return false }
        let dormantSlot = state.dormantContentTabSlots.first { $0.id == tabID }
        let optimisticOrder: FileManagerTopNavigationOrder
        if let placement {
            guard let projectedOrder = FileManagerTopNavigationOrderPolicy.insertingContentTab(
                tabID,
                at: placement,
                in: state.optimisticTopNavigationOrder,
            ) else { return false }
            optimisticOrder = projectedOrder
        } else {
            optimisticOrder = FileManagerTopNavigationOrderPolicy.insertingPinnedItem(
                tabID,
                into: state.optimisticTopNavigationOrder,
                dormantSlot: dormantSlot,
            )
        }
        let token = contentTabPinnedRecordClient.reserveTopNavigationOperationToken()
        state.pendingTopNavigationIntents.append(.init(token: token, intent: .pin(tabID, placement: placement)))
        if state.pendingSelectedContentTabPinMutation?.currentTabID == tabID {
            state.pendingSelectedContentTabPinMutation?.currentTopNavigationToken = token
        }
        state.optimisticTopNavigationOrder = optimisticOrder
        return true
    }

    private func prepareTopNavigationUnpin(
        tabID: ContentTabID,
        placement: ContentTabPlacement?,
        state: inout State,
    ) -> Bool {
        guard ContentTabPinMutationPreflight.unpin(
            id: tabID,
            placement: placement,
            state: state.contentTabs,
        ) != nil else { return false }
        let item = FileManagerTopNavigationItemID.contentTab(tabID)
        guard let index = state.optimisticTopNavigationOrder.items.firstIndex(of: item) else { return false }
        let items = state.optimisticTopNavigationOrder.items
        let slot = FileManagerTopNavigationOrderPolicy.DormantContentTabSlot(
            id: tabID,
            before: index > items.startIndex ? items[index - 1] : nil,
            after: index + 1 < items.endIndex ? items[index + 1] : nil,
        )
        state.dormantContentTabSlots.removeAll { $0.id == tabID }
        state.dormantContentTabSlots.append(slot)
        let token = contentTabPinnedRecordClient.reserveTopNavigationOperationToken()
        state.pendingTopNavigationIntents.append(.init(token: token, intent: .unpin(tabID)))
        if state.pendingSelectedContentTabPinMutation?.currentTabID == tabID {
            state.pendingSelectedContentTabPinMutation?.currentTopNavigationToken = token
        }
        state.optimisticTopNavigationOrder = .init(items: items.filter { $0 != item })
        return true
    }

    private func requestTopNavigationClose(
        tabID: ContentTabID,
        state: inout State,
    ) -> Effect<Action> {
        guard !state.contentTabs.pendingPinnedRecordIDs.contains(tabID) else { return .none }
        state.dormantContentTabSlots.removeAll { $0.id == tabID }
        guard state.contentTabs.tabs[id: tabID]?.isPinned == true else {
            state.replayTopNavigationOverlays()
            return .none
        }
        let token = contentTabPinnedRecordClient.reserveTopNavigationOperationToken()
        state.pendingTopNavigationIntents.append(.init(token: token, intent: .close(tabID)))
        state.optimisticTopNavigationOrder = .init(items: state.optimisticTopNavigationOrder.items.filter {
            $0 != .contentTab(tabID)
        })
        return .none
    }

    private func prepareTopNavigationUpdate(
        tabID: ContentTabID,
        anchor: ContentTabPageAnchor,
        state: inout State,
    ) {
        guard state.contentTabs.tabs[id: tabID]?.isPinned == true,
              anchor.supportsPinnedRecordPersistence
        else { return }
        let token = contentTabPinnedRecordClient.reserveTopNavigationOperationToken()
        state.pendingTopNavigationIntents.append(.init(token: token, intent: .update(tabID)))
    }

    private func completeTopNavigationLifecycleIfNeeded(
        tabID: ContentTabID,
        context: ContentTabPinnedRecordTerminalContext,
        terminal: FileManagerTopNavigationIntentTerminal?,
        state: inout State,
    ) -> Effect<Action> {
        guard state.contentTabs.isCurrentPinnedRecordPersistenceIntent(
            tabID: tabID,
            intentID: context.intentID,
        ) else { return .none }
        guard let pending = state.pendingTopNavigationIntents.last(where: { candidate in
            switch candidate.intent {
            case let .pin(id, _), let .unpin(id), let .close(id), let .update(id): id == tabID
            case .move, .movePinnedGroup: false
            }
        }) else {
            if case let .failed(.storeUnavailable(failure)) = terminal {
                state.topNavigationArrangementAvailability = .unavailable(failure)
                state.topNavigationArrangementPresentation = .init(failure: .storeUnavailable(failure))
            }
            return .none
        }

        let resolvedTerminal = resolveTopNavigationTerminal(terminal, state: state)
        let intent = pending.intent
        switch (intent, resolvedTerminal) {
        case (.pin(_, _), .committed(_)):
            state.dormantContentTabSlots.removeAll { $0.id == tabID }
        case (.unpin(_), .failed(_)):
            state.dormantContentTabSlots.removeAll { $0.id == tabID }
        default:
            break
        }
        _ = completeTopNavigationIntent(token: pending.token, terminal: resolvedTerminal, state: &state)
        state.replayTopNavigationOverlays()
        return closeTopNavigationLifecycleEffect(
            intent: intent,
            terminal: resolvedTerminal,
            tabID: tabID,
            context: context,
            state: state,
        )
    }

    private func completeContentTabPinnedRecordPersistence(
        action: ContentTabAction,
        state: inout State,
    ) -> Effect<Action> {
        guard let result = pinnedRecordPersistenceResult(action) else { return .none }
        return completeTopNavigationLifecycleIfNeeded(
            tabID: result.tabID,
            context: result.context,
            terminal: result.terminal,
            state: &state,
        )
    }

    private func resolveTopNavigationTerminal(
        _ terminal: FileManagerTopNavigationIntentTerminal?,
        state: State,
    ) -> FileManagerTopNavigationIntentTerminal {
        if let terminal { return terminal }
        do {
            let commit = try contentTabPinnedRecordClient.loadTopNavigationCommit(
                userDefaultsClient,
                state.sidebar.allFixedLocationItems.map(\.id),
            )
            return .committed(commit)
        } catch let error as ContentTabPinnedRecordStoreLoadError {
            let failure: FileManagerTopNavigationArrangementLoadFailure = switch error {
            case .corruptUnavailable: .corrupt
            case let .futureSchemaUnavailable(schemaVersion): .unsupportedSchema(schemaVersion)
            }
            return .failed(.storeUnavailable(failure))
        } catch {
            return .failed(.save)
        }
    }

    private func closeTopNavigationLifecycleEffect(
        intent: FileManagerTopNavigationIntent,
        terminal: FileManagerTopNavigationIntentTerminal,
        tabID: ContentTabID,
        context: ContentTabPinnedRecordTerminalContext,
        state: State,
    ) -> Effect<Action> {
        guard case .close = intent else { return .none }
        if let operationID = state.pendingContentTabClose?.batchOperationID {
            let outcome: SelectedContentTabCloseOutcome = switch terminal {
            case .committed:
                contentTabPinnedRecordClient.isCurrentMutationGeneration(context.generation)
                    ? .unpinned
                    : .cancelled
            case .failed(.save), .failed(.storeUnavailable):
                .failed
            case .failed(.superseded), .failed(.cancelled):
                .cancelled
            }
            return .send(.selectedContentTabCloseItemCompleted(
                operationID: operationID,
                tabID: tabID,
                outcome: outcome,
            ))
        }
        guard case .committed = terminal else { return .none }
        return .send(.contentTabs(.commitClose(tabID)))
    }

    private func forwardPinnedRecordPersistence(
        _ request: ContentTabPinnedRecordPersistenceRequest,
        source: FileManagerPinnedRecordPersistenceSource,
        state: inout State,
    ) -> Effect<Action> {
        guard let index = state.pendingTopNavigationIntents.lastIndex(where: { pending in
            guard pending.persistenceContext == nil else { return false }
            switch pending.intent {
            case let .pin(tabID, _), let .unpin(tabID), let .close(tabID), let .update(tabID):
                return tabID == request.tabID
            case .move, .movePinnedGroup:
                return false
            }
        }) else { return .none }

        state.pendingTopNavigationIntents[index].persistenceContext = request.context
        if case let .selectedPin(operationID) = source,
           state.pendingSelectedContentTabPinMutation?.operationID == operationID,
           state.pendingSelectedContentTabPinMutation?.currentTabID == request.tabID
        {
            state.pendingSelectedContentTabPinMutation?.currentPersistenceContext = request.context
        }
        return .send(.delegate(.persistPinnedRecordMutation(
            token: state.pendingTopNavigationIntents[index].token,
            source: source,
            request: request,
            discoveredLocationIDs: state.sidebar.allFixedLocationItems.map(\.id),
        )))
    }

    private func completePinnedRecordPersistence(
        token: FileManagerTopNavigationOperationToken,
        source: FileManagerPinnedRecordPersistenceSource,
        request: ContentTabPinnedRecordPersistenceRequest,
        terminal: FileManagerTopNavigationIntentTerminal,
        state: inout State,
    ) -> Effect<Action> {
        if case let .selectedPin(operationID) = source {
            guard let selectedPin = state.pendingSelectedContentTabPinMutation,
                  selectedPin.operationID == operationID,
                  selectedPin.currentTabID == request.tabID,
                  selectedPin.currentPersistenceContext == request.context,
                  selectedPin.currentTopNavigationToken == token
            else { return .none }
        }
        guard let pending = state.pendingTopNavigationIntents.first(where: { $0.token == token }) else {
            return .none
        }
        let isCurrentIntent = state.contentTabs.isCurrentPinnedRecordPersistenceIntent(
            tabID: request.tabID,
            intentID: request.context.intentID,
        )
        _ = completeTopNavigationIntent(
            token: token,
            terminal: terminal,
            state: &state,
            isCurrentTerminal: isCurrentIntent,
        )

        guard isCurrentIntent,
              state.contentTabs.tabs[id: request.tabID] != nil,
              isLivePersistenceSource(source, request: request, state: state)
        else { return .none }

        let childAction = pinnedRecordTerminalAction(request: request, terminal: terminal)
        let childEffect: Effect<Action> = switch source {
        case .contentTab:
            reduceContentTabAction(childAction, state: &state)
        case let .selectedPin(operationID):
            .send(.performSelectedContentTabPinMutation(
                operationID: operationID,
                tabID: request.tabID,
                action: childAction,
            ))
        case let .selectedClose(operationID):
            ContentTabFeature()
                .reduce(into: &state.contentTabs, action: childAction)
                .map {
                    .performSelectedContentTabCloseMutation(
                        operationID: operationID,
                        tabID: request.tabID,
                        action: $0,
                    )
                }
        }
        state.replayTopNavigationOverlays()
        let closeEffect = closeTopNavigationLifecycleEffect(
            intent: pending.intent,
            terminal: terminal,
            tabID: request.tabID,
            context: request.context,
            state: state,
        )
        return .concatenate(childEffect, closeEffect)
    }

    private func isLivePersistenceSource(
        _ source: FileManagerPinnedRecordPersistenceSource,
        request: ContentTabPinnedRecordPersistenceRequest,
        state: State,
    ) -> Bool {
        switch source {
        case .contentTab:
            true
        case let .selectedPin(operationID):
            state.pendingSelectedContentTabPinMutation?.operationID == operationID
                && state.pendingSelectedContentTabPinMutation?.currentTabID == request.tabID
        case let .selectedClose(operationID):
            state.isCurrentSelectedContentTabClose(
                operationID: operationID,
                tabID: request.tabID,
            )
        }
    }

    private func pinnedRecordTerminalAction(
        request: ContentTabPinnedRecordPersistenceRequest,
        terminal: FileManagerTopNavigationIntentTerminal,
    ) -> ContentTabAction {
        switch terminal {
        case .committed:
            .pinnedRecordSaveSucceeded(tabID: request.tabID, context: request.context)
        case .failed(.save):
            .pinnedRecordSaveFailed(
                tabID: request.tabID,
                context: request.context,
                rollback: request.rollback,
            )
        case let .failed(.storeUnavailable(failure)):
            .pinnedRecordStoreUnavailable(
                tabID: request.tabID,
                context: request.context,
                failure: failure,
                rollback: request.rollback,
            )
        case .failed(.superseded):
            .pinnedRecordSaveNotApplied(
                tabID: request.tabID,
                context: request.context,
                reason: .superseded,
                rollback: request.rollback,
            )
        case .failed(.cancelled):
            .pinnedRecordSaveNotApplied(
                tabID: request.tabID,
                context: request.context,
                reason: .cancelled,
                rollback: request.rollback,
            )
        }
    }

    private func requestTopNavigationMove(
        source: FileManagerTopNavigationItemID,
        destination: FileManagerTopNavigationMoveDestination,
        state: inout State,
    ) -> Effect<Action> {
        if case let .contentTab(sourceTabID) = source,
           let snapshot = state.sidebar.contentTabDragSnapshot,
           snapshot.lifecycle == .inFlight,
           snapshot.initiatingTabID == sourceTabID,
           snapshot.orderedTabIDs.contains(sourceTabID),
           snapshot.orderedTabIDs.count > 1
        {
            return requestTopNavigationPinnedGroupMove(
                orderedIDs: snapshot.orderedTabIDs,
                destination: destination,
                state: &state,
            )
        }

        let movedOrder = FileManagerTopNavigationOrderPolicy.moving(
            source,
            to: destination,
            in: state.optimisticTopNavigationOrder,
        )
        guard movedOrder != state.optimisticTopNavigationOrder else { return .none }

        let token = contentTabPinnedRecordClient.reserveTopNavigationOperationToken()
        state.pendingTopNavigationIntents.append(.init(
            token: token,
            intent: .move(source: source, destination: destination),
        ))
        state.optimisticTopNavigationOrder = movedOrder

        let discoveredLocationIDs = state.sidebar.allFixedLocationItems.map(\.id)
        return .send(.delegate(.persistTopNavigationMove(
            token: token,
            source: source,
            destination: destination,
            discoveredLocationIDs: discoveredLocationIDs,
        )))
    }

    private func requestTopNavigationPinnedGroupMove(
        orderedIDs: [ContentTabID],
        destination: FileManagerTopNavigationMoveDestination,
        state: inout State,
    ) -> Effect<Action> {
        guard Set(orderedIDs).count == orderedIDs.count,
              orderedIDs.allSatisfy({ state.contentTabs.tabs[id: $0]?.isPinned == true })
        else { return .none }

        let movedOrder = FileManagerTopNavigationOrderPolicy.movingPinnedContentTabs(
            orderedIDs,
            to: destination,
            in: state.optimisticTopNavigationOrder,
        )
        guard movedOrder != state.optimisticTopNavigationOrder else { return .none }

        state.sidebar.contentTabDragSnapshot = nil
        let token = contentTabPinnedRecordClient.reserveTopNavigationOperationToken()
        state.pendingTopNavigationIntents.append(.init(
            token: token,
            intent: .movePinnedGroup(orderedIDs: orderedIDs, destination: destination),
        ))
        state.optimisticTopNavigationOrder = movedOrder

        let discoveredLocationIDs = state.sidebar.allFixedLocationItems.map(\.id)
        return .send(.delegate(.persistTopNavigationPinnedGroupMove(
            token: token,
            orderedIDs: orderedIDs,
            destination: destination,
            discoveredLocationIDs: discoveredLocationIDs,
        )))
    }

    private func completeTopNavigationIntent(
        token: FileManagerTopNavigationOperationToken,
        terminal: FileManagerTopNavigationIntentTerminal,
        state: inout State,
        isCurrentTerminal: Bool? = nil,
    ) -> Effect<Action> {
        let hadPendingIntent = state.pendingTopNavigationIntents.contains { $0.token == token }
        let isRelevantCurrentTerminal = hadPendingIntent
            && (isCurrentTerminal ?? contentTabPinnedRecordClient.isCurrentTopNavigationOperationToken(token))
        switch terminal {
        case let .committed(commit):
            if state.lastConfirmedTopNavigationCommitRevision.map({ commit.revision >= $0 }) != false {
                state.lastConfirmedTopNavigationOrder = commit.order
                state.lastConfirmedTopNavigationCommitRevision = commit.revision
            }
            if isRelevantCurrentTerminal {
                state.topNavigationArrangementAvailability = .available
                state.topNavigationArrangementPresentation = nil
            }

        case let .failed(.storeUnavailable(failure)):
            if isRelevantCurrentTerminal {
                state.topNavigationArrangementAvailability = .unavailable(failure)
                state.topNavigationArrangementPresentation = .init(failure: .storeUnavailable(failure))
            }

        case .failed(.save):
            if isRelevantCurrentTerminal {
                state.topNavigationArrangementPresentation = .init(failure: .save)
            }

        case .failed(.cancelled), .failed(.superseded):
            break
        }

        guard hadPendingIntent else {
            state.replayTopNavigationOverlays()
            return .none
        }
        state.pendingTopNavigationIntents.removeAll { $0.token == token }
        state.replayTopNavigationOverlays()
        return .none
    }

    private func clearLogicalUndoHistory(tabID: ContentTabID, state: inout State) {
        let isActiveTab = state.contentTabs.activeTabID == tabID
        guard var contentState = isActiveTab ? state.content : state.tabContentStates[tabID] else { return }
        contentState.entryViewLayout.entryOperations.undoRecords.removeAll()
        contentState.entryViewLayout.entryOperations.redoRecords.removeAll()
        if isActiveTab {
            state.content = contentState
        }
        state.tabContentStates[tabID] = contentState
    }

    private func undoManagerGeneration(
        tabID: ContentTabID,
        state: State,
    ) -> FileOperationUndoManagerClient.Generation? {
        guard let windowID = state.windowID else { return nil }
        return fileOperationUndoManagerClient.generation(UndoManagerScope(
            windowID: windowID,
            contentTabID: tabID.rawValue,
        ))
    }

    private static func completedEntryActionRecord(
        from action: FileManagerContentAction,
    ) -> EntryActionRecord? {
        guard case let .entryViewLayout(
            .entryOperations(.lifecycle(.entryActionCompleted(record))),
        ) = action else { return nil }
        return record
    }

    private static func routeContentEffectAction(
        _ action: FileManagerContentAction,
        tabID: ContentTabID,
        undoManagerGeneration: FileOperationUndoManagerClient.Generation?,
    ) -> Action {
        guard let record = completedEntryActionRecord(from: action) else {
            return .tabContent(tabID: tabID, action: action)
        }
        return .internal(.entryActionCompleted(
            tabID: tabID,
            record: record,
            undoManagerGeneration: undoManagerGeneration,
        ))
    }

    private func reduceContentTabAction(
        _ action: ContentTabAction,
        state: inout State,
    ) -> Effect<Action> {
        let reducedAction: ContentTabAction = if case let .pin(tabID, placement) = action, placement == nil {
            .pinUsingDormantSlot(
                tabID,
                state.dormantContentTabSlots.first { $0.id == tabID },
            )
        } else {
            action
        }
        let preReductionEffect: Effect<Action> = switch action {
        case let .duplicate(sourceID, duplicateID):
            .send(.internal(.duplicateContentTabReduced(
                sourceID: sourceID,
                duplicateID: duplicateID,
                duplicateIDWasPreexisting: state.contentTabs.tabs[id: duplicateID] != nil,
            )))

        case let .duplicateSelected(requests):
            .send(.internal(.duplicateSelectedContentTabsReduced(
                requests: requests,
                preexistingTabIDs: Set(state.contentTabs.tabs.ids),
            )))

        default:
            .none
        }
        let childEffect = withDependencies {
            $0.contentTabPinnedRecordPersistenceRouting = pinnedRecordPersistenceRouting(state: state)
        } operation: {
            ContentTabFeature().reduce(
                into: &state.contentTabs,
                action: reducedAction,
            )
        }
        .map { Action.contentTabs($0) }
        return .merge(preReductionEffect, childEffect)
    }

    private func pinnedRecordPersistenceRouting(
        state: State,
    ) -> ContentTabPinnedRecordPersistenceRouting {
        switch pinnedRecordPersistenceOwnership {
        case .local:
            .local(discoveredLocationIDs: state.sidebar.allFixedLocationItems.map(\.id))
        case .windowManager:
            .delegate
        }
    }
}

private extension ContentTabPageAnchor {
    var supportsPinnedRecordPersistence: Bool {
        switch self {
        case .homeDefault, .directory, .collectionFile:
            true
        case .virtualCollection, .aiChat:
            false
        }
    }
}

func fileManagerContentState(
    for tabID: ContentTabID,
    state: FileManagerWindowState,
) -> FileManagerContentFeature.State? {
    state.contentTabs.activeTabID == tabID ? state.content : state.tabContentStates[tabID]
}

private func isComposerSaveRequest(_ action: FileManagerContentAction) -> Bool {
    switch action {
    case .composer(.view(.saveCollection)),
         .composer(.view(.saveCollectionAs)):
        true
    default:
        false
    }
}

private func isPinnedRecordPersistenceTerminal(_ action: ContentTabAction) -> Bool {
    pinnedRecordPersistenceResult(action) != nil
}

private func pinnedRecordPersistenceResult(
    _ action: ContentTabAction,
) -> ContentTabPinnedRecordPersistenceResult? {
    switch action {
    case let .pinnedRecordSaveSucceeded(tabID, context):
        .init(tabID: tabID, context: context, terminal: nil)
    case let .pinnedRecordSaveFailed(tabID, context, _):
        .init(tabID: tabID, context: context, terminal: .failed(.save))
    case let .pinnedRecordStoreUnavailable(tabID, context, failure, _):
        .init(
            tabID: tabID,
            context: context,
            terminal: .failed(.storeUnavailable(failure)),
        )
    case let .pinnedRecordSaveNotApplied(tabID, context, reason, _):
        .init(
            tabID: tabID,
            context: context,
            terminal: .failed(reason == .superseded ? .superseded : .cancelled),
        )
    default:
        nil
    }
}

func isSelectionAllowedDuringBatchClose(_ action: ContentTabAction) -> Bool {
    switch action {
    case .delegate,
         .toggleSelection,
         .selectRange,
         .collapseSelectionToActive,
         .pinnedRecordSaveSucceeded,
         .pinnedRecordSaveFailed,
         .pinnedRecordStoreUnavailable,
         .pinnedRecordSaveNotApplied:
        true
    default:
        false
    }
}

private func rebasingPinnedRecordRollback(
    _ action: ContentTabAction,
    to rollback: ContentTabPinnedRecordRollbackSnapshot?,
) -> ContentTabAction {
    guard let rollback else { return action }
    return switch action {
    case let .pinnedRecordSaveFailed(tabID, context, _):
        .pinnedRecordSaveFailed(tabID: tabID, context: context, rollback: rollback)
    case let .pinnedRecordStoreUnavailable(tabID, context, failure, _):
        .pinnedRecordStoreUnavailable(
            tabID: tabID,
            context: context,
            failure: failure,
            rollback: rollback,
        )
    case let .pinnedRecordSaveNotApplied(tabID, context, reason, _):
        .pinnedRecordSaveNotApplied(
            tabID: tabID,
            context: context,
            reason: reason,
            rollback: rollback,
        )
    default:
        action
    }
}

func isStalePinnedRecordPersistenceResult(
    _ action: ContentTabAction,
    in state: ContentTabState,
) -> Bool {
    switch action {
    case let .pinnedRecordSaveSucceeded(tabID, context),
         let .pinnedRecordSaveFailed(tabID, context, _),
         let .pinnedRecordStoreUnavailable(tabID, context, _, _),
         let .pinnedRecordSaveNotApplied(tabID, context, _, _):
        !state.isCurrentPinnedRecordPersistenceIntent(tabID: tabID, intentID: context.intentID)
    default:
        false
    }
}

private func isDirectPinMutation(_ action: ContentTabAction) -> Bool {
    switch action {
    case .pin, .unpin:
        true
    default:
        false
    }
}

func isDirectCloseMutation(_ action: ContentTabAction) -> Bool {
    switch action {
    case .requestClose, .close, .commitClose:
        true
    default:
        false
    }
}

private func isSelectedContentTabPinMutationPersistenceReplacement(
    _ action: ContentTabAction,
    for tabID: ContentTabID,
) -> Bool {
    guard case let .updateActivePageAnchor(id, _) = action else { return false }
    return id == tabID
}

func isCorrelatedSelectedContentTabPinMutation(
    _ action: ContentTabAction,
    for tabID: ContentTabID,
    target: SelectedContentTabPinMutationTargetState,
) -> Bool {
    switch action {
    case let .delegate(.persistPinnedRecord(request)):
        request.tabID == tabID
    case let .pin(id, _):
        id == tabID && target == .pinned
    case let .unpin(id, _):
        id == tabID && target == .unpinned
    case let .updateActivePageAnchor(id, _):
        id == tabID
    case let .pinnedRecordSaveSucceeded(id, _),
         let .pinnedRecordSaveFailed(id, _, _),
         let .pinnedRecordStoreUnavailable(id, _, _, _),
         let .pinnedRecordSaveNotApplied(id, _, _, _):
        id == tabID
    default:
        false
    }
}

func isCorrelatedSelectedContentTabCloseMutation(
    _ action: ContentTabAction,
    for tabID: ContentTabID,
) -> Bool {
    switch action {
    case let .delegate(.persistPinnedRecord(request)):
        request.tabID == tabID
    case let .setCurrent(id),
         let .requestClose(id),
         let .close(id),
         let .commitClose(id),
         let .pin(id, _),
         let .pinUsingDormantSlot(id, _),
         let .unpin(id, _):
        id == tabID
    case let .updateActivePageAnchor(id, _):
        id == tabID
    case let .pinnedRecordSaveSucceeded(id, _):
        id == tabID
    case let .pinnedRecordSaveFailed(id, _, _):
        id == tabID
    case let .pinnedRecordStoreUnavailable(id, _, _, _):
        id == tabID
    case let .pinnedRecordSaveNotApplied(id, _, _, _):
        id == tabID
    default:
        false
    }
}

private struct ContentTabPinnedRecordPersistenceResult {
    let tabID: ContentTabID
    let context: ContentTabPinnedRecordTerminalContext
    let terminal: FileManagerTopNavigationIntentTerminal?
}

private extension FileManagerWindowState {
    func isCurrentSelectedContentTabClose(operationID: UUID, tabID: ContentTabID) -> Bool {
        guard !isClosing,
              let batch = pendingSelectedContentTabClose,
              let pendingClose = pendingContentTabClose
        else { return false }
        return batch.operationID == operationID
            && batch.currentTabID == tabID
            && pendingClose.batchOperationID == operationID
            && pendingClose.tabID == tabID
    }
}
