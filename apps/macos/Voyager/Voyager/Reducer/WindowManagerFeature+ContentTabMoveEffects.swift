import ComposableArchitecture
import Foundation
import VoyagerFeaturesComposer
import VoyagerFeaturesEntryOperations
import VoyagerPagesFileManager
import VoyagerWidgetsEntryViewLayout

extension WindowManagerFeature {
    func contentTabMoveLifecycleEffects(
        request: ContentTabMoveRequest,
        teardownIntents: [ContentTabTransfer.TeardownIntent],
        rebindIntents: [ContentTabTransfer.RebindIntent],
        target: FileManagerWindowState,
    ) -> Effect<Action> {
        .concatenate(
            contentTabMoveTeardownEffect(
                teardownIntents,
                targetWindowID: request.targetWindowID,
            ),
            contentTabMoveFolderTeardownEffect(
                request: request,
                rebindIntents,
                target: target,
            ),
            contentTabMoveCollectionTeardownEffect(
                rebindIntents,
                target: target,
            ),
            contentTabMoveOwnerRebindEffect(
                request: request,
                rebindIntents,
            ),
            contentTabMoveHierarchyRestartEffect(
                request: request,
                rebindIntents,
            ),
            contentTabMoveCollectionRestartEffect(
                request: request,
                rebindIntents,
                target: target,
            ),
            contentTabMoveObservationRebindEffect(
                request: request,
                rebindIntents,
            ),
        )
    }

    func contentTabMoveFolderTeardownEffect(
        request: ContentTabMoveRequest,
        _ intents: [ContentTabTransfer.RebindIntent],
        target: FileManagerWindowState,
    ) -> Effect<Action> {
        // projectTarget가 commit 시점에 moved tab의 entryOperations.windowID를 이미 target으로 재지정하므로,
        // 이 시점의 cancelAllFolderItems는 target-keyed cancel ID만 만들어 원본 source-keyed folder stream을
        // 놓친다. 따라서 postCommit.target에 복사된 folderLoadingContexts의 requestID와, 각 rebind의
        // sourceWindowID 및 복사된 stable loadingCancellationOwnerID를 조합해 source-keyed cancel ID를
        // 명시적으로 먼저 발행한다. 그 뒤의 cancelAllFolderItems가 복사된 folderLoadingContexts를 비운다.
        var sourceKeyedCancelIDs = Set<EntryOperationsFolderLoadingCancelID>()
        for intent in intents {
            guard let entryOperations = movedEntryOperations(for: intent.tabID, in: target) else { continue }
            let ownerID = entryOperations.loadingCancellationOwnerID
            for requestID in entryOperations.folderLoadingContexts.keys {
                sourceKeyedCancelIDs.insert(.loadFolderItems(
                    requestID: requestID,
                    windowID: intent.sourceWindowID,
                    ownerID: ownerID,
                ))
            }
        }
        let clearEffects = intents.map { intent in
            contentTabMoveWindowActionEffect(
                request: request,
                windowID: intent.targetWindowID,
                action: .tabContent(
                    tabID: intent.tabID,
                    action: .entryViewLayout(.entryOperations(.loading(.cancelAllFolderItems))),
                ),
            )
        }
        return .concatenate(sourceKeyedCancelIDs.map { .cancel(id: $0) } + clearEffects)
    }

    func movedEntryOperations(
        for tabID: ContentTabID,
        in target: FileManagerWindowState,
    ) -> EntryOperationsState? {
        movedEntryViewLayout(for: tabID, in: target)?.entryOperations
    }

    func movedEntryViewLayout(
        for tabID: ContentTabID,
        in target: FileManagerWindowState,
    ) -> EntryViewLayoutState? {
        if target.contentTabs.activeTabID == tabID {
            return target.content.entryViewLayout
        }
        return target.tabContentStates[tabID]?.entryViewLayout
    }

    func contentTabMoveCollectionTeardownEffect(
        _ intents: [ContentTabTransfer.RebindIntent],
        target: FileManagerWindowState,
    ) -> Effect<Action> {
        var cancelIDs = Set<EntryViewLayoutCollectionCancelID>()
        for intent in intents {
            guard let layout = movedEntryViewLayout(for: intent.tabID, in: target) else { continue }
            let ownerID = layout.entryOperations.loadingCancellationOwnerID
            if !layout.activeCollectionReplacePaths.isEmpty {
                cancelIDs.insert(.replace(windowID: intent.sourceWindowID, ownerID: ownerID))
            }
            for token in layout.activeAppendExpectedBatchIndices.keys {
                cancelIDs.insert(.append(
                    token: token,
                    windowID: intent.sourceWindowID,
                    ownerID: ownerID,
                ))
            }
        }
        return .concatenate(cancelIDs.map { .cancel(id: $0) })
    }

    func contentTabMoveHierarchyRestartEffect(
        request: ContentTabMoveRequest,
        _ intents: [ContentTabTransfer.RebindIntent],
    ) -> Effect<Action> {
        .concatenate(intents.map { intent in
            contentTabMoveWindowActionEffect(
                request: request,
                windowID: intent.targetWindowID,
                action: .tabContent(
                    tabID: intent.tabID,
                    action: .entryViewLayout(.hierarchy(.restartUnfinishedExpandedFolderLoads)),
                ),
            )
        })
    }

    func contentTabMoveCollectionRestartEffect(
        request: ContentTabMoveRequest,
        _ intents: [ContentTabTransfer.RebindIntent],
        target: FileManagerWindowState,
    ) -> Effect<Action> {
        .concatenate(intents.compactMap { intent in
            guard let layout = movedEntryViewLayout(for: intent.tabID, in: target),
                  !layout.activeCollectionReplacePaths.isEmpty
                  || !layout.activeAppendExpectedBatchIndices.isEmpty
            else { return nil }
            return contentTabMoveWindowActionEffect(
                request: request,
                windowID: intent.targetWindowID,
                action: .tabContent(
                    tabID: intent.tabID,
                    action: .entryViewLayout(.internal(.restartCollectionMaterialization)),
                ),
            )
        })
    }

    func contentTabMoveOwnerRebindEffect(
        request: ContentTabMoveRequest,
        _ intents: [ContentTabTransfer.RebindIntent],
    ) -> Effect<Action> {
        .concatenate(intents.map { intent in
            contentTabMoveWindowActionEffect(
                request: request,
                windowID: intent.targetWindowID,
                action: .tabContent(
                    tabID: intent.tabID,
                    action: .entryViewLayout(.entryOperations(.lifecycle(.windowIDChanged(intent.targetWindowID)))),
                ),
            )
        })
    }

    func contentTabMoveTeardownEffect(
        _ intents: [ContentTabTransfer.TeardownIntent],
        targetWindowID: UUID,
    ) -> Effect<Action> {
        var loadingScopes: Set<ContentTabTransfer.LoadingTeardownScope> = []
        var composerOwnerIDs: Set<UUID> = []
        var effects: [Effect<Action>] = []
        for intent in intents {
            if let scope = intent.loadingScope, loadingScopes.insert(scope).inserted {
                effects.append(.cancel(id: EntryOperationsLoadingCancelID.loadItems(
                    windowID: scope.windowID,
                    ownerID: scope.ownerID,
                )))
            }
            if let scope = intent.composerScope, composerOwnerIDs.insert(scope.ownerID).inserted {
                effects.append(.send(.windows(.element(
                    id: targetWindowID,
                    action: .window(.tabContent(
                        tabID: intent.tabID,
                        action: .composer(.internal(.cleanupCollectionWork)),
                    )),
                ))))
            }
        }
        return .concatenate(effects)
    }

    func contentTabMoveObservationRebindEffect(
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

    func contentTabMoveObservationSequence(
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

    func contentTabMoveObservationEffect(
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

    func contentTabMoveWindowActionEffect(
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

    func contentTabMoveCategory(
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

    func contentTabMoveCategory(
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

    func contentTabMoveCategory(
        for failure: FileManagerTopNavigationIntentFailure,
    ) -> ContentTabMoveFailurePresentation.Category {
        switch failure {
        case .cancelled, .superseded, .save, .storeUnavailable:
            .generic
        }
    }

    func contentTabMovePinnedAt(_ request: ContentTabMoveRequest) -> Date? {
        guard request.sourceDomain != .pinned, request.targetDomain == .pinned else { return nil }
        return date()
    }

    func targetFixedLocationIDs(
        from state: State,
        request: ContentTabMoveRequest,
    ) -> [String] {
        state.windows[id: request.targetWindowID]?.window.lastConfirmedTopNavigationOrder.items.compactMap { item in
            guard case let .location(id) = item else { return nil }
            return id
        } ?? []
    }

    func rollbackUndoDescriptors(
        from descriptors: [FileOperationUndoScopeMoveDescriptor],
    ) -> [FileOperationUndoScopeMoveDescriptor] {
        descriptors.map { descriptor in
            .init(source: descriptor.target, target: descriptor.source)
        }
    }

    func isMatchingContentTabMoveSourceWindow(
        _ request: ContentTabMoveRequest,
        sourceWindow: FileManagerWindowFeature.State,
    ) -> Bool {
        sourceWindow.pendingContentTabMove?.lifecycle == .inFlight
            && sourceWindow.pendingContentTabMove?.request == request
            && sourceWindow.sidebar.pendingContentTabMoveRequest == request
    }

    func validatedContentTabMoveTargetWindow(
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

    func contentTabMoveHasBusyConflict(
        _ request: ContentTabMoveRequest,
        state: State,
    ) -> Bool {
        contentTabMoveOverlapsActiveTransaction(request, state: state)
            || !state.contentTabMoveActivationAttempts.isEmpty
            || state.topNavigationPersistenceQueue.contains(where: { queued in
                guard case let .pinnedRecord(_, persistenceRequest, _) = queued.operation else { return false }
                return request.orderedTabIDs.contains(persistenceRequest.tabID)
            })
    }

    func contentTabMoveCategory(
        for error: PreparedContentTabMoveError,
    ) -> ContentTabMoveFailurePresentation.Category {
        switch error {
        case let .rejection(rejection):
            contentTabMoveCategory(for: rejection)
        case let .undoOutcome(undoOutcome):
            contentTabMoveCategory(for: undoOutcome)
        }
    }

    func prepareContentTabMove(
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
