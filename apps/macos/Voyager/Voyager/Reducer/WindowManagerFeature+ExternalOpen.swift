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
            if let request = plan.request?.retryExcluding(
                failedPinnedCollectionTabIDs(for: plan, state: state, excluding: excludedWindowIDs),
            ),
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

        state.externalOpenActivationBecameKey = false
        let attempt = ExternalOpenActivationAttempt(
            batchID: plan.batchID,
            plan: plan,
            windowID: windowID,
            excludedWindowIDs: excludedWindowIDs,
        )
        state.externalOpenActivationAttempt = attempt
        return .run { [fileManagerWindowClient] send in
            let result = await fileManagerWindowClient.activate(windowID)
            await send(.externalOpenActivationResult(attempt: attempt, result: result))
        }
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
            ] + activation.pinnedAnchorReturns.map { pinnedReturn in
                .send(.windows(.element(
                    id: activation.windowID,
                    action: .window(.returnContentTabToPinnedLocation(
                        pinnedReturn.tabID,
                        pendingSelectEntryID: pinnedReturn.pendingSelectEntryID,
                        activateIfNeeded: pinnedReturn.tabID == activation.activeTabID,
                    )),
                )))
            } + [
                .send(.windows(.element(
                    id: activation.windowID,
                    action: .window(.contentTabs(.setCurrent(activation.activeTabID))),
                ))),
                .send(.windows(.element(
                    id: activation.windowID,
                    action: .window(.contentTabs(.collapseSelectionToActive)),
                ))),
            ] + (activation.shouldPublishSelectionChange
                ? [
                    .send(.windows(.element(
                        id: activation.windowID,
                        action: .window(.content(.entryViewLayout(.delegate(.selectionChanged)))),
                    ))),
                ]
                : [])
        }
    }

    func completeExternalOpenActivationIfSettled(state: inout State) -> Effect<Action> {
        guard let attempt = state.externalOpenActivationAttempt,
              state.authorizedExternalOpenBatchID == attempt.batchID
        else { return .none }
        if hasPendingPinnedCollectionReturn(for: attempt.plan, state: state, excluding: attempt.excludedWindowIDs) {
            return .none
        }
        if hasFailedPinnedCollectionReturn(for: attempt.plan, state: state, excluding: attempt.excludedWindowIDs) {
            state.externalOpenActivationAttempt = nil
            state.externalOpenActivationBecameKey = false
            if let request = attempt.plan.request?.retryExcluding(
                failedPinnedCollectionTabIDs(
                    for: attempt.plan,
                    state: state,
                    excluding: attempt.excludedWindowIDs,
                ),
            ),
                case let .success(replacementPlan) = ExternalOpenPlacementPlanner.make(
                    request,
                    state: state,
                    generateUUID: uuid(),
                )
            {
                return .send(.placement(.apply(
                    plan: replacementPlan,
                    reservationsByItemID: replacementPlan.reservationsByItemID,
                )))
            }
            return retryExternalOpenActivation(after: attempt, state: &state)
        }
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

    private func hasPendingPinnedCollectionReturn(
        for plan: ExternalOpenPlacementPlan,
        state: State,
        excluding excludedWindowIDs: Set<State.WindowID>,
    ) -> Bool {
        plan.orderedItems.contains { item in
            guard item.requiresPinnedAnchorReturn,
                  case .collectionFile = item.anchor,
                  let windowID = plan.windows.first(where: { $0.items.contains(where: { $0.itemID == item.itemID }) })?
                  .windowID,
                  !excludedWindowIDs.contains(windowID),
                  let window = state.windows[id: windowID]?.window
            else { return false }
            return window.pendingCollectionOpenRequest != nil
        }
    }

    private func hasFailedPinnedCollectionReturn(
        for plan: ExternalOpenPlacementPlan,
        state: State,
        excluding excludedWindowIDs: Set<State.WindowID>,
    ) -> Bool {
        !failedPinnedCollectionTabIDs(for: plan, state: state, excluding: excludedWindowIDs).isEmpty
    }

    private func failedPinnedCollectionTabIDs(
        for plan: ExternalOpenPlacementPlan,
        state: State,
        excluding excludedWindowIDs: Set<State.WindowID>,
    ) -> Set<ContentTabID> {
        Set(plan.orderedItems.compactMap { item in
            guard item.requiresPinnedAnchorReturn,
                  case .collectionFile = item.anchor,
                  let windowID = plan.windows.first(where: { $0.items.contains(where: { $0.itemID == item.itemID }) })?
                  .windowID,
                  !excludedWindowIDs.contains(windowID),
                  let window = state.windows[id: windowID]?.window,
                  window.pendingCollectionOpenRequest == nil,
                  window.contentTabs.tabs[id: item.tabID] != nil,
                  window.contentTabs.tabs[id: item.tabID]?.anchor != item.anchor
            else { return nil }
            return item.tabID
        })
    }
}
