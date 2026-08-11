import ComposableArchitecture
import Foundation
import VoyagerFeaturesComposer
import VoyagerFeaturesEntryOperations
import VoyagerPagesFileManager

extension WindowManagerFeature {
    private struct PreparedContentTabMove {
        let token: ContentTabTransfer.SuccessToken
        let pendingPersistence: ContentTabMoveTransaction.PendingPersistence
        let durablePinnedMutation: ContentTabTransfer.DurablePinnedBatchMutation?
    }

    private enum PreparedContentTabMoveError: Error {
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

    private func finishPreparedContentTabMove(
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

    private func setContentTabMoveParticipant(
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

    private func enqueueCorrelatedContentTabMovePersistence(
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
            return .none
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

    private func commitContentTabMove(
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

    private func contentTabMoveUndoRecovery(
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

    private func commitCorrelatedContentTabMove(
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
            ),
            .send(.contentTabMoveLifecycleCompleted(request: request)),
            .send(.contentTabMoveNativeEffectsRequested(request: request)),
            .merge(
                startNextTopNavigationPersistenceIfNeeded(state: &state),
                bootstrapLifecycle.restart,
            ),
        )
    }

    private func installCorrelatedContentTabMoveCommit(
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

    private func correlatedContentTabMoveParticipantSnapshotEffects(
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

    private func rejectContentTabMove(
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

    private func correlatedContentTabMoveTerminalEffect(
        _ request: ContentTabMoveRequest,
        outcome: ContentTabMoveTerminalRecord.Outcome,
    ) -> Effect<Action> {
        contentTabMoveWindowActionEffect(
            request: request,
            windowID: request.sourceWindowID,
            action: contentTabMoveTerminalWindowAction(request, outcome: outcome),
        )
    }

    private func contentTabMoveTerminalEffect(
        _ request: ContentTabMoveRequest,
        outcome: ContentTabMoveTerminalRecord.Outcome,
    ) -> Effect<Action> {
        .send(.windows(.element(
            id: request.sourceWindowID,
            action: .window(contentTabMoveTerminalWindowAction(request, outcome: outcome)),
        )))
    }

    private func contentTabMoveTerminalWindowAction(
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
        request: ContentTabMoveRequest,
        teardownIntents: [ContentTabTransfer.TeardownIntent],
        rebindIntents: [ContentTabTransfer.RebindIntent],
    ) -> Effect<Action> {
        .concatenate(
            contentTabMoveTeardownEffect(teardownIntents),
            contentTabMoveObservationRebindEffect(
                request: request,
                rebindIntents,
            ),
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
        request: ContentTabMoveRequest,
        _ intents: [ContentTabTransfer.RebindIntent],
    ) -> Effect<Action> {
        .concatenate(intents.compactMap { intent in
            guard intent.rebindNavigationObservation else { return nil }
            var effects: [Effect<Action>] = []
            if let source = intent.sourceActiveNavigationObservation {
                effects.append(contentTabMoveObservationSequence(request: request, rebind: source))
            }
            effects.append(contentTabMoveObservationSequence(
                request: request,
                rebind: intent.targetActiveNavigationObservation,
            ))
            return effects.isEmpty ? nil : .concatenate(effects)
        })
    }

    private func contentTabMoveObservationSequence(
        request: ContentTabMoveRequest,
        rebind: ContentTabTransfer.ActiveNavigationObservationRebind,
    ) -> Effect<Action> {
        .concatenate(
            contentTabMoveObservationEffect(
                request: request,
                rebind: rebind,
                action: .internal(.stopObservingSystemNotifications),
            ),
            contentTabMoveObservationEffect(
                request: request,
                rebind: rebind,
                action: .internal(.startObservingSystemNotifications),
            ),
            contentTabMoveObservationEffect(
                request: request,
                rebind: rebind,
                action: .internal(.applyNavigationState(rebind.navigationRoute)),
            ),
        )
    }

    private func contentTabMoveObservationEffect(
        request: ContentTabMoveRequest,
        rebind: ContentTabTransfer.ActiveNavigationObservationRebind,
        action: FileManagerContentAction,
    ) -> Effect<Action> {
        contentTabMoveWindowActionEffect(
            request: request,
            windowID: rebind.windowID,
            action: .tabContent(tabID: rebind.tabID, action: action),
        )
    }

    private func contentTabMoveWindowActionEffect(
        request: ContentTabMoveRequest,
        windowID: State.WindowID,
        action: FileManagerWindowAction,
    ) -> Effect<Action> {
        .send(.contentTabMoveWindowActionRequested(
            request: request,
            windowID: windowID,
            action: action,
        ))
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
        case .ineligible(.malformedOwnership),
             .missingPinnedTimestamp,
             .targetPlacementInvalid:
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

    private func contentTabMoveCategory(
        for failure: FileManagerTopNavigationIntentFailure,
    ) -> ContentTabMoveFailurePresentation.Category {
        switch failure {
        case .cancelled, .superseded, .save, .storeUnavailable:
            .generic
        }
    }

    private func contentTabMovePinnedAt(_ request: ContentTabMoveRequest) -> Date? {
        guard request.sourceDomain != .pinned, request.targetDomain == .pinned else { return nil }
        return date()
    }

    private func targetFixedLocationIDs(
        from state: State,
        request: ContentTabMoveRequest,
    ) -> [String] {
        state.windows[id: request.targetWindowID]?.window.lastConfirmedTopNavigationOrder.items.compactMap { item in
            guard case let .location(id) = item else { return nil }
            return id
        } ?? []
    }

    private func rollbackUndoDescriptors(
        from descriptors: [FileOperationUndoScopeMoveDescriptor],
    ) -> [FileOperationUndoScopeMoveDescriptor] {
        descriptors.map { descriptor in
            .init(source: descriptor.target, target: descriptor.source)
        }
    }

    private func isMatchingContentTabMoveSourceWindow(
        _ request: ContentTabMoveRequest,
        sourceWindow: FileManagerWindowFeature.State,
    ) -> Bool {
        sourceWindow.pendingContentTabMove?.lifecycle == .inFlight
            && sourceWindow.pendingContentTabMove?.request == request
            && sourceWindow.sidebar.pendingContentTabMoveRequest == request
    }

    private func validatedContentTabMoveTargetWindow(
        _ request: ContentTabMoveRequest,
        state: State,
    ) -> FileManagerWindowFeature.State? {
        guard request.sourceWindowID != request.targetWindowID,
              isWindowReady(request.sourceWindowID, state: state),
              isWindowReady(request.targetWindowID, state: state),
              let targetWindow = state.windows[id: request.targetWindowID]?.window
        else {
            return nil
        }
        return targetWindow
    }

    private func contentTabMoveHasBusyConflict(
        _ request: ContentTabMoveRequest,
        state: State,
    ) -> Bool {
        contentTabMoveOverlapsActiveTransaction(request, state: state)
            || state.topNavigationPersistenceQueue.contains(where: { queued in
                guard case let .pinnedRecord(_, persistenceRequest, _) = queued.operation else { return false }
                return request.orderedTabIDs.contains(persistenceRequest.tabID)
            })
    }

    private func contentTabMoveCategory(
        for error: PreparedContentTabMoveError,
    ) -> ContentTabMoveFailurePresentation.Category {
        switch error {
        case let .rejection(rejection):
            contentTabMoveCategory(for: rejection)
        case let .undoOutcome(undoOutcome):
            contentTabMoveCategory(for: undoOutcome)
        }
    }

    private func prepareContentTabMove(
        _ request: ContentTabMoveRequest,
        sourceWindow: FileManagerWindowFeature.State,
        targetWindow: FileManagerWindowFeature.State,
    ) throws -> PreparedContentTabMove {
        let pinnedAt = contentTabMovePinnedAt(request)
        let token = switch ContentTabTransfer.preflight(
            source: sourceWindow,
            target: targetWindow,
            orderedTabIDs: request.orderedTabIDs,
            primaryTabID: request.initiatingTabID,
            sourceDomain: request.sourceDomain,
            targetDomain: request.targetDomain,
            placement: request.placement,
            pinnedAt: pinnedAt,
        ) {
        case let .success(token): token
        case let .rejected(reason): throw PreparedContentTabMoveError.rejection(reason)
        }

        let undoDescriptors = contentTabMoveUndoDescriptors(token, originalTarget: targetWindow)
        let undoOutcome = fileOperationUndoManagerClient.moveScopes(undoDescriptors)
        guard undoOutcome == .moved else { throw PreparedContentTabMoveError.undoOutcome(undoOutcome) }
        let undoMoveReceipts = undoDescriptors.map { descriptor in
            FileOperationUndoScopeMoveReceipt(
                descriptor: descriptor,
                targetGeneration: fileOperationUndoManagerClient.generation(descriptor.target),
            )
        }

        let pendingPersistence = switch ContentTabTransfer.apply(token) {
        case let .moved(postCommit):
            ContentTabMoveTransaction.PendingPersistence(
                postCommit: postCommit,
                closesSourceWindow: false,
                undoDescriptors: undoDescriptors,
                undoMoveReceipts: undoMoveReceipts,
            )
        case let .closeSourceWindow(postCommit):
            ContentTabMoveTransaction.PendingPersistence(
                postCommit: postCommit,
                closesSourceWindow: true,
                undoDescriptors: undoDescriptors,
                undoMoveReceipts: undoMoveReceipts,
            )
        case .rejected:
            preconditionFailure("Validated ContentTabTransfer token must apply infallibly")
        }

        return PreparedContentTabMove(
            token: token,
            pendingPersistence: pendingPersistence,
            durablePinnedMutation: token.durablePinnedMutation,
        )
    }
}
