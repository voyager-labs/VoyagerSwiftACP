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
                state: &state,
            )
        }
    }

    func handleWindowCommand(_ action: Action, state: inout State) -> Effect<Action> {
        switch action {
        case let .file(.newWindow(path, selectEntryID)):
            return openWindowSession(path: path, selectEntryID: selectEntryID, state: &state)
        case let .file(.openCollectionFile(url)):
            return openCollectionWindowSession(url: url, state: &state)
        case .file(.newTab):
            return sendContentTabCommandToFocusedWindow(
                state,
                .openNewContentTab,
                capability: \.canOpenNewContentTab,
            )
        case .window(.closeFocusedWindow):
            guard let id = state.focusedWindowID else { return .none }
            return closeWindow(id, state: &state)
        case .window(.closeAllWindows):
            let openWindowIDs = state.windows.ids.filter { !state.closingWindowIDs.contains($0) }
            guard !openWindowIDs.isEmpty else { return .none }
            let pendingWindowOpenIDs = openWindowIDs.filter { state.pendingWindowOpenIDs.contains($0) }
            let externalBatchIDs = Set(openWindowIDs.compactMap { state.externalWindowBatchIDs[$0] })
            let trackedRequestIDs: Set<UUID> = Set(openWindowIDs.compactMap { windowID -> UUID? in
                guard state.trackedSingletonWindow?.windowID == windowID else { return nil }
                return state.trackedSingletonWindow?.requestID
            })
            state.closingWindowIDs.formUnion(openWindowIDs)
            state.focusedWindowID = nil
            state.lastUsedWindowIDs.removeAll()
            state.refreshContentTabMoveTargets()
            state.defaultWindowBootstrapRequestID = nil
            state.defaultWindowBootstrapWindowIDs.removeAll()
            state.authorizedExternalOpenBatchID = nil
            state.externalOpenActivationAttempt = nil
            state.retainedExternalOpenPlacementOwnership = nil
            var cancellationEffects: [Effect<Action>] = [.cancel(id: CancelID.defaultWindowBootstrap)]
            cancellationEffects.append(contentsOf: pendingWindowOpenIDs.map { .cancel(id: CancelID.windowOpen($0)) })
            cancellationEffects.append(contentsOf: externalBatchIDs.map { .cancel(id: CancelID.externalOpenBatch($0)) })
            cancellationEffects.append(contentsOf: trackedRequestIDs.map { requestID in
                Effect<Action>.cancel(id: CancelID.trackedSingletonNativeOpen(requestID))
            })
            let closeAllEffect = Effect<Action>.run { [fileManagerWindowClient] send in
                await fileManagerWindowClient.closeAll()
                let registeredWindowIDs = await fileManagerWindowClient.registeredWindowIDs()
                for id in pendingWindowOpenIDs where !registeredWindowIDs.contains(id) {
                    await fileManagerWindowClient.finalizeClose(id)
                    await send(.pendingWindowCloseFinalized(id: id))
                }
            }
            return .concatenate(.merge(cancellationEffects), closeAllEffect)
        default:
            return .none
        }
    }

    private func openTrackedWindowSession(
        requestID: UUID,
        path: String?,
        selectEntryID: String?,
        state: inout State,
    ) -> Effect<Action> {
        guard state.authorizedTrackedSingletonRequestID == requestID else {
            return trackedSingletonCompletionEffect(requestID)
        }
        guard !onboardingWindowClient.showIfNeeded() else {
            state.authorizedTrackedSingletonRequestID = nil
            return trackedSingletonCompletionEffect(requestID)
        }
        let windowSession = makeWindowSession(path: path, selectEntryID: selectEntryID)
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
        guard let trackedWindow = state.trackedSingletonWindow,
              trackedWindow.requestID == requestID
        else {
            if wasAuthorized { effects.append(trackedSingletonCompletionEffect(requestID)) }
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
            await fileManagerWindowClient.open(id)
            guard !Task.isCancelled else { return }
            let registeredWindowIDs = await fileManagerWindowClient.registeredWindowIDs()
            guard !Task.isCancelled else { return }
            await send(.windowOpenCompleted(
                id: id,
                shouldBootstrapDefaultWindow: shouldBootstrapDefaultWindow,
                isRegistered: registeredWindowIDs.contains(id),
            ))
        }
        .cancellable(id: CancelID.windowOpen(id))
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
            await fileManagerWindowClient.open(id)
            guard !Task.isCancelled else { return }
            let registeredWindowIDs = await fileManagerWindowClient.registeredWindowIDs()
            guard !Task.isCancelled else { return }
            await send(.windowOpenCompleted(
                id: id,
                shouldBootstrapDefaultWindow: shouldBootstrapDefaultWindow,
                isRegistered: registeredWindowIDs.contains(id),
            ))
            guard !Task.isCancelled else { return }
            await send(.trackedSingletonNativeOpenCompleted(requestID: requestID))
        }
        .cancellable(id: CancelID.trackedSingletonNativeOpen(requestID), cancelInFlight: true)
    }

    func closeWindow(_ id: State.WindowID, state: inout State) -> Effect<Action> {
        guard state.windows[id: id] != nil, !state.closingWindowIDs.contains(id) else { return .none }
        state.closingWindowIDs.insert(id)
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
        state.deferredClosedWindowIDs.insert(id)
        state.lastUsedWindowIDs.removeAll { $0 == id }
        state.defaultWindowBootstrapWindowIDs.remove(id)
        state.externalWindowBatchIDs[id] = nil
        if var ownership = state.retainedExternalOpenPlacementOwnership {
            ownership.newWindowIDs.removeAll { $0 == id }
            state.retainedExternalOpenPlacementOwnership = ownership.newWindowIDs.isEmpty ? nil : ownership
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
            effects.append(finalizeWindowRemoval(id, state: &state))
        }
        return effects.isEmpty ? .none : .merge(effects)
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

    func finalizeWindowRemoval(
        _ id: State.WindowID,
        state: inout State,
        preservingTrackedNativeOpen: Bool = false,
    ) -> Effect<Action> {
        let wasFocused = state.focusedWindowID == id
        let trackedWindow = state.trackedSingletonWindow.flatMap { $0.windowID == id ? $0 : nil }
        let activationAttempt = state.externalOpenActivationAttempt.flatMap { $0.windowID == id ? $0 : nil }
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
            state.retainedExternalOpenPlacementOwnership = ownership.newWindowIDs.isEmpty ? nil : ownership
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
        if let activationAttempt, state.authorizedExternalOpenBatchID == activationAttempt.batchID {
            state.externalOpenActivationAttempt = nil
            effects.append(retryExternalOpenActivation(after: activationAttempt, state: &state))
        }
        if state.defaultWindowBootstrapWindowIDs.isEmpty, state.defaultWindowBootstrapRequestID != nil {
            state.defaultWindowBootstrapRequestID = nil
            effects.append(.cancel(id: CancelID.defaultWindowBootstrap))
        }
        state.refreshContentTabMoveTargets()
        return effects.isEmpty ? .none : .merge(effects)
    }

    func isWindowReady(_ id: State.WindowID, state: State) -> Bool {
        state.windows[id: id] != nil
            && !state.closingWindowIDs.contains(id)
            && !state.pendingWindowOpenIDs.contains(id)
    }

    private func openWindowSession(
        path: String?,
        selectEntryID: String?,
        state: inout State,
    ) -> Effect<Action> {
        if onboardingWindowClient.showIfNeeded() { return .none }
        let windowSession = makeWindowSession(path: path, selectEntryID: selectEntryID)
        state.windows.append(windowSession)
        state.focusedWindowID = windowSession.id
        state.moveWindowToMRUFront(windowSession.id)
        state.pendingWindowOpenIDs.insert(windowSession.id)
        state.refreshContentTabMoveTargets()
        var effects: [Effect<Action>] = [
            windowIDChangedEffect(for: windowSession.id),
            appPreferencesEffect(for: windowSession.id, preferences: state.appPreferences),
        ]
        effects.append(windowOpenEffect(
            for: windowSession.id,
            shouldBootstrapDefaultWindow: path == nil,
        ))
        return .concatenate(effects)
    }

    private func openCollectionWindowSession(url: URL, state: inout State) -> Effect<Action> {
        if onboardingWindowClient.showIfNeeded() { return .none }
        let windowSession = makeWindowSession(path: nil)
        state.windows.append(windowSession)
        state.focusedWindowID = windowSession.id
        state.moveWindowToMRUFront(windowSession.id)
        state.pendingWindowOpenIDs.insert(windowSession.id)
        state.refreshContentTabMoveTargets()
        return .concatenate(
            windowIDChangedEffect(for: windowSession.id),
            .send(.windows(.element(
                id: windowSession.id,
                action: .window(.navigation(.view(.openCollectionFile(url)))),
            ))),
            appPreferencesEffect(for: windowSession.id, preferences: state.appPreferences),
            windowOpenEffect(for: windowSession.id, shouldBootstrapDefaultWindow: true),
        )
    }

    private func windowIDChangedEffect(for id: UUID) -> Effect<Action> {
        .send(.windows(.element(
            id: id,
            action: .window(.content(.entryViewLayout(.entryOperations(.lifecycle(.windowIDChanged(id)))))),
        )))
    }
}
