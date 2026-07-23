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
        if state.authorizedExternalOpenBatchID == batchID {
            state.authorizedExternalOpenBatchID = nil
        }
        if state.externalOpenActivationAttempt?.batchID == batchID {
            state.externalOpenActivationAttempt = nil
        }

        var effects: [Effect<Action>] = [
            .cancel(id: CancelID.externalOpenBatch(batchID)),
        ]
        guard let ownership = state.retainedExternalOpenPlacementOwnership,
              ownership.batchID == batchID
        else {
            return .concatenate(effects)
        }
        state.retainedExternalOpenPlacementOwnership = nil

        let ownedWindowIDs = ownership.newWindowIDs.filter {
            state.externalWindowBatchIDs[$0] == batchID
        }
        let removedFocusedWindow = state.focusedWindowID.map(ownedWindowIDs.contains) ?? false
        let removedBootstrapWindow = ownedWindowIDs.contains {
            state.defaultWindowBootstrapWindowIDs.contains($0)
        }
        for windowID in ownedWindowIDs {
            state.windows.remove(id: windowID)
            state.lastUsedWindowIDs.removeAll { $0 == windowID }
            state.defaultWindowBootstrapWindowIDs.remove(windowID)
            state.externalWindowBatchIDs[windowID] = nil
        }
        if removedFocusedWindow {
            state.focusedWindowID = state.lastUsedWindowIDs.first { state.windows[id: $0] != nil }
        }
        if removedBootstrapWindow,
           state.defaultWindowBootstrapWindowIDs.isEmpty,
           state.defaultWindowBootstrapRequestID != nil
        {
            state.defaultWindowBootstrapRequestID = nil
            effects.append(.cancel(id: CancelID.defaultWindowBootstrap))
        }
        effects.append(contentsOf: ownedWindowIDs.map { windowID in
            .run { [fileManagerWindowClient] _ in
                await fileManagerWindowClient.close(windowID)
            }
        })
        return .concatenate(effects)
    }
}
