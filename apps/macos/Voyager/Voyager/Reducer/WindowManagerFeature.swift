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
    @Dependency(\.fileManagerLocationsClient)
    private var fileManagerLocationsClient
    @Dependency(\.fileManagerFavoritesClient)
    private var fileManagerFavoritesClient
    @Dependency(\.entryLoadingClient)
    private var entryLoadingClient
    @Dependency(\.userDefaultsClient)
    private var userDefaultsClient
    @Dependency(\.metricsClient)
    private var metricsClient
    @Dependency(\.workspaceClient)
    private var workspaceClient

    @Dependency(\.date)
    private var date

    @Dependency(\.uuid)
    private var uuid

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .lifecycle(.openInitialWindowIfNeeded):
                guard state.windows.ids.allSatisfy(state.closingWindowIDs.contains) else { return .none }
                return .send(.file(.newWindow(path: nil)))

            case let .lifecycle(.reopenWindowIfNeeded(hasVisibleWindows: flag)):
                guard !flag else { return .none }

                guard let reopenWindowID = state.focusedWindowID.flatMap({ id in
                    state.closingWindowIDs.contains(id) ? nil : id
                })
                    ?? state.lastUsedWindowIDs.first(where: {
                        state.windows[id: $0] != nil && !state.closingWindowIDs.contains($0)
                    })
                    ?? state.windows.ids.first(where: { !state.closingWindowIDs.contains($0) })
                else {
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

            case let .defaultWindowBootstrapRequested(id):
                return handleDefaultWindowBootstrapRequested(id, state: &state)

            case let .windowReadyToOpen(id):
                return readyToOpenWindow(id, state: &state)

            case let .pendingWindowCloseFinalized(id):
                return finalizePendingWindowClose(id, state: &state)

            case let .windowInvalidationFinished(id, result):
                guard state.closingWindowIDs.contains(id) else { return .none }
                guard result.succeeded else { return .none }
                return finalizeWindowRemoval(id, state: &state)

            case let .event(.windowClosed(id)):
                if state.topNavigationPersistenceQueue.contains(where: { $0.sourceWindowID == id }) {
                    return deferWindowRemovalUntilTopNavigationPersistenceCompletes(id, state: &state)
                }
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
                action: .window(.delegate(.persistTopNavigationMove(
                    token: token,
                    source: source,
                    destination: destination,
                    discoveredLocationIDs: discoveredLocationIDs,
                ))),
            )):
                return .send(.topNavigationPersistenceRequested(.init(
                    sourceWindowID: sourceWindowID,
                    token: token,
                    operation: .move(
                        source: source,
                        destination: destination,
                        discoveredLocationIDs: discoveredLocationIDs,
                    ),
                )))

            case let .windows(.element(
                id: sourceWindowID,
                action: .window(.delegate(.persistPinnedRecordMutation(
                    token: token,
                    source: source,
                    request: request,
                    discoveredLocationIDs: discoveredLocationIDs,
                ))),
            )):
                return .send(.topNavigationPersistenceRequested(.init(
                    sourceWindowID: sourceWindowID,
                    token: token,
                    operation: .pinnedRecord(
                        source: source,
                        request: request,
                        discoveredLocationIDs: discoveredLocationIDs,
                    ),
                )))

            case let .topNavigationPersistenceRequested(request):
                return enqueueTopNavigationPersistence(request, state: &state)

            case let .topNavigationMovePersistenceCompleted(sourceWindowID, token, terminal):
                return completeTopNavigationMovePersistence(
                    sourceWindowID: sourceWindowID,
                    token: token,
                    terminal: terminal,
                    state: state,
                )

            case let .topNavigationPersistenceCompleted(result):
                return completeTopNavigationPersistence(result, state: &state)

            case .pinnedContentTabsStoreChanged:
                return handlePinnedContentTabsStoreChanged(state: &state)

            case let .defaultWindowBootstrapCompleted(requestID, result):
                return handleDefaultWindowBootstrapCompleted(requestID, result: result, state: &state)

            case let .defaultWindowBootstrapFailed(requestID):
                return handleDefaultWindowBootstrapFailed(requestID, state: &state)

            case let .windows(.element(id: _, action: .window(.inspector(.setInspectorWidth(width))))):
                state.appPreferences.inspectorWidth = max(FileManagerInspectorLayoutMetrics.minWidth, width)
                return .none

            case let .windows(.element(id: id, action: .window(.delegate(.requestAttachmentPicker)))):
                return requestAttachmentPicker(for: id)

            case .windows(.element(id: _, action: .window(.delegate(.openAISettings)))):
                return .send(.delegate(.openAISettings))

            case let .windows(.element(id: sourceWindowID, action: action)):
                return handleLegacyPinnedRecordTerminal(
                    sourceWindowID: sourceWindowID,
                    action: action,
                    state: state,
                )

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

    func syncPinnedContentTabsAcrossWindows(state: inout State) -> Effect<Action> {
        guard !state.windows.isEmpty else { return .none }
        do {
            let fixedLocations = FileManagerHomeDashboardProjection.makeFixedLocations(
                from: fileManagerLocationsClient.loadLocations(entryLoadingClient),
            )
            let discoveredLocationIDs = fixedLocations.map(\.id)
            guard let store = try contentTabPinnedRecordClient.loadStoreOutcome(
                userDefaultsClient,
                discoveredLocationIDs: discoveredLocationIDs,
            ).writableStore else { return .none }
            let restoreResult = ContentTabState.restoringPinnedRecords(
                from: store,
                isRestorableAnchor: { _ in true },
            )
            return .merge(
                state.windows.ids.map { id in
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
            locationsClient: fileManagerLocationsClient,
            loadingClient: entryLoadingClient,
            defaultsClient: userDefaultsClient,
            metricsClient: metricsClient,
            workspaceClient: workspaceClient,
            now: { now() },
        )

        return .run { send in
            guard let result = await DefaultWindowBootstrap.run(dependencies) else {
                await send(.defaultWindowBootstrapFailed(requestID: requestID))
                return
            }
            await send(.defaultWindowBootstrapCompleted(requestID: requestID, result: result))
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

extension WindowManagerFeature {
    private func enqueueTopNavigationPersistence(
        _ request: WindowManagerTopNavigationPersistenceRequest,
        state: inout State,
    ) -> Effect<Action> {
        state.topNavigationPersistenceQueue.append(request)
        return startNextTopNavigationPersistenceIfNeeded(state: &state)
    }

    private func startNextTopNavigationPersistenceIfNeeded(
        state: inout State,
    ) -> Effect<Action> {
        guard !state.isTopNavigationPersistenceInFlight,
              let request = state.topNavigationPersistenceQueue.first
        else { return .none }
        state.isTopNavigationPersistenceInFlight = true
        return runTopNavigationPersistence(request)
    }

    private func runTopNavigationPersistence(
        _ request: WindowManagerTopNavigationPersistenceRequest,
    ) -> Effect<Action> {
        let client = contentTabPinnedRecordClient
        let defaults = userDefaultsClient
        return .run { send in
            let result: WindowManagerTopNavigationPersistenceResult
            do {
                result = try await Self.persistTopNavigation(request, client: client, defaults: defaults)
            } catch is CancellationError {
                result = Self.failedTopNavigationPersistence(request, failure: .cancelled)
            } catch let error as ContentTabPinnedRecordStoreLoadError {
                let failure: FileManagerTopNavigationArrangementLoadFailure = switch error {
                case .corruptUnavailable:
                    .corrupt
                case let .futureSchemaUnavailable(schemaVersion):
                    .unsupportedSchema(schemaVersion)
                }
                result = Self.failedTopNavigationPersistence(request, failure: .storeUnavailable(failure))
            } catch {
                result = Self.failedTopNavigationPersistence(request, failure: .save)
            }
            await send(.topNavigationPersistenceCompleted(result))
        }
    }

    nonisolated private static func persistTopNavigation(
        _ request: WindowManagerTopNavigationPersistenceRequest,
        client: ContentTabPinnedRecordClient,
        defaults: UserDefaultsClient,
    ) async throws -> WindowManagerTopNavigationPersistenceResult {
        switch request.operation {
        case let .move(source, destination, discoveredLocationIDs):
            let commit = try await client.moveTopNavigationItemCommitted(
                defaults,
                discoveredLocationIDs,
                source,
                destination,
            )
            return .init(
                request: request,
                terminal: .committed(commit),
                authoritativePinnedContentTabs: nil,
            )

        case let .pinnedRecord(_, persistenceRequest, discoveredLocationIDs):
            let committed = try await client.applyPersistenceMutationCommitted(
                defaults,
                discoveredLocationIDs,
                persistenceRequest.mutation,
            )
            return .init(
                request: request,
                terminal: .committed(committed.topNavigation),
                authoritativePinnedContentTabs: ContentTabState.restoringPinnedRecords(
                    from: committed.store,
                ).state,
            )
        }
    }

    nonisolated private static func failedTopNavigationPersistence(
        _ request: WindowManagerTopNavigationPersistenceRequest,
        failure: FileManagerTopNavigationIntentFailure,
    ) -> WindowManagerTopNavigationPersistenceResult {
        .init(
            request: request,
            terminal: .failed(failure),
            authoritativePinnedContentTabs: nil,
        )
    }

    private func completeTopNavigationPersistence(
        _ result: WindowManagerTopNavigationPersistenceResult,
        state: inout State,
    ) -> Effect<Action> {
        guard state.isTopNavigationPersistenceInFlight,
              state.topNavigationPersistenceQueue.first == result.request
        else { return .none }
        state.topNavigationPersistenceQueue.removeFirst()
        state.isTopNavigationPersistenceInFlight = false

        let bootstrapLifecycle: (cancel: Effect<Action>, restart: Effect<Action>) = if case .committed = result
            .terminal,
            case .pinnedRecord = result.request.operation
        {
            invalidateAndRestartDefaultWindowBootstrapForPinnedChange(state: &state)
        } else {
            (.none, .none)
        }

        var effects: [Effect<Action>] = []
        effects.append(bootstrapLifecycle.cancel)
        if case let .committed(commit) = result.terminal {
            effects.append(fanOutCommittedTopNavigationSnapshot(
                commit,
                authoritativePinnedContentTabs: result.authoritativePinnedContentTabs,
                state: state,
            ))
        }
        if let sourceTerminal = topNavigationSourceTerminalEffect(result, state: state) {
            effects.append(sourceTerminal)
        }
        effects.append(.merge(
            finalizeDeferredWindowClosuresWithoutPendingPersistence(state: &state),
            startNextTopNavigationPersistenceIfNeeded(state: &state),
            bootstrapLifecycle.restart,
        ))
        return .concatenate(effects)
    }

    private func fanOutCommittedTopNavigationSnapshot(
        _ commit: FileManagerTopNavigationCommit,
        authoritativePinnedContentTabs: ContentTabState?,
        state: State,
    ) -> Effect<Action> {
        .merge(
            state.windows.ids
                .filter { !state.closingWindowIDs.contains($0) }
                .map { windowID in
                    .send(.windows(.element(
                        id: windowID,
                        action: .window(.applyCommittedTopNavigationSnapshot(
                            order: commit.order,
                            revision: commit.revision,
                            authoritativePinnedContentTabs: authoritativePinnedContentTabs,
                        )),
                    )))
                },
        )
    }

    private func topNavigationSourceTerminalEffect(
        _ result: WindowManagerTopNavigationPersistenceResult,
        state: State,
    ) -> Effect<Action>? {
        let sourceWindowID = result.request.sourceWindowID
        guard let sourceWindow = state.windows[id: sourceWindowID]?.window,
              !state.closingWindowIDs.contains(sourceWindowID)
        else { return nil }

        switch result.request.operation {
        case .move:
            return .send(.windows(.element(
                id: sourceWindowID,
                action: .window(.internal(.topNavigationIntentCompleted(
                    token: result.request.token,
                    terminal: result.terminal,
                ))),
            )))

        case let .pinnedRecord(source, request, _):
            guard sourceWindow.contentTabs.tabs[id: request.tabID] != nil else { return nil }
            return .send(.windows(.element(
                id: sourceWindowID,
                action: .window(.internal(.pinnedRecordPersistenceCompleted(
                    token: result.request.token,
                    source: source,
                    request: request,
                    terminal: result.terminal,
                ))),
            )))
        }
    }

    private func persistTopNavigationMove(
        sourceWindowID: State.WindowID,
        token: FileManagerTopNavigationOperationToken,
        source: FileManagerTopNavigationItemID,
        destination: FileManagerTopNavigationMoveDestination,
        discoveredLocationIDs: [String],
    ) -> Effect<Action> {
        let client = contentTabPinnedRecordClient
        let defaults = userDefaultsClient
        return .run { send in
            let terminal: FileManagerTopNavigationIntentTerminal
            do {
                let commit = try await client.moveTopNavigationItemCommitted(
                    defaults,
                    discoveredLocationIDs,
                    source,
                    destination,
                )
                terminal = .committed(commit)
            } catch is CancellationError {
                terminal = .failed(.cancelled)
            } catch let error as ContentTabPinnedRecordStoreLoadError {
                let failure: FileManagerTopNavigationArrangementLoadFailure = switch error {
                case .corruptUnavailable:
                    .corrupt
                case let .futureSchemaUnavailable(schemaVersion):
                    .unsupportedSchema(schemaVersion)
                }
                terminal = .failed(.storeUnavailable(failure))
            } catch {
                terminal = .failed(.save)
            }
            await send(.topNavigationMovePersistenceCompleted(
                sourceWindowID: sourceWindowID,
                token: token,
                terminal: terminal,
            ))
        }
    }

    private func completeTopNavigationMovePersistence(
        sourceWindowID: State.WindowID,
        token: FileManagerTopNavigationOperationToken,
        terminal: FileManagerTopNavigationIntentTerminal,
        state: State,
    ) -> Effect<Action> {
        var effects: [Effect<Action>] = []
        if state.windows[id: sourceWindowID] != nil {
            effects.append(.send(.windows(.element(
                id: sourceWindowID,
                action: .window(.internal(.topNavigationIntentCompleted(
                    token: token,
                    terminal: terminal,
                ))),
            ))))
        }
        if case let .committed(commit) = terminal {
            effects.append(fanOutCommittedTopNavigation(
                commit,
                excluding: sourceWindowID,
                state: state,
            ))
        }
        return .merge(effects)
    }

    private func handleLegacyPinnedRecordTerminal(
        sourceWindowID: State.WindowID,
        action: WindowSessionAction,
        state: State,
    ) -> Effect<Action> {
        switch action {
        case let .window(.contentTabs(.pinnedRecordSaveSucceeded(tabID, context))),
             let .window(.performSelectedContentTabCloseMutation(
                 operationID: _,
                 tabID: tabID,
                 action: .pinnedRecordSaveSucceeded(_, context),
             )):
            return handleCommittedPinnedRecordTerminal(
                sourceWindowID: sourceWindowID,
                tabID: tabID,
                context: context,
                state: state,
            )

        case let .window(.contentTabs(.pinnedRecordSaveFailed(tabID, context, _))),
             let .window(.contentTabs(.pinnedRecordSaveNotApplied(tabID, context, _, _))),
             let .window(.performSelectedContentTabCloseMutation(
                 operationID: _,
                 tabID: tabID,
                 action: .pinnedRecordSaveFailed(_, context, _),
             )),
             let .window(.performSelectedContentTabCloseMutation(
                 operationID: _,
                 tabID: tabID,
                 action: .pinnedRecordSaveNotApplied(_, context, _, _),
             )):
            guard isCurrentPinnedRecordTerminal(
                sourceWindowID: sourceWindowID,
                tabID: tabID,
                context: context,
                state: state,
            ) else { return .none }
            return .send(.pinnedContentTabsStoreChanged)

        default:
            return .none
        }
    }

    private func handleCommittedPinnedRecordTerminal(
        sourceWindowID: State.WindowID,
        tabID: ContentTabID,
        context: ContentTabPinnedRecordTerminalContext,
        state: State,
    ) -> Effect<Action> {
        guard contentTabPinnedRecordClient.isCurrentMutationGeneration(context.generation) else {
            return .none
        }
        if state.windows[id: sourceWindowID] != nil {
            guard isCurrentPinnedRecordTerminal(
                sourceWindowID: sourceWindowID,
                tabID: tabID,
                context: context,
                state: state,
            ) else { return .none }
        }

        return .merge(
            .send(.pinnedContentTabsStoreChanged),
            loadCommittedTopNavigationFanOut(excluding: sourceWindowID, state: state),
        )
    }

    private func loadCommittedTopNavigationFanOut(
        excluding sourceWindowID: State.WindowID,
        state: State,
    ) -> Effect<Action> {
        do {
            let fixedLocations = FileManagerHomeDashboardProjection.makeFixedLocations(
                from: fileManagerLocationsClient.loadLocations(entryLoadingClient),
            )
            let discoveredLocationIDs = fixedLocations.map(\.id)
            let commit = try contentTabPinnedRecordClient.loadTopNavigationCommit(
                userDefaultsClient,
                discoveredLocationIDs,
            )
            return fanOutCommittedTopNavigation(commit, excluding: sourceWindowID, state: state)
        } catch {
            return .none
        }
    }

    private func fanOutCommittedTopNavigation(
        _ commit: FileManagerTopNavigationCommit,
        excluding sourceWindowID: State.WindowID,
        state: State,
    ) -> Effect<Action> {
        .merge(
            state.windows.ids
                .filter { $0 != sourceWindowID && !state.closingWindowIDs.contains($0) }
                .map { windowID in
                    .send(.windows(.element(
                        id: windowID,
                        action: .window(.applyExternalCommittedTopNavigationOrder(
                            commit.order,
                            revision: commit.revision,
                        )),
                    )))
                },
        )
    }

    func isCurrentPinnedRecordTerminal(
        sourceWindowID: State.WindowID,
        tabID: ContentTabID,
        context: ContentTabPinnedRecordTerminalContext,
        state: State,
    ) -> Bool {
        state.windows[id: sourceWindowID]?.window.contentTabs.isCurrentPinnedRecordPersistenceIntent(
            tabID: tabID,
            intentID: context.intentID,
        ) == true
    }
}
