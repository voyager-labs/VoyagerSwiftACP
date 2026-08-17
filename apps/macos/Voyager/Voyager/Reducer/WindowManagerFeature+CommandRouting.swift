import ComposableArchitecture
import Foundation
import VoyagerEntitiesAi
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

    func applyExternalOpenPlacement(
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
        state.refreshContentTabMoveTargets()
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

    func routeFindCommand(_ state: State) -> Effect<Action> {
        guard let id = state.focusedWindowID, state.windows[id: id] != nil else {
            return .none
        }
        return .send(.windows(.element(id: id, action: .window(.request(.find)))))
    }

    func sendCommandToFocusedWindow(
        _ state: State,
        _ command: FileManagerWindowAction.WindowCommand,
    ) -> Effect<Action> {
        guard let id = state.focusedWindowID,
              isWindowReady(id, state: state)
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

    func sendPinTabCommandToFocusedWindow(_ state: State) -> Effect<Action> {
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

    func sendCloseTabCommandToFocusedWindow(_ state: State) -> Effect<Action> {
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

    func sendDuplicateTabCommandToFocusedWindow(_ state: State) -> Effect<Action> {
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
            let commit = (try? contentTabPinnedRecordClient.loadTopNavigationCommit(
                userDefaultsClient,
                discoveredLocationIDs,
            )) ?? .init(
                order: store.topNavigationOrder,
                revision: state.windows.compactMap(\.window.lastConfirmedTopNavigationCommitRevision).max() ?? 0,
            )
            let survivingWindowIDs = state.windows.ids.filter { id in
                guard let window = state.windows[id: id]?.window else { return false }
                return !window.isClosing && !state.closingWindowIDs.contains(id)
            }
            return .merge(survivingWindowIDs.map { windowID in
                let snapshotEffect: Effect<Action> = .send(.windows(.element(
                    id: windowID,
                    action: .window(.applyCommittedTopNavigationSnapshot(
                        order: commit.order,
                        revision: commit.revision,
                        authoritativePinnedContentTabs: nil,
                    )),
                )))
                return .concatenate(
                    snapshotEffect,
                    .send(.windows(.element(
                        id: windowID,
                        action: .window(.applyAuthoritativePinnedContentTabs(restoreResult.state)),
                    ))),
                )
            })
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
    func runDefaultWindowBootstrapEffect(requestID: UUID) -> Effect<Action> {
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
                windowID: id,
            )
            return .init(id: id, window: windowState)
        }

        // Default window: Home shell immediately, no synchronous IO.
        // Pinned store restore/seed/validation runs asynchronously via
        // runDefaultWindowBootstrapEffect() attached in openWindowSession.
        let windowState = FileManagerWindowFeature.State.makeInitial(
            path: nil,
            selectEntryID: selectEntryID,
            windowID: id,
        )
        return .init(id: id, window: windowState)
    }
}

extension WindowManagerFeature {
    func handleLifecycleAction(_ action: Action, state: inout State) -> Effect<Action>? {
        switch action {
        case .lifecycle(.openInitialWindowIfNeeded):
            guard state.windows.ids.allSatisfy(state.closingWindowIDs.contains) else { return .none }
            return .send(.file(.newWindow(path: nil)))

        case let .lifecycle(.reopenWindowIfNeeded(hasVisibleWindows: flag)):
            guard !flag else { return .none }

            guard let reopenWindowID = state.focusedWindowID.flatMap({ id in
                isWindowReady(id, state: state) ? id : nil
            })
                ?? state.lastUsedWindowIDs.first(where: {
                    isWindowReady($0, state: state)
                })
                ?? state.windows.ids.first(where: { isWindowReady($0, state: state) })
            else {
                guard !state.windows.ids.contains(where: {
                    state.pendingWindowOpenIDs.contains($0) && !state.closingWindowIDs.contains($0)
                }) else { return .none }
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

        default:
            return nil
        }
    }
}
