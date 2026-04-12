import AppKit
import ComposableArchitecture
import Foundation
import VoyagerEntitiesSettings
import VoyagerShared

@Reducer
struct PermissionsFeature {
    typealias State = PermissionsState
    typealias Action = PermissionsAction

    @Dependency(\.fullDiskAccessClient)
    var fullDiskAccessClient
    @Dependency(\.helperFolderAccessClient)
    var helperFolderAccessClient
    @Dependency(\.userDefaultsClient)
    var userDefaultsClient
    @Dependency(\.launchAtLoginClient)
    var launchAtLoginClient
    @Dependency(\.notificationCenterClient)
    var notificationCenterClient
    @Dependency(\.systemSettingsClient)
    var systemSettingsClient

    private let appDidBecomeActiveObserverCancelID = "PermissionsFeature.appDidBecomeActiveObserver"

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .onAppear:
                return .merge(
                    loadInitialState(),
                    observeAppDidBecomeActive(),
                )

            case .onDisappear:
                return .cancel(id: appDidBecomeActiveObserverCancelID)

            case .appDidBecomeActive:
                return .merge(
                    refreshFullDiskAccess(),
                    refreshHelperFolderAccess(),
                )

            case let .fullDiskAccessStatusResponse(status):
                let resolvedStatus = resolveFullDiskAccessStatus(
                    status,
                    hasAttempted: state.hasAttemptedFullDiskAccessEnable,
                )
                state.fullDiskAccessStatus = resolvedStatus
                refreshCompletionState(state: &state)
                return .none

            case let .helperFolderAccessStatusLoaded(result):
                state.helperFolderAccess = result
                if result.status == .granted {
                    state.helperFolderAccessError = nil
                }
                let data = try? JSONEncoder().encode(result)
                userDefaultsClient.setObject(data, SettingsKeys.helperFolderAccessSnapshot)
                refreshCompletionState(state: &state)
                return .none

            case .requestHelperFolderAccessTapped:
                state.helperFolderAccessError = nil
                state.isRequestingHelperFolderAccess = true
                return .run { [helperFolderAccessClient] send in
                    let result = await helperFolderAccessClient.requestAccess()
                    await send(.helperFolderAccessResponse(result))
                }

            case let .helperFolderAccessResponse(result):
                state.isRequestingHelperFolderAccess = false
                state.helperFolderAccess = result
                state.helperFolderAccessError = result.status == .granted
                    ? nil
                    : "VoyagerHelper still needs Desktop, Documents, and Downloads access."
                let data = try? JSONEncoder().encode(result)
                userDefaultsClient.setObject(data, SettingsKeys.helperFolderAccessSnapshot)
                refreshCompletionState(state: &state)
                return .none

            case .openSystemSettingsTapped:
                state.systemSettingsError = nil
                return .run { [systemSettingsClient] send in
                    let opened = systemSettingsClient.openFullDiskAccess()
                    await send(.systemSettingsOpenResult(opened))
                }

            case let .systemSettingsOpenResult(opened):
                if !opened {
                    state.systemSettingsError = "We couldn't open System Settings. Please open it manually."
                } else {
                    state.hasAttemptedFullDiskAccessEnable = true
                }
                return .none

            case let .launchAtLoginToggled(enabled):
                let previousValue = state.launchAtLoginEnabled
                state.launchAtLoginEnabled = enabled
                state.launchAtLoginError = nil
                return .run { [launchAtLoginClient] send in
                    do {
                        try launchAtLoginClient.setEnabled(enabled)
                        await send(.launchAtLoginUpdateSucceeded)
                    } catch {
                        await send(.launchAtLoginUpdateFailed(previousValue))
                    }
                }

            case .launchAtLoginUpdateSucceeded:
                state.launchAtLoginError = nil
                return .none

            case let .launchAtLoginUpdateFailed(previousValue):
                state.launchAtLoginEnabled = previousValue
                state.launchAtLoginError =
                    "We couldn't update your Login Items. Manage this in System Settings."
                return .none

            case let .launchAtLoginStateLoaded(isEnabled):
                state.launchAtLoginEnabled = isEnabled
                return .none
            }
        }
    }

    private func loadInitialState() -> Effect<Action> {
        .run { [fullDiskAccessClient, helperFolderAccessClient, launchAtLoginClient] send in
            let status = fullDiskAccessClient.status()
            await send(.fullDiskAccessStatusResponse(status))
            let helperFolderAccess = await helperFolderAccessClient.checkAccess()
            await send(.helperFolderAccessStatusLoaded(helperFolderAccess))
            let isEnabled = launchAtLoginClient.isEnabled()
            await send(.launchAtLoginStateLoaded(isEnabled))
        }
    }

    private func observeAppDidBecomeActive() -> Effect<Action> {
        .run { [notificationCenterClient] send in
            for await _ in notificationCenterClient.notifications(
                NSApplication.didBecomeActiveNotification,
                nil,
            ) {
                await send(.appDidBecomeActive)
            }
        }
        .cancellable(id: appDidBecomeActiveObserverCancelID, cancelInFlight: true)
    }

    private func refreshFullDiskAccess() -> Effect<Action> {
        .run { [fullDiskAccessClient] send in
            let status = fullDiskAccessClient.status()
            await send(.fullDiskAccessStatusResponse(status))
        }
    }

    private func refreshHelperFolderAccess() -> Effect<Action> {
        .run { [helperFolderAccessClient] send in
            let result = await helperFolderAccessClient.checkAccess()
            await send(.helperFolderAccessStatusLoaded(result))
        }
    }

    private func resolveFullDiskAccessStatus(
        _ status: FullDiskAccessStatus,
        hasAttempted: Bool,
    ) -> FullDiskAccessStatus {
        if status == .needsAction, hasAttempted {
            return .denied
        }
        return status
    }

    private func refreshCompletionState(state: inout State) {
        state.isComplete = state.fullDiskAccessStatus == .granted && state.helperFolderAccessStatus == .granted
    }
}
