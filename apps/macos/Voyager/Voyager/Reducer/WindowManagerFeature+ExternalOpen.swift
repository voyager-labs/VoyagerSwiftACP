import ComposableArchitecture
import Foundation
import VoyagerPagesFileManager
import VoyagerShared

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
            state.authorizedExternalOpenBatchID = nil
            state.externalOpenActivationAttempt = nil
            return .send(.delegate(.externalOpenActivationCompleted(batchID: plan.batchID)))
        }

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
        if state.externalOpenActivationAttempt?.batchID == batchID { state.externalOpenActivationAttempt = nil }
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
                .send(.windows(.element(
                    id: activation.windowID,
                    action: .window(.contentTabs(.setCurrent(activation.activeTabID))),
                ))),
                .send(.windows(.element(
                    id: activation.windowID,
                    action: .window(.contentTabs(.collapseSelectionToActive)),
                ))),
            ]
        }
    }
}
