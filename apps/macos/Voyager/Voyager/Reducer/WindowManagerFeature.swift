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

                if state.windows.isEmpty {
                    return .send(.file(.newWindow(path: nil)))
                }

                guard let reopenWindowID = state.focusedWindowID
                    ?? state.lastUsedWindowIDs.first(where: { state.windows[id: $0] != nil })
                    ?? state.windows.first?.id
                else {
                    return .none
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
                return sendCommandToFocusedWindow(state, .closeActiveContentTab)

            case .file(.togglePinTab):
                return sendCommandToFocusedWindow(state, .toggleActiveContentTabPin)

            case .file(.restoreLastClosedTab):
                return sendCommandToFocusedWindow(state, .restoreLastClosedContentTab)

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

            case .edit(.newChat):
                return sendCommandToFocusedWindow(state, .newChat)

            case .edit(.showChatHistory):
                return sendCommandToFocusedWindow(state, .showChatHistory)

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
                guard state.windows[id: id] != nil else { return .none }
                state.focusedWindowID = id
                state.moveWindowToMRUFront(id)
                return .none

            case let .event(.windowResignedKey(id)):
                if state.focusedWindowID == id {
                    state.focusedWindowID = nil
                }
                return .none

            case let .event(.windowClosed(id)):
                let wasFocused = state.focusedWindowID == id
                state.windows.remove(id: id)
                state.lastUsedWindowIDs.removeAll { $0 == id }
                state.defaultWindowBootstrapWindowIDs.remove(id)
                state.externalWindowBatchIDs[id] = nil
                if wasFocused {
                    state.focusedWindowID = state.lastUsedWindowIDs.first(where: { state.windows[id: $0] != nil })
                }
                guard state.defaultWindowBootstrapWindowIDs.isEmpty,
                      state.defaultWindowBootstrapRequestID != nil
                else { return .none }
                state.defaultWindowBootstrapRequestID = nil
                return .cancel(id: CancelID.defaultWindowBootstrap)

            case let .event(.focusWindow(path)):
                return .run { _ in
                    await fileManagerWindowClient.focusPath(path)
                }

            case let .trackedSingleton(command):
                return handleTrackedSingletonCommand(command, state: &state)

            case let .trackedSingletonNativeOpenCompleted(requestID):
                guard state.authorizedTrackedSingletonRequestID == requestID else { return .none }
                state.authorizedTrackedSingletonRequestID = nil
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
                return startExternalOpenActivation(
                    plan: plan,
                    excluding: [],
                    state: &state,
                )

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

            case .windows(.element(id: _, action: .window(.contentTabs(.pinnedRecordSaveSucceeded)))):
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
        if state.authorizedExternalOpenBatchID == batchID {
            state.authorizedExternalOpenBatchID = nil
        }
        if state.externalOpenActivationAttempt?.batchID == batchID {
            state.externalOpenActivationAttempt = nil
        }

        var effects: [Effect<Action>] = [
            .cancel(id: CancelID.externalOpenBatch(batchID)),
        ]
        guard let ownership = state.retainedExternalOpenPlacementOwnership,
              ownership.batchID == batchID
        else {
            return .concatenate(effects)
        }
        state.retainedExternalOpenPlacementOwnership = nil

        let ownedWindowIDs = ownership.newWindowIDs.filter {
            state.externalWindowBatchIDs[$0] == batchID
        }
        let removedFocusedWindow = state.focusedWindowID.map(ownedWindowIDs.contains) ?? false
        let removedBootstrapWindow = ownedWindowIDs.contains {
            state.defaultWindowBootstrapWindowIDs.contains($0)
        }
        for windowID in ownedWindowIDs {
            state.windows.remove(id: windowID)
            state.lastUsedWindowIDs.removeAll { $0 == windowID }
            state.defaultWindowBootstrapWindowIDs.remove(windowID)
            state.externalWindowBatchIDs[windowID] = nil
        }
        if removedFocusedWindow {
            state.focusedWindowID = state.lastUsedWindowIDs.first { state.windows[id: $0] != nil }
        }
        if removedBootstrapWindow,
           state.defaultWindowBootstrapWindowIDs.isEmpty,
           state.defaultWindowBootstrapRequestID != nil
        {
            state.defaultWindowBootstrapRequestID = nil
            effects.append(.cancel(id: CancelID.defaultWindowBootstrap))
        }
        effects.append(contentsOf: ownedWindowIDs.map { windowID in
            .run { [fileManagerWindowClient] _ in
                await fileManagerWindowClient.close(windowID)
            }
        })
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
            return openWindowSession(path: path, selectEntryID: selectEntryID, state: &state) { id in
                await fileManagerWindowClient.open(id)
            }

        case let .file(.openCollectionFile(url)):
            return openCollectionWindowSession(url: url, state: &state)

        case .file(.newTab):
            return sendCommandToFocusedWindow(state, .openNewContentTab)

        case .window(.closeFocusedWindow):
            guard let id = state.focusedWindowID else { return .none }
            return .run { [id] _ in
                await fileManagerWindowClient.close(id)
            }

        case .window(.closeAllWindows):
            state.windows.removeAll()
            state.focusedWindowID = nil
            state.lastUsedWindowIDs.removeAll()
            state.defaultWindowBootstrapRequestID = nil
            state.defaultWindowBootstrapWindowIDs.removeAll()
            state.externalWindowBatchIDs.removeAll()
            return .merge(
                .cancel(id: CancelID.defaultWindowBootstrap),
                .run { _ in
                    await fileManagerWindowClient.closeAll()
                },
            )

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
        state.trackedSingletonWindow = .init(requestID: requestID, windowID: windowSession.id)

        let bootstrapEffect: Effect<Action> = if path == nil {
            defaultWindowBootstrapEffectIfNeeded(for: windowSession.id, state: &state)
        } else {
            .none
        }

        return .concatenate(
            windowIDChangedEffect(for: windowSession.id),
            appPreferencesEffect(for: windowSession.id, preferences: state.appPreferences),
            .run { [fileManagerWindowClient, id = windowSession.id] send in
                await fileManagerWindowClient.open(id)
                await send(.trackedSingletonNativeOpenCompleted(requestID: requestID))
            },
            bootstrapEffect,
        )
        .cancellable(id: CancelID.trackedSingletonNativeOpen(requestID), cancelInFlight: true)
    }

    private func revokeTrackedSingleton(
        requestID: UUID,
        state: inout State,
    ) -> Effect<Action> {
        if state.authorizedTrackedSingletonRequestID == requestID {
            state.authorizedTrackedSingletonRequestID = nil
        }
        guard let trackedWindow = state.trackedSingletonWindow,
              trackedWindow.requestID == requestID
        else {
            return .cancel(id: CancelID.trackedSingletonNativeOpen(requestID))
        }

        let windowID = trackedWindow.windowID
        let wasFocused = state.focusedWindowID == windowID
        state.trackedSingletonWindow = nil
        state.windows.remove(id: windowID)
        state.lastUsedWindowIDs.removeAll { $0 == windowID }
        state.defaultWindowBootstrapWindowIDs.remove(windowID)
        state.externalWindowBatchIDs[windowID] = nil
        if wasFocused {
            state.focusedWindowID = state.lastUsedWindowIDs.first { state.windows[id: $0] != nil }
        }

        var effects: [Effect<Action>] = [
            .cancel(id: CancelID.trackedSingletonNativeOpen(requestID)),
        ]
        if state.defaultWindowBootstrapWindowIDs.isEmpty,
           state.defaultWindowBootstrapRequestID != nil
        {
            state.defaultWindowBootstrapRequestID = nil
            effects.append(.cancel(id: CancelID.defaultWindowBootstrap))
        }
        effects.append(.run { [fileManagerWindowClient] _ in
            await fileManagerWindowClient.close(windowID)
        })
        return .concatenate(effects)
    }

    private func trackedSingletonCompletionEffect(_ requestID: UUID) -> Effect<Action> {
        .send(.delegate(.trackedSingletonCompleted(requestID: requestID)))
    }

    private func openWindowSession(
        path: String?,
        selectEntryID: String?,
        state: inout State,
        open: @escaping @Sendable (UUID) async -> Void,
    ) -> Effect<Action> {
        if onboardingWindowClient.showIfNeeded() {
            return .none
        }
        let windowSession = makeWindowSession(path: path, selectEntryID: selectEntryID)

        state.windows.append(windowSession)
        state.focusedWindowID = windowSession.id
        state.moveWindowToMRUFront(windowSession.id)

        let bootstrapEffect: Effect<Action> = if path == nil {
            defaultWindowBootstrapEffectIfNeeded(for: windowSession.id, state: &state)
        } else {
            .none
        }

        return .concatenate(
            windowIDChangedEffect(for: windowSession.id),
            appPreferencesEffect(for: windowSession.id, preferences: state.appPreferences),
            .run { [id = windowSession.id] _ in
                await open(id)
            },
            bootstrapEffect,
        )
    }

    private func openCollectionWindowSession(url: URL, state: inout State) -> Effect<Action> {
        if onboardingWindowClient.showIfNeeded() {
            return .none
        }
        let windowSession = makeWindowSession(path: nil)

        state.windows.append(windowSession)
        state.focusedWindowID = windowSession.id
        state.moveWindowToMRUFront(windowSession.id)
        let bootstrapEffect = defaultWindowBootstrapEffectIfNeeded(for: windowSession.id, state: &state)

        return .concatenate(
            windowIDChangedEffect(for: windowSession.id),
            .send(.windows(.element(
                id: windowSession.id,
                action: .window(.navigation(.view(.openCollectionFile(url)))),
            ))),
            appPreferencesEffect(for: windowSession.id, preferences: state.appPreferences),
            .run { [fileManagerWindowClient, id = windowSession.id] _ in
                await fileManagerWindowClient.open(id)
            },
            bootstrapEffect,
        )
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
        guard let application = ExternalOpenPlacementApplication.apply(
            plan,
            reservationsByItemID: reservationsByItemID,
            to: state.windows,
        ) else {
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
        }
        for windowID in plan.windows.map(\.windowID) {
            state.defaultWindowBootstrapWindowIDs.remove(windowID)
        }

        var effects: [Effect<Action>] = application.existingWindowActivations.map { activation in
            Effect.send(.windows(.element(
                id: activation.windowID,
                action: .window(.contentTabs(.setCurrent(activation.tabID))),
            )))
        }
        effects.append(contentsOf: application.newWindowIDs.flatMap { windowID in
            [
                appPreferencesEffect(for: windowID, preferences: state.appPreferences),
                Effect.run { [fileManagerWindowClient] _ in
                    await fileManagerWindowClient.open(windowID)
                },
                Effect.send(.windows(.element(
                    id: windowID,
                    action: .window(.resyncActiveCollectionNavigation),
                ))),
            ]
        })
        if state.defaultWindowBootstrapWindowIDs.isEmpty,
           state.defaultWindowBootstrapRequestID != nil
        {
            state.defaultWindowBootstrapRequestID = nil
            effects.append(.cancel(id: CancelID.defaultWindowBootstrap))
        }
        effects.append(.send(.delegate(.externalOpenApplyCompleted(.init(
            batchID: plan.batchID,
            result: .success(plan),
        )))))
        return .concatenate(effects)
    }

    private func sendCommandToFocusedWindow(
        _ state: State,
        _ command: FileManagerWindowAction.WindowCommand,
    ) -> Effect<Action> {
        guard let id = state.focusedWindowID else { return .none }
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
