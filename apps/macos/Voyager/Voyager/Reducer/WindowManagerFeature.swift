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

    nonisolated enum CancelID: Hashable {
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
    var onboardingWindowClient

    @Dependency(\.fileManagerWindowClient)
    var fileManagerWindowClient
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
                return sendCloseTabCommandToFocusedWindow(state)

            case .file(.togglePinTab):
                return sendPinTabCommandToFocusedWindow(state)

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

            case let .windows(.element(
                id: sourceWindowID,
                action: .window(.delegate(.pinnedRecordPersistenceRequested(request))),
            )):
                let mutationID = request.request.mutationID
                guard state.inFlightPinnedRecordMutations[mutationID] == nil else { return .none }
                let generation = contentTabPinnedRecordClient.reserveMutationGeneration(request.request.tabID)
                state.inFlightPinnedRecordMutations[mutationID] = WindowManagerInFlightPinnedRecordMutation(
                    sourceWindowID: sourceWindowID,
                    request: request,
                    generation: generation,
                )
                return runPinnedRecordMutation(
                    mutationID: mutationID,
                    request: request.request,
                    generation: generation,
                )

            case let .pinnedRecordMutationFinished(mutationID, outcome):
                guard let mutation = state.inFlightPinnedRecordMutations.removeValue(forKey: mutationID) else {
                    return .none
                }
                let localTerminal = localPinnedRecordTerminalAction(
                    mutation: mutation,
                    outcome: outcome,
                    state: state,
                )
                return .concatenate(
                    localTerminal.map(Effect.send) ?? .none,
                    .send(.pinnedContentTabsStoreChanged),
                )

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

extension WindowManagerFeature {
    func appPreferencesEffect(
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

        var effects = externalOpenActivationEffects(application.existingWindowActivations)
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

    func sendCommandToFocusedWindow(
        _ state: State,
        _ command: FileManagerWindowAction.WindowCommand,
    ) -> Effect<Action> {
        guard let id = state.focusedWindowID,
              !state.closingWindowIDs.contains(id)
        else { return .none }
        return .send(.windows(.element(id: id, action: .window(.request(command)))))
    }

    func sendContentTabCommandToFocusedWindow(
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

    private func sendPinTabCommandToFocusedWindow(_ state: State) -> Effect<Action> {
        guard let id = state.focusedWindowID,
              !state.closingWindowIDs.contains(id),
              let window = state.windows[id: id]
        else { return .none }

        let projection = window.window.menuCommandProjection
        if projection.selectedContentTabCount > 1 {
            guard projection.canSetSelectedContentTabsPinned else { return .none }
            let target: SelectedContentTabPinMutationTargetState = projection.isSelectedContentTabPinTargetPinned
                ? .unpinned
                : .pinned
            return .send(.windows(.element(
                id: id,
                action: .window(.requestSelectedContentTabPinMutation(target: target)),
            )))
        }

        guard projection.canToggleActiveContentTabPin else { return .none }
        return .send(.windows(.element(
            id: id,
            action: .window(.request(.toggleActiveContentTabPin)),
        )))
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

    private func runPinnedRecordMutation(
        mutationID: UUID,
        request: ContentTabPinnedRecordPersistenceRequest,
        generation: ContentTabPinnedRecordMutationGeneration,
    ) -> Effect<Action> {
        let client = contentTabPinnedRecordClient
        let defaults = userDefaultsClient
        return .run { send in
            let outcome: WindowManagerPinnedRecordMutationOutcome
            do {
                let disposition = try await client.updateStoreGuarded(generation, defaults) { store in
                    request.mutation.applying(to: store)
                }
                outcome = disposition == .applied ? .applied : .superseded
            } catch is CancellationError {
                outcome = .cancelled
            } catch {
                outcome = .failed
            }
            await send(.pinnedRecordMutationFinished(mutationID: mutationID, outcome: outcome))
        }
    }

    private func localPinnedRecordTerminalAction(
        mutation: WindowManagerInFlightPinnedRecordMutation,
        outcome: WindowManagerPinnedRecordMutationOutcome,
        state: State,
    ) -> Action? {
        let sourceWindowID = mutation.sourceWindowID
        let request = mutation.request.request
        guard let window = state.windows[id: sourceWindowID]?.window,
              !window.isClosing,
              !state.closingWindowIDs.contains(sourceWindowID),
              window.contentTabs.isCurrentPinnedRecordPersistenceIntent(
                  tabID: request.tabID,
                  intentID: request.intentID,
              ),
              isCurrentLocalPinnedRecordRoute(
                  mutation.request.route,
                  tabID: request.tabID,
                  window: window,
              )
        else { return nil }

        let context = ContentTabPinnedRecordTerminalContext(
            intentID: request.intentID,
            generation: mutation.generation,
        )
        let terminal = pinnedRecordTerminal(
            outcome: outcome,
            request: request,
            context: context,
        )
        let windowAction = routePinnedRecordTerminal(
            terminal,
            request: mutation.request,
        )
        return .windows(.element(id: sourceWindowID, action: .window(windowAction)))
    }

    private func isCurrentLocalPinnedRecordRoute(
        _ route: FileManagerPinnedRecordPersistenceRoute,
        tabID: ContentTabID,
        window: FileManagerWindowFeature.State,
    ) -> Bool {
        switch route {
        case .single:
            true
        case let .selectedPin(operationID):
            window.pendingSelectedContentTabPinMutation?.operationID == operationID
                && window.pendingSelectedContentTabPinMutation?.currentTabID == tabID
        case let .selectedClose(operationID):
            window.pendingSelectedContentTabClose?.operationID == operationID
                && window.pendingSelectedContentTabClose?.currentTabID == tabID
        }
    }

    private func pinnedRecordTerminal(
        outcome: WindowManagerPinnedRecordMutationOutcome,
        request: ContentTabPinnedRecordPersistenceRequest,
        context: ContentTabPinnedRecordTerminalContext,
    ) -> ContentTabAction {
        switch outcome {
        case .applied:
            .pinnedRecordSaveSucceeded(tabID: request.tabID, context: context)
        case .failed:
            .pinnedRecordSaveFailed(
                tabID: request.tabID,
                context: context,
                rollback: request.rollback,
            )
        case .cancelled:
            .pinnedRecordSaveNotApplied(
                tabID: request.tabID,
                context: context,
                reason: .cancelled,
                rollback: request.rollback,
            )
        case .superseded:
            .pinnedRecordSaveNotApplied(
                tabID: request.tabID,
                context: context,
                reason: .superseded,
                rollback: request.rollback,
            )
        }
    }

    private func routePinnedRecordTerminal(
        _ terminal: ContentTabAction,
        request: FileManagerPinnedRecordPersistenceRequest,
    ) -> FileManagerWindowAction {
        switch request.route {
        case .single:
            .contentTabs(terminal)
        case let .selectedPin(operationID):
            .performSelectedContentTabPinMutation(
                operationID: operationID,
                tabID: request.request.tabID,
                action: terminal,
            )
        case let .selectedClose(operationID):
            .performSelectedContentTabCloseMutation(
                operationID: operationID,
                tabID: request.request.tabID,
                action: terminal,
            )
        }
    }

    private func syncPinnedContentTabsAcrossWindows(state: inout State) -> Effect<Action> {
        do {
            let store = try contentTabPinnedRecordClient.loadStore(userDefaultsClient)
            let restoreResult = ContentTabState.restoringPinnedRecords(
                from: store,
                isRestorableAnchor: { _ in true },
            )
            let survivingWindowIDs = state.windows.ids.filter { id in
                guard let window = state.windows[id: id]?.window else { return false }
                return !window.isClosing && !state.closingWindowIDs.contains(id)
            }
            return .merge(
                survivingWindowIDs.map { id in
                    .send(.windows(.element(
                        id: id,
                        action: .window(.applyAuthoritativePinnedContentTabs(restoreResult.state)),
                    )))
                },
            )
        } catch {
            return .none
        }
    }

    func defaultWindowBootstrapEffectIfNeeded(
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

    func makeWindowSession(path: String?, selectEntryID: String? = nil) -> WindowSessionState {
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
