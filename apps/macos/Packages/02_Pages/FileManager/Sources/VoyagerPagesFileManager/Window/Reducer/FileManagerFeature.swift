import ComposableArchitecture
import Foundation
import VoyagerFeaturesContentPageNavigation
import VoyagerFeaturesEntryOperations
import VoyagerWidgetsEntryViewLayout

@Reducer
public struct FileManagerFeature {
    public typealias State = FileManagerWindowState
    public typealias Action = FileManagerWindowAction

    public init() {}

    @Dependency(\.fileOperationUndoManagerClient)
    var fileOperationUndoManagerClient
    @Dependency(\.contentTabPinnedRecordClient)
    var contentTabPinnedRecordClient
    @Dependency(\.fileManagerPinnedRecordOwner)
    var pinnedRecordPersistenceOwnership
    @Dependency(\.userDefaultsClient)
    var userDefaultsClient

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

    private func isContentTabMoveParticipantActionAllowed(_ action: Action) -> Bool {
        switch action {
        case .applyCommittedTopNavigationSnapshot,
             .applyExternalCommittedTopNavigationOrder,
             .backgroundAiChat,
             .backgroundAiChatSnapshotPersisted,
             .backgroundInspectorAiChat,
             .backgroundInspectorAiChatSnapshotPersisted,
             .contentTabMoveSucceeded,
             .contentTabMoveRejected,
             .onDisappear:
            true

        case .tabContent(_, .internal(.applyNavigationState)),
             .tabContent(_, .internal(.startObservingSystemNotifications)),
             .tabContent(_, .internal(.stopObservingSystemNotifications)):
            true

        case .internal(.entryActionCompleted):
            true

        case let .content(.entryViewLayout(.entryOperations(entryAction))),
             let .tabContent(_, .entryViewLayout(.entryOperations(entryAction))),
             let .internal(.sidebarEntryDrop(entryAction)):
            isEntryOperationsCompletionActionAllowed(entryAction)

        default:
            false
        }
    }

    private func isEntryOperationsCompletionActionAllowed(_ action: EntryOperationsAction) -> Bool {
        switch action {
        case .lifecycle(.windowIDChanged),
             .lifecycle(.operationStarted),
             .lifecycle(.operationFinished),
             .lifecycle(.dropOperationFinished),
             .lifecycle(.entryActionCompleted),
             .lifecycle(.emptyTrashCompleted),
             .lifecycle(.pathsMutated),
             .outcome(.entriesMutated),
             .outcome(.undoManagerAvailabilityChanged),
             .outcome(.entryActionReplayFinished):
            true

        default:
            false
        }
    }
}

extension ContentTabPageAnchor {
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

func pinnedRecordPersistenceResult(
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

struct ContentTabPinnedRecordPersistenceResult {
    let tabID: ContentTabID
    let context: ContentTabPinnedRecordTerminalContext
    let terminal: FileManagerTopNavigationIntentTerminal?
}

extension FileManagerWindowState {
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
