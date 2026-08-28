import ComposableArchitecture
import Foundation
import VoyagerFeaturesComposer
import VoyagerFeaturesEntryOperations
import VoyagerPagesFileManager
import VoyagerWidgetsEntryViewLayout

extension WindowManagerFeature {
    struct PreparedContentTabMove {
        let token: ContentTabTransfer.SuccessToken
        let pendingPersistence: ContentTabMoveTransaction.PendingPersistence
        let durablePinnedMutation: ContentTabTransfer.DurablePinnedBatchMutation?
    }

    enum PreparedContentTabMoveError: Error {
        case rejection(ContentTabTransfer.Rejection)
        case undoOutcome(FileOperationUndoScopesMoveOutcome)
    }

    func handleContentTabMoveRequest(
        _ request: ContentTabMoveRequest,
        state: inout State,
    ) -> Effect<Action> {
        guard state.contentTabMoveTerminalRecords[request.requestID] == nil else { return .none }
        guard let sourceWindow = state.windows[id: request.sourceWindowID]?.window else { return .none }
        if sourceWindow.pendingContentTabMove?.lifecycle == .inFlight,
           let pendingRequest = sourceWindow.pendingContentTabMove?.request,
           pendingRequest.requestID == request.requestID,
           pendingRequest != request
        {
            return .none
        }
        guard isMatchingContentTabMoveSourceWindow(request, sourceWindow: sourceWindow) else {
            return rejectContentTabMove(request, category: .unavailable, state: &state)
        }
        guard let targetWindow = validatedContentTabMoveTargetWindow(request, state: state) else {
            return rejectContentTabMove(request, category: .unavailable, state: &state)
        }
        guard !contentTabMoveHasBusyConflict(request, state: state) else {
            return rejectContentTabMove(request, category: .busy, state: &state)
        }

        let prepared: PreparedContentTabMove
        do {
            prepared = try prepareContentTabMove(
                request,
                sourceWindow: sourceWindow,
                targetWindow: targetWindow,
            )
        } catch let error as PreparedContentTabMoveError {
            return rejectContentTabMove(request, category: contentTabMoveCategory(for: error), state: &state)
        } catch {
            preconditionFailure("Unexpected ContentTab move preparation error: \(error)")
        }

        return finishPreparedContentTabMove(request, prepared: prepared, state: &state)
    }

    func finishPreparedContentTabMove(
        _ request: ContentTabMoveRequest,
        prepared: PreparedContentTabMove,
        state: inout State,
    ) -> Effect<Action> {
        setContentTabMoveParticipant(request, state: &state)
        if let durablePinnedMutation = prepared.durablePinnedMutation {
            return enqueueCorrelatedContentTabMovePersistence(
                request,
                durablePinnedMutation: durablePinnedMutation,
                pendingPersistence: prepared.pendingPersistence,
                state: &state,
            )
        }
        return commitContentTabMove(
            request,
            postCommit: prepared.pendingPersistence.postCommit,
            closesSourceWindow: prepared.pendingPersistence.closesSourceWindow,
            state: &state,
        )
    }

    func setContentTabMoveParticipant(
        _ request: ContentTabMoveRequest,
        state: inout State,
    ) {
        state.windows[id: request.sourceWindowID]?.window.contentTabMoveParticipantRequestID = request.requestID
        state.windows[id: request.targetWindowID]?.window.contentTabMoveParticipantRequestID = request.requestID
    }

    func clearContentTabMoveParticipant(
        _ request: ContentTabMoveRequest,
        state: inout State,
    ) {
        for windowID in [request.sourceWindowID, request.targetWindowID]
            where state.windows[id: windowID]?.window.contentTabMoveParticipantRequestID == request.requestID
        {
            state.windows[id: windowID]?.window.contentTabMoveParticipantRequestID = nil
        }
    }

    func enqueueCorrelatedContentTabMovePersistence(
        _ request: ContentTabMoveRequest,
        durablePinnedMutation: ContentTabTransfer.DurablePinnedBatchMutation,
        pendingPersistence: ContentTabMoveTransaction.PendingPersistence,
        state: inout State,
    ) -> Effect<Action> {
        state.contentTabMoveTransactions[request.requestID] = .init(
            request: request,
            pendingPersistence: pendingPersistence,
        )
        return .send(.topNavigationPersistenceRequested(.init(
            sourceWindowID: request.sourceWindowID,
            token: contentTabPinnedRecordClient.reserveTopNavigationOperationToken(),
            operation: .contentTabMove(
                request: request,
                mutation: durablePinnedMutation,
                discoveredLocationIDs: targetFixedLocationIDs(from: state, request: request),
            ),
        )))
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
        guard isWindowReady(request.targetWindowID, state: state) else {
            state.contentTabMoveActivationAttempts[request.requestID] = nil
            state.contentTabMoveTransactions[request.requestID] = nil
            clearContentTabMoveParticipant(request, state: &state)
            return finalizeDeferredWindowClosuresWithoutPendingPersistence(state: &state)
        }

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

    func commitContentTabMove(
        _ request: ContentTabMoveRequest,
        postCommit: ContentTabTransfer.PostCommit,
        closesSourceWindow: Bool,
        state: inout State,
    ) -> Effect<Action> {
        state.windows[id: request.sourceWindowID]?.window = postCommit.source
        state.windows[id: request.targetWindowID]?.window = postCommit.target
        setContentTabMoveParticipant(request, state: &state)
        state.recordContentTabMoveTerminal(.init(request: request, outcome: .succeeded))
        state.contentTabMoveTransactions[request.requestID] = .init(request: request)
        state.contentTabMoveNativeEffectsPlans[request.requestID] = .init(
            request: request,
            closesSourceWindow: closesSourceWindow,
        )
        state.contentTabMoveActivationAttempts[request.requestID] = .init(request: request)
        state.refreshContentTabMoveTargets()

        return .concatenate(
            correlatedContentTabMoveTerminalEffect(request, outcome: .succeeded),
            contentTabMoveLifecycleEffects(
                request: request,
                teardownIntents: postCommit.teardownIntents,
                rebindIntents: postCommit.rebinds,
                target: postCommit.target,
            ),
            .send(.contentTabMoveLifecycleCompleted(request: request)),
            .send(.contentTabMoveNativeEffectsRequested(request: request)),
        )
    }

    func completeCorrelatedContentTabMovePersistence(
        _ result: WindowManagerTopNavigationPersistenceResult,
        state: inout State,
    ) -> Effect<Action> {
        guard case let .contentTabMove(request, _, _) = result.request.operation else {
            return .none
        }
        guard let transaction = state.contentTabMoveTransactions[request.requestID],
              transaction.request == request,
              let pendingPersistence = transaction.pendingPersistence
        else {
            return .merge(
                .send(.finalizeDeferredWindowClosures),
                startNextTopNavigationPersistenceIfNeeded(state: &state),
            )
        }

        switch result.terminal {
        case let .committed(commit):
            guard let authoritativePinnedContentTabs = result.authoritativePinnedContentTabs else {
                preconditionFailure("Correlated Content Tab move requires authoritative pinned snapshot")
            }
            return commitCorrelatedContentTabMove(
                request,
                pendingPersistence: pendingPersistence,
                commit: commit,
                authoritativePinnedContentTabs: authoritativePinnedContentTabs,
                state: &state,
            )

        case let .failed(failure):
            let rollbackOutcome = fileOperationUndoManagerClient.moveScopes(
                rollbackUndoDescriptors(from: pendingPersistence.undoDescriptors),
            )
            let undoRecovery = contentTabMoveUndoRecovery(
                pendingPersistence: pendingPersistence,
                rollbackOutcome: rollbackOutcome,
            )
            return .concatenate(
                rejectContentTabMove(
                    request,
                    category: contentTabMoveCategory(for: failure),
                    state: &state,
                    undoRecovery: undoRecovery,
                ),
                .send(.contentTabMoveLifecycleCompleted(request: request)),
                .merge(
                    startNextTopNavigationPersistenceIfNeeded(state: &state),
                ),
            )
        }
    }

    func contentTabMoveUndoRecovery(
        pendingPersistence: ContentTabMoveTransaction.PendingPersistence,
        rollbackOutcome: FileOperationUndoScopesMoveOutcome,
    ) -> ContentTabMoveTerminalRecord.UndoRecovery {
        guard rollbackOutcome != .moved else { return .preserved }
        return switch fileOperationUndoManagerClient.reconcileFailedScopeMove(
            pendingPersistence.undoMoveReceipts,
            rollbackOutcome,
        ) {
        case .restored:
            .reconciled(rollbackOutcome)
        case let .historyLost(reverseOutcome):
            .historyLost(reverseOutcome)
        }
    }

    func commitCorrelatedContentTabMove(
        _ request: ContentTabMoveRequest,
        pendingPersistence: ContentTabMoveTransaction.PendingPersistence,
        commit: FileManagerTopNavigationCommit,
        authoritativePinnedContentTabs: ContentTabState,
        state: inout State,
    ) -> Effect<Action> {
        let usesUnavailableTargetFallback = installCorrelatedContentTabMoveCommit(
            request,
            pendingPersistence: pendingPersistence,
            state: &state,
        )
        let bootstrapLifecycle = invalidateAndRestartDefaultWindowBootstrapForTopNavigationChange(state: &state)
        return .concatenate(
            bootstrapLifecycle.cancel,
            correlatedContentTabMoveParticipantSnapshotEffects(
                request,
                commit: commit,
                authoritativePinnedContentTabs: authoritativePinnedContentTabs,
                state: state,
            ),
            fanOutCommittedTopNavigationSnapshot(
                commit,
                authoritativePinnedContentTabs: authoritativePinnedContentTabs,
                state: state,
                excludingWindowIDs: [request.sourceWindowID, request.targetWindowID],
            ),
            correlatedContentTabMoveTerminalEffect(request, outcome: .succeeded),
            contentTabMoveLifecycleEffects(
                request: request,
                teardownIntents: usesUnavailableTargetFallback
                    ? pendingPersistence.postCommit.unavailableTargetFallbackTeardownIntents
                    : pendingPersistence.postCommit.teardownIntents,
                rebindIntents: usesUnavailableTargetFallback ? [] : pendingPersistence.postCommit.rebinds,
                target: pendingPersistence.postCommit.target,
            ),
            .send(.contentTabMoveLifecycleCompleted(request: request)),
            .send(.contentTabMoveNativeEffectsRequested(request: request)),
            .merge(
                startNextTopNavigationPersistenceIfNeeded(state: &state),
                bootstrapLifecycle.restart,
            ),
        )
    }

    func installCorrelatedContentTabMoveCommit(
        _ request: ContentTabMoveRequest,
        pendingPersistence: ContentTabMoveTransaction.PendingPersistence,
        state: inout State,
    ) -> Bool {
        let fallbackSource = isWindowReady(request.targetWindowID, state: state)
            ? nil
            : pendingPersistence.postCommit.unavailableTargetFallbackSource
        let undoRecovery: ContentTabMoveTerminalRecord.UndoRecovery
        if let fallbackSource {
            let rollbackOutcome = fileOperationUndoManagerClient.moveScopes(
                rollbackUndoDescriptors(from: pendingPersistence.undoDescriptors),
            )
            undoRecovery = contentTabMoveUndoRecovery(
                pendingPersistence: pendingPersistence,
                rollbackOutcome: rollbackOutcome,
            )
            state.windows[id: request.sourceWindowID]?.window = fallbackSource
        } else {
            undoRecovery = .preserved
            state.windows[id: request.sourceWindowID]?.window = pendingPersistence.postCommit.source
            state.windows[id: request.targetWindowID]?.window = pendingPersistence.postCommit.target
        }
        setContentTabMoveParticipant(request, state: &state)
        state.recordContentTabMoveTerminal(.init(
            request: request,
            outcome: .succeeded,
            undoRecovery: undoRecovery,
        ))
        state.contentTabMoveTransactions[request.requestID] = .init(request: request)
        if fallbackSource == nil {
            state.contentTabMoveNativeEffectsPlans[request.requestID] = .init(
                request: request,
                closesSourceWindow: pendingPersistence.closesSourceWindow,
            )
            state.contentTabMoveActivationAttempts[request.requestID] = .init(request: request)
        }
        state.refreshContentTabMoveTargets()
        return fallbackSource != nil
    }

    func correlatedContentTabMoveParticipantSnapshotEffects(
        _ request: ContentTabMoveRequest,
        commit: FileManagerTopNavigationCommit,
        authoritativePinnedContentTabs: ContentTabState,
        state: State,
    ) -> Effect<Action> {
        let snapshotEffect: (State.WindowID) -> Effect<Action> = { windowID in
            committedTopNavigationSnapshotAction(
                for: windowID,
                commit: commit,
                authoritativePinnedContentTabs: authoritativePinnedContentTabs,
                state: state,
            ).map {
                contentTabMoveWindowActionEffect(request: request, windowID: windowID, action: $0)
            } ?? .none
        }
        return .concatenate(
            snapshotEffect(request.targetWindowID),
            snapshotEffect(request.sourceWindowID),
        )
    }

    func rejectContentTabMove(
        _ request: ContentTabMoveRequest,
        category: ContentTabMoveFailurePresentation.Category,
        state: inout State,
        undoRecovery: ContentTabMoveTerminalRecord.UndoRecovery = .preserved,
    ) -> Effect<Action> {
        state.recordContentTabMoveTerminal(.init(
            request: request,
            outcome: .rejected(category),
            undoRecovery: undoRecovery,
        ))
        if state.contentTabMoveTransactions[request.requestID]?.request == request {
            return correlatedContentTabMoveTerminalEffect(request, outcome: .rejected(category))
        }
        guard state.windows[id: request.sourceWindowID] != nil,
              !state.closingWindowIDs.contains(request.sourceWindowID)
        else { return .none }
        return contentTabMoveTerminalEffect(request, outcome: .rejected(category))
    }

    func correlatedContentTabMoveTerminalEffect(
        _ request: ContentTabMoveRequest,
        outcome: ContentTabMoveTerminalRecord.Outcome,
    ) -> Effect<Action> {
        contentTabMoveWindowActionEffect(
            request: request,
            windowID: request.sourceWindowID,
            action: contentTabMoveTerminalWindowAction(request, outcome: outcome),
        )
    }

    func contentTabMoveTerminalEffect(
        _ request: ContentTabMoveRequest,
        outcome: ContentTabMoveTerminalRecord.Outcome,
    ) -> Effect<Action> {
        .send(.windows(.element(
            id: request.sourceWindowID,
            action: .window(contentTabMoveTerminalWindowAction(request, outcome: outcome)),
        )))
    }

    func contentTabMoveTerminalWindowAction(
        _ request: ContentTabMoveRequest,
        outcome: ContentTabMoveTerminalRecord.Outcome,
    ) -> FileManagerWindowAction {
        switch outcome {
        case .succeeded:
            .contentTabMoveSucceeded(request: request)
        case let .rejected(category):
            .contentTabMoveRejected(request: request, category: category)
        }
    }

    func contentTabMoveOverlapsActiveTransaction(
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

    func contentTabMoveUndoDescriptors(
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
}
