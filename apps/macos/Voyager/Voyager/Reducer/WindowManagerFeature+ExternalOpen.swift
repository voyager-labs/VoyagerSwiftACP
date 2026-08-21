import ComposableArchitecture
import Foundation
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
            return .send(.delegate(.externalOpenActivationCompleted(batchID: plan.batchID)))
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
        if state.authorizedExternalOpenBatchID == batchID { state.authorizedExternalOpenBatchID = nil }
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
        state.refreshContentTabMoveTargets()
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
            ] + (activation.shouldReloadActiveDirectory
                ? [
                    .send(.windows(.element(
                        id: activation.windowID,
                        action: .window(.content(.internal(.reloadDirectoryListing))),
                    ))),
                ]
                : []) + (activation.shouldPublishSelectionChange
                ? [
                    .send(.windows(.element(
                        id: activation.windowID,
                        action: .window(.content(.entryViewLayout(.delegate(.selectionChanged)))),
                    ))),
                ]
                : [])
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
        // pinned collection 복귀는 navigation/anchor commit 후의 성공 delegate가 올 때까지 대기한다.
        let awaitedPinnedCollectionTabIDs = Set<ContentTabID>(attempt.plan.windows.compactMap { window in
            guard !window.isNewWindow,
                  let activeItem = window.items.last,
                  activeItem.requiresPinnedAnchorReturn,
                  case .collectionFile = activeItem.anchor
            else { return nil }
            return activeItem.tabID
        })
        guard awaitedPinnedCollectionTabIDs.isSubset(of: attempt.settledPinnedReturnTabIDs) else { return .none }
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

    /// pinned route 복귀 실패 delegate를 받으면 해당 tab을 제외하고 배치를 한 번 재계획한다.
    func replanExternalOpenActivationExcluding(
        tabID: ContentTabID,
        windowID: State.WindowID,
        state: inout State,
    ) -> Effect<Action> {
        guard let attempt = state.externalOpenActivationAttempt,
              state.authorizedExternalOpenBatchID == attempt.batchID,
              !attempt.excludedWindowIDs.contains(windowID),
              attempt.plan.orderedItems.contains(where: { $0.tabID == tabID && $0.requiresPinnedAnchorReturn })
        else { return .none }
        state.externalOpenActivationAttempt = nil
        state.externalOpenActivationBecameKey = false
        let failedItem = attempt.plan.orderedItems.last(where: {
            $0.tabID == tabID && $0.requiresPinnedAnchorReturn
        })
        var excludedTabIDs = Set([tabID])
        if let failedAnchor = failedItem?.anchor {
            for window in state.windows {
                for tab in window.window.contentTabs.tabs
                    where tab.isPinned
                    && window.window.contentTabs.pinnedRecords[tab.id]?.anchor == failedAnchor
                {
                    excludedTabIDs.insert(tab.id)
                }
            }
        }
        guard let request = attempt.plan.request?.retryExcluding(excludedTabIDs),
              case let .success(replacementPlan) = ExternalOpenPlacementPlanner.make(
                  request,
                  state: state,
                  generateUUID: uuid(),
              )
        else {
            return retryExternalOpenActivation(after: attempt, state: &state)
        }
        return .send(.placement(.apply(
            plan: replacementPlan,
            reservationsByItemID: replacementPlan.reservationsByItemID,
        )))
    }
}
