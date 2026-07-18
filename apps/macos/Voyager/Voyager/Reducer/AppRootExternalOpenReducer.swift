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

    /// didOpenFirstWindow 분기에서 버퍼링된 외부 URL 큐를 소비하고 리셋
    func flushPendingExternalURL(state: inout State) -> Effect<Action> {
        let urls = state.pendingExternalURLs
        guard !urls.isEmpty else { return .none }
        state.pendingExternalURLs = []
        // 버퍼링된 URL을 적재 순서대로 ExternalFileRouter에 전달
        return .concatenate(urls.map { url in
            .send(.externalFileRouter(.receive(url)))
        })
    }

    func hasPendingExternalRoutes(_ state: State) -> Bool {
        !state.pendingExternalURLs.isEmpty
            || !state.externalOpenBatchQueue.isEmpty
            || state.activeExternalOpenBatch != nil
    }

    func canFlushPendingExternalRoutes(_ state: State) -> Bool {
        state.lifecycle.isExternalRouteFlushAllowed
    }

    func flushPendingExternalRoutes(state: inout State) -> Effect<Action> {
        .concatenate(
            flushPendingExternalURL(state: &state),
            startNextExternalOpenBatchIfPossible(state: &state),
        )
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
           state.lifecycle.accessGatePhase == .recoveryRequired,
           !state.isExternalURLFlushDelegateScheduled
        {
            state.isExternalURLFlushDelegateScheduled = true
            return .send(.lifecycle(.delegate(.openInitialWindowIfNeeded)))
        }
        return startNextExternalOpenBatchIfPossible(state: &state)
    }

    func startNextExternalOpenBatchIfPossible(state: inout State) -> Effect<Action> {
        guard state.activeExternalOpenBatch == nil,
              !state.externalOpenBatchQueue.isEmpty,
              state.lifecycle.isExternalRouteFlushAllowed,
              !onboardingWindowClient.isRequired()
        else { return .none }

        let batch = state.externalOpenBatchQueue.removeFirst()
        state.activeExternalOpenBatch = .init(
            batch: batch,
            preferredWindowIDs: state.windowManager.lastUsedWindowIDs,
        )
        return .send(.externalFileRouter(.receiveBatch(batch.request)))
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

        switch active.phase {
        case .normalizing, .planning:
            var retryBatch = active.batch
            retryBatch.request = .init(
                batchID: uuid(),
                items: active.batch.request.items,
            )
            state.externalOpenBatchQueue.insert(retryBatch, at: 0)
            guard active.phase == .normalizing else { return .none }
            return .send(.externalFileRouter(.cancelBatch(active.batch.request.batchID)))

        case .applying, .alerting, .activating, .advancing:
            if !hasPendingExternalRoutes(state) {
                state.isInitialWindowFallbackPending = false
                state.isExternalURLRouteInFlightWithoutWindow = false
                state.isExternalURLFlushDelegateScheduled = false
            }
            return .none
        }
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
        case let .externalOpenAdvanceToNextBatch(batchID):
            advanceExternalOpenBatch(batchID: batchID, state: &state)
        default:
            .none
        }
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
              active.phase == .applying
        else { return .none }

        switch completion.result {
        case let .success(plan):
            guard active.placementPlan == plan else { return .none }
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
        let successfulItemIDs = orderedItems.compactMap { item -> UUID? in
            if case .success = item.outcome { return item.itemID }
            return nil
        }
        if successfulItemIDs.isEmpty {
            active.phase = .alerting
            state.activeExternalOpenBatch = active
            return continueExternalOpenAfterAlert(state: &state)
        }

        active.phase = .planning
        state.activeExternalOpenBatch = active
        return .send(.windowManager(.placement(.plan(.init(
            batchID: result.batchID,
            itemIDs: successfulItemIDs,
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

        return plannedItems.reduce(into: [UUID: ExternalContentTabReservation]()) { result, item in
            guard let destination = destinations[item.itemID] else { return }
            let reservation: ExternalContentTabReservation = switch destination {
            case let .collection(path):
                .init(
                    id: item.tabID,
                    anchor: .collectionFile(url: URL(fileURLWithPath: path)),
                )
            case let .directory(path, revealPath):
                .init(
                    id: item.tabID,
                    anchor: .directory(path: path),
                    pendingSelectEntryID: revealPath,
                )
            }
            result[item.itemID] = reservation
        }
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
