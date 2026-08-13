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

    func trackedSingletonCompletionEffect(_ requestID: UUID) -> Effect<Action> {
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
        return openWindowSession(
            windowSession,
            startsDefaultBootstrap: path == nil,
            state: &state,
            open: open,
        )
    }

    private func openCollectionWindowSession(url: URL, state: inout State) -> Effect<Action> {
        if onboardingWindowClient.showIfNeeded() {
            return .none
        }
        let windowSession = makeWindowSession(path: nil)
        return openWindowSession(
            windowSession,
            startsDefaultBootstrap: true,
            state: &state,
            open: { [fileManagerWindowClient] id in
                await fileManagerWindowClient.open(id)
            },
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
        open: @escaping @Sendable (UUID) async -> Void,
        beforePreferences: Effect<Action> = .none,
    ) -> Effect<Action> {
        state.windows.append(windowSession)
        state.focusedWindowID = windowSession.id
        state.moveWindowToMRUFront(windowSession.id)

        let bootstrapEffect: Effect<Action> = if startsDefaultBootstrap {
            defaultWindowBootstrapEffectIfNeeded(for: windowSession.id, state: &state)
        } else {
            .none
        }

        return .concatenate(
            windowIDChangedEffect(for: windowSession.id),
            beforePreferences,
            appPreferencesEffect(for: windowSession.id, preferences: state.appPreferences),
            .run { [id = windowSession.id] _ in
                await open(id)
            },
            bootstrapEffect,
        )
    }

    private func windowIDChangedEffect(for id: UUID) -> Effect<Action> {
        .send(.windows(.element(
            id: id,
            action: .window(.content(.entryOperations(.lifecycle(.windowIDChanged(id))))),
        )))
    }
}
