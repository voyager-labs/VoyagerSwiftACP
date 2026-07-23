import ComposableArchitecture
import Foundation
import VoyagerEntitiesAppPreferences
import VoyagerEntitiesCollection
import VoyagerEntitiesEntry
import VoyagerFeaturesAiChat
import VoyagerFeaturesContentPageNavigation
import VoyagerFeaturesEntryArrangements
import VoyagerFeaturesEntryOperations
import VoyagerPagesFileManager
import VoyagerPagesOnboarding
import VoyagerShared
import VoyagerWidgetsEntryViewLayout

typealias FileManagerWindowFeature = FileManagerFeature

@Reducer
struct WindowManagerFeature {
    typealias State = WindowManagerState
    typealias Action = WindowManagerAction

    nonisolated private enum CancelID: Hashable {
        case defaultWindowBootstrap
        case windowOpen(State.WindowID)
        case externalOpenBatch(UUID)
        case trackedSingletonNativeOpen(UUID)
    }

    let pickAttachments: @Sendable () async -> [URL]

    init(
        pickAttachments: @escaping @Sendable () async -> [URL] = {
            await MainActor.run {
                AttachmentPickerPresenter.pickAttachments()
            }
        },
    ) {
        self.pickAttachments = pickAttachments
    }

    @Dependency(\.onboardingWindowClient)
    private var onboardingWindowClient

    @Dependency(\.fileManagerWindowClient)
    private var fileManagerWindowClient
    @Dependency(\.attachmentPickerClient)
    private var attachmentPickerClient
    @Dependency(\.undoManagerClient)
    private var undoManagerClient

    @Dependency(\.fileManagerBuiltInCollectionClient)
    private var fileManagerBuiltInCollectionClient
    @Dependency(\.contentTabPinnedRecordClient)
    private var contentTabPinnedRecordClient
    @Dependency(\.fileManagerClient)
    private var fileManagerClient
    @Dependency(\.fileManagerFavoritesClient)
    private var fileManagerFavoritesClient
    @Dependency(\.entryLoadingClient)
    private var entryLoadingClient
    @Dependency(\.userDefaultsClient)
    private var userDefaultsClient
    @Dependency(\.metricsClient)
    private var metricsClient

    @Dependency(\.date)
    private var date

    @Dependency(\.uuid)
    private var uuid

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .lifecycle(.openInitialWindowIfNeeded):
                guard state.windows.isEmpty else { return .none }
                return .send(.file(.newWindow(path: nil)))

            case let .lifecycle(.reopenWindowIfNeeded(hasVisibleWindows: flag)):
                guard !flag else { return .none }

                let reopenWindowID = state.focusedWindowID
                    .flatMap { isWindowReady($0, state: state) ? $0 : nil }
                    ?? state.lastUsedWindowIDs.first(where: { isWindowReady($0, state: state) })
                    ?? state.windows.ids.first(where: { isWindowReady($0, state: state) })
                guard let reopenWindowID else {
                    let hasPendingWindow = state.pendingWindowOpenIDs.contains { id in
                        state.windows[id: id] != nil && !state.closingWindowIDs.contains(id)
                    }
                    guard !hasPendingWindow else { return .none }
                    return .send(.file(.newWindow(path: nil)))
                }

                state.focusedWindowID = reopenWindowID
                state.moveWindowToMRUFront(reopenWindowID)
                return .run { [fileManagerWindowClient, reopenWindowID] _ in
                    await fileManagerWindowClient.open(reopenWindowID)
                }

            case let .lifecycle(.applyAppPreferences(preferences)):
                state.appPreferences = preferences
                return .merge(
                    state.windows.map { windowSession in
                        let packagePreferences = windowSession.window.appPreferencesPreservingSidebarState(
                            from: preferences.toPackageState(),
                        )
                        return .send(.windows(.element(
                            id: windowSession.id,
                            action: .window(.applyAppPreferences(packagePreferences)),
                        )))
                    },
                )

            case let .lifecycle(.aiConnectionsFileUpdated(file)):
                return .merge(
                    state.windows.ids.map { id in
                        .send(.windows(.element(id: id, action: .window(.aiConnectionsFileUpdated(file)))))
                    },
                )

            case .file(.newWindow),
                 .file(.openCollectionFile),
                 .file(.newTab),
                 .window(.closeFocusedWindow),
                 .window(.closeAllWindows):
                return handleWindowCommand(action, state: &state)

            case .file(.closeTab):
                return sendCloseTabCommandToFocusedWindow(state)

            case .file(.togglePinTab):
                return sendContentTabCommandToFocusedWindow(
                    state,
                    .toggleActiveContentTabPin,
                    capability: \.canToggleActiveContentTabPin,
                )

            case .file(.restoreLastClosedTab):
                return sendContentTabCommandToFocusedWindow(
                    state,
                    .restoreLastClosedContentTab,
                    capability: \.canRestoreLastClosedTab,
                )

            case .file(.duplicateTab):
                return sendDuplicateTabCommandToFocusedWindow(state)

            case .file(.newFolder):
                return sendCommandToFocusedWindow(state, .newFolder)

            case .file(.open):
                return sendCommandToFocusedWindow(state, .openSelectedItem)

            case .file(.quickLook):
                return sendCommandToFocusedWindow(state, .quickLookSelectedItem)

            case .file(.saveCollection):
                return sendCommandToFocusedWindow(state, .saveCollection)

            case .file(.saveCollectionAs):
                return sendCommandToFocusedWindow(state, .saveCollectionAs)

            case .window(.goBack):
                return sendCommandToFocusedWindow(state, .goBack)

            case .window(.goForward):
                return sendCommandToFocusedWindow(state, .goForward)

            case .window(.goToEnclosingDirectory):
                return sendCommandToFocusedWindow(state, .goToEnclosingDirectory)

            case .window(.toggleSidebar):
                return sendCommandToFocusedWindow(state, .toggleSidebar)

            case .window(.toggleShowHiddenFiles):
                return sendCommandToFocusedWindow(state, .toggleShowHiddenFiles)

            case let .view(.setViewLayout(layout)):
                return sendCommandToFocusedWindow(state, .setViewLayout(layout))

            case let .view(.setGroupKey(key)):
                return sendCommandToFocusedWindow(state, .setGroupKey(key))

            case let .view(.setSortKey(key)):
                return sendCommandToFocusedWindow(state, .setSortKey(key))

            case let .view(.setSortOrder(order)):
                return sendCommandToFocusedWindow(state, .setSortOrder(order))

            case .edit(.requestUndo):
                return sendCommandToFocusedWindow(state, .requestUndo)

            case .edit(.requestRedo):
                return sendCommandToFocusedWindow(state, .requestRedo)

            case .edit(.toggleComposer):
                return sendCommandToFocusedWindow(state, .toggleComposer)

            case .edit(.openContextualAiChat):
                return sendCommandToFocusedWindow(state, .openContextualAiChat)

            case .edit(.cut):
                return sendCommandToFocusedWindow(state, .cut)

            case .edit(.copy):
                return sendCommandToFocusedWindow(state, .copy)

            case .edit(.paste):
                return sendCommandToFocusedWindow(state, .paste)

            case .edit(.duplicate):
                return sendCommandToFocusedWindow(state, .duplicate)

            case .edit(.makeAlias):
                return sendCommandToFocusedWindow(state, .makeAlias)

            case .edit(.selectAll):
                return sendCommandToFocusedWindow(state, .selectAll)

            case .edit(.copyAbsolutePaths):
                return sendCommandToFocusedWindow(state, .copyAbsolutePaths)

            case .edit(.copyURLs):
                return sendCommandToFocusedWindow(state, .copyURLs)

            case let .event(.windowBecameKey(id)):
                guard state.windows[id: id] != nil,
                      !state.closingWindowIDs.contains(id)
                else { return .none }
                state.focusedWindowID = id
                state.moveWindowToMRUFront(id)
                return .none

            case let .event(.windowResignedKey(id)):
                if state.focusedWindowID == id {
                    state.focusedWindowID = nil
                }
                return .none

            case let .event(.windowClosed(id)):
                guard state.windows[id: id] != nil else {
                    return .run { [fileManagerWindowClient] _ in
                        await fileManagerWindowClient.finalizeClose(id)
                    }
                }
                guard !state.invalidatingWindowIDs.contains(id) else { return .none }
                state.closingWindowIDs.insert(id)
                state.invalidatingWindowIDs.insert(id)
                return .run { [undoManagerClient, fileManagerWindowClient] send in
                    let result = await undoManagerClient.invalidateWindow(id)
                    if result.succeeded {
                        await fileManagerWindowClient.finalizeClose(id)
                    }
                    await send(.windowInvalidationFinished(id: id, result: result))
                }

            case let .windowOpenCompleted(id, shouldBootstrapDefaultWindow, isRegistered):
                guard state.pendingWindowOpenIDs.contains(id),
                      state.windows[id: id] != nil,
                      !state.closingWindowIDs.contains(id)
                else { return .none }
                guard isRegistered else {
                    state.closingWindowIDs.insert(id)
                    return finalizePendingWindowClose(
                        id,
                        state: &state,
                        preservingTrackedNativeOpen: state.trackedSingletonWindow?.windowID == id,
                    )
                }
                state.pendingWindowOpenIDs.remove(id)
                guard shouldBootstrapDefaultWindow else { return .none }
                return defaultWindowBootstrapEffectIfNeeded(for: id, state: &state)

            case let .pendingWindowCloseFinalized(id):
                return finalizePendingWindowClose(id, state: &state)

            case let .windowInvalidationFinished(id, result):
                guard state.closingWindowIDs.contains(id) else { return .none }
                guard result.succeeded else { return .none }
                return finalizeWindowRemoval(id, state: &state)

            case let .event(.focusWindow(path)):
                return .run { _ in
                    await fileManagerWindowClient.focusPath(path)
                }

            case let .windows(.element(id: id, action: .window(.delegate(.closeWindow)))):
                return closeWindow(id, state: &state)

            case let .trackedSingleton(command):
                return handleTrackedSingletonCommand(command, state: &state)

            case let .trackedSingletonNativeOpenCompleted(requestID):
                guard state.authorizedTrackedSingletonRequestID == requestID else { return .none }
                state.authorizedTrackedSingletonRequestID = nil
                if state.trackedSingletonWindow?.requestID == requestID {
                    state.trackedSingletonWindow?.terminalOutcomeEmitted = true
                }
                return trackedSingletonCompletionEffect(requestID)

            case let .placement(.plan(request)):
                return .send(.delegate(.externalOpenPlacementCompleted(.init(
                    batchID: request.batchID,
                    result: ExternalOpenPlacementPlanner.make(request, state: state, generateUUID: uuid()),
                ))))

            case let .placement(.apply(plan, reservationsByItemID)):
                guard state.authorizedExternalOpenBatchID == plan.batchID else { return .none }
                return applyExternalOpenPlacement(
                    plan,
                    reservationsByItemID: reservationsByItemID,
                    state: &state,
                )
                .cancellable(id: CancelID.externalOpenBatch(plan.batchID), cancelInFlight: true)

            case let .placement(.activate(plan)):
                guard state.authorizedExternalOpenBatchID == plan.batchID else { return .none }
                return startExternalOpenActivation(plan: plan, excluding: [], state: &state)

            case let .placement(.cancel(batchID)):
                return cancelExternalOpenPlacement(batchID: batchID, state: &state)

            case let .externalOpenActivationResult(attempt, result):
                guard state.authorizedExternalOpenBatchID == attempt.batchID,
                      state.externalOpenActivationAttempt == attempt
                else { return .none }
                switch result {
                case .discarded:
                    return retryExternalOpenActivation(after: attempt, state: &state)
                case .becameKey:
                    let survivingWindowID = ExternalOpenPlacementApplication.lastSurvivingWindowID(
                        for: attempt.plan,
                        state: state,
                        excluding: attempt.excludedWindowIDs,
                    )
                    guard survivingWindowID == attempt.windowID else {
                        return retryExternalOpenActivation(after: attempt, state: &state)
                    }
                    state.authorizedExternalOpenBatchID = nil
                    state.externalOpenActivationAttempt = nil
                    return .send(.delegate(.externalOpenActivationCompleted(batchID: attempt.batchID)))
                }

            case let .windows(.element(id: _, action: .window(.delegate(.openPathInNewWindow(path))))):
                return .send(.file(.newWindow(path: path)))

            case let .windows(.element(
                id: sourceWindowID,
                action: .window(.delegate(.fixedLocationVisibilityChanged(hiddenIDs))),
            )):
                return .merge(
                    state.windows.ids
                        .filter { $0 != sourceWindowID }
                        .map { windowID in
                            .send(.windows(.element(
                                id: windowID,
                                action: .window(.applyHiddenFixedLocationIDs(hiddenIDs)),
                            )))
                        },
                )

            case .windows(.element(id: _, action: .window(.contentTabs(.pinnedRecordSaveSucceeded)))),
                 .windows(.element(
                     id: _,
                     action: .window(.performSelectedContentTabCloseMutation(
                         operationID: _,
                         tabID: _,
                         action: .pinnedRecordSaveSucceeded,
                     )),
                 )):
                return .send(.pinnedContentTabsStoreChanged)

            case .pinnedContentTabsStoreChanged:
                let syncEffect = syncPinnedContentTabsAcrossWindows(state: &state)
                state.defaultWindowBootstrapRequestID = nil
                state.defaultWindowBootstrapWindowIDs.removeAll()
                return .merge(
                    .cancel(id: CancelID.defaultWindowBootstrap),
                    syncEffect,
                )

            case let .defaultWindowBootstrapCompleted(requestID, restoredState):
                guard state.defaultWindowBootstrapRequestID == requestID else { return .none }
                state.defaultWindowBootstrapRequestID = nil
                let targetWindowIDs = state.windows.ids.filter {
                    state.defaultWindowBootstrapWindowIDs.contains($0)
                        && state.externalWindowBatchIDs[$0] == nil
                }
                state.defaultWindowBootstrapWindowIDs.removeAll()
                return .merge(
                    targetWindowIDs.map { id in
                        .send(.windows(.element(
                            id: id,
                            action: .window(.applyPinnedContentTabs(restoredState)),
                        )))
                    },
                )

            case let .defaultWindowBootstrapFailed(requestID):
                guard state.defaultWindowBootstrapRequestID == requestID else { return .none }
                state.defaultWindowBootstrapRequestID = nil
                state.defaultWindowBootstrapWindowIDs.removeAll()
                return .none

            case let .windows(.element(id: _, action: .window(.inspector(.setInspectorWidth(width))))):
                state.appPreferences.inspectorWidth = max(FileManagerInspectorLayoutMetrics.minWidth, width)
                return .none

            case let .windows(.element(id: id, action: .window(.delegate(.requestAttachmentPicker)))):
                return requestAttachmentPicker(for: id)

            case .windows(.element(id: _, action: .window(.delegate(.openAISettings)))):
                return .send(.delegate(.openAISettings))

            case .delegate, .windows:
                return .none
            }
        }
        .forEach(\.windows, action: \.windows) {
            WindowSessionFeature()
        }
    }
}

private extension WindowManagerFeature {
    func startExternalOpenActivation(
        plan: ExternalOpenPlacementPlan,
        excluding excludedWindowIDs: Set<State.WindowID>,
        state: inout State,
    ) -> Effect<Action> {
        guard let windowID = ExternalOpenPlacementApplication.lastSurvivingWindowID(
            for: plan,
            state: state,
            excluding: excludedWindowIDs,
        ) else {
            state.authorizedExternalOpenBatchID = nil
            state.externalOpenActivationAttempt = nil
            return .send(.delegate(.externalOpenActivationCompleted(batchID: plan.batchID)))
        }

        let attempt = ExternalOpenActivationAttempt(
            batchID: plan.batchID,
            plan: plan,
            windowID: windowID,
            excludedWindowIDs: excludedWindowIDs,
        )
        state.externalOpenActivationAttempt = attempt
        return .run { [fileManagerWindowClient] send in
            let result = await fileManagerWindowClient.activate(windowID)
            await send(.externalOpenActivationResult(attempt: attempt, result: result))
        }
        .cancellable(id: CancelID.externalOpenBatch(plan.batchID), cancelInFlight: false)
    }

    func retryExternalOpenActivation(
        after attempt: ExternalOpenActivationAttempt,
        state: inout State,
    ) -> Effect<Action> {
        var excludedWindowIDs = attempt.excludedWindowIDs
        excludedWindowIDs.insert(attempt.windowID)
        return startExternalOpenActivation(
            plan: attempt.plan,
            excluding: excludedWindowIDs,
            state: &state,
        )
    }

    func retainExternalOpenPlacementOwnership(
        _ batchID: UUID,
        _ newWindowIDs: [State.WindowID],
        state: inout State,
    ) {
        if newWindowIDs.isEmpty {
            if state.retainedExternalOpenPlacementOwnership?.batchID == batchID {
                state.retainedExternalOpenPlacementOwnership = nil
            }
        } else {
            state.retainedExternalOpenPlacementOwnership = .init(
                batchID: batchID,
                newWindowIDs: newWindowIDs,
            )
        }
    }

    func cancelExternalOpenPlacement(
        batchID: UUID,
        state: inout State,
    ) -> Effect<Action> {
        if state.authorizedExternalOpenBatchID == batchID { state.authorizedExternalOpenBatchID = nil }
        if state.externalOpenActivationAttempt?.batchID == batchID { state.externalOpenActivationAttempt = nil }
        var effects: [Effect<Action>] = [.cancel(id: CancelID.externalOpenBatch(batchID))]
        guard let ownership = state.retainedExternalOpenPlacementOwnership,
              ownership.batchID == batchID
        else { return .concatenate(effects) }
        state.retainedExternalOpenPlacementOwnership = nil
        let ownedWindowIDs = ownership.newWindowIDs.filter { state.externalWindowBatchIDs[$0] == batchID }
        for windowID in ownedWindowIDs {
            effects.append(closeWindow(windowID, state: &state))
        }
        return .concatenate(effects)
    }

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
            guard state.windows.isEmpty else {
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
        state.trackedSingletonWindow = .init(requestID: requestID, windowID: windowSession.id)
        return .concatenate(
            windowIDChangedEffect(for: windowSession.id),
            appPreferencesEffect(for: windowSession.id, preferences: state.appPreferences),
            .run { [fileManagerWindowClient, id = windowSession.id] send in
                await fileManagerWindowClient.open(id)
                guard !Task.isCancelled else { return }
                let registeredWindowIDs = await fileManagerWindowClient.registeredWindowIDs()
                guard !Task.isCancelled else { return }
                await send(.windowOpenCompleted(
                    id: id,
                    shouldBootstrapDefaultWindow: path == nil,
                    isRegistered: registeredWindowIDs.contains(id),
                ))
                guard !Task.isCancelled else { return }
                await send(.trackedSingletonNativeOpenCompleted(requestID: requestID))
            },
        )
        .cancellable(id: CancelID.trackedSingletonNativeOpen(requestID), cancelInFlight: true)
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

    private func trackedSingletonCompletionEffect(_ requestID: UUID) -> Effect<Action> {
        .send(.delegate(.trackedSingletonCompleted(requestID: requestID)))
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
        return .concatenate(
            windowIDChangedEffect(for: windowSession.id),
            appPreferencesEffect(for: windowSession.id, preferences: state.appPreferences),
            windowOpenEffect(for: windowSession.id, shouldBootstrapDefaultWindow: path == nil),
        )
    }

    private func openCollectionWindowSession(url: URL, state: inout State) -> Effect<Action> {
        if onboardingWindowClient.showIfNeeded() { return .none }
        let windowSession = makeWindowSession(path: nil)
        state.windows.append(windowSession)
        state.focusedWindowID = windowSession.id
        state.moveWindowToMRUFront(windowSession.id)
        state.pendingWindowOpenIDs.insert(windowSession.id)
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

    private func windowOpenEffect(
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

    private func closeWindow(_ id: State.WindowID, state: inout State) -> Effect<Action> {
        guard state.windows[id: id] != nil, !state.closingWindowIDs.contains(id) else { return .none }
        state.closingWindowIDs.insert(id)
        if state.focusedWindowID == id {
            state.focusedWindowID = state.lastUsedWindowIDs.first(where: {
                $0 != id && isWindowReady($0, state: state)
            }) ?? state.windows.ids.first(where: {
                $0 != id && isWindowReady($0, state: state)
            })
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

    private func finalizePendingWindowClose(
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

    private func finalizeWindowRemoval(
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
        return effects.isEmpty ? .none : .merge(effects)
    }

    private func isWindowReady(_ id: State.WindowID, state: State) -> Bool {
        state.windows[id: id] != nil
            && !state.closingWindowIDs.contains(id)
            && !state.pendingWindowOpenIDs.contains(id)
    }

    private func windowIDChangedEffect(for id: UUID) -> Effect<Action> {
        .send(.windows(.element(
            id: id,
            action: .window(.content(.entryViewLayout(.entryOperations(.lifecycle(.windowIDChanged(id)))))),
        )))
    }

    private func appPreferencesEffect(
        for id: UUID,
        preferences: AppPreferencesFeature.State,
    ) -> Effect<Action> {
        .send(.windows(.element(
            id: id,
            action: .window(.applyAppPreferences(preferences.toPackageState())),
        )))
    }

    private func applyExternalOpenPlacement(
        _ plan: ExternalOpenPlacementPlan,
        reservationsByItemID: [UUID: ExternalContentTabReservation],
        state: inout State,
    ) -> Effect<Action> {
        let existingWindowIDs = plan.windows.filter { !$0.isNewWindow }.map(\.windowID)
        guard existingWindowIDs.allSatisfy({ isWindowReady($0, state: state) }),
              let application = ExternalOpenPlacementApplication.apply(
                  plan,
                  reservationsByItemID: reservationsByItemID,
                  to: state.windows,
              )
        else {
            state.authorizedExternalOpenBatchID = nil
            return .send(.delegate(.externalOpenApplyCompleted(.init(
                batchID: plan.batchID,
                result: .failure(.validationFailed),
            ))))
        }
        state.windows = application.windows
        retainExternalOpenPlacementOwnership(plan.batchID, application.newWindowIDs, state: &state)
        for windowID in application.newWindowIDs {
            state.externalWindowBatchIDs[windowID] = plan.batchID
            state.pendingWindowOpenIDs.insert(windowID)
            state.moveWindowToMRUFront(windowID)
        }
        if let focusedWindowID = application.newWindowIDs.last { state.focusedWindowID = focusedWindowID }
        for windowID in plan.windows.map(\.windowID) {
            state.defaultWindowBootstrapWindowIDs.remove(windowID)
        }
        var effects: [Effect<Action>] = application.existingWindowActivations.map { activation in
            activateExternalContentTab(
                windowID: activation.windowID,
                tabID: activation.tabID,
            )
        }
        effects.append(contentsOf: application.newWindowIDs.flatMap { windowID in
            [
                appPreferencesEffect(for: windowID, preferences: state.appPreferences),
                windowOpenEffect(for: windowID, shouldBootstrapDefaultWindow: false),
                .send(.windows(.element(id: windowID, action: .window(.resyncActiveCollectionNavigation)))),
            ]
        })
        if state.defaultWindowBootstrapWindowIDs.isEmpty, state.defaultWindowBootstrapRequestID != nil {
            state.defaultWindowBootstrapRequestID = nil
            effects.append(.cancel(id: CancelID.defaultWindowBootstrap))
        }
        effects.append(.send(.delegate(.externalOpenApplyCompleted(.init(
            batchID: plan.batchID,
            result: .success(plan),
        )))))
        return .concatenate(effects)
    }

    private func activateExternalContentTab(
        windowID: WindowManagerState.WindowID,
        tabID: ContentTabID,
    ) -> Effect<Action> {
        .send(.windows(.element(
            id: windowID,
            action: .window(.contentTabs(.setCurrent(tabID))),
        )))
    }

    private func sendCommandToFocusedWindow(
        _ state: State,
        _ command: FileManagerWindowAction.WindowCommand,
    ) -> Effect<Action> {
        guard let id = state.focusedWindowID,
              !state.closingWindowIDs.contains(id)
        else { return .none }
        return .send(.windows(.element(id: id, action: .window(.request(command)))))
    }

    private func sendContentTabCommandToFocusedWindow(
        _ state: State,
        _ command: FileManagerWindowAction.WindowCommand,
        capability: KeyPath<FileManagerWindowMenuCommandProjection, Bool>,
    ) -> Effect<Action> {
        guard let id = state.focusedWindowID,
              !state.closingWindowIDs.contains(id),
              let window = state.windows[id: id],
              window.window.menuCommandProjection[keyPath: capability]
        else { return .none }
        return .send(.windows(.element(id: id, action: .window(.request(command)))))
    }

    private func sendCloseTabCommandToFocusedWindow(_ state: State) -> Effect<Action> {
        guard let id = state.focusedWindowID,
              !state.closingWindowIDs.contains(id),
              let window = state.windows[id: id]
        else { return .none }

        let projection = window.window.menuCommandProjection
        let command: FileManagerWindowAction.WindowCommand
        if projection.selectedContentTabCount > 1 {
            guard projection.canCloseSelectedContentTabs else { return .none }
            command = .closeSelectedContentTabs
        } else {
            guard projection.canCloseActiveContentTab else { return .none }
            command = .closeActiveContentTab
        }
        return .send(.windows(.element(id: id, action: .window(.request(command)))))
    }

    private func sendDuplicateTabCommandToFocusedWindow(_ state: State) -> Effect<Action> {
        guard let id = state.focusedWindowID,
              !state.closingWindowIDs.contains(id),
              let window = state.windows[id: id]
        else { return .none }

        let projection = window.window.menuCommandProjection
        let command: FileManagerWindowAction.WindowCommand
        if projection.selectedContentTabCount > 1 {
            guard projection.canDuplicateSelectedContentTabs else { return .none }
            command = .duplicateSelectedContentTabs
        } else {
            guard projection.canDuplicateActiveContentTab else { return .none }
            command = .duplicateActiveContentTab
        }
        return .send(.windows(.element(id: id, action: .window(.request(command)))))
    }

    private func syncPinnedContentTabsAcrossWindows(state: inout State) -> Effect<Action> {
        guard !state.windows.isEmpty else { return .none }
        do {
            let store = try contentTabPinnedRecordClient.loadStore(userDefaultsClient)
            let restoreResult = ContentTabState.restoringPinnedRecords(
                from: store,
                isRestorableAnchor: { _ in true },
            )
            return .merge(
                state.windows.ids.map { id in
                    .send(.windows(.element(
                        id: id,
                        action: .window(.applyPinnedContentTabs(restoreResult.state)),
                    )))
                },
            )
        } catch {
            return .none
        }
    }

    private func defaultWindowBootstrapEffectIfNeeded(
        for windowID: State.WindowID,
        state: inout State,
    ) -> Effect<Action> {
        state.defaultWindowBootstrapWindowIDs.insert(windowID)
        guard state.defaultWindowBootstrapRequestID == nil else { return .none }
        let requestID = uuid()
        state.defaultWindowBootstrapRequestID = requestID
        return runDefaultWindowBootstrapEffect(requestID: requestID)
            .cancellable(id: CancelID.defaultWindowBootstrap, cancelInFlight: true)
    }

    /// Default window's asynchronous pinned-store bootstrap.
    /// Concurrent default and Collection windows share one in-flight load.
    /// Completion applies pinned tabs only to windows that requested this bootstrap.
    private func runDefaultWindowBootstrapEffect(requestID: UUID) -> Effect<Action> {
        let now = date
        let dependencies = DefaultWindowBootstrap.Dependencies(
            builtInClient: fileManagerBuiltInCollectionClient,
            pinnedRecordClient: contentTabPinnedRecordClient,
            favoritesClient: fileManagerFavoritesClient,
            managerClient: fileManagerClient,
            loadingClient: entryLoadingClient,
            defaultsClient: userDefaultsClient,
            metricsClient: metricsClient,
            now: { now() },
        )

        return .run { send in
            guard let restoredState = await DefaultWindowBootstrap.run(dependencies) else { return }
            await send(.defaultWindowBootstrapCompleted(
                requestID: requestID,
                contentTabs: restoredState,
            ))
        }
    }

    private func makeWindowSession(path: String?, selectEntryID: String? = nil) -> WindowSessionState {
        let id = uuid()

        if let path {
            let windowState = FileManagerWindowFeature.State.makeInitial(
                path: path,
                selectEntryID: selectEntryID,
            )
            return .init(id: id, window: windowState)
        }

        // Default window: Home shell immediately, no synchronous IO.
        // Pinned store restore/seed/validation runs asynchronously via
        // runDefaultWindowBootstrapEffect() attached in openWindowSession.
        let windowState = FileManagerWindowFeature.State.makeInitial(
            path: nil,
            selectEntryID: selectEntryID,
        )
        return .init(id: id, window: windowState)
    }
}

private enum DefaultWindowBootstrap {
    struct Dependencies {
        let builtInClient: FileManagerBuiltInCollectionClient
        let pinnedRecordClient: ContentTabPinnedRecordClient
        let favoritesClient: FileManagerFavoritesClient
        let managerClient: FileManagerClient
        let loadingClient: EntryLoadingClient
        let defaultsClient: UserDefaultsClient
        let metricsClient: MetricsClient
        let now: @Sendable () -> Date
    }

    struct RestoreResult {
        let state: ContentTabState
        let didCompact: Bool
    }

    static func run(_ dependencies: Dependencies) async -> ContentTabState? {
        guard !Task.isCancelled else { return nil }
        let initialStore = (try? dependencies.pinnedRecordClient.loadStore(dependencies.defaultsClient))
            ?? ContentTabPinnedRecordStore()
        if !dependencies.defaultsClient.bool(SettingsKeys.defaultPinnedTabsSeedCompleted) {
            dependencies.defaultsClient.setBool(true, SettingsKeys.defaultPinnedTabsSeedCompleted)
        }
        seedFinderFavoritesIfNeeded(initialStore: initialStore, dependencies: dependencies)
        guard !Task.isCancelled else { return nil }
        let ensureReport = await dependencies.builtInClient.ensureAll()
        guard !Task.isCancelled else { return nil }
        dependencies.metricsClient.logMetric("built_in_pinned_seed_started", 1, nil)
        seedBuiltInCollectionIfNeeded(
            identity: .recents,
            ensureResult: ensureReport.recents,
            completionKey: SettingsKeys.recentsPinnedSeedCompleted,
            dependencies: dependencies,
        )
        guard !Task.isCancelled else { return nil }
        seedBuiltInCollectionIfNeeded(
            identity: .allTags,
            ensureResult: ensureReport.allTags,
            completionKey: SettingsKeys.allTagsPinnedSeedCompleted,
            dependencies: dependencies,
        )
        guard !Task.isCancelled else { return nil }
        let reloadedStore = (try? dependencies.pinnedRecordClient.loadStore(dependencies.defaultsClient))
            ?? ContentTabPinnedRecordStore()
        let restoreResult = restorePinnedRecords(from: reloadedStore, dependencies: dependencies)
        return compactIfNeeded(restoreResult, dependencies: dependencies)
    }

    private static func seedFinderFavoritesIfNeeded(
        initialStore: ContentTabPinnedRecordStore,
        dependencies: Dependencies,
    ) {
        guard !dependencies.defaultsClient.bool(SettingsKeys.finderFavoritesPinnedSeedCompleted) else { return }
        let applicationSupportURL = dependencies.managerClient.urlsForDirectory(
            .applicationSupportDirectory,
            .userDomainMask,
        ).first
        guard nonBuiltInRecords(
            in: initialStore,
            applicationSupportURL: applicationSupportURL,
        ).isEmpty else {
            dependencies.defaultsClient.setBool(true, SettingsKeys.finderFavoritesPinnedSeedCompleted)
            return
        }
        let favorites = dependencies.favoritesClient.loadFavorites(
            dependencies.loadingClient,
            dependencies.defaultsClient,
        )
        let mappedRecords = uniqueRecordsByID(FileManagerFavoritesPinnedRecordMapper.pinnedRecords(
            from: favorites,
            pinnedAt: dependencies.now(),
            fileExistsWithIsDirectory: { path, isDirectory in
                dependencies.managerClient.fileExistsWithIsDirectory(path, isDirectory)
            },
        ))
        do {
            _ = try dependencies.pinnedRecordClient.updateStoreAndLoad(
                dependencies.defaultsClient,
            ) { latestStore in
                try Task.checkCancellation()
                guard nonBuiltInRecords(
                    in: latestStore,
                    applicationSupportURL: applicationSupportURL,
                ).isEmpty else {
                    return latestStore
                }

                return mergingFinderRecords(
                    mappedRecords,
                    into: latestStore,
                    applicationSupportURL: applicationSupportURL,
                )
            }
            guard !Task.isCancelled else { return }
            dependencies.defaultsClient.setBool(true, SettingsKeys.finderFavoritesPinnedSeedCompleted)
        } catch {
            // Finder 저장 실패 시 완료 플래그를 남기지 않아 다음 부트스트랩에서 재시도한다.
        }
    }

    private static func seedBuiltInCollectionIfNeeded(
        identity: BuiltInCollectionIdentity,
        ensureResult: BuiltInCollectionEnsureItemResult,
        completionKey: String,
        dependencies: Dependencies,
    ) {
        guard !Task.isCancelled else { return }
        if dependencies.defaultsClient.bool(completionKey) {
            logSeedMetric("built_in_pinned_item_suppressed", identity: identity, dependencies: dependencies)
            return
        }
        let descriptor: BuiltInCollectionDescriptor
        switch ensureResult {
        case let .ready(value): descriptor = value
        case .deferred:
            logSeedMetric("built_in_pinned_item_deferred", identity: identity, dependencies: dependencies)
            return
        case .failed:
            logSeedMetric("built_in_pinned_item_failed", identity: identity, dependencies: dependencies)
            return
        }
        let policyDescriptor = BuiltInContentTabPinnedRecordSeedPolicy.VerifiedDescriptor(
            identity: descriptor.identity,
            canonicalPackageURL: descriptor.packageURL,
        )
        do {
            let finalStore = try dependencies.pinnedRecordClient.updateStoreAndLoad(
                dependencies.defaultsClient,
            ) { latestStore in
                try Task.checkCancellation()
                let result = BuiltInContentTabPinnedRecordSeedPolicy.evaluate(
                    ensureResult: .ready(policyDescriptor),
                    completion: false,
                    store: latestStore,
                    now: dependencies.now(),
                )
                return switch result {
                case let .seed(store), let .alreadyPresent(store):
                    store
                case .suppressed, .deferred, .failed:
                    latestStore
                }
            }
            guard BuiltInContentTabPinnedRecordSeedPolicy.containsCanonicalRecord(
                in: finalStore,
                descriptor: policyDescriptor,
            ) else {
                logSeedMetric("built_in_pinned_item_deferred", identity: identity, dependencies: dependencies)
                return
            }
            guard !Task.isCancelled else { return }
            dependencies.defaultsClient.setBool(true, completionKey)
            logSeedMetric("built_in_pinned_item_seeded", identity: identity, dependencies: dependencies)
        } catch {
            logSeedMetric("built_in_pinned_item_failed", identity: identity, dependencies: dependencies)
            // 항목별 저장 실패는 완료 플래그를 남기지 않아 독립적으로 재시도한다.
        }
    }

    private static func logSeedMetric(
        _ name: String,
        identity: BuiltInCollectionIdentity,
        dependencies: Dependencies,
    ) {
        let outcome = name.replacingOccurrences(of: "built_in_pinned_item_", with: "")
        dependencies.metricsClient.logMetric(
            name,
            1,
            ["identity": identity.rawValue, "outcome": outcome],
        )
    }

    private static func compactIfNeeded(
        _ restoreResult: RestoreResult,
        dependencies: Dependencies,
    ) -> ContentTabState {
        guard restoreResult.didCompact else { return restoreResult.state }

        do {
            let compactedStore = try dependencies.pinnedRecordClient.updateStoreAndLoad(
                dependencies.defaultsClient,
            ) { latestStore in
                try Task.checkCancellation()
                let latestRestoreResult = restorePinnedRecords(
                    from: latestStore,
                    dependencies: dependencies,
                )
                guard latestRestoreResult.didCompact else { return latestStore }

                return ContentTabPinnedRecordStore(
                    schemaVersion: latestStore.schemaVersion,
                    records: latestRestoreResult.state.tabs.compactMap { tab in
                        latestRestoreResult.state.pinnedRecords[tab.id]
                    },
                )
            }
            return restorePinnedRecords(from: compactedStore, dependencies: dependencies).state
        } catch {
            return restoreResult.state
        }
    }

    nonisolated private static func mergingFinderRecords(
        _ records: [ContentTabPinnedRecord],
        into store: ContentTabPinnedRecordStore,
        applicationSupportURL: URL?,
    ) -> ContentTabPinnedRecordStore {
        let recentsResidue = BuiltInContentTabPinnedRecordSeedPolicy.records(
            classifiedAs: .recents,
            in: store,
            applicationSupportURL: applicationSupportURL,
        )
        let allTagsResidue = BuiltInContentTabPinnedRecordSeedPolicy.records(
            classifiedAs: .allTags,
            in: store,
            applicationSupportURL: applicationSupportURL,
        )
        return ContentTabPinnedRecordStore(
            schemaVersion: store.schemaVersion,
            records: recentsResidue + records + allTagsResidue,
        )
    }

    nonisolated private static func nonBuiltInRecords(
        in store: ContentTabPinnedRecordStore,
        applicationSupportURL: URL?,
    ) -> [ContentTabPinnedRecord] {
        store.records.filter {
            BuiltInContentTabPinnedRecordSeedPolicy.classify(
                $0,
                applicationSupportURL: applicationSupportURL,
            ) == nil
        }
    }

    private static func uniqueRecordsByID(
        _ records: [ContentTabPinnedRecord],
    ) -> [ContentTabPinnedRecord] {
        var seenIDs = Set<String>()
        return records.filter { seenIDs.insert($0.id).inserted }
    }

    nonisolated private static func restorePinnedRecords(
        from store: ContentTabPinnedRecordStore,
        dependencies: Dependencies,
    ) -> RestoreResult {
        let result = ContentTabState.restoringPinnedRecords(
            from: store,
            isRestorableAnchor: { anchor in
                switch anchor {
                case let .directory(path):
                    var isDirectory = ObjCBool(false)
                    return dependencies.managerClient.fileExistsWithIsDirectory(path, &isDirectory)
                        && isDirectory.boolValue
                case let .collectionFile(url):
                    return dependencies.managerClient.fileExistsWithIsDirectory(url.path, nil)
                case .homeDefault, .virtualCollection, .aiChat:
                    return true
                }
            },
        )
        return RestoreResult(state: result.state, didCompact: result.didCompact)
    }
}

private extension WindowManagerFeature {
    func requestAttachmentPicker(for windowID: WindowManagerState.WindowID) -> Effect<Action> {
        .run { [attachmentPickerClient] send in
            let urls = await attachmentPickerClient.pickAttachments()
            guard !urls.isEmpty else { return }
            let action = await MainActor.run {
                Action.windows(.element(
                    id: windowID,
                    action: .window(.inspector(.aiChat(.attachmentPickerSelection(urls)))),
                ))
            }
            await send(action)
        }
    }
}
