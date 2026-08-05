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
        guard let sourceWindow = state.windows[id: request.sourceWindowID]?.window,
              sourceWindow.pendingContentTabMove?.lifecycle == .inFlight,
              sourceWindow.pendingContentTabMove?.request == request,
              sourceWindow.sidebar.pendingContentTabMoveRequest == request
        else { return .none }
        guard state.contentTabMoveTerminalRecords[request.requestID] == nil else { return .none }
        guard request.sourceWindowID != request.targetWindowID,
              isWindowReady(request.sourceWindowID, state: state),
              isWindowReady(request.targetWindowID, state: state),
              let targetWindow = state.windows[id: request.targetWindowID]?.window
        else {
            return rejectContentTabMove(request, category: .unavailable, state: &state)
        }

        guard !contentTabMoveOverlapsActiveTransaction(request, state: state),
              !state.topNavigationPersistenceQueue.contains(where: { queued in
                  guard case let .pinnedRecord(_, persistenceRequest, _) = queued.operation else { return false }
                  return request.orderedTabIDs.contains(persistenceRequest.tabID)
              })
        else {
            return rejectContentTabMove(request, category: .busy, state: &state)
        }

        let token: ContentTabTransfer.SuccessToken
        switch ContentTabTransfer.preflight(
            source: sourceWindow,
            target: targetWindow,
            orderedTabIDs: request.orderedTabIDs,
            primaryTabID: request.initiatingTabID,
        ) {
        case let .success(value):
            token = value
        case let .rejected(reason):
            return rejectContentTabMove(request, category: contentTabMoveCategory(for: reason), state: &state)
        }

        let undoOutcome = fileOperationUndoManagerClient.moveScopes(
            contentTabMoveUndoDescriptors(token, originalTarget: targetWindow),
        )
        guard undoOutcome == .moved else {
            return rejectContentTabMove(
                request,
                category: contentTabMoveCategory(for: undoOutcome),
                state: &state,
            )
        }

        return applyContentTabMoveToken(request, token: token, state: &state)
    }

    private func applyContentTabMoveToken(
        _ request: ContentTabMoveRequest,
        token: ContentTabTransfer.SuccessToken,
        state: inout State,
    ) -> Effect<Action> {
        switch ContentTabTransfer.apply(token) {
        case let .moved(postCommit):
            commitContentTabMove(
                request,
                postCommit: postCommit,
                closesSourceWindow: false,
                state: &state,
            )
        case let .closeSourceWindow(postCommit):
            commitContentTabMove(
                request,
                postCommit: postCommit,
                closesSourceWindow: true,
                state: &state,
            )
        case .rejected:
            preconditionFailure("Validated ContentTabTransfer token must apply infallibly")
        }
    }

    func startContentTabMoveNativeEffects(
        _ request: ContentTabMoveRequest,
        state: inout State,
    ) -> Effect<Action> {
        guard let plan = state.contentTabMoveNativeEffectsPlans[request.requestID],
              plan.request == request,
              state.contentTabMoveActivationAttempts[request.requestID]?.request == request,
              state.contentTabMoveTerminalRecords[request.requestID] == .init(request: request, outcome: .succeeded)
        else { return .none }
        state.contentTabMoveNativeEffectsPlans[request.requestID] = nil

        let activationAttempt = ContentTabMoveActivationAttempt(request: request)
        let activationEffect: Effect<Action> = .run { [fileManagerWindowClient] send in
            let result = await fileManagerWindowClient.activate(request.targetWindowID)
            await send(.contentTabMoveActivationResult(attempt: activationAttempt, result: result))
        }
        guard plan.closesSourceWindow else { return activationEffect }
        return .merge(
            closeWindow(request.sourceWindowID, state: &state),
            activationEffect,
        )
    }

    private func commitContentTabMove(
        _ request: ContentTabMoveRequest,
        postCommit: ContentTabTransfer.PostCommit,
        closesSourceWindow: Bool,
        state: inout State,
    ) -> Effect<Action> {
        state.windows[id: request.sourceWindowID]?.window = postCommit.source
        state.windows[id: request.targetWindowID]?.window = postCommit.target
        state.recordContentTabMoveTerminal(.init(request: request, outcome: .succeeded))
        state.contentTabMoveTransactions[request.requestID] = .init(request: request)
        state.contentTabMoveNativeEffectsPlans[request.requestID] = .init(
            request: request,
            closesSourceWindow: closesSourceWindow,
        )
        state.contentTabMoveActivationAttempts[request.requestID] = .init(request: request)
        state.refreshContentTabMoveTargets()

        return .concatenate(
            contentTabMoveTerminalEffect(request, outcome: .succeeded),
            contentTabMoveLifecycleEffects(
                teardownIntents: postCommit.teardownIntents,
                rebindIntents: postCommit.rebinds,
            ),
            .send(.contentTabMoveLifecycleCompleted(request: request)),
            .send(.contentTabMoveNativeEffectsRequested(request: request)),
        )
    }

    private func rejectContentTabMove(
        _ request: ContentTabMoveRequest,
        category: ContentTabMoveFailurePresentation.Category,
        state: inout State,
    ) -> Effect<Action> {
        state.recordContentTabMoveTerminal(.init(request: request, outcome: .rejected(category)))
        return contentTabMoveTerminalEffect(request, outcome: .rejected(category))
    }

    private func contentTabMoveTerminalEffect(
        _ request: ContentTabMoveRequest,
        outcome: ContentTabMoveTerminalRecord.Outcome,
    ) -> Effect<Action> {
        let windowAction: FileManagerWindowAction = switch outcome {
        case .succeeded:
            .contentTabMoveSucceeded(request: request)
        case let .rejected(category):
            .contentTabMoveRejected(request: request, category: category)
        }
        return .send(.windows(.element(
            id: request.sourceWindowID,
            action: .window(windowAction),
        )))
    }

    private func contentTabMoveOverlapsActiveTransaction(
        _ request: ContentTabMoveRequest,
        state: State,
    ) -> Bool {
        let requestedWindowIDs: Set<State.WindowID> = [request.sourceWindowID, request.targetWindowID]
        return state.contentTabMoveTransactions.values.contains { transaction in
            let activeWindowIDs: Set<State.WindowID> = [
                transaction.request.sourceWindowID,
                transaction.request.targetWindowID,
            ]
            return !requestedWindowIDs.isDisjoint(with: activeWindowIDs)
        }
    }

    private func contentTabMoveUndoDescriptors(
        _ token: ContentTabTransfer.SuccessToken,
        originalTarget: FileManagerWindowFeature.State,
    ) -> [FileOperationUndoScopeMoveDescriptor] {
        token.rebindIntents.compactMap { intent in
            guard intent.rebindUndoScope else { return nil }
            return FileOperationUndoScopeMoveDescriptor(
                source: UndoManagerScope(
                    windowID: intent.sourceWindowID,
                    contentTabID: intent.tabID.rawValue,
                ),
                target: UndoManagerScope(
                    windowID: intent.targetWindowID,
                    contentTabID: intent.tabID.rawValue,
                ),
                targetPolicy: originalTarget.contentTabs.tabs[id: intent.tabID] == nil
                    ? .requireVacant
                    : .replaceEmpty,
            )
        }
    }

    private func contentTabMoveLifecycleEffects(
        teardownIntents: [ContentTabTransfer.TeardownIntent],
        rebindIntents: [ContentTabTransfer.RebindIntent],
    ) -> Effect<Action> {
        .concatenate(
            contentTabMoveTeardownEffect(teardownIntents),
            contentTabMoveObservationRebindEffect(rebindIntents),
        )
    }

    private func contentTabMoveTeardownEffect(
        _ intents: [ContentTabTransfer.TeardownIntent],
    ) -> Effect<Action> {
        var loadingScopes: Set<ContentTabTransfer.LoadingTeardownScope> = []
        var composerScopes: Set<ContentTabTransfer.ComposerTeardownScope> = []
        var effects: [Effect<Action>] = []
        for intent in intents {
            if let scope = intent.loadingScope, loadingScopes.insert(scope).inserted {
                effects.append(.cancel(id: EntryOperationsLoadingCancelID.loadItems(
                    windowID: scope.windowID,
                    ownerID: scope.ownerID,
                )))
            }
            if let scope = intent.composerScope, composerScopes.insert(scope).inserted {
                effects.append(.cancel(id: ComposerFeature.CancelID.search(ownerID: scope.ownerID)))
                effects.append(.cancel(id: ComposerFeature.CancelID.filters(ownerID: scope.ownerID)))
            }
        }
        return .concatenate(effects)
    }

    private func contentTabMoveObservationRebindEffect(
        _ intents: [ContentTabTransfer.RebindIntent],
    ) -> Effect<Action> {
        .concatenate(intents.compactMap { intent in
            guard intent.rebindNavigationObservation else { return nil }
            let targetEffect = contentTabMoveObservationSequence(intent.targetActiveNavigationObservation)
            guard let source = intent.sourceActiveNavigationObservation else { return targetEffect }
            return .concatenate(
                contentTabMoveObservationSequence(source),
                targetEffect,
            )
        })
    }

    private func contentTabMoveObservationSequence(
        _ rebind: ContentTabTransfer.ActiveNavigationObservationRebind,
    ) -> Effect<Action> {
        .concatenate(
            contentTabMoveObservationEffect(rebind, action: .internal(.stopObservingSystemNotifications)),
            contentTabMoveObservationEffect(rebind, action: .internal(.startObservingSystemNotifications)),
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
        for outcome: FileOperationUndoScopesMoveOutcome,
    ) -> ContentTabMoveFailurePresentation.Category {
        switch outcome {
        case .sourceMissing:
            .unavailable
        case .moved:
            preconditionFailure("Successful Undo batch has no rejection category")
        case .emptyBatch, .duplicateSource, .duplicateTarget, .targetOccupied:
            .generic
        }
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
