import ComposableArchitecture
import Foundation
import VoyagerEntitiesCollection
import VoyagerFeaturesExternalFileRouter
import VoyagerPagesFileManager
import VoyagerPagesOnboarding

extension AppRootFeature {
    func reduceExternalFileURL(
        into state: inout State,
        action: Action,
    ) -> Effect<Action> {
        switch action {
        case let .receiveExternalFileURL(url, source, mode):
            .send(.receiveExternalFileBatch([url], source: source, mode: mode))

        case let .receiveExternalFileBatch(urls, source, mode):
            enqueueExternalOpenBatch(
                urls: urls,
                source: source,
                mode: mode,
                state: &state,
            )

        case let .receiveCollectionFileURL(url):
            .send(.receiveExternalFileBatch(
                [url],
                source: .systemOpenEvent,
                mode: .open,
            ))

        default:
            .none
        }
    }

    func enqueueExternalURL(_ url: URL, state: inout State) -> Effect<Action> {
        state.pendingExternalURLs.append(url)
        guard state.windowManager.windows.isEmpty else {
            return flushPendingExternalRoutes(state: &state)
        }
        state.isExternalURLRouteInFlightWithoutWindow = true
        guard state.lifecycle.didFinishLaunching,
              !state.isExternalURLFlushDelegateScheduled
        else { return .none }
        state.isExternalURLFlushDelegateScheduled = true
        return .send(.lifecycle(.delegate(.openInitialWindowIfNeeded)))
    }

    /// pending deep-link occurrence 하나만 시작하고 Router terminal까지 다음 작업을 막는다.
    func startNextPendingExternalURLIfPossible(state: inout State) -> Effect<Action> {
        guard state.activePendingExternalURL == nil,
              state.activeExternalOpenBatch == nil,
              !state.pendingExternalURLs.isEmpty,
              canFlushPendingExternalRoutes(state)
        else { return .none }

        let pending = AppRootPendingExternalURL(
            requestID: uuid(),
            url: state.pendingExternalURLs.removeFirst(),
        )
        state.activePendingExternalURL = pending
        return .send(.externalFileRouter(.receiveTracked(
            pending.url,
            requestID: pending.requestID,
        )))
    }

    func hasPendingExternalRoutes(_ state: State) -> Bool {
        !state.pendingExternalURLs.isEmpty
            || state.activePendingExternalURL != nil
            || !state.externalOpenBatchQueue.isEmpty
            || state.activeExternalOpenBatch != nil
    }

    func canFlushPendingExternalRoutes(_ state: State) -> Bool {
        state.lifecycle.isShellReady && !onboardingWindowClient.isRequired()
    }

    func flushPendingExternalRoutes(state: inout State) -> Effect<Action> {
        if state.activePendingExternalURL != nil || !state.pendingExternalURLs.isEmpty {
            return startNextPendingExternalURLIfPossible(state: &state)
        }
        return startNextExternalOpenBatchIfPossible(state: &state)
    }

    func consumePendingExternalURLCompletion(
        requestID: UUID,
        state: inout State,
    ) -> Effect<Action> {
        guard state.activePendingExternalURL?.requestID == requestID else { return .none }
        state.activePendingExternalURL = nil
        return flushPendingExternalRoutes(state: &state)
    }

    func enqueueExternalOpenBatch(
        urls: [URL],
        source: RouteSource,
        mode: DeepLinkMode,
        state: inout State,
    ) -> Effect<Action> {
        guard !urls.isEmpty else { return .none }
        let batchID = uuid()
        let items = urls.enumerated().map { index, url in
            ExternalFileRouterBatchRequest.Item(
                itemID: uuid(),
                index: index,
                url: url,
                source: source,
                mode: mode,
            )
        }
        let requiresFallback = state.windowManager.windows.isEmpty
        state.externalOpenBatchQueue.append(.init(
            request: .init(batchID: batchID, items: items),
            requiresInitialWindowFallback: requiresFallback,
        ))
        if requiresFallback {
            state.isInitialWindowFallbackPending = true
            state.isExternalURLRouteInFlightWithoutWindow = true
        }
        if requiresFallback,
           state.lifecycle.didFinishLaunching,
           !state.isExternalURLFlushDelegateScheduled
        {
            state.isExternalURLFlushDelegateScheduled = true
            return .send(.lifecycle(.delegate(.openInitialWindowIfNeeded)))
        }
        return startNextExternalOpenBatchIfPossible(state: &state)
    }

    func startNextExternalOpenBatchIfPossible(state: inout State) -> Effect<Action> {
        guard state.activeExternalOpenBatch == nil,
              state.activePendingExternalURL == nil,
              state.pendingExternalURLs.isEmpty,
              !state.externalOpenBatchQueue.isEmpty,
              canFlushPendingExternalRoutes(state),
              !onboardingWindowClient.isRequired()
        else { return .none }

        let batch = state.externalOpenBatchQueue.removeFirst()
        state.activeExternalOpenBatch = .init(
            batch: batch,
            preferredWindowIDs: state.windowManager.lastUsedWindowIDs,
        )
        return .send(.externalFileRouter(.receiveBatch(batch.request)))
    }

    func handleActivePendingExternalURLGateClosure(state: inout State) -> Effect<Action> {
        guard let active = state.activePendingExternalURL else { return .none }
        if state.windowManager.authorizedTrackedSingletonRequestID == active.requestID {
            state.windowManager.authorizedTrackedSingletonRequestID = nil
        }
        state.activePendingExternalURL = nil
        state.pendingExternalURLs.insert(active.url, at: 0)
        return .concatenate(
            .send(.windowManager(.trackedSingleton(.revoke(requestID: active.requestID)))),
            .send(.externalFileRouter(.cancelTrackedRequest(active.requestID))),
        )
    }

    func handleActiveExternalOpenBatchGateClosure(state: inout State) -> Effect<Action> {
        guard let active = state.activeExternalOpenBatch else { return .none }
        let batchID = active.batch.request.batchID
        if state.windowManager.authorizedExternalOpenBatchID == batchID {
            state.windowManager.authorizedExternalOpenBatchID = nil
        }
        if state.windowManager.externalOpenActivationAttempt?.batchID == batchID {
            state.windowManager.externalOpenActivationAttempt = nil
        }
        state.activeExternalOpenBatch = nil

        var effects: [Effect<Action>] = [
            .send(.windowManager(.placement(.cancel(batchID: batchID)))),
        ]
        switch active.phase {
        case .normalizing, .planning:
            var retryBatch = active.batch
            retryBatch.request = .init(
                batchID: uuid(),
                items: active.batch.request.items,
            )
            state.externalOpenBatchQueue.insert(retryBatch, at: 0)
            if active.phase == .normalizing {
                effects.append(.send(.externalFileRouter(.cancelBatch(active.batch.request.batchID))))
            }

        case .applying, .alerting, .activating, .advancing:
            if !hasPendingExternalRoutes(state) {
                state.isInitialWindowFallbackPending = false
                state.isExternalURLRouteInFlightWithoutWindow = false
                state.isExternalURLFlushDelegateScheduled = false
            }
        }
        return .merge(effects)
    }

    func reduceExternalOpenBatch(
        into state: inout State,
        action: Action,
    ) -> Effect<Action> {
        switch action {
        case let .windowManager(.delegate(.externalOpenPlacementCompleted(completion))):
            consumeExternalOpenPlacementCompletion(completion, state: &state)
        case let .windowManager(.delegate(.externalOpenApplyCompleted(completion))):
            consumeExternalOpenPlacementApplicationCompletion(completion, state: &state)
        case let .externalOpenAlertCompleted(completion):
            consumeExternalOpenAlertCompletion(completion, state: &state)
        case let .windowManager(.delegate(.externalOpenActivationCompleted(batchID))):
            consumeExternalOpenActivation(batchID: batchID, state: &state)
        case let .windowManager(.delegate(.trackedSingletonCompleted(requestID))):
            consumeTrackedSingletonCompletion(requestID: requestID, state: &state)
        case let .externalOpenAdvanceToNextBatch(batchID):
            advanceExternalOpenBatch(batchID: batchID, state: &state)
        default:
            .none
        }
    }

    private func consumeTrackedSingletonCompletion(
        requestID: UUID,
        state: inout State,
    ) -> Effect<Action> {
        guard state.activePendingExternalURL?.requestID == requestID,
              canFlushPendingExternalRoutes(state)
        else { return .none }
        if state.windowManager.authorizedTrackedSingletonRequestID == requestID {
            state.windowManager.authorizedTrackedSingletonRequestID = nil
        }
        if state.windowManager.trackedSingletonWindow?.requestID == requestID {
            state.windowManager.trackedSingletonWindow = nil
        }
        if state.externalFileRouter.activeTrackedRequestID == requestID {
            state.externalFileRouter.activeTrackedRequestID = nil
        }
        return consumePendingExternalURLCompletion(requestID: requestID, state: &state)
    }

    func consumeExternalOpenPlacementCompletion(
        _ completion: ExternalOpenPlacementCompletion,
        state: inout State,
    ) -> Effect<Action> {
        guard state.activeExternalOpenBatch?.batch.request.batchID == completion.batchID else {
            return .none
        }
        return handleExternalOpenPlacementCompleted(completion.result, state: &state)
    }

    func consumeExternalOpenPlacementApplicationCompletion(
        _ completion: ExternalOpenPlacementApplicationCompletion,
        state: inout State,
    ) -> Effect<Action> {
        guard var active = state.activeExternalOpenBatch,
              active.batch.request.batchID == completion.batchID,
              active.phase == .applying || active.phase == .activating
        else { return .none }

        switch completion.result {
        case let .success(plan):
            guard plan.batchID == completion.batchID else { return .none }
            active.placementPlan = plan
            if active.phase == .activating {
                state.activeExternalOpenBatch = active
                return .send(.windowManager(.placement(.activate(plan))))
            }
            active.phase = .alerting
            state.activeExternalOpenBatch = active
            return continueExternalOpenAfterAlert(state: &state)

        case .failure:
            active.phase = .advancing
            state.activeExternalOpenBatch = active
            return .send(.externalOpenAdvanceToNextBatch(batchID: completion.batchID))
        }
    }

    func consumeExternalOpenAlertCompletion(
        _ completion: ExternalOpenAlertCompletion,
        state: inout State,
    ) -> Effect<Action> {
        guard var active = state.activeExternalOpenBatch,
              active.batch.request.batchID == completion.batchID,
              active.phase == .alerting,
              active.nextFailureOffset < active.orderedFailures.count,
              active.orderedFailures[active.nextFailureOffset].index == completion.failureIndex
        else { return .none }
        active.nextFailureOffset += 1
        state.activeExternalOpenBatch = active
        return continueExternalOpenAfterAlert(state: &state)
    }

    func consumeExternalOpenActivation(
        batchID: UUID,
        state: inout State,
    ) -> Effect<Action> {
        guard var active = state.activeExternalOpenBatch,
              active.batch.request.batchID == batchID,
              active.phase == .activating
        else { return .none }
        if state.windowManager.retainedExternalOpenPlacementOwnership?.batchID == batchID {
            state.windowManager.retainedExternalOpenPlacementOwnership = nil
        }
        active.phase = .advancing
        state.activeExternalOpenBatch = active
        return .send(.externalOpenAdvanceToNextBatch(batchID: batchID))
    }

    func advanceExternalOpenBatch(
        batchID: UUID,
        state: inout State,
    ) -> Effect<Action> {
        guard let active = state.activeExternalOpenBatch,
              active.batch.request.batchID == batchID,
              active.phase == .advancing
        else { return .none }
        if state.windowManager.authorizedExternalOpenBatchID == batchID {
            state.windowManager.authorizedExternalOpenBatchID = nil
        }
        state.activeExternalOpenBatch = nil
        if !state.pendingExternalURLs.isEmpty,
           canFlushPendingExternalRoutes(state)
        {
            return flushPendingExternalRoutes(state: &state)
        }
        if !state.externalOpenBatchQueue.isEmpty {
            return startNextExternalOpenBatchIfPossible(state: &state)
        }

        let shouldOpenInitialWindow = state.isInitialWindowFallbackPending
            && state.windowManager.windows.isEmpty
        state.isInitialWindowFallbackPending = false
        state.isExternalURLRouteInFlightWithoutWindow = false
        if shouldOpenInitialWindow {
            return .send(.windowManager(.lifecycle(.openInitialWindowIfNeeded)))
        }
        return .none
    }

    func handleExternalOpenBatchNormalized(
        _ result: ExternalFileRouterBatchResult,
        state: inout State,
    ) -> Effect<Action> {
        guard var active = state.activeExternalOpenBatch,
              active.batch.request.batchID == result.batchID,
              active.phase == .normalizing
        else { return .none }

        let orderedItems = result.items.sorted { $0.index < $1.index }
        let expectedItems = active.batch.request.items.sorted { $0.index < $1.index }
        guard orderedItems.map(\.itemID) == expectedItems.map(\.itemID),
              orderedItems.map(\.index) == expectedItems.map(\.index)
        else { return .none }

        active.normalizedItems = orderedItems
        active.orderedFailures = orderedItems.filter { item in
            if case .failure = item.outcome { return true }
            return false
        }
        let placementItems = orderedItems.compactMap { item -> ExternalOpenPlacementRequest.Item? in
            guard case let .success(destination) = item.outcome else { return nil }
            return switch destination {
            case let .collection(path):
                .init(
                    itemID: item.itemID,
                    anchor: .collectionFile(url: URL(fileURLWithPath: path).standardizedFileURL),
                    pendingSelectEntryID: nil,
                )
            case let .directory(path, revealPath):
                .init(
                    itemID: item.itemID,
                    anchor: .directory(path: URL(fileURLWithPath: path).standardizedFileURL.path),
                    pendingSelectEntryID: revealPath.map { URL(fileURLWithPath: $0).standardizedFileURL.path },
                )
            }
        }
        if placementItems.isEmpty {
            active.phase = .alerting
            state.activeExternalOpenBatch = active
            return continueExternalOpenAfterAlert(state: &state)
        }

        active.phase = .planning
        state.activeExternalOpenBatch = active
        return .send(.windowManager(.placement(.plan(.init(
            batchID: result.batchID,
            items: placementItems,
            preferredWindowIDs: active.preferredWindowIDs,
        )))))
    }

    func handleExternalOpenPlacementCompleted(
        _ result: Result<ExternalOpenPlacementPlan, ExternalOpenPlacementFailure>,
        state: inout State,
    ) -> Effect<Action> {
        guard var active = state.activeExternalOpenBatch,
              active.phase == .planning
        else { return .none }

        switch result {
        case let .success(plan):
            guard plan.batchID == active.batch.request.batchID else { return .none }
            guard let reservations = makeExternalOpenReservations(active: active, plan: plan) else {
                active.phase = .alerting
                state.activeExternalOpenBatch = active
                return continueExternalOpenAfterAlert(state: &state)
            }
            active.placementPlan = plan
            active.phase = .applying
            state.activeExternalOpenBatch = active
            state.windowManager.authorizedExternalOpenBatchID = plan.batchID
            return .send(.windowManager(.placement(.apply(
                plan: plan,
                reservationsByItemID: reservations,
            ))))

        case .failure:
            active.phase = .alerting
            state.activeExternalOpenBatch = active
            return continueExternalOpenAfterAlert(state: &state)
        }
    }

    func makeExternalOpenReservations(
        active: AppRootActiveExternalOpenBatch,
        plan: ExternalOpenPlacementPlan,
    ) -> [UUID: ExternalContentTabReservation]? {
        var destinations: [UUID: ExternalFileRouterBatchDestination] = [:]
        for item in active.normalizedItems {
            guard case let .success(destination) = item.outcome else { continue }
            destinations[item.itemID] = destination
        }
        let plannedItems = plan.windows.flatMap(\.items)
        guard plannedItems.count == destinations.count,
              Set(plannedItems.map(\.itemID)) == Set(destinations.keys)
        else { return nil }

        return plan.reservationsByItemID
    }

    func continueExternalOpenAfterAlert(state: inout State) -> Effect<Action> {
        guard var active = state.activeExternalOpenBatch,
              active.phase == .alerting
        else { return .none }
        let batchID = active.batch.request.batchID

        if active.nextFailureOffset < active.orderedFailures.count {
            let failure = active.orderedFailures[active.nextFailureOffset]
            guard case let .failure(error) = failure.outcome else { return .none }
            state.activeExternalOpenBatch = active
            return showExternalOpenFailure(
                error,
                batchID: batchID,
                failureIndex: failure.index,
            )
        }

        guard let plan = active.placementPlan, !plan.windows.isEmpty else {
            active.phase = .advancing
            state.activeExternalOpenBatch = active
            return .send(.externalOpenAdvanceToNextBatch(batchID: batchID))
        }
        active.phase = .activating
        state.activeExternalOpenBatch = active
        return .send(.windowManager(.placement(.activate(plan))))
    }

    func showExternalOpenFailure(
        _ error: ExternalFileRouterError,
        batchID: UUID,
        failureIndex: Int,
    ) -> Effect<Action> {
        let content: (title: String, message: String) = switch error {
        case let .permissionDenied(path):
            (
                "Voyager에서 위치를 열 수 없습니다",
                "접근 권한이 없어 \(path)를 열 수 없습니다. macOS 시스템 설정에서 Voyager의 파일 및 폴더 접근 권한을 확인해 주세요.",
            )
        case .invalidPath, .urlValidationError, .unknown:
            (
                "Voyager에서 위치를 열 수 없습니다",
                "선택한 위치를 찾을 수 없습니다. 경로를 확인한 뒤 다시 시도해 주세요.",
            )
        }

        return .run { [collectionAlertClient] send in
            await collectionAlertClient.showCollectionOpenErrorAlert(content.title, content.message)
            await send(.externalOpenAlertCompleted(.init(batchID: batchID, failureIndex: failureIndex)))
        } catch: { _, send in
            await send(.externalOpenAlertCompleted(.init(batchID: batchID, failureIndex: failureIndex)))
        }
    }
}

// MARK: - Tracked singleton route ownership

extension AppRootFeature {
    func routeExternalAppFallback(
        requestID: UUID?,
        state: inout State,
    ) -> Effect<Action> {
        guard let requestID else {
            return .send(.windowManager(.lifecycle(.openInitialWindowIfNeeded)))
        }
        guard authorizeTrackedPendingRequest(requestID, state: &state) else { return .none }
        return .send(.windowManager(.trackedSingleton(.openInitialWindow(requestID: requestID))))
    }

    func routeExternalFolder(
        path: String,
        requestID: UUID?,
        state: inout State,
    ) -> Effect<Action> {
        guard let requestID else { return .send(.windowManager(.file(.newWindow(path: path)))) }
        guard authorizeTrackedPendingRequest(requestID, state: &state) else { return .none }
        return .send(.windowManager(.trackedSingleton(.openWindow(
            requestID: requestID,
            path: path,
            selectEntryID: nil,
        ))))
    }

    func routeExternalParentFolder(
        path: String,
        selectEntryPath: String?,
        requestID: UUID?,
        state: inout State,
    ) -> Effect<Action> {
        guard let requestID else {
            return .send(.windowManager(.file(.newWindow(path: path, selectEntryID: selectEntryPath))))
        }
        guard authorizeTrackedPendingRequest(requestID, state: &state) else { return .none }
        return .send(.windowManager(.trackedSingleton(.openWindow(
            requestID: requestID,
            path: path,
            selectEntryID: selectEntryPath,
        ))))
    }

    func routeExternalAuthCallback(
        url: URL,
        requestID: UUID?,
        state: inout State,
    ) -> Effect<Action> {
        state.isExternalURLRouteInFlightWithoutWindow = false
        guard let requestID else { return .send(.receiveAuthCallbackURL(url)) }
        guard isCurrentTrackedPendingRequest(requestID, state: state) else { return .none }
        return .send(.receiveTrackedAuthCallbackURL(url, requestID: requestID))
    }

    func showExternalRouteError(
        message: String,
        requestID: UUID?,
        state: inout State,
    ) -> Effect<Action> {
        guard requestID.map({ isCurrentTrackedPendingRequest($0, state: state) }) ?? true else {
            return .none
        }
        state.isExternalURLRouteInFlightWithoutWindow = false
        return completeTrackedPendingURL(
            after: showExternalFileOpenError(
                title: "Voyager에서 위치를 열 수 없습니다",
                message: message,
            ),
            requestID: requestID,
        )
    }

    func isCurrentTrackedPendingRequest(_ requestID: UUID, state: State) -> Bool {
        state.lifecycle.isShellReady
            && state.activePendingExternalURL?.requestID == requestID
    }

    func authorizeTrackedPendingRequest(_ requestID: UUID, state: inout State) -> Bool {
        guard isCurrentTrackedPendingRequest(requestID, state: state) else { return false }
        state.windowManager.authorizedTrackedSingletonRequestID = requestID
        return true
    }

    func completeTrackedPendingURL(
        after routeEffect: Effect<Action>,
        requestID: UUID?,
    ) -> Effect<Action> {
        guard let requestID else { return routeEffect }
        return .concatenate(
            routeEffect,
            .send(.externalFileRouter(.singletonRequestCompleted(requestID))),
        )
    }

    func showExternalFileOpenError(title: String, message: String) -> Effect<Action> {
        .run { [collectionAlertClient] _ in
            await collectionAlertClient.showCollectionOpenErrorAlert(title, message)
        }
    }
}
