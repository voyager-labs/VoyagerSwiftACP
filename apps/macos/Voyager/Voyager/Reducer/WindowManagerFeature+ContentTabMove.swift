import ComposableArchitecture
import Foundation
import VoyagerFeaturesComposer
import VoyagerFeaturesEntryOperations
import VoyagerPagesFileManager

extension WindowManagerFeature {
    func handleContentTabMoveRequest(
        _ request: ContentTabMoveRequest,
        state: inout State,
    ) -> Effect<Action> {
        guard state.contentTabMoveTerminalRecords[request.requestID] == nil else { return .none }
        guard request.sourceWindowID != request.targetWindowID,
              isWindowReady(request.sourceWindowID, state: state),
              isWindowReady(request.targetWindowID, state: state),
              var sourceWindow = state.windows[id: request.sourceWindowID]?.window,
              let targetWindow = state.windows[id: request.targetWindowID]?.window,
              sourceWindow.sidebar.pendingContentTabMoveRequest == request
        else {
            return rejectContentTabMove(request, category: .unavailable, state: &state)
        }

        switch ContentTabTransfer.transfer(
            source: sourceWindow,
            target: targetWindow,
            tabID: request.tabID,
        ) {
        case let .rejected(reason):
            return rejectContentTabMove(request, category: contentTabMoveCategory(for: reason), state: &state)

        case let .moved(postCommit):
            sourceWindow = postCommit.source
            sourceWindow.sidebar.pendingContentTabMoveRequest = nil
            state.windows[id: request.sourceWindowID]?.window = sourceWindow
            state.windows[id: request.targetWindowID]?.window = postCommit.target
            return commitContentTabMove(
                request,
                rebind: postCommit.rebind,
                state: &state,
            )

        case let .closeSourceWindow(postCommit):
            state.windows[id: request.sourceWindowID]?.window = postCommit.source
            state.windows[id: request.targetWindowID]?.window = postCommit.target
            let closeEffect = closeWindow(request.sourceWindowID, state: &state)
            let commitEffect = commitContentTabMove(
                request,
                rebind: postCommit.rebind,
                state: &state,
            )
            return .merge(closeEffect, commitEffect)
        }
    }

    private func rejectContentTabMove(
        _ request: ContentTabMoveRequest,
        category: ContentTabMoveFailurePresentation.Category,
        state: inout State,
    ) -> Effect<Action> {
        if state.windows[id: request.sourceWindowID]?.window.sidebar.pendingContentTabMoveRequest == request {
            state.windows[id: request.sourceWindowID]?.window.sidebar.pendingContentTabMoveRequest = nil
            state.windows[id: request.sourceWindowID]?.window.contentTabMoveFailurePresentation = .init(
                requestID: request.requestID,
                category: category,
            )
        }
        state.recordContentTabMoveTerminal(.init(
            requestID: request.requestID,
            sourceWindowID: request.sourceWindowID,
            tabID: request.tabID,
            targetWindowID: request.targetWindowID,
            outcome: .rejected(category),
        ))
        return .none
    }

    private func commitContentTabMove(
        _ request: ContentTabMoveRequest,
        rebind: ContentTabTransfer.RebindIntent,
        state: inout State,
    ) -> Effect<Action> {
        state.recordContentTabMoveTerminal(.init(
            requestID: request.requestID,
            sourceWindowID: request.sourceWindowID,
            tabID: request.tabID,
            targetWindowID: request.targetWindowID,
            outcome: .succeeded,
        ))
        let activationAttempt = ContentTabMoveActivationAttempt(
            requestID: request.requestID,
            targetWindowID: request.targetWindowID,
        )
        state.contentTabMoveActivationAttempts[request.requestID] = activationAttempt
        state.refreshContentTabMoveTargets()
        return postCommitContentTabMoveEffects(
            request,
            rebind: rebind,
            activationAttempt: activationAttempt,
        )
    }

    private func postCommitContentTabMoveEffects(
        _ request: ContentTabMoveRequest,
        rebind: ContentTabTransfer.RebindIntent,
        activationAttempt: ContentTabMoveActivationAttempt,
    ) -> Effect<Action> {
        let sourceScope = UndoManagerScope(
            windowID: rebind.sourceWindowID,
            contentTabID: rebind.tabID.rawValue,
        )
        let targetScope = UndoManagerScope(
            windowID: rebind.targetWindowID,
            contentTabID: rebind.tabID.rawValue,
        )
        var effects = contentTabMoveRebindEffects(
            rebind: rebind,
            sourceScope: sourceScope,
            targetScope: targetScope,
        )
        effects.append(.run { [fileManagerWindowClient] send in
            let result = await fileManagerWindowClient.activate(request.targetWindowID)
            await send(.contentTabMoveActivationResult(attempt: activationAttempt, result: result))
        })
        return .merge(effects)
    }

    private func contentTabMoveRebindEffects(
        rebind: ContentTabTransfer.RebindIntent,
        sourceScope: UndoManagerScope,
        targetScope: UndoManagerScope,
    ) -> [Effect<Action>] {
        [
            .run { [fileOperationUndoManagerClient] _ in
                fileOperationUndoManagerClient.deactivate(sourceScope)
                _ = fileOperationUndoManagerClient.activate(targetScope)
            },
            .concatenate(
                contentTabMoveOutgoingOwnerTeardown(rebind.sourceOutgoingOwner),
                rebind.targetOutgoingOwner.map(contentTabMoveOutgoingOwnerTeardown) ?? .none,
                contentTabMoveObservationRebindEffect(rebind),
            ),
        ]
    }

    private func contentTabMoveOutgoingOwnerTeardown(
        _ owner: ContentTabTransfer.OutgoingContentOwner,
    ) -> Effect<Action> {
        var effects: [Effect<Action>] = []
        if owner.canCancelLoadingExclusively {
            effects.append(.cancel(id: EntryOperationsLoadingCancelID.loadItems(
                windowID: owner.loadingWindowID,
                ownerID: owner.loadingOwnerID,
            )))
        }
        if owner.canCancelComposerExclusively {
            effects.append(.cancel(id: ComposerFeature.CancelID.search(ownerID: owner.composerOwnerID)))
            effects.append(.cancel(id: ComposerFeature.CancelID.filters(ownerID: owner.composerOwnerID)))
        }
        return .concatenate(effects)
    }

    private func contentTabMoveObservationRebindEffect(
        _ rebind: ContentTabTransfer.RebindIntent,
    ) -> Effect<Action> {
        let targetEffect = contentTabMoveObservationSequence(rebind.targetActiveNavigationObservation)
        guard let source = rebind.sourceActiveNavigationObservation else {
            return targetEffect
        }
        return .concatenate(
            contentTabMoveObservationSequence(source),
            targetEffect,
        )
    }

    private func contentTabMoveObservationSequence(
        _ rebind: ContentTabTransfer.ActiveNavigationObservationRebind,
    ) -> Effect<Action> {
        .concatenate(
            contentTabMoveObservationEffect(
                rebind,
                action: .internal(.stopObservingSystemNotifications),
            ),
            contentTabMoveObservationEffect(
                rebind,
                action: .internal(.startObservingSystemNotifications),
            ),
            contentTabMoveObservationEffect(
                rebind,
                action: .internal(.applyNavigationState(rebind.navigationRoute)),
            ),
        )
    }

    private func contentTabMoveObservationEffect(
        _ rebind: ContentTabTransfer.ActiveNavigationObservationRebind,
        action: FileManagerContentAction,
    ) -> Effect<Action> {
        .send(.windows(.element(
            id: rebind.windowID,
            action: .window(.tabContent(tabID: rebind.tabID, action: action)),
        )))
    }

    private func contentTabMoveCategory(
        for rejection: ContentTabTransfer.Rejection,
    ) -> ContentTabMoveFailurePresentation.Category {
        switch rejection {
        case .sourceTabMissing, .sourceWindowIdentityMissing, .targetWindowIdentityMissing, .sameWindow:
            .unavailable
        case .targetCapacityExceeded:
            .capacity
        case .ineligible(.malformedOwnership):
            .generic
        case .ineligible:
            .busy
        case .sourceTabAmbiguous,
             .sourcePinParity,
             .targetMalformedOwnership,
             .targetTabCollision,
             .targetOwnerCollision,
             .targetSessionCollision,
             .targetPinCollision:
            .generic
        }
    }
}
