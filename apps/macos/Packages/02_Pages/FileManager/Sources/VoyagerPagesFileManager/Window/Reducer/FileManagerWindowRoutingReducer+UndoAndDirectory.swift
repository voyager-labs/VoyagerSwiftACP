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
    func handleWindowDisappear(state: inout State) -> Effect<Action> {
        let closeOperationID = state.pendingSelectedContentTabClose?.operationID
            ?? state.pendingContentTabClose?.batchOperationID
        let pinMutationOperationID = recordPendingPinMutationCancellation(state: &state)
        if let pendingClose = state.pendingContentTabClose {
            restorePreviousActiveContentIfNeeded(pendingClose, state: &state)
            normalizeCloseTriggeredSaveState(pendingClose, state: &state)
        }
        if let metric = state.productContentTabCloseMetric {
            recordProductContentTabCloseMetric(for: metric.tabID, result: .cancelled, state: &state)
        }
        if let teardown = state.pendingContentTabTeardown,
           case let .tearingDownTab(requestID, ownerID) = state.undoRedoPhase,
           requestID == teardown.requestID,
           ownerID == teardown.ownerID
        {
            state.undoRedoPhase = .desynchronized
            state.undoManagerAvailability = .init()
        }
        state.isClosing = true
        state.pendingSelectedContentTabClose = nil
        state.pendingContentTabClose = nil
        state.deferredPinnedContentTabs = nil
        state.deferredPinnedContentTabsMode = nil
        state.pendingRuntimePreservationRecords.removeAll()
        state.pendingContentTabTeardown = nil
        var cancellationEffects: [Effect<Action>] = []
        if let closeOperationID {
            cancellationEffects.append(.cancel(
                id: SelectedContentTabCloseOperationCancelID(operationID: closeOperationID),
            ))
        }
        if let pinMutationOperationID {
            cancellationEffects.append(.cancel(
                id: SelectedContentTabPinMutationOperationCancelID(operationID: pinMutationOperationID),
            ))
        }
        return .merge(cancellationEffects)
    }

    private func recordPendingPinMutationCancellation(state: inout State) -> UUID? {
        let pendingPinMutation = state.pendingSelectedContentTabPinMutation
        let directPinMutationMetrics = Array(state.productContentTabPinMutationMetrics.values)
        for metric in directPinMutationMetrics {
            productMetricsClient.record(FileManagerProductMetricsProducer.contentTabTerminal(
                operationID: metric.operationID,
                identity: metric.identity,
                source: metric.source,
                result: .cancelled,
            ))
        }
        if let pendingPinMutation {
            recordSelectedPinMutationBatchMetric(.init(
                operationID: pendingPinMutation.operationID,
                target: pendingPinMutation.target,
                totalCount: pendingPinMutation.totalCount,
                successCount: pendingPinMutation.successCount,
                failureCount: pendingPinMutation.failureCount,
                remainingCount: pendingPinMutation.totalCount
                    - pendingPinMutation.successCount
                    - pendingPinMutation.failureCount,
                origin: pendingPinMutation.origin,
            ))
        }
        state.pendingSelectedContentTabPinMutation = nil
        state.productContentTabPinMutationMetrics.removeAll()
        return pendingPinMutation?.operationID
    }

    func normalizeCloseTriggeredSaveState(
        _ pendingClose: PendingContentTabClose,
        state: inout State,
    ) {
        if pendingClose.targetContent != nil,
           var targetContent = state.tabContentStates[pendingClose.tabID]
        {
            normalizeCloseTriggeredCollectionState(&targetContent.collection)
            state.tabContentStates[pendingClose.tabID] = targetContent
        } else {
            normalizeCloseTriggeredCollectionState(&state.content.collection)
            state.syncActiveTabContentState()
        }
    }

    func normalizeCloseTriggeredCollectionState(_ collection: inout CollectionState) {
        collection.isSaving = false
        collection.pendingSave = nil
        collection.pendingSaveContext = nil
        if collection.collectionSession.phase.isInflightRefresh
            || collection.collectionSession.phase.isInflightWriteBack
        {
            collection.collectionSession.failRefreshOrWriteBack()
        }
    }
}

// MARK: - Close Content Tab Request

func routeContentAction(
    _ action: FileManagerContentAction,
    tabID: ContentTabID,
    makeFallbackRequestID: @escaping () -> UUID,
    undoManagerClient: UndoManagerClient,
    state: inout FileManagerWindowState,
) -> Effect<FileManagerWindowAction> {
    let ownerID = if tabID == state.contentTabs.activeTabID {
        state.content.entryViewLayout.entryOperations.undoOwnerID
    } else {
        state.tabContentStates[tabID]?.entryViewLayout.entryOperations.undoOwnerID
    }
    let windowEffect: Effect<FileManagerWindowAction>
    switch action {
    case let .entryViewLayout(.entryOperations(.outcome(.entriesMutated(impact)))):
        windowEffect = handleEntriesMutated(impact, state: &state)
    case let .entryViewLayout(.entryOperations(.outcome(.undoManagerAvailabilityChanged(availability)))):
        state.undoManagerAvailability = availability
        windowEffect = .none
    case let .entryViewLayout(.entryOperations(.outcome(.entryActionReplayFinished(direction, terminal)))):
        guard let ownerID else {
            state.undoRedoPhase = .desynchronized
            state.undoManagerAvailability = .init()
            return .none
        }
        windowEffect = handleEntryActionReplayTerminal(
            direction: direction,
            terminal: terminal,
            ownerID: ownerID,
            context: EntryActionReplayContext(
                makeFallbackRequestID: makeFallbackRequestID,
                undoManagerClient: undoManagerClient,
            ),
            state: &state,
        )
    default:
        windowEffect = .none
    }
    guard state.contentTabs.tabs[id: tabID] != nil else { return windowEffect }

    let effect: Effect<FileManagerContentAction>
    if tabID == state.contentTabs.activeTabID {
        effect = FileManagerContentFeature().reduce(into: &state.content, action: action)
        state.syncActiveTabContentState()
    } else {
        guard var content = state.tabContentStates[tabID] else { return .none }
        effect = FileManagerContentFeature().reduce(into: &content, action: action)
        state.tabContentStates[tabID] = content
    }

    let routedEffect = effect.map { FileManagerWindowAction.internal(.routeContent(tabID: tabID, action: $0)) }
    return .merge(routedEffect, windowEffect)
}

func routeUndoManagerEvent(
    _ event: UndoManagerEvent,
    state: inout FileManagerWindowState,
) -> Effect<FileManagerWindowAction> {
    let requestID: UUID
    let expectedDirection: EntryActionDirection
    switch state.undoRedoPhase {
    case let .invoking(currentRequestID, direction), let .replaying(currentRequestID, direction):
        requestID = currentRequestID
        expectedDirection = direction
    case .idle, .refreshing, .recovering, .tearingDownTab, .desynchronized:
        state.undoRedoPhase = .desynchronized
        state.undoManagerAvailability = .init()
        return .none
    }

    guard expectedDirection == event.direction else {
        state.undoRedoPhase = .desynchronized
        return .none
    }

    let replayAction: EntryOperationsAction = switch event.direction {
    case .undo:
        .undoRedo(.undoEntryAction(event.record))
    case .redo:
        .undoRedo(.redoEntryAction(event.record))
    }
    state.undoRedoPhase = .replaying(requestID: requestID, direction: event.direction)

    if state.sidebarEntryDropOperations.undoOwnerID == event.ownerID {
        return .send(.internal(.sidebarEntryDrop(replayAction)))
    }
    if state.content.entryViewLayout.entryOperations.undoOwnerID == event.ownerID {
        return .send(.content(.entryViewLayout(.entryOperations(replayAction))))
    }

    let activeTabID = state.contentTabs.activeTabID
    let matchingTabIDs: [ContentTabID] = state.tabContentStates.compactMap { element in
        let (tabID, contentState) = element
        guard tabID != activeTabID,
              contentState.entryViewLayout.entryOperations.undoOwnerID == event.ownerID
        else { return nil }
        return tabID
    }
    guard matchingTabIDs.count == 1, let tabID = matchingTabIDs.first else {
        state.undoRedoPhase = .desynchronized
        return .none
    }
    return .send(.internal(.routeContent(
        tabID: tabID,
        action: .entryViewLayout(.entryOperations(replayAction)),
    )))
}

func handleEntriesMutated(
    _ impact: EntryOperationsMutationImpact,
    state: inout FileManagerWindowState,
) -> Effect<FileManagerWindowAction> {
    handleAffectedDirectoryRefresh(
        paths: impact.sourceParentPaths + [impact.destinationPath],
        state: &state,
    )
}

struct EntryActionReplayContext {
    let makeFallbackRequestID: () -> UUID
    let undoManagerClient: UndoManagerClient
}

func handleEntryActionReplayTerminal(
    direction: EntryActionDirection,
    terminal: EntryActionReplayTerminal,
    ownerID: UUID,
    context: EntryActionReplayContext,
    state: inout FileManagerWindowState,
) -> Effect<FileManagerWindowAction> {
    let requestID: UUID?
    switch state.undoRedoPhase {
    case let .invoking(currentRequestID, expectedDirection),
         let .replaying(currentRequestID, expectedDirection):
        guard expectedDirection == direction else {
            state.undoRedoPhase = .desynchronized
            state.undoManagerAvailability = .init()
            return .none
        }
        requestID = currentRequestID
    case .idle:
        requestID = nil
    case .refreshing, .recovering, .tearingDownTab, .desynchronized:
        return .none
    }

    switch terminal {
    case .success:
        let refreshRequestID = requestID ?? context.makeFallbackRequestID()
        state.undoRedoPhase = .refreshing(requestID: refreshRequestID)
        return handleReplaySuccessEffect(
            requestID: refreshRequestID,
            windowID: state.windowID,
            undoManagerClient: context.undoManagerClient,
        )

    case .failure(reason: .operationFailed, appliedTargets: _):
        guard let requestID, let windowID = state.windowID else {
            state.undoRedoPhase = .desynchronized
            state.undoManagerAvailability = .init()
            return .none
        }
        state.undoRedoPhase = .recovering(
            requestID: requestID,
            direction: direction,
            ownerID: ownerID,
        )
        state.undoManagerAvailability = .init()
        return invalidateUndoOwnerEffect(
            requestID: requestID,
            ownerID: ownerID,
            windowID: windowID,
            undoManagerClient: context.undoManagerClient,
        )

    case .failure(reason: .ownerRecordMismatch, appliedTargets: _),
         .failure(reason: .ownerBusy, appliedTargets: _):
        state.undoRedoPhase = .desynchronized
        state.undoManagerAvailability = .init()
        return .none
    }
}

private func handleReplaySuccessEffect(
    requestID: UUID,
    windowID: UUID?,
    undoManagerClient: UndoManagerClient,
) -> Effect<FileManagerWindowAction> {
    .run { send in
        let availability = await undoManagerClient.availability(windowID)
        await send(.internal(.undoManagerReplayAvailabilityChanged(
            requestID: requestID,
            availability: availability,
        )))
    }
}

func invalidateUndoOwnerEffect(
    requestID: UUID,
    ownerID: UUID,
    windowID: UUID,
    undoManagerClient: UndoManagerClient,
) -> Effect<FileManagerWindowAction> {
    .run { send in
        let result = await undoManagerClient.invalidateOwner(windowID, ownerID)
        await send(.internal(.undoManagerOwnerInvalidationFinished(
            requestID: requestID,
            ownerID: ownerID,
            result: result,
        )))
    }
}

func rotateRecoveredUndoOwner(
    ownerID: UUID,
    makeUndoOwnerID: () -> UUID,
    state: inout FileManagerWindowState,
) -> Bool {
    if state.sidebarEntryDropOperations.undoOwnerID == ownerID {
        state.sidebarEntryDropOperations.rotateUndoOwner(to: makeUndoOwnerID())
        return true
    }
    if state.content.entryViewLayout.entryOperations.undoOwnerID == ownerID {
        state.content.entryViewLayout.entryOperations.rotateUndoOwner(to: makeUndoOwnerID())
        state.syncActiveTabContentState()
        return true
    }

    let activeTabID = state.contentTabs.activeTabID
    let matchingTabIDs = state.tabContentStates.compactMap { element -> ContentTabID? in
        let (tabID, contentState) = element
        guard tabID != activeTabID,
              contentState.entryViewLayout.entryOperations.undoOwnerID == ownerID
        else { return nil }
        return tabID
    }
    guard matchingTabIDs.count == 1, let tabID = matchingTabIDs.first else { return false }
    state.tabContentStates[tabID]?.entryViewLayout.entryOperations.rotateUndoOwner(to: makeUndoOwnerID())
    return true
}

func handleUndoManagerOwnerInvalidationFinished(
    requestID: UUID,
    ownerID: UUID,
    result: UndoManagerInvalidationResult,
    makeUndoOwnerID: () -> UUID,
    state: inout FileManagerWindowState,
) -> Effect<FileManagerWindowAction> {
    switch state.undoRedoPhase {
    case let .recovering(currentRequestID, _, currentOwnerID):
        guard currentRequestID == requestID, currentOwnerID == ownerID else { return .none }
        guard result.succeeded,
              rotateRecoveredUndoOwner(
                  ownerID: ownerID,
                  makeUndoOwnerID: makeUndoOwnerID,
                  state: &state,
              )
        else {
            state.undoRedoPhase = .desynchronized
            state.undoManagerAvailability = .init()
            return .none
        }
        state.undoRedoPhase = .idle
        state.undoManagerAvailability = result.availability
        return .none

    case let .tearingDownTab(currentRequestID, currentOwnerID):
        guard currentRequestID == requestID,
              currentOwnerID == ownerID,
              let pending = state.pendingContentTabTeardown,
              pending.requestID == requestID,
              pending.ownerID == ownerID
        else { return .none }
        state.pendingContentTabTeardown = nil
        guard result.succeeded else {
            state.undoRedoPhase = .desynchronized
            state.undoManagerAvailability = .init()
            if let operationID = state.pendingContentTabClose?.batchOperationID {
                return .send(.selectedContentTabCloseItemCompleted(
                    operationID: operationID,
                    tabID: pending.tabID,
                    outcome: .failed,
                ))
            }
            return .none
        }
        state.undoRedoPhase = .idle
        state.undoManagerAvailability = result.availability
        if let operationID = state.pendingContentTabClose?.batchOperationID {
            return .send(.performSelectedContentTabCloseMutation(
                operationID: operationID,
                tabID: pending.tabID,
                action: .commitClose(pending.tabID),
            ))
        }
        return .send(.contentTabs(.commitClose(pending.tabID)))

    case .idle, .invoking, .replaying, .refreshing, .desynchronized:
        return .none
    }
}

func handleSidebarEntryActionReplayTerminal(
    _ terminal: EntryActionReplayTerminal,
    state: inout FileManagerWindowState,
) -> Effect<FileManagerWindowAction> {
    let targets: [EntryActionRecord.Target]
    switch terminal {
    case let .success(record):
        targets = record.targets
    case let .failure(reason: .operationFailed, appliedTargets: appliedTargets):
        targets = appliedTargets
    case .failure(reason: .ownerRecordMismatch, appliedTargets: _),
         .failure(reason: .ownerBusy, appliedTargets: _):
        return .none
    }

    return handleAffectedDirectoryRefresh(paths: parentDirectoryPaths(for: targets), state: &state)
}

func parentDirectoryPaths(for targets: [EntryActionRecord.Target]) -> [String] {
    var parentPaths: [String] = []
    for path in targets.flatMap({ [$0.beforePath, $0.afterPath] }).compactMap(\.self) {
        let parentPath = URL(fileURLWithPath: path).deletingLastPathComponent().path
        guard !parentPaths.contains(where: { EntryDropPathPolicy.areEquivalent($0, parentPath) }) else { continue }
        parentPaths.append(parentPath)
    }
    return parentPaths
}

func handleAffectedDirectoryRefresh(
    paths affectedPaths: [String],
    state: inout FileManagerWindowState,
) -> Effect<FileManagerWindowAction> {
    var activeDirectoryTabID: ContentTabID?

    for tab in state.contentTabs.tabs where tab.page == .directory {
        guard let currentPath = currentDirectoryPath(for: tab, state: state),
              affectedPaths.contains(where: { EntryDropPathPolicy.areEquivalent($0, currentPath) })
        else { continue }

        if tab.id == state.contentTabs.activeTabID {
            activeDirectoryTabID = tab.id
        } else {
            state.pendingDirectoryReloadTabIDs.insert(tab.id)
        }
    }

    guard let activeDirectoryTabID else { return .none }
    return .send(.internal(.routeContent(
        tabID: activeDirectoryTabID,
        action: .internal(.reloadDirectoryListing),
    )))
}

func currentDirectoryPath(
    for tab: ContentTabItem,
    state: FileManagerWindowState,
) -> String? {
    if tab.id == state.contentTabs.activeTabID {
        guard case let .folder(path) = state.content.navigation.navigationState else { return nil }
        return path
    }
    if let content = state.tabContentStates[tab.id] {
        guard case let .folder(path) = content.navigation.navigationState else { return nil }
        return path
    }
    guard case let .directory(path) = tab.anchor else { return nil }
    return path
}

func consumePendingDirectoryReloadForActiveTab(state: inout FileManagerWindowState) {
    guard let activeTabID = state.contentTabs.activeTabID,
          state.pendingDirectoryReloadTabIDs.contains(activeTabID),
          state.contentTabs.tabs[id: activeTabID]?.page == .directory,
          case .folder = state.content.navigation.navigationState
    else {
        cleanPendingDirectoryReloadTabIDs(state: &state)
        return
    }
    state.pendingDirectoryReloadTabIDs.remove(activeTabID)
}

func cleanPendingDirectoryReloadTabIDs(state: inout FileManagerWindowState) {
    let directoryTabIDs = Set(state.contentTabs.tabs.compactMap { tab in
        tab.page == .directory ? tab.id : nil
    })
    state.pendingDirectoryReloadTabIDs.formIntersection(directoryTabIDs)
}
