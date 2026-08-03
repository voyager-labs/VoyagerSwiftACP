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
              let sourceWindow = state.windows[id: request.sourceWindowID]?.window,
              let targetWindow = state.windows[id: request.targetWindowID]?.window,
              sourceWindow.sidebar.pendingContentTabMoveRequest == request
        else {
            return rejectContentTabMove(request, category: .unavailable, state: &state)
        }

        guard !state.topNavigationPersistenceQueue.contains(where: {
            guard case let .pinnedRecord(_, persistenceRequest, _) = $0.operation else { return false }
            return persistenceRequest.tabID == request.tabID
        }) else {
            return rejectContentTabMove(request, category: .busy, state: &state)
        }

        let targetUndoScopePolicy: FileOperationUndoScopeTargetPolicy =
            targetWindow.contentTabs.tabs[id: request.tabID] == nil ? .requireVacant : .replaceEmpty
        switch ContentTabTransfer.transfer(
            source: sourceWindow,
            target: targetWindow,
            tabID: request.tabID,
        ) {
        case let .rejected(reason):
            return rejectContentTabMove(request, category: contentTabMoveCategory(for: reason), state: &state)

        case let .moved(postCommit):
            return finalizeContentTabMove(
                request,
                postCommit: postCommit,
                targetUndoScopePolicy: targetUndoScopePolicy,
                closesSourceWindow: false,
                state: &state,
            )

        case let .closeSourceWindow(postCommit):
            return finalizeContentTabMove(
                request,
                postCommit: postCommit,
                targetUndoScopePolicy: targetUndoScopePolicy,
                closesSourceWindow: true,
                state: &state,
            )
        }
    }

    private func finalizeContentTabMove(
        _ request: ContentTabMoveRequest,
        postCommit: ContentTabTransfer.PostCommit,
        targetUndoScopePolicy: FileOperationUndoScopeTargetPolicy,
        closesSourceWindow: Bool,
        state: inout State,
    ) -> Effect<Action> {
        if let category = contentTabMoveUndoScopeFailureCategory(
            postCommit.rebind,
            targetPolicy: targetUndoScopePolicy,
        ) {
            return rejectContentTabMove(request, category: category, state: &state)
        }

        var sourceWindow = postCommit.source
        if !closesSourceWindow {
            sourceWindow.sidebar.pendingContentTabMoveRequest = nil
        }
        state.windows[id: request.sourceWindowID]?.window = sourceWindow
        state.windows[id: request.targetWindowID]?.window = postCommit.target

        let commitEffect = commitContentTabMove(
            request,
            rebind: postCommit.rebind,
            state: &state,
        )
        guard closesSourceWindow else { return commitEffect }
        return .merge(
            closeWindow(request.sourceWindowID, state: &state),
            commitEffect,
        )
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
        var effects = contentTabMoveRebindEffects(rebind: rebind)
        effects.append(.run { [fileManagerWindowClient] send in
            let result = await fileManagerWindowClient.activate(request.targetWindowID)
            await send(.contentTabMoveActivationResult(attempt: activationAttempt, result: result))
        })
        return .merge(effects)
    }

    private func contentTabMoveRebindEffects(
        rebind: ContentTabTransfer.RebindIntent,
    ) -> [Effect<Action>] {
        [
            .concatenate(
                contentTabMoveOutgoingOwnerTeardown(rebind.sourceOutgoingOwner),
                rebind.targetOutgoingOwner.map(contentTabMoveOutgoingOwnerTeardown) ?? .none,
                contentTabMoveObservationRebindEffect(rebind),
            ),
        ]
    }

    private func contentTabMoveUndoScopeFailureCategory(
        _ rebind: ContentTabTransfer.RebindIntent,
        targetPolicy: FileOperationUndoScopeTargetPolicy,
    ) -> ContentTabMoveFailurePresentation.Category? {
        let outcome = fileOperationUndoManagerClient.moveScope(
            UndoManagerScope(
                windowID: rebind.sourceWindowID,
                contentTabID: rebind.tabID.rawValue,
            ),
            UndoManagerScope(
                windowID: rebind.targetWindowID,
                contentTabID: rebind.tabID.rawValue,
            ),
            targetPolicy,
        )
        switch outcome {
        case .moved:
            return nil
        case .sourceMissing:
            return .unavailable
        case .targetOccupied:
            return .generic
        }
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
