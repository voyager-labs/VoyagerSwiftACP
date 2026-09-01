import ComposableArchitecture
import Foundation
import VoyagerEntitiesAppPreferences
import VoyagerFeaturesContentPageNavigation
import VoyagerFeaturesEntryOperations
import VoyagerPagesFileManager
import VoyagerPagesOnboarding
import VoyagerShared
import VoyagerWidgetsEntryViewLayout

extension WindowManagerFeature {
    func handleTrackedSingletonCommand(
        _ command: Action.TrackedSingletonCommand,
        state: inout State,
    ) -> Effect<Action> {
        switch command {
        case let .revoke(requestID):
            return revokeTrackedSingleton(requestID: requestID, state: &state)

        case let .openInitialWindow(requestID):
            guard state.authorizedTrackedSingletonRequestID == requestID else {
                return trackedSingletonCompletionEffect(requestID)
            }
            guard state.windows.ids.allSatisfy(state.closingWindowIDs.contains) else {
                state.authorizedTrackedSingletonRequestID = nil
                return trackedSingletonCompletionEffect(requestID)
            }
            return openTrackedWindowSession(
                requestID: requestID,
                path: nil,
                selectEntryID: nil,
                resolvedStartPage: nil,
                state: &state,
            )

        case let .openWindow(requestID, path, selectEntryID):
            guard state.authorizedTrackedSingletonRequestID == requestID else {
                return trackedSingletonCompletionEffect(requestID)
            }
            return openTrackedWindowSession(
                requestID: requestID,
                path: path,
                selectEntryID: selectEntryID,
                resolvedStartPage: nil,
                state: &state,
            )
        }
    }

    func handleWindowCommand(_ action: Action, state: inout State) -> Effect<Action> {
        switch action {
        case let .file(.newWindow(path, selectEntryID)):
            return openWindowSession(
                path: path,
                selectEntryID: selectEntryID,
                resolvedStartPage: nil,
                state: &state,
            )
        case let .file(.openCollectionFile(url)):
            return openCollectionWindowSession(url: url, state: &state)
        case .file(.newTab):
            return sendContentTabCommandToFocusedWindow(
                state,
                .openNewContentTab(source: .menuCommand),
                capability: \.canOpenNewContentTab,
            )
        case .window(.closeFocusedWindow):
            guard let id = state.focusedWindowID else { return .none }
            return closeWindow(id, state: &state)
        case .window(.closeAllWindows):
            return closeAllWindows(state: &state)
        default:
            return .none
        }
    }

    private func closeAllWindows(state: inout State) -> Effect<Action> {
        let openWindowIDs = state.windows.ids.filter { !state.closingWindowIDs.contains($0) }
        let pendingResolutions = state.pendingDefaultStartPageResolutions
        guard !openWindowIDs.isEmpty || !pendingResolutions.isEmpty else { return .none }
        let pendingWindowOpenIDs = openWindowIDs.filter { state.pendingWindowOpenIDs.contains($0) }
        let externalBatchIDs = Set(openWindowIDs.compactMap { state.externalWindowBatchIDs[$0] })
        let trackedRequestIDs = Set(openWindowIDs.compactMap { windowID in
            state.trackedSingletonWindow?.windowID == windowID ? state.trackedSingletonWindow?.requestID : nil
        })
        state.closingWindowIDs.formUnion(openWindowIDs)
        clearAllWindowFocus(openWindowIDs, state: &state)
        state.lastUsedWindowIDs.removeAll()
        state.refreshContentTabMoveTargets()
        state.defaultWindowBootstrapRequestID = nil
        state.defaultWindowBootstrapWindowIDs.removeAll()
        state.pendingDefaultStartPageResolutions.removeAll()
        state.authorizedExternalOpenBatchID = nil
        state.externalOpenActivationAttempt = nil
        state.retainedExternalOpenPlacementOwnership = nil
        var cancellationEffects: [Effect<Action>] = [.cancel(id: CancelID.defaultWindowBootstrap)]
        cancellationEffects += pendingResolutions.keys.map { .cancel(id: CancelID.defaultStartPageResolution($0)) }
        cancellationEffects += pendingWindowOpenIDs.map { .cancel(id: CancelID.windowOpen($0)) }
        cancellationEffects += externalBatchIDs.map { .cancel(id: CancelID.externalOpenBatch($0)) }
        cancellationEffects += trackedRequestIDs.map { .cancel(id: CancelID.trackedSingletonNativeOpen($0)) }
        let pendingTrackedRequestIDs = Set(pendingResolutions.values.compactMap(\.trackedRequestID))
        for requestID in pendingTrackedRequestIDs where state.authorizedTrackedSingletonRequestID == requestID {
            state.authorizedTrackedSingletonRequestID = nil
            cancellationEffects.append(trackedSingletonCompletionEffect(requestID))
        }
        guard !openWindowIDs.isEmpty else { return .merge(cancellationEffects) }
        let closeAllEffect = Effect<Action>.run { [fileManagerWindowClient] send in
            await fileManagerWindowClient.closeAll()
            let registeredWindowIDs = await fileManagerWindowClient.registeredWindowIDs()
            for id in pendingWindowOpenIDs where !registeredWindowIDs.contains(id) {
                await fileManagerWindowClient.finalizeClose(id)
                await send(.pendingWindowCloseFinalized(id: id))
            }
        }
        return .concatenate(.merge(cancellationEffects), closeAllEffect)
    }

    private func openTrackedWindowSession(
        requestID: UUID,
        path: String?,
        selectEntryID: String?,
        resolvedStartPage: StartPage?,
        state: inout State,
    ) -> Effect<Action> {
        guard state.authorizedTrackedSingletonRequestID == requestID else {
            return trackedSingletonCompletionEffect(requestID)
        }
        guard !onboardingWindowClient.showIfNeeded() else {
            state.authorizedTrackedSingletonRequestID = nil
            return trackedSingletonCompletionEffect(requestID)
        }
        var startPage: StartPage?
        if path == nil {
            if let resolvedStartPage {
                startPage = resolvedStartPage
            } else {
                let snapshot = state.appPreferences.defaultStartPage
                if case .home = snapshot {
                    // home 선호는 IO가 없으므로 동기 fast path로 즉시 생성한다.
                    startPage = .home
                } else {
                    // 클라우드 placeholder stat이 메인 스레드를 막지 않도록 프로브를 effect로 미룬다.
                    let resolutionID = uuid()
                    state.pendingDefaultStartPageResolutions[resolutionID] = .init(trackedRequestID: requestID)
                    return resolveDefaultStartPageEffect(resolutionID: resolutionID, snapshot: snapshot) { resolved in
                        .defaultStartPageResolved(
                            resolutionID: resolutionID,
                            requestID: requestID,
                            selectEntryID: selectEntryID,
                            startPage: resolved,
                        )
                    }
                }
            }
        }
        let windowSession = makeWindowSession(
            path: path,
            startPage: startPage,
            selectEntryID: selectEntryID,
        )
        state.windows.append(windowSession)
        state.focusedWindowID = windowSession.id
        state.moveWindowToMRUFront(windowSession.id)
        state.pendingWindowOpenIDs.insert(windowSession.id)
        state.refreshContentTabMoveTargets()
        state.trackedSingletonWindow = .init(requestID: requestID, windowID: windowSession.id)
        var effects: [Effect<Action>] = [
            windowIDChangedEffect(for: windowSession.id),
            appPreferencesEffect(for: windowSession.id, preferences: state.appPreferences),
        ]
        effects.append(trackedWindowOpenEffect(
            for: windowSession.id,
            requestID: requestID,
            shouldBootstrapDefaultWindow: path == nil,
        ))
        return .concatenate(effects)
    }

    private func revokeTrackedSingleton(
        requestID: UUID,
        state: inout State,
    ) -> Effect<Action> {
        let wasAuthorized = state.authorizedTrackedSingletonRequestID == requestID
        if wasAuthorized { state.authorizedTrackedSingletonRequestID = nil }
        var effects: [Effect<Action>] = [.cancel(id: CancelID.trackedSingletonNativeOpen(requestID))]
        let pendingResolutionIDs = state.pendingDefaultStartPageResolutions.compactMap { resolutionID, pending in
            pending.trackedRequestID == requestID ? resolutionID : nil
        }
        for resolutionID in pendingResolutionIDs {
            state.pendingDefaultStartPageResolutions[resolutionID] = nil
            effects.append(.cancel(id: CancelID.defaultStartPageResolution(resolutionID)))
        }
        guard let trackedWindow = state.trackedSingletonWindow,
              trackedWindow.requestID == requestID
        else {
            if wasAuthorized || !pendingResolutionIDs.isEmpty {
                effects.append(trackedSingletonCompletionEffect(requestID))
            }
            return .concatenate(effects)
        }
        state.trackedSingletonWindow = nil
        effects.append(closeWindow(trackedWindow.windowID, state: &state))
        if !trackedWindow.terminalOutcomeEmitted {
            effects.append(trackedSingletonCompletionEffect(requestID))
        }
        return .concatenate(effects)
    }

    func trackedSingletonCompletionEffect(_ requestID: UUID) -> Effect<Action> {
        .send(.delegate(.trackedSingletonCompleted(requestID: requestID)))
    }

    func windowOpenEffect(
        for id: State.WindowID,
        shouldBootstrapDefaultWindow: Bool,
    ) -> Effect<Action> {
        .run { [fileManagerWindowClient] send in
            guard let isRegistered = await Self.openAndVerifyWindowRegistration(
                id,
                client: fileManagerWindowClient,
            ) else { return }
            await send(.windowOpenCompleted(
                id: id,
                shouldBootstrapDefaultWindow: shouldBootstrapDefaultWindow,
                isRegistered: isRegistered,
            ))
        }
        .cancellable(id: CancelID.windowOpen(id))
    }

    static func openAndVerifyWindowRegistration(
        _ id: State.WindowID,
        client: FileManagerWindowClient,
    ) async -> Bool? {
        await client.open(id)
        guard !Task.isCancelled else { return nil }
        let registeredWindowIDs = await client.registeredWindowIDs()
        guard !Task.isCancelled else { return nil }
        return registeredWindowIDs.contains(id)
    }

    func readyToOpenWindow(_ id: State.WindowID, state: inout State) -> Effect<Action> {
        guard state.windows[id: id] != nil,
              state.pendingWindowOpenIDs.contains(id),
              !state.closingWindowIDs.contains(id),
              state.externalWindowBatchIDs[id] == nil,
              state.retainedExternalOpenPlacementOwnership?.newWindowIDs.contains(id) != true
        else { return .none }

        if let trackedWindow = state.trackedSingletonWindow,
           trackedWindow.windowID == id
        {
            guard state.authorizedTrackedSingletonRequestID == trackedWindow.requestID else { return .none }
            return trackedWindowOpenEffect(
                for: id,
                requestID: trackedWindow.requestID,
                shouldBootstrapDefaultWindow: false,
            )
        }
        return windowOpenEffect(for: id, shouldBootstrapDefaultWindow: false)
    }

    private func trackedWindowOpenEffect(
        for id: State.WindowID,
        requestID: UUID,
        shouldBootstrapDefaultWindow: Bool,
    ) -> Effect<Action> {
        .run { [fileManagerWindowClient] send in
            guard let isRegistered = await Self.openAndVerifyWindowRegistration(
                id,
                client: fileManagerWindowClient,
            ) else { return }
            await send(.windowOpenCompleted(
                id: id,
                shouldBootstrapDefaultWindow: shouldBootstrapDefaultWindow,
                isRegistered: isRegistered,
            ))
            guard !Task.isCancelled else { return }
            await send(.trackedSingletonNativeOpenCompleted(requestID: requestID))
        }
        .cancellable(id: CancelID.trackedSingletonNativeOpen(requestID), cancelInFlight: true)
    }

    func closeWindow(_ id: State.WindowID, state: inout State) -> Effect<Action> {
        guard state.windows[id: id] != nil, !state.closingWindowIDs.contains(id) else { return .none }
        state.closingWindowIDs.insert(id)
        clearWindowFocus(id, state: &state)
        state.refreshContentTabMoveTargets()
        if state.focusedWindowID == id {
            state.focusedWindowID = nil
        }
        guard state.pendingWindowOpenIDs.contains(id) else {
            return .run { [fileManagerWindowClient] _ in await fileManagerWindowClient.close(id) }
        }
        return .concatenate(
            .cancel(id: CancelID.windowOpen(id)),
            .run { [fileManagerWindowClient] send in
                await fileManagerWindowClient.close(id)
                let registeredWindowIDs = await fileManagerWindowClient.registeredWindowIDs()
                guard !registeredWindowIDs.contains(id) else { return }
                await fileManagerWindowClient.finalizeClose(id)
                await send(.pendingWindowCloseFinalized(id: id))
            },
        )
    }

    func finalizePendingWindowClose(
        _ id: State.WindowID,
        state: inout State,
        preservingTrackedNativeOpen: Bool = false,
    ) -> Effect<Action> {
        guard state.closingWindowIDs.contains(id), state.pendingWindowOpenIDs.contains(id) else { return .none }
        return finalizeWindowRemoval(
            id,
            state: &state,
            preservingTrackedNativeOpen: preservingTrackedNativeOpen,
        )
    }

    func deferWindowRemovalUntilTopNavigationPersistenceCompletes(
        _ id: State.WindowID,
        state: inout State,
    ) -> Effect<Action> {
        guard state.windows[id: id] != nil else { return .none }
        let wasPendingOpen = state.pendingWindowOpenIDs.remove(id) != nil
        state.closingWindowIDs.insert(id)
        clearWindowFocus(id, state: &state)
        state.deferredClosedWindowIDs.insert(id)
        state.lastUsedWindowIDs.removeAll { $0 == id }
        state.defaultWindowBootstrapWindowIDs.remove(id)
        state.externalWindowBatchIDs[id] = nil
        if var ownership = state.retainedExternalOpenPlacementOwnership {
            ownership.newWindowIDs.removeAll { $0 == id }
            let isEmpty = ownership.newWindowIDs.isEmpty
            state.retainedExternalOpenPlacementOwnership = isEmpty ? nil : ownership
        }
        if state.focusedWindowID == id {
            state.focusedWindowID = state.lastUsedWindowIDs.first(where: { isWindowReady($0, state: state) })
                ?? state.windows.ids.first(where: { isWindowReady($0, state: state) })
        }

        var effects: [Effect<Action>] = []
        if wasPendingOpen {
            effects.append(.cancel(id: CancelID.windowOpen(id)))
        }
        if state.defaultWindowBootstrapWindowIDs.isEmpty, state.defaultWindowBootstrapRequestID != nil {
            state.defaultWindowBootstrapRequestID = nil
            effects.append(.cancel(id: CancelID.defaultWindowBootstrap))
        }
        return effects.isEmpty ? .none : .merge(effects)
    }

    func finalizeDeferredWindowClosuresWithoutPendingPersistence(
        state: inout State,
    ) -> Effect<Action> {
        let pendingParticipantWindowIDs = topNavigationPersistenceParticipantWindowIDs(in: state)
        let readyWindowIDs = state.deferredClosedWindowIDs
            .filter { !pendingParticipantWindowIDs.contains($0) }
        var effects: [Effect<Action>] = []
        for id in readyWindowIDs {
            effects.append(invalidateWindowBeforeFinalization(id, state: &state))
        }
        return effects.isEmpty ? .none : .merge(effects)
    }

    func invalidateWindowBeforeFinalization(
        _ id: State.WindowID,
        state: inout State,
    ) -> Effect<Action> {
        guard !state.invalidatingWindowIDs.contains(id) else { return .none }
        state.closingWindowIDs.insert(id)
        clearWindowFocus(id, state: &state)
        state.invalidatingWindowIDs.insert(id)
        state.refreshContentTabMoveTargets()
        return .run { [undoManagerClient, fileManagerWindowClient] send in
            let result = await undoManagerClient.invalidateWindow(id)
            if result.succeeded {
                await fileManagerWindowClient.finalizeClose(id)
            }
            await send(.windowInvalidationFinished(id: id, result: result))
        }
    }

    func topNavigationPersistenceParticipantWindowIDs(in state: State) -> Set<State.WindowID> {
        var windowIDs = Set(state.topNavigationPersistenceQueue.map(\.sourceWindowID))
        for queuedRequest in state.topNavigationPersistenceQueue {
            guard case let .contentTabMove(request, _, _) = queuedRequest.operation else { continue }
            windowIDs.insert(request.targetWindowID)
        }
        for transaction in state.contentTabMoveTransactions.values {
            windowIDs.insert(transaction.request.sourceWindowID)
            windowIDs.insert(transaction.request.targetWindowID)
        }
        return windowIDs
    }

    func clearWindowFocus(_ id: State.WindowID, state: inout State) {
        state.windows[id: id]?.window.isFocused = false
    }

    func clearAllWindowFocus(_ ids: [State.WindowID], state: inout State) {
        state.focusedWindowID = nil
        for id in ids {
            clearWindowFocus(id, state: &state)
        }
    }

    func finalizeWindowRemoval(
        _ id: State.WindowID,
        state: inout State,
        preservingTrackedNativeOpen: Bool = false,
    ) -> Effect<Action> {
        let wasFocused = state.focusedWindowID == id
        let trackedWindow = state.trackedSingletonWindow.flatMap { $0.windowID == id ? $0 : nil }
        state.windows.remove(id: id)
        state.pendingWindowOpenIDs.remove(id)
        state.closingWindowIDs.remove(id)
        state.deferredClosedWindowIDs.remove(id)
        state.invalidatingWindowIDs.remove(id)
        state.lastUsedWindowIDs.removeAll { $0 == id }
        state.defaultWindowBootstrapWindowIDs.remove(id)
        state.externalWindowBatchIDs[id] = nil
        if var ownership = state.retainedExternalOpenPlacementOwnership {
            ownership.newWindowIDs.removeAll { $0 == id }
            let isEmpty = ownership.newWindowIDs.isEmpty
            state.retainedExternalOpenPlacementOwnership = isEmpty ? nil : ownership
        }
        if wasFocused {
            state.focusedWindowID = state.lastUsedWindowIDs.first(where: { isWindowReady($0, state: state) })
                ?? state.windows.ids.first(where: { isWindowReady($0, state: state) })
        }
        var effects: [Effect<Action>] = []
        if let trackedWindow, !preservingTrackedNativeOpen {
            state.trackedSingletonWindow = nil
            effects.append(.cancel(id: CancelID.trackedSingletonNativeOpen(trackedWindow.requestID)))
            if state.authorizedTrackedSingletonRequestID == trackedWindow.requestID {
                state.authorizedTrackedSingletonRequestID = nil
            }
            if !trackedWindow.terminalOutcomeEmitted {
                effects.append(trackedSingletonCompletionEffect(trackedWindow.requestID))
            }
        }
        if let effect = externalOpenWindowRemovalEffect(id, state: &state) {
            effects.append(effect)
        }
        if state.defaultWindowBootstrapWindowIDs.isEmpty, state.defaultWindowBootstrapRequestID != nil {
            state.defaultWindowBootstrapRequestID = nil
            effects.append(.cancel(id: CancelID.defaultWindowBootstrap))
        }
        state.refreshContentTabMoveTargets()
        return effects.isEmpty ? .none : .merge(effects)
    }

    func externalOpenWindowRemovalEffect(
        _ id: State.WindowID,
        state: inout State,
    ) -> Effect<Action>? {
        guard let attempt = state.externalOpenActivationAttempt,
              state.authorizedExternalOpenBatchID == attempt.batchID,
              let removedPlanWindow = attempt.plan.windows.first(where: { $0.windowID == id })
        else { return nil }
        let unsettledPinnedTabID = removedPlanWindow.items.last(where: {
            $0.requiresPinnedAnchorReturn
                && !attempt.settledPinnedReturnTabIDs.contains($0.tabID)
        })?.tabID
        if let unsettledPinnedTabID {
            return replanExternalOpenActivationExcluding(
                windowID: id,
                tabID: unsettledPinnedTabID,
                state: &state,
            )
        }
        if let request = attempt.plan.request {
            let cancellationEffects = externalOpenPinnedReturnCancellationEffects(
                attempt,
                excludingWindowID: id,
                excludingTabID: nil,
                state: state,
            )
            state.externalOpenActivationAttempt = nil
            state.externalOpenActivationBecameKey = false
            guard let retryRequest = request.retryRequest,
                  case let .success(replacementPlan) = ExternalOpenPlacementPlanner.make(
                      retryRequest,
                      state: state,
                      generateUUID: uuid(),
                  )
            else {
                state.authorizedExternalOpenBatchID = nil
                return .concatenate(cancellationEffects + [
                    .send(.delegate(.externalOpenActivationFailed(
                        batchID: attempt.batchID,
                        failure: .recoveryExhausted,
                    ))),
                ])
            }
            return .concatenate(cancellationEffects + [
                .send(.placement(.apply(
                    plan: replacementPlan,
                    reservationsByItemID: replacementPlan.reservationsByItemID,
                ))),
            ])
        }
        guard attempt.windowID == id else { return nil }
        return retryExternalOpenActivation(after: attempt, state: &state)
    }

    func isWindowReady(_ id: State.WindowID, state: State) -> Bool {
        state.windows[id: id] != nil
            && !state.closingWindowIDs.contains(id)
            && !state.pendingWindowOpenIDs.contains(id)
    }

    private func openWindowSession(
        path: String?,
        selectEntryID: String?,
        resolvedStartPage: StartPage?,
        state: inout State,
    ) -> Effect<Action> {
        if onboardingWindowClient.showIfNeeded() { return .none }
        var startPage: StartPage?
        if path == nil {
            if let resolvedStartPage {
                startPage = resolvedStartPage
            } else {
                let snapshot = state.appPreferences.defaultStartPage
                if case .home = snapshot {
                    // home 선호는 IO가 없으므로 동기 fast path로 즉시 생성한다.
                    startPage = .home
                } else {
                    // 클라우드 placeholder stat이 메인 스레드를 막지 않도록 프로브를 effect로 미룬다.
                    let resolutionID = uuid()
                    state.pendingDefaultStartPageResolutions[resolutionID] = .init(trackedRequestID: nil)
                    return resolveDefaultStartPageEffect(resolutionID: resolutionID, snapshot: snapshot) { resolved in
                        .defaultStartPageResolved(
                            resolutionID: resolutionID,
                            requestID: nil,
                            selectEntryID: selectEntryID,
                            startPage: resolved,
                        )
                    }
                }
            }
        }
        let windowSession = makeWindowSession(
            path: path,
            startPage: startPage,
            selectEntryID: selectEntryID,
        )
        return openWindowSession(
            windowSession,
            startsDefaultBootstrap: path == nil,
            state: &state,
        )
    }

    /// 비동기 시작 페이지 프로브 완료 후 원래 요청 경로로 창 생성을 재개한다.
    func resumeDefaultStartPageResolution(
        resolutionID: UUID,
        requestID: UUID?,
        selectEntryID: String?,
        startPage: StartPage,
        state: inout State,
    ) -> Effect<Action> {
        guard let pending = state.pendingDefaultStartPageResolutions[resolutionID],
              pending.trackedRequestID == requestID
        else { return .none }
        state.pendingDefaultStartPageResolutions[resolutionID] = nil
        if let requestID {
            return openTrackedWindowSession(
                requestID: requestID,
                path: nil,
                selectEntryID: selectEntryID,
                resolvedStartPage: startPage,
                state: &state,
            )
        }
        return openWindowSession(
            path: nil,
            selectEntryID: selectEntryID,
            resolvedStartPage: startPage,
            state: &state,
        )
    }

    private func openCollectionWindowSession(url: URL, state: inout State) -> Effect<Action> {
        if onboardingWindowClient.showIfNeeded() { return .none }
        let windowSession = makeWindowSession(path: nil)
        return openWindowSession(
            windowSession,
            startsDefaultBootstrap: true,
            state: &state,
            beforePreferences: .send(.windows(.element(
                id: windowSession.id,
                action: .window(.navigation(.view(.openCollectionFile(url)))),
            ))),
        )
    }

    private func openWindowSession(
        _ windowSession: WindowSessionState,
        startsDefaultBootstrap: Bool,
        state: inout State,
        beforePreferences: Effect<Action> = .none,
    ) -> Effect<Action> {
        state.windows.append(windowSession)
        state.focusedWindowID = windowSession.id
        state.moveWindowToMRUFront(windowSession.id)
        state.pendingWindowOpenIDs.insert(windowSession.id)
        state.refreshContentTabMoveTargets()

        return .concatenate(
            windowIDChangedEffect(for: windowSession.id),
            beforePreferences,
            appPreferencesEffect(for: windowSession.id, preferences: state.appPreferences),
            windowOpenEffect(
                for: windowSession.id,
                shouldBootstrapDefaultWindow: startsDefaultBootstrap,
            ),
        )
    }

    private func windowIDChangedEffect(for id: UUID) -> Effect<Action> {
        .send(.windows(.element(
            id: id,
            action: .window(.content(.entryViewLayout(.entryOperations(.lifecycle(.windowIDChanged(id)))))),
        )))
    }
}
