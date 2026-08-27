import AppKit
import ComposableArchitecture
import Foundation
import VoyagerEntitiesAppPreferences
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
    @Dependency(\.onboardingProductMetricsClient)
    var metricsClient

    private enum CancelID {
        case appDidBecomeActiveObserver
        case helperFolderAccessRequest
        case initialStateLoad
        case permissionRefresh
    }

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .onAppear:
                return .merge(
                    loadInitialState()
                        .cancellable(id: CancelID.initialStateLoad, cancelInFlight: true),
                    observeAppDidBecomeActive(),
                )

            case .onDisappear:
                if let operationID = state.pendingHelperFolderOperationID {
                    metricsClient.record(.helperFolderAccess(
                        operationID: operationID,
                        result: .unavailable,
                    ))
                }
                if let operationID = state.pendingFullDiskAccessOperationID {
                    metricsClient.record(.fullDiskAccess(
                        operationID: operationID,
                        result: .unavailable,
                    ))
                }
                state.pendingHelperFolderOperationID = nil
                state.pendingFullDiskAccessOperationID = nil
                state.pendingFullDiskAccessGeneration = nil
                state.isRequestingHelperFolderAccess = false
                return .merge(
                    .cancel(id: CancelID.helperFolderAccessRequest),
                    .cancel(id: CancelID.appDidBecomeActiveObserver),
                    .cancel(id: CancelID.initialStateLoad),
                    .cancel(id: CancelID.permissionRefresh),
                )

            case .appDidBecomeActive:
                state.latestAppActiveRefreshGeneration += 1
                let generation = state.latestAppActiveRefreshGeneration
                if state.pendingFullDiskAccessOperationID != nil {
                    state.pendingFullDiskAccessGeneration = generation
                }
                return .merge(
                    refreshFullDiskAccess(generation: generation),
                    refreshHelperFolderAccess(generation: generation),
                )
                .cancellable(id: CancelID.permissionRefresh, cancelInFlight: true)

            case let .fullDiskAccessRefreshResponse(generation, status):
                guard generation == state.latestAppActiveRefreshGeneration else { return .none }
                let resolvedStatus = resolveFullDiskAccessStatus(
                    status,
                    hasAttempted: state.hasAttemptedFullDiskAccessEnable,
                )
                state.fullDiskAccessStatus = resolvedStatus
                refreshCompletionState(state: &state)
                if let operationID = state.pendingFullDiskAccessOperationID,
                   state.pendingFullDiskAccessGeneration == generation
                {
                    state.pendingFullDiskAccessOperationID = nil
                    state.pendingFullDiskAccessGeneration = nil
                    metricsClient.record(.fullDiskAccess(
                        operationID: operationID,
                        result: status == .granted ? .success : .unavailable,
                    ))
                }
                return .none

            case let .helperFolderAccessRefreshLoaded(generation, result):
                guard generation == state.latestAppActiveRefreshGeneration else { return .none }
                state.helperFolderAccess = result
                if result.status == .granted {
                    state.helperFolderAccessError = nil
                }
                let data = try? JSONEncoder().encode(result)
                userDefaultsClient.setObject(data, SettingsKeys.helperFolderAccessSnapshot)
                refreshCompletionState(state: &state)
                return .none

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
                state.pendingHelperFolderOperationID = UUID()
                state.helperFolderAccessError = nil
                state.isRequestingHelperFolderAccess = true
                return .run { [helperFolderAccessClient] send in
                    let result = await helperFolderAccessClient.requestAccess()
                    await send(.helperFolderAccessResponse(result))
                }
                .cancellable(id: CancelID.helperFolderAccessRequest, cancelInFlight: true)

            case let .helperFolderAccessResponse(result):
                guard let operationID = state.pendingHelperFolderOperationID else { return .none }
                state.pendingHelperFolderOperationID = nil
                state.isRequestingHelperFolderAccess = false
                state.helperFolderAccess = result
                state.helperFolderAccessError = result.status == .granted
                    ? nil
                    : "VoyagerHelper still needs Desktop, Documents, and Downloads access."
                let data = try? JSONEncoder().encode(result)
                userDefaultsClient.setObject(data, SettingsKeys.helperFolderAccessSnapshot)
                refreshCompletionState(state: &state)
                metricsClient.record(.helperFolderAccess(
                    operationID: operationID,
                    result: result.status == .granted ? .success : .failure,
                ))
                return .none

            case .openSystemSettingsTapped:
                state.systemSettingsError = nil
                state.pendingFullDiskAccessOperationID = UUID()
                return .run { [systemSettingsClient] send in
                    let opened = systemSettingsClient.openFullDiskAccess()
                    await send(.systemSettingsOpenResult(opened))
                }

            case let .systemSettingsOpenResult(opened):
                if !opened {
                    state.systemSettingsError = "We couldn't open System Settings. Please open it manually."
                    if let operationID = state.pendingFullDiskAccessOperationID {
                        state.pendingFullDiskAccessOperationID = nil
                        state.pendingFullDiskAccessGeneration = nil
                        metricsClient.record(.fullDiskAccess(
                            operationID: operationID,
                            result: .unavailable,
                        ))
                    }
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
            guard !Task.isCancelled else { return }
            await send(.helperFolderAccessStatusLoaded(helperFolderAccess))
            let isEnabled = launchAtLoginClient.isEnabled()
            guard !Task.isCancelled else { return }
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
        .cancellable(id: CancelID.appDidBecomeActiveObserver, cancelInFlight: true)
    }

    private func refreshFullDiskAccess(generation: Int) -> Effect<Action> {
        .run { [fullDiskAccessClient] send in
            let status = fullDiskAccessClient.status()
            guard !Task.isCancelled else { return }
            await send(.fullDiskAccessRefreshResponse(generation, status))
        }
    }

    private func refreshHelperFolderAccess(generation: Int) -> Effect<Action> {
        .run { [helperFolderAccessClient] send in
            let result = await helperFolderAccessClient.checkAccess()
            guard !Task.isCancelled else { return }
            await send(.helperFolderAccessRefreshLoaded(generation, result))
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
