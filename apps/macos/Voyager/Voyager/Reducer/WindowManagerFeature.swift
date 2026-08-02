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

    private func pendingRepinPeerRuntimeNavigationEffect(
        sourceWindowID: UUID,
        tabID: ContentTabID,
        state: State,
    ) -> Effect<Action> {
        guard let sourceWindow = state.windows[id: sourceWindowID],
              sourceWindow.window.contentTabs.pendingPinnedRecordIDs.contains(tabID),
              sourceWindow.window.contentTabs.tabs[id: tabID]?.isPinned == true
        else { return .none }

        let eligiblePeers = state.windows.filter { windowSession in
            windowSession.id != sourceWindowID
                && windowSession.window.contentTabs.tabs[id: tabID]?.isPinned == true
                && !windowSession.window.contentTabs.pendingPinnedRecordIDs.contains(tabID)
        }
        let peerRoutes = eligiblePeers.map { windowSession -> ContentPageNavigationRoute? in
            if windowSession.window.contentTabs.activeTabID == tabID {
                return windowSession.window.content.navigation.navigationState
            }
            return windowSession.window.tabContentStates[tabID]?.navigation.navigationState
        }
        guard let firstPeerRoute = peerRoutes.first,
              let peerRoute = firstPeerRoute,
              peerRoutes.dropFirst().allSatisfy({ $0 == Optional(peerRoute) })
        else { return .none }

        return .send(.windows(.element(
            id: sourceWindowID,
            action: .window(.applyPinnedContentTabRuntimeNavigation(
                tabID: tabID,
                navigationState: peerRoute,
            )),
        )))
    }

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

            case .edit(.find):
                return routeFindCommand(state)

            case .edit(.toggleComposer):
                return sendCommandToFocusedWindow(state, .toggleComposer)

            case .edit(.openChat):
                return sendCommandToFocusedWindow(state, .reopenChat)

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

            case let .windows(.element(
                id: sourceWindowID,
                action: .window(.delegate(.pinnedContentTabRuntimeNavigationChanged(
                    tabID: tabID,
                    navigationState: navigationState,
                ))),
            )):
                return .merge(
                    state.windows
                        .filter { windowSession in
                            windowSession.id != sourceWindowID
                                && windowSession.window.contentTabs.tabs[id: tabID]?.isPinned == true
                        }
                        .map { windowSession in
                            .send(.windows(.element(
                                id: windowSession.id,
                                action: .window(.applyPinnedContentTabRuntimeNavigation(
                                    tabID: tabID,
                                    navigationState: navigationState,
                                )),
                            )))
                        },
                )

            case let .windows(.element(
                id: sourceWindowID,
                action: .window(.contentTabs(.pinnedRecordSaveSucceeded(tabID))),
            )):
                let reconciliationEffect = pendingRepinPeerRuntimeNavigationEffect(
                    sourceWindowID: sourceWindowID,
                    tabID: tabID,
                    state: state,
                )
                state.windows[id: sourceWindowID]?.window.contentTabs.pendingPinnedRecordIDs.remove(tabID)
                return .concatenate(
                    .send(.pinnedContentTabsStoreChanged),
                    reconciliationEffect,
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

    private func externalOpenActivationEffects(
        _ activations: [ExternalOpenPlacementApplication.ExistingWindowActivation],
    ) -> [Effect<Action>] {
        activations.flatMap { activation in
            [
                .send(.windows(.element(
                    id: activation.windowID,
                    action: .window(.activateExternalContentTabUndoScopes(activation.tabIDs)),
                ))),
                .send(.windows(.element(
                    id: activation.windowID,
                    action: .window(.contentTabs(.setCurrent(activation.activeTabID))),
                ))),
            ]
        }
    }

    private func routeFindCommand(_ state: State) -> Effect<Action> {
        guard let id = state.focusedWindowID, state.windows[id: id] != nil else {
            return .none
        }
        return .send(.windows(.element(id: id, action: .window(.request(.find)))))
    }

    func sendCommandToFocusedWindow(
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
