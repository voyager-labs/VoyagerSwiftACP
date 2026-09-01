import ComposableArchitecture
import Foundation
import VoyagerEntitiesCollection
import VoyagerEntitiesEntry
import VoyagerFeaturesEntryOperations
import VoyagerWidgetsEntryViewLayout

extension FileManagerFeature {
    func requestTopNavigationPin(
        tabID: ContentTabID,
        placement: ContentTabPlacement?,
        state: inout State,
    ) -> Bool {
        guard case .valid = ContentTabPinMutationPreflight.pin(
            id: tabID,
            placement: placement,
            state: state.contentTabs,
        ) else { return false }
        let dormantSlot = state.dormantContentTabSlots.first { $0.id == tabID }
        let optimisticOrder: FileManagerTopNavigationOrder
        if let placement {
            guard let projectedOrder = FileManagerTopNavigationOrderPolicy.insertingContentTab(
                tabID,
                at: placement,
                in: state.optimisticTopNavigationOrder,
            ) else { return false }
            optimisticOrder = projectedOrder
        } else {
            optimisticOrder = FileManagerTopNavigationOrderPolicy.insertingPinnedItem(
                tabID,
                into: state.optimisticTopNavigationOrder,
                dormantSlot: dormantSlot,
            )
        }
        let token = contentTabPinnedRecordClient.reserveTopNavigationOperationToken()
        state.pendingTopNavigationIntents.append(.init(token: token, intent: .pin(tabID, placement: placement)))
        if state.pendingSelectedContentTabPinMutation?.currentTabID == tabID {
            state.pendingSelectedContentTabPinMutation?.currentTopNavigationToken = token
        }
        state.optimisticTopNavigationOrder = optimisticOrder
        return true
    }

    func prepareTopNavigationUnpin(
        tabID: ContentTabID,
        placement: ContentTabPlacement?,
        state: inout State,
    ) -> Bool {
        guard ContentTabPinMutationPreflight.unpin(
            id: tabID,
            placement: placement,
            state: state.contentTabs,
        ) != nil else { return false }
        let item = FileManagerTopNavigationItemID.contentTab(tabID)
        guard let index = state.optimisticTopNavigationOrder.items.firstIndex(of: item) else { return false }
        let items = state.optimisticTopNavigationOrder.items
        let slot = FileManagerTopNavigationOrderPolicy.DormantContentTabSlot(
            id: tabID,
            before: index > items.startIndex ? items[index - 1] : nil,
            after: index + 1 < items.endIndex ? items[index + 1] : nil,
        )
        state.dormantContentTabSlots.removeAll { $0.id == tabID }
        state.dormantContentTabSlots.append(slot)
        let token = contentTabPinnedRecordClient.reserveTopNavigationOperationToken()
        state.pendingTopNavigationIntents.append(.init(token: token, intent: .unpin(tabID)))
        if state.pendingSelectedContentTabPinMutation?.currentTabID == tabID {
            state.pendingSelectedContentTabPinMutation?.currentTopNavigationToken = token
        }
        state.optimisticTopNavigationOrder = .init(items: items.filter { $0 != item })
        return true
    }

    func requestTopNavigationClose(
        tabID: ContentTabID,
        state: inout State,
    ) -> Effect<Action> {
        guard !state.contentTabs.pendingPinnedRecordIDs.contains(tabID) else { return .none }
        state.dormantContentTabSlots.removeAll { $0.id == tabID }
        guard state.contentTabs.tabs[id: tabID]?.isPinned == true else {
            state.replayTopNavigationOverlays()
            return .none
        }
        let token = contentTabPinnedRecordClient.reserveTopNavigationOperationToken()
        state.pendingTopNavigationIntents.append(.init(token: token, intent: .close(tabID)))
        state.optimisticTopNavigationOrder = .init(items: state.optimisticTopNavigationOrder.items.filter {
            $0 != .contentTab(tabID)
        })
        return .none
    }

    func prepareTopNavigationUpdate(
        tabID: ContentTabID,
        anchor: ContentTabPageAnchor,
        state: inout State,
    ) {
        guard state.contentTabs.tabs[id: tabID]?.isPinned == true,
              anchor.supportsPinnedRecordPersistence
        else { return }
        let token = contentTabPinnedRecordClient.reserveTopNavigationOperationToken()
        state.pendingTopNavigationIntents.append(.init(token: token, intent: .update(tabID)))
    }

    func completeTopNavigationLifecycleIfNeeded(
        tabID: ContentTabID,
        context: ContentTabPinnedRecordTerminalContext,
        terminal: FileManagerTopNavigationIntentTerminal?,
        state: inout State,
    ) -> Effect<Action> {
        guard state.contentTabs.isCurrentPinnedRecordPersistenceIntent(
            tabID: tabID,
            intentID: context.intentID,
        ) else { return .none }
        guard let pending = state.pendingTopNavigationIntents.last(where: { candidate in
            switch candidate.intent {
            case let .pin(id, _), let .unpin(id), let .close(id), let .update(id): id == tabID
            case .move, .movePinnedGroup: false
            }
        }) else {
            if case let .failed(.storeUnavailable(failure)) = terminal {
                state.topNavigationArrangementAvailability = .unavailable(failure)
                state.topNavigationArrangementPresentation = .init(failure: .storeUnavailable(failure))
            }
            return .none
        }

        let resolvedTerminal = resolveTopNavigationTerminal(terminal, state: state)
        let intent = pending.intent
        switch (intent, resolvedTerminal) {
        case (.pin(_, _), .committed(_)):
            state.dormantContentTabSlots.removeAll { $0.id == tabID }
        case (.unpin(_), .failed(_)):
            state.dormantContentTabSlots.removeAll { $0.id == tabID }
        default:
            break
        }
        _ = completeTopNavigationIntent(token: pending.token, terminal: resolvedTerminal, state: &state)
        state.replayTopNavigationOverlays()
        clearProductContentTabCloseMetricIfFailed(
            intent: intent,
            terminal: resolvedTerminal,
            state: &state,
        )
        return closeTopNavigationLifecycleEffect(
            intent: intent,
            terminal: resolvedTerminal,
            tabID: tabID,
            context: context,
            state: state,
        )
    }

    func completeContentTabPinnedRecordPersistence(
        action: ContentTabAction,
        state: inout State,
    ) -> Effect<Action> {
        guard let result = pinnedRecordPersistenceResult(action) else { return .none }
        return completeTopNavigationLifecycleIfNeeded(
            tabID: result.tabID,
            context: result.context,
            terminal: result.terminal,
            state: &state,
        )
    }

    func resolveTopNavigationTerminal(
        _ terminal: FileManagerTopNavigationIntentTerminal?,
        state: State,
    ) -> FileManagerTopNavigationIntentTerminal {
        if let terminal { return terminal }
        do {
            let commit = try contentTabPinnedRecordClient.loadTopNavigationCommit(
                userDefaultsClient,
                state.sidebar.allFixedLocationItems.map(\.id),
            )
            return .committed(commit)
        } catch let error as ContentTabPinnedRecordStoreLoadError {
            let failure: FileManagerTopNavigationArrangementLoadFailure = switch error {
            case .corruptUnavailable: .corrupt
            case let .futureSchemaUnavailable(schemaVersion): .unsupportedSchema(schemaVersion)
            }
            return .failed(.storeUnavailable(failure))
        } catch {
            return .failed(.save)
        }
    }

    func closeTopNavigationLifecycleEffect(
        intent: FileManagerTopNavigationIntent,
        terminal: FileManagerTopNavigationIntentTerminal,
        tabID: ContentTabID,
        context: ContentTabPinnedRecordTerminalContext,
        state: State,
    ) -> Effect<Action> {
        guard case .close = intent else { return .none }
        if let operationID = state.pendingContentTabClose?.batchOperationID {
            let outcome: SelectedContentTabCloseOutcome = switch terminal {
            case .committed:
                contentTabPinnedRecordClient.isCurrentMutationGeneration(context.generation)
                    ? .unpinned
                    : .cancelled
            case .failed(.save), .failed(.storeUnavailable):
                .failed
            case .failed(.superseded), .failed(.cancelled):
                .cancelled
            }
            return .send(.selectedContentTabCloseItemCompleted(
                operationID: operationID,
                tabID: tabID,
                outcome: outcome,
            ))
        }
        guard case .committed = terminal else { return .none }
        return .send(.contentTabs(.commitClose(tabID)))
    }

    func forwardPinnedRecordPersistence(
        _ request: ContentTabPinnedRecordPersistenceRequest,
        source: FileManagerPinnedRecordPersistenceSource,
        state: inout State,
    ) -> Effect<Action> {
        guard let index = state.pendingTopNavigationIntents.lastIndex(where: { pending in
            guard pending.persistenceContext == nil else { return false }
            switch pending.intent {
            case let .pin(tabID, _), let .unpin(tabID), let .close(tabID), let .update(tabID):
                return tabID == request.tabID
            case .move, .movePinnedGroup:
                return false
            }
        }) else { return .none }

        state.pendingTopNavigationIntents[index].persistenceContext = request.context
        if case let .selectedPin(operationID) = source,
           state.pendingSelectedContentTabPinMutation?.operationID == operationID,
           state.pendingSelectedContentTabPinMutation?.currentTabID == request.tabID
        {
            state.pendingSelectedContentTabPinMutation?.currentPersistenceContext = request.context
        }
        return .send(.delegate(.persistPinnedRecordMutation(
            token: state.pendingTopNavigationIntents[index].token,
            source: source,
            request: request,
            discoveredLocationIDs: state.sidebar.allFixedLocationItems.map(\.id),
        )))
    }

    func completePinnedRecordPersistence(
        token: FileManagerTopNavigationOperationToken,
        source: FileManagerPinnedRecordPersistenceSource,
        request: ContentTabPinnedRecordPersistenceRequest,
        terminal: FileManagerTopNavigationIntentTerminal,
        state: inout State,
    ) -> Effect<Action> {
        if case let .selectedPin(operationID) = source {
            guard let selectedPin = state.pendingSelectedContentTabPinMutation,
                  selectedPin.operationID == operationID,
                  selectedPin.currentTabID == request.tabID,
                  selectedPin.currentPersistenceContext == request.context,
                  selectedPin.currentTopNavigationToken == token
            else { return .none }
        }
        guard let pending = state.pendingTopNavigationIntents.first(where: { $0.token == token }) else {
            return .none
        }
        let isCurrentIntent = state.contentTabs.isCurrentPinnedRecordPersistenceIntent(
            tabID: request.tabID,
            intentID: request.context.intentID,
        )
        _ = completeTopNavigationIntent(
            token: token,
            terminal: terminal,
            state: &state,
            isCurrentTerminal: isCurrentIntent,
        )

        guard isCurrentIntent,
              state.contentTabs.tabs[id: request.tabID] != nil,
              isLivePersistenceSource(source, request: request, state: state)
        else { return .none }

        let childAction = pinnedRecordTerminalAction(request: request, terminal: terminal)
        // windowManager 소유 왕복은 터미널 자식 액션을 인라인 축소하므로 .contentTabs 단말 케이스를
        // 다시 거치지 않는다. 직접 pin/unpin 메트릭은 이 지점에서 상관을 소비해 기록해야 정확히 한 번 귀환한다.
        if case .contentTab = source {
            recordContentTabMetricIfNeeded(childAction, state: &state)
        }
        let childEffect = pinnedRecordTerminalChildEffect(
            childAction: childAction,
            source: source,
            tabID: request.tabID,
            state: &state,
        )
        state.replayTopNavigationOverlays()
        let closeEffect = closeTopNavigationLifecycleEffect(
            intent: pending.intent,
            terminal: terminal,
            tabID: request.tabID,
            context: request.context,
            state: state,
        )
        clearProductContentTabCloseMetricIfFailed(
            intent: pending.intent,
            terminal: terminal,
            state: &state,
        )
        return .concatenate(childEffect, closeEffect)
    }

    func pinnedRecordTerminalChildEffect(
        childAction: ContentTabAction,
        source: FileManagerPinnedRecordPersistenceSource,
        tabID: ContentTabID,
        state: inout State,
    ) -> Effect<Action> {
        switch source {
        case .contentTab:
            reduceContentTabAction(childAction, state: &state)
        case let .selectedPin(operationID):
            .send(.performSelectedContentTabPinMutation(
                operationID: operationID,
                tabID: tabID,
                action: childAction,
            ))
        case let .selectedClose(operationID):
            ContentTabFeature()
                .reduce(into: &state.contentTabs, action: childAction)
                .map {
                    .performSelectedContentTabCloseMutation(
                        operationID: operationID,
                        tabID: tabID,
                        action: $0,
                    )
                }
        }
    }

    func isLivePersistenceSource(
        _ source: FileManagerPinnedRecordPersistenceSource,
        request: ContentTabPinnedRecordPersistenceRequest,
        state: State,
    ) -> Bool {
        switch source {
        case .contentTab:
            true
        case let .selectedPin(operationID):
            state.pendingSelectedContentTabPinMutation?.operationID == operationID
                && state.pendingSelectedContentTabPinMutation?.currentTabID == request.tabID
        case let .selectedClose(operationID):
            state.isCurrentSelectedContentTabClose(
                operationID: operationID,
                tabID: request.tabID,
            )
        }
    }

    func pinnedRecordTerminalAction(
        request: ContentTabPinnedRecordPersistenceRequest,
        terminal: FileManagerTopNavigationIntentTerminal,
    ) -> ContentTabAction {
        switch terminal {
        case .committed:
            .pinnedRecordSaveSucceeded(tabID: request.tabID, context: request.context)
        case .failed(.save):
            .pinnedRecordSaveFailed(
                tabID: request.tabID,
                context: request.context,
                rollback: request.rollback,
            )
        case let .failed(.storeUnavailable(failure)):
            .pinnedRecordStoreUnavailable(
                tabID: request.tabID,
                context: request.context,
                failure: failure,
                rollback: request.rollback,
            )
        case .failed(.superseded):
            .pinnedRecordSaveNotApplied(
                tabID: request.tabID,
                context: request.context,
                reason: .superseded,
                rollback: request.rollback,
            )
        case .failed(.cancelled):
            .pinnedRecordSaveNotApplied(
                tabID: request.tabID,
                context: request.context,
                reason: .cancelled,
                rollback: request.rollback,
            )
        }
    }

    func requestTopNavigationMove(
        source: FileManagerTopNavigationItemID,
        destination: FileManagerTopNavigationMoveDestination,
        actionSource: ContentTabActionSource,
        state: inout State,
    ) -> Effect<Action> {
        if case let .contentTab(sourceTabID) = source,
           let snapshot = state.sidebar.contentTabDragSnapshot,
           snapshot.lifecycle == .inFlight,
           snapshot.initiatingTabID == sourceTabID,
           snapshot.orderedTabIDs.contains(sourceTabID),
           snapshot.orderedTabIDs.count > 1
        {
            return requestTopNavigationPinnedGroupMove(
                orderedIDs: snapshot.orderedTabIDs,
                destination: destination,
                actionSource: actionSource,
                state: &state,
            )
        }

        let movedOrder = FileManagerTopNavigationOrderPolicy.moving(
            source,
            to: destination,
            in: state.optimisticTopNavigationOrder,
        )
        guard movedOrder != state.optimisticTopNavigationOrder else { return .none }

        let token = contentTabPinnedRecordClient.reserveTopNavigationOperationToken()
        state.productContentTabMoveMetricContexts[token] = ProductContentTabActionMetricContext(
            operationID: productMetricsClient.makeOperationID(),
            source: actionSource,
        )
        state.pendingTopNavigationIntents.append(.init(
            token: token,
            intent: .move(source: source, destination: destination),
        ))
        state.optimisticTopNavigationOrder = movedOrder

        let discoveredLocationIDs = state.sidebar.allFixedLocationItems.map(\.id)
        return .send(.delegate(.persistTopNavigationMove(
            token: token,
            source: source,
            destination: destination,
            discoveredLocationIDs: discoveredLocationIDs,
        )))
    }

    func requestTopNavigationPinnedGroupMove(
        orderedIDs: [ContentTabID],
        destination: FileManagerTopNavigationMoveDestination,
        actionSource: ContentTabActionSource,
        state: inout State,
    ) -> Effect<Action> {
        guard Set(orderedIDs).count == orderedIDs.count,
              orderedIDs.allSatisfy({ state.contentTabs.tabs[id: $0]?.isPinned == true })
        else { return .none }

        let movedOrder = FileManagerTopNavigationOrderPolicy.movingPinnedContentTabs(
            orderedIDs,
            to: destination,
            in: state.optimisticTopNavigationOrder,
        )
        guard movedOrder != state.optimisticTopNavigationOrder else { return .none }

        state.sidebar.contentTabDragSnapshot = nil
        let token = contentTabPinnedRecordClient.reserveTopNavigationOperationToken()
        state.productContentTabMoveMetricContexts[token] = ProductContentTabActionMetricContext(
            operationID: productMetricsClient.makeOperationID(),
            source: actionSource,
        )
        state.pendingTopNavigationIntents.append(.init(
            token: token,
            intent: .movePinnedGroup(orderedIDs: orderedIDs, destination: destination),
        ))
        state.optimisticTopNavigationOrder = movedOrder

        let discoveredLocationIDs = state.sidebar.allFixedLocationItems.map(\.id)
        return .send(.delegate(.persistTopNavigationPinnedGroupMove(
            token: token,
            orderedIDs: orderedIDs,
            destination: destination,
            discoveredLocationIDs: discoveredLocationIDs,
        )))
    }

    func completeTopNavigationIntent(
        token: FileManagerTopNavigationOperationToken,
        terminal: FileManagerTopNavigationIntentTerminal,
        state: inout State,
        isCurrentTerminal: Bool? = nil,
    ) -> Effect<Action> {
        let hadPendingIntent = state.pendingTopNavigationIntents.contains { $0.token == token }
        let moveMetricIntent = hadPendingIntent
            ? pendingTopNavigationIntent(token: token, state: state)?.intent
            : nil
        let isMoveMetricPending = moveMetricIntent?.isContentTabMoveMetricEligible == true
        let isRelevantCurrentTerminal = hadPendingIntent
            && (isCurrentTerminal ?? contentTabPinnedRecordClient.isCurrentTopNavigationOperationToken(token))
        switch terminal {
        case let .committed(commit):
            if state.lastConfirmedTopNavigationCommitRevision.map({ commit.revision >= $0 }) != false {
                state.lastConfirmedTopNavigationOrder = commit.order
                state.lastConfirmedTopNavigationCommitRevision = commit.revision
            }
            if isRelevantCurrentTerminal {
                state.topNavigationArrangementAvailability = .available
                state.topNavigationArrangementPresentation = nil
            }

        case let .failed(.storeUnavailable(failure)):
            if isRelevantCurrentTerminal {
                state.topNavigationArrangementAvailability = .unavailable(failure)
                state.topNavigationArrangementPresentation = .init(failure: .storeUnavailable(failure))
            }

        case .failed(.save):
            if isRelevantCurrentTerminal {
                state.topNavigationArrangementPresentation = .init(failure: .save)
            }

        case .failed(.cancelled), .failed(.superseded):
            break
        }

        guard hadPendingIntent else {
            state.replayTopNavigationOverlays()
            return .none
        }
        state.pendingTopNavigationIntents.removeAll { $0.token == token }
        if isMoveMetricPending {
            Self.recordContentTabMoveMetric(
                token: token,
                terminal: terminal,
                intent: moveMetricIntent,
                state: &state,
                productMetricsClient: productMetricsClient,
            )
        }
        state.replayTopNavigationOverlays()
        return .none
    }

    private func pendingTopNavigationIntent(
        token: FileManagerTopNavigationOperationToken,
        state: State,
    ) -> FileManagerPendingTopNavigationIntent? {
        state.pendingTopNavigationIntents.first { $0.token == token }
    }

    /// move persistence terminal을 operation ID와 상관해 정확히 한 번 기록하고 상관 키를 함께 제거한다.
    /// intent가 이미 제거된 지연/중복 terminal은 이벤트를 만들지 않는다.
    /// 같은 창 top-navigation 이동은 inter-window move가 아니므로 reorder family identity로 보고한다.
    static func recordContentTabMoveMetric(
        token: FileManagerTopNavigationOperationToken,
        terminal: FileManagerTopNavigationIntentTerminal,
        intent: FileManagerTopNavigationIntent?,
        state: inout State,
        productMetricsClient: FileManagerProductMetricsClient,
    ) {
        guard let context = state.productContentTabMoveMetricContexts.removeValue(forKey: token) else {
            return
        }
        let identity: ContentTabInteractionIdentity = if case .movePinnedGroup = intent {
            .reorderSelectedContentTabs
        } else {
            .reorderContentTab
        }
        productMetricsClient.record(FileManagerProductMetricsProducer.contentTabTerminal(
            operationID: context.operationID,
            identity: identity,
            source: context.source,
            result: contentTabActionResult(from: terminal),
        ))
    }

    private static func contentTabActionResult(
        from terminal: FileManagerTopNavigationIntentTerminal,
    ) -> ContentTabActionResult {
        switch terminal {
        case .committed:
            .success
        case .failed(.save):
            .failure
        case .failed(.storeUnavailable):
            .unavailable
        case .failed(.superseded):
            .failure
        case .failed(.cancelled):
            .cancelled
        }
    }

    func clearLogicalUndoHistory(tabID: ContentTabID, state: inout State) {
        let isActiveTab = state.contentTabs.activeTabID == tabID
        guard var contentState = isActiveTab ? state.content : state.tabContentStates[tabID] else { return }
        contentState.entryViewLayout.entryOperations.undoRecords.removeAll()
        contentState.entryViewLayout.entryOperations.redoRecords.removeAll()
        if isActiveTab {
            state.content = contentState
        }
        state.tabContentStates[tabID] = contentState
    }

    func undoManagerGeneration(
        tabID: ContentTabID,
        state: State,
    ) -> FileOperationUndoManagerClient.Generation? {
        guard let windowID = state.windowID else { return nil }
        return fileOperationUndoManagerClient.generation(UndoManagerScope(
            windowID: windowID,
            contentTabID: tabID.rawValue,
        ))
    }

    static func completedEntryActionRecord(
        from action: FileManagerContentAction,
    ) -> EntryActionRecord? {
        guard case let .entryViewLayout(.entryOperations(.lifecycle(.entryActionCompleted(record)))) = action
        else { return nil }
        return record
    }

    static func routeContentEffectAction(
        _ action: FileManagerContentAction,
        tabID: ContentTabID,
        undoManagerGeneration: FileOperationUndoManagerClient.Generation?,
    ) -> Action {
        guard let record = completedEntryActionRecord(from: action) else {
            return .tabContent(tabID: tabID, action: action)
        }
        // 비-undo terminal은 registry/owner-generation 경로(.internal)에서 drop되므로
        // 일반 tabContent 라우팅으로 되돌려 bridge 메트릭이 정확히 한 번 기록되게 한다.
        guard record.operationKind.isUndoable else {
            return .tabContent(tabID: tabID, action: action)
        }
        return .internal(.entryActionCompleted(
            tabID: tabID,
            record: record,
            undoManagerGeneration: undoManagerGeneration,
        ))
    }

    func reduceContentTabAction(
        _ action: ContentTabAction,
        state: inout State,
        source: ContentTabActionSource = .contentTabBar,
    ) -> Effect<Action> {
        let syncMetricObservation = contentTabSyncMetricObservation(for: action, state: state)
        let pendingCollectionOpenCancellationEffect = pendingCollectionOpenCancellationEffect(
            for: action,
            state: &state,
        )
        let reducedAction: ContentTabAction = if case let .pin(tabID, placement) = action, placement == nil {
            .pinUsingDormantSlot(
                tabID,
                state.dormantContentTabSlots.first { $0.id == tabID },
            )
        } else {
            action
        }
        let preReductionEffect: Effect<Action> = switch action {
        case let .duplicate(sourceID, duplicateID):
            .send(.internal(.duplicateContentTabReduced(
                sourceID: sourceID,
                duplicateID: duplicateID,
                duplicateIDWasPreexisting: state.contentTabs.tabs[id: duplicateID] != nil,
            )))

        case let .duplicateSelected(requests):
            .send(.internal(.duplicateSelectedContentTabsReduced(
                requests: requests,
                preexistingTabIDs: Set(state.contentTabs.tabs.ids),
            )))

        default:
            .none
        }
        let childEffect = withDependencies {
            $0.contentTabPinnedRecordPersistenceRouting = pinnedRecordPersistenceRouting(state: state)
        } operation: {
            ContentTabFeature().reduce(
                into: &state.contentTabs,
                action: reducedAction,
            )
        }
        .map { Action.contentTabs($0) }
        captureDirectContentTabCloseMetric(action, source: source, state: &state)
        let closeCancellationEffect = contentTabCloseCancellationEffect(for: action, state: &state)
        recordContentTabSyncMetricIfAccepted(syncMetricObservation, source: source, state: &state)
        return .merge(
            preReductionEffect,
            pendingCollectionOpenCancellationEffect,
            closeCancellationEffect,
            childEffect,
        )
    }

    func pendingCollectionOpenCancellationEffect(
        for action: ContentTabAction,
        state: inout State,
    ) -> Effect<Action> {
        let tabID: ContentTabID? = switch action {
        case let .close(tabID), let .commitClose(tabID): tabID
        default: nil
        }
        guard let tabID, state.contentTabs.activeTabID == tabID else { return .none }
        let failedPinnedReturnTabID = state.pendingPinnedCollectionReturnTabID(for: tabID)
        return cancelPendingCollectionOpen(
            state: &state,
            failedPinnedReturnTabID: failedPinnedReturnTabID,
        )
    }

    /// 동기 content tab 작업의 수용 판정에 필요한 사전 상태 스냅샷.
    private enum ContentTabSyncMetricObservation {
        case open(previousTabCount: Int)
        case restore(hadRecentlyClosed: Bool, previousTabCount: Int)
        case reorder(previousOrder: [ContentTabID])
        case reorderGroup(previousOrder: [ContentTabID])
        case duplicate(previousIDs: Set<ContentTabID>, duplicateIDs: [ContentTabID])
        case duplicateSelected(previousIDs: Set<ContentTabID>, duplicateIDs: [ContentTabID])

        var identity: ContentTabInteractionIdentity {
            switch self {
            case .open: .openNewContentTab
            case .restore: .restoreLastClosedTab
            case .reorder: .reorderContentTab
            case .reorderGroup: .reorderSelectedContentTabs
            case .duplicate: .duplicateContentTab
            case .duplicateSelected: .duplicateSelectedContentTabs
            }
        }
    }

    private func contentTabSyncMetricObservation(
        for action: ContentTabAction,
        state: State,
    ) -> ContentTabSyncMetricObservation? {
        switch action {
        case .open:
            .open(previousTabCount: state.contentTabs.tabs.count)
        case .restore:
            .restore(
                hadRecentlyClosed: state.contentTabs.recentlyClosed != nil,
                previousTabCount: state.contentTabs.tabs.count,
            )
        case .reorder:
            .reorder(previousOrder: state.contentTabs.tabs.map(\.id))
        case .reorderGroup:
            .reorderGroup(previousOrder: state.contentTabs.tabs.map(\.id))
        case let .duplicate(_, duplicateID):
            .duplicate(previousIDs: Set(state.contentTabs.tabs.ids), duplicateIDs: [duplicateID])
        case let .duplicateSelected(requests):
            .duplicateSelected(
                previousIDs: Set(state.contentTabs.tabs.ids),
                duplicateIDs: requests.map(\.duplicateID),
            )
        default:
            nil
        }
    }

    /// 상태가 적용을 증명할 때만 success terminal을 한 건 기록한다. no-op/rejected 경로는 이벤트가 없다.
    private func recordContentTabSyncMetricIfAccepted(
        _ observation: ContentTabSyncMetricObservation?,
        source: ContentTabActionSource,
        state: inout State,
    ) {
        guard let observation else { return }
        let accepted: Bool = switch observation {
        case let .open(previousTabCount):
            state.contentTabs.tabs.count > previousTabCount
        case let .restore(hadRecentlyClosed, previousTabCount):
            hadRecentlyClosed && state.contentTabs.tabs.count > previousTabCount
        case let .reorder(previousOrder), let .reorderGroup(previousOrder):
            state.contentTabs.tabs.map(\.id) != previousOrder
        case let .duplicate(previousIDs, duplicateIDs), let .duplicateSelected(previousIDs, duplicateIDs):
            duplicateIDs.contains { duplicateID in
                !previousIDs.contains(duplicateID) && state.contentTabs.tabs[id: duplicateID] != nil
            }
        }
        guard accepted else { return }
        if state.pendingContentTabClose != nil {
            switch observation {
            case .duplicate, .duplicateSelected, .restore:
                return
            default:
                break
            }
        }
        productMetricsClient.record(FileManagerProductMetricsProducer.contentTabTerminal(
            operationID: productMetricsClient.makeOperationID(),
            identity: observation.identity,
            source: source,
            result: .success,
        ))
    }

    func contentTabCloseCancellationEffect(
        for action: ContentTabAction,
        state: inout State,
    ) -> Effect<Action> {
        guard case let .close(tabID) = action,
              var content = tabID == state.contentTabs.activeTabID
              ? state.content
              : state.tabContentStates[tabID]
        else { return .none }
        let operations = content.entryViewLayout.entryOperations
        let cancelRoot = Effect<Action>.cancel(id: EntryOperationsLoadingCancelID.loadItems(
            windowID: operations.windowID,
            ownerID: operations.loadingCancellationOwnerID,
        ))
        let folderEffect = FileManagerContentFeature().reduce(
            into: &content,
            action: .entryViewLayout(.entryOperations(.loading(.cancelAllFolderItems))),
        )
        let collectionEffect = FileManagerContentFeature().reduce(
            into: &content,
            action: .entryViewLayout(.internal(.cancelCollectionMaterialization)),
        )
        if tabID == state.contentTabs.activeTabID {
            state.content = content
        }
        state.tabContentStates[tabID] = content
        return .merge(
            cancelRoot,
            folderEffect.map { .tabContent(tabID: tabID, action: $0) },
            collectionEffect.map { .tabContent(tabID: tabID, action: $0) },
        )
    }

    func pinnedRecordPersistenceRouting(
        state: State,
    ) -> ContentTabPinnedRecordPersistenceRouting {
        switch pinnedRecordPersistenceOwnership {
        case .local:
            .local(discoveredLocationIDs: state.sidebar.allFixedLocationItems.map(\.id))
        case .windowManager:
            .delegate
        }
    }
}
