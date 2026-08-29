import ComposableArchitecture
import Foundation
import VoyagerEntitiesCollection
import VoyagerFeaturesContentPageNavigation
import VoyagerPagesFileManager
import VoyagerShared
import VoyagerWidgetsEntryViewLayout

extension WindowManagerFeature {
    func startExternalOpenActivation(
        plan: ExternalOpenPlacementPlan,
        excluding excludedWindowIDs: Set<State.WindowID>,
        state: inout State,
    ) -> Effect<Action> {
        guard let windowID = ExternalOpenPlacementApplication.lastSurvivingWindowID(
            for: plan,
            state: state,
            excluding: excludedWindowIDs,
        ) else {
            if let request = plan.request?.retryRequest,
               case let .success(replacementPlan) = ExternalOpenPlacementPlanner.make(
                   request,
                   state: state,
                   generateUUID: uuid(),
               )
            {
                state.externalOpenActivationAttempt = nil
                state.externalOpenActivationBecameKey = false
                return .send(.placement(.apply(
                    plan: replacementPlan,
                    reservationsByItemID: replacementPlan.reservationsByItemID,
                )))
            }
            state.authorizedExternalOpenBatchID = nil
            state.externalOpenActivationAttempt = nil
            state.externalOpenActivationBecameKey = false
            return .send(.delegate(.externalOpenActivationFailed(
                batchID: plan.batchID,
                failure: .recoveryExhausted,
            )))
        }

        let previousAttempt = state.externalOpenActivationAttempt.flatMap { attempt in
            attempt.batchID == plan.batchID && attempt.plan == plan ? attempt : nil
        }
        let shouldStartPinnedReturns = previousAttempt == nil
        state.externalOpenActivationBecameKey = false
        let attempt = ExternalOpenActivationAttempt(
            batchID: plan.batchID,
            plan: plan,
            windowID: windowID,
            excludedWindowIDs: excludedWindowIDs,
            settledPinnedReturnTabIDs: previousAttempt?.settledPinnedReturnTabIDs ?? [],
        )
        state.externalOpenActivationAttempt = attempt
        let activationEffect: Effect<Action> = .run { [fileManagerWindowClient] send in
            let result = await fileManagerWindowClient.activate(windowID)
            await send(.externalOpenActivationResult(attempt: attempt, result: result))
        }
        let pinnedReturnEffects = shouldStartPinnedReturns
            ? externalOpenPinnedAnchorReturnEffects(plan)
            : []
        return .merge([activationEffect] + pinnedReturnEffects)
            .cancellable(id: CancelID.externalOpenBatch(plan.batchID), cancelInFlight: false)
    }

    func retryExternalOpenActivation(
        after attempt: ExternalOpenActivationAttempt,
        state: inout State,
    ) -> Effect<Action> {
        var excludedWindowIDs = attempt.excludedWindowIDs
        excludedWindowIDs.insert(attempt.windowID)
        return startExternalOpenActivation(
            plan: attempt.plan,
            excluding: excludedWindowIDs,
            state: &state,
        )
    }

    func retainExternalOpenPlacementOwnership(
        _ batchID: UUID,
        _ newWindowIDs: [State.WindowID],
        state: inout State,
    ) {
        if newWindowIDs.isEmpty {
            if state.retainedExternalOpenPlacementOwnership?.batchID == batchID {
                state.retainedExternalOpenPlacementOwnership = nil
            }
        } else {
            state.retainedExternalOpenPlacementOwnership = .init(
                batchID: batchID,
                newWindowIDs: newWindowIDs,
            )
        }
    }

    func cancelExternalOpenPlacement(
        batchID: UUID,
        state: inout State,
    ) -> Effect<Action> {
        if state.authorizedExternalOpenBatchID == batchID {
            state.authorizedExternalOpenBatchID = nil
            state.externalOpenRegistrationTransactionID = nil
        }
        if state.retainedExternalOpenPlacementOwnership?.batchID == batchID {
            state.externalOpenRegistrationTransactionID = nil
        }
        if state.externalOpenActivationAttempt?.batchID == batchID {
            state.externalOpenActivationAttempt = nil
            state.externalOpenActivationBecameKey = false
        }
        var effects: [Effect<Action>] = [.cancel(id: CancelID.externalOpenBatch(batchID))]
        guard let ownership = state.retainedExternalOpenPlacementOwnership,
              ownership.batchID == batchID
        else { return .concatenate(effects) }
        state.retainedExternalOpenPlacementOwnership = nil
        let ownedWindowIDs = ownership.newWindowIDs.filter { state.externalWindowBatchIDs[$0] == batchID }
        for windowID in ownedWindowIDs {
            state.closingWindowIDs.insert(windowID)
            effects.append(.run { [fileManagerWindowClient] _ in
                await fileManagerWindowClient.close(windowID)
                await fileManagerWindowClient.finalizeClose(windowID)
            })
            effects.append(finalizeWindowRemoval(windowID, state: &state))
        }
        return .concatenate(effects)
    }

    func externalOpenActivationEffects(
        _ activations: [ExternalOpenPlacementApplication.ExistingWindowActivation],
    ) -> [Effect<Action>] {
        activations.flatMap { activation in
            [
                .send(.windows(.element(
                    id: activation.windowID,
                    action: .window(.activateExternalContentTabUndoScopes(activation.tabIDs)),
                ))),
            ] + [
                .send(.windows(.element(
                    id: activation.windowID,
                    action: .window(.contentTabs(.setCurrent(activation.activeTabID))),
                ))),
                .send(.windows(.element(
                    id: activation.windowID,
                    action: .window(.contentTabs(.collapseSelectionToActive)),
                ))),
            ] + externalOpenDirectoryReloadEffects(activation)
                + externalOpenSelectionChangeEffects(activation)
        }
    }

    private func externalOpenDirectoryReloadEffects(
        _ activation: ExternalOpenPlacementApplication.ExistingWindowActivation,
    ) -> [Effect<Action>] {
        activation.directoryReloadTabIDs.map { tabID in
            let action: FileManagerWindowAction = tabID == activation.activeTabID
                ? .content(.internal(.reloadDirectoryListing))
                : .tabContent(tabID: tabID, action: .internal(.reloadDirectoryListing))
            return .send(.windows(.element(id: activation.windowID, action: .window(action))))
        }
    }

    private func externalOpenSelectionChangeEffects(
        _ activation: ExternalOpenPlacementApplication.ExistingWindowActivation,
    ) -> [Effect<Action>] {
        activation.selectionChangedTabIDs.map { tabID in
            let action: FileManagerWindowAction = tabID == activation.activeTabID
                ? .content(.entryViewLayout(.delegate(.selectionChanged)))
                : .tabContent(
                    tabID: tabID,
                    action: .entryViewLayout(.delegate(.selectionChanged)),
                )
            return .send(.windows(.element(id: activation.windowID, action: .window(action))))
        }
    }

    func externalOpenPinnedAnchorReturnEffects(
        _ plan: ExternalOpenPlacementPlan,
    ) -> [Effect<Action>] {
        var effects: [Effect<Action>] = []
        for window in plan.windows where !window.isNewWindow {
            guard let activeTabID = window.items.last?.tabID else { continue }
            var lastItemsByTabID: [ContentTabID: ExternalOpenPlacementPlan.Item] = [:]
            for item in window.items where item.requiresPinnedAnchorReturn {
                lastItemsByTabID[item.tabID] = item
            }
            var emittedTabIDs: Set<ContentTabID> = []
            for item in window.items where item.requiresPinnedAnchorReturn {
                guard emittedTabIDs.insert(item.tabID).inserted,
                      let lastItem = lastItemsByTabID[item.tabID]
                else { continue }
                effects.append(.send(.windows(.element(
                    id: window.windowID,
                    action: .window(.returnContentTabToPinnedLocation(
                        item.tabID,
                        pendingSelectEntryID: lastItem.pendingSelectEntryID,
                        activateIfNeeded: item.tabID == activeTabID,
                    )),
                ))))
            }
        }
        return effects
    }

    func completeExternalOpenActivationIfSettled(state: inout State) -> Effect<Action> {
        guard let attempt = state.externalOpenActivationAttempt,
              state.authorizedExternalOpenBatchID == attempt.batchID
        else { return .none }
        let awaitedPinnedReturnTabIDs = Set<ContentTabID>(attempt.plan.orderedItems.compactMap { item in
            item.requiresPinnedAnchorReturn ? item.tabID : nil
        })
        guard awaitedPinnedReturnTabIDs.isSubset(of: attempt.settledPinnedReturnTabIDs) else { return .none }
        guard state.externalOpenActivationBecameKey else { return .none }
        let survivingWindowID = ExternalOpenPlacementApplication.lastSurvivingWindowID(
            for: attempt.plan,
            state: state,
            excluding: attempt.excludedWindowIDs,
        )
        guard survivingWindowID == attempt.windowID else {
            return retryExternalOpenActivation(after: attempt, state: &state)
        }
        state.authorizedExternalOpenBatchID = nil
        state.externalOpenActivationAttempt = nil
        state.externalOpenActivationBecameKey = false
        return .send(.delegate(.externalOpenActivationCompleted(batchID: attempt.batchID)))
    }

    /// pinned route 복귀 실패 delegate를 받으면 native 재시도에서 제외된 window의 실패도 소비해 배치를 한 번 재계획한다.
    func replanExternalOpenActivationExcluding(
        windowID: State.WindowID,
        tabID: ContentTabID,
        state: inout State,
    ) -> Effect<Action> {
        guard let attempt = state.externalOpenActivationAttempt,
              state.authorizedExternalOpenBatchID == attempt.batchID,
              let failedItem = attempt.plan.windows.first(where: { $0.windowID == windowID })?.items.last(where: {
                  $0.tabID == tabID && $0.requiresPinnedAnchorReturn
              })
        else { return .none }
        let cancellationEffects = externalOpenPinnedReturnCancellationEffects(
            attempt,
            excludingWindowID: windowID,
            excludingTabID: tabID,
            state: state,
        )
        state.externalOpenActivationAttempt = nil
        state.externalOpenActivationBecameKey = false
        let excludedTabIDs = externalOpenPinnedFallbackExclusions(
            attempt,
            failedItem: failedItem,
            failedTabID: tabID,
            state: state,
        )
        guard let request = attempt.plan.request?.fallbackExcludingPinnedCandidates(excludedTabIDs),
              case let .success(replacementPlan) = ExternalOpenPlacementPlanner.make(
                  request,
                  state: state,
                  generateUUID: uuid(),
              )
        else {
            state.authorizedExternalOpenBatchID = nil
            return .concatenate(cancellationEffects + [
                .send(.delegate(.externalOpenActivationFailed(
                    batchID: attempt.batchID,
                    failure: .recoveryExhausted,
                ))),
            ])
        }
        return .concatenate(cancellationEffects + [
            .send(.placement(.apply(
                plan: replacementPlan,
                reservationsByItemID: replacementPlan.reservationsByItemID,
            ))),
        ])
    }

    private func externalOpenPinnedFallbackExclusions(
        _ attempt: ExternalOpenActivationAttempt,
        failedItem: ExternalOpenPlacementPlan.Item,
        failedTabID: ContentTabID,
        state: State,
    ) -> Set<ContentTabID> {
        let settledTabIDs = attempt.settledPinnedReturnTabIDs
        var excludedTabIDs = Set<ContentTabID>(attempt.plan.orderedItems.compactMap { item in
            item.requiresPinnedAnchorReturn && !settledTabIDs.contains(item.tabID) ? item.tabID : nil
        })
        excludedTabIDs.insert(failedTabID)
        for window in state.windows {
            for tab in window.window.contentTabs.tabs
                where tab.isPinned
                && !settledTabIDs.contains(tab.id)
                && window.window.contentTabs.pinnedRecords[tab.id]?.anchor == failedItem.anchor
            {
                excludedTabIDs.insert(tab.id)
            }
        }
        return excludedTabIDs
    }

    func externalOpenPinnedReturnCancellationEffects(
        _ attempt: ExternalOpenActivationAttempt,
        excludingWindowID: State.WindowID,
        excludingTabID: ContentTabID?,
        state: State,
    ) -> [Effect<Action>] {
        var windowIDs: Set<State.WindowID> = []
        var effects: [Effect<Action>] = []
        for window in attempt.plan.windows where !window.isNewWindow {
            guard let liveWindow = state.windows[id: window.windowID]?.window,
                  let pendingRequest = liveWindow.pendingCollectionOpenRequest,
                  let item = window.items.last(where: { item in
                      guard item.requiresPinnedAnchorReturn,
                            !attempt.settledPinnedReturnTabIDs.contains(item.tabID),
                            case let .collectionFile(url) = item.anchor,
                            url.standardizedFileURL == pendingRequest.url.standardizedFileURL
                      else { return false }
                      return true
                  })
            else { continue }
            let isExcluded = window.windowID == excludingWindowID
                && (excludingTabID == nil || item.tabID == excludingTabID)
            guard !isExcluded,
                  windowIDs.insert(window.windowID).inserted
            else { continue }
            effects.append(.send(.windows(.element(
                id: window.windowID,
                action: .window(.cancelPendingPinnedCollectionReturn(item.tabID)),
            ))))
        }
        return effects
    }
}

private func externalOpenReservationLifecycleOwnsTab(
    _ tabID: ContentTabID,
    in window: FileManagerWindowState,
) -> Bool {
    window.isClosing
        || window.pendingContentTabClose?.tabID == tabID
        || window.pendingSelectedContentTabClose?.orderedTargetIDs.contains(tabID) == true
        || window.pendingSelectedContentTabPinMutation?.orderedTargetIDs.contains(tabID) == true
        || window.pendingContentTabTeardown?.tabID == tabID
        || window.pendingContentTabMove?.request.orderedTabIDs.contains(tabID) == true
        || !window.pendingTopNavigationIntents.isEmpty
        || window.contentTabMoveParticipantRequestID != nil
}
