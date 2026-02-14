import ComposableArchitecture
import Foundation
import Logging

@Reducer
struct PermissionsFeature {
    typealias State = PermissionsState
    typealias Action = PermissionsAction

    @Dependency(\.folderAccessClient)
    var folderAccessClient
    @Dependency(\.fullDiskAccessClient)
    var fullDiskAccessClient
    @Dependency(\.helperFolderAccessClient)
    var helperFolderAccessClient
    @Dependency(\.launchAtLoginClient)
    var launchAtLoginClient
    @Dependency(\.systemSettingsClient)
    var systemSettingsClient
    @Dependency(\.indexingClient)
    var indexingClient
    private let logger = Logger(label: "Voyager")

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .onAppear:
                return loadInitialState()

            case .appDidBecomeActive:
                return refreshFullDiskAccess()

            case let .fullDiskAccessStatusResponse(status):
                let resolvedStatus = resolveFullDiskAccessStatus(
                    status,
                    hasAttempted: state.hasAttemptedFullDiskAccessEnable,
                )
                state.fullDiskAccessStatus = resolvedStatus
                refreshCompletionState(state: &state)
                return startIndexingIfReady(state: &state)

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

            case .requestFilesAndFoldersTapped:
                state.isRequestingFilesAndFolders = true
                state.filesAndFoldersStatus = .idle
                state.folderAccessResult = nil
                state.helperFilesAndFoldersStatus = .idle
                state.helperFolderAccessResult = nil
                return .run { [folderAccessClient, helperFolderAccessClient] send in
                    let result = await folderAccessClient.requestAccess()
                    let helperResult = await helperFolderAccessClient.requestAccess()
                    await send(.filesAndFoldersResponse(result))
                    await send(.helperFilesAndFoldersResponse(helperResult))
                }

            case let .filesAndFoldersResponse(result):
                state.folderAccessResult = result
                state.filesAndFoldersStatus = result.status
                refreshCompletionState(state: &state)
                return startIndexingIfReady(state: &state)

            case let .helperFilesAndFoldersResponse(result):
                state.isRequestingFilesAndFolders = false
                state.helperFolderAccessResult = result
                state.helperFilesAndFoldersStatus = result.status
                refreshCompletionState(state: &state)
                return startIndexingIfReady(state: &state)

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
        .run { [fullDiskAccessClient, launchAtLoginClient] send in
            let status = fullDiskAccessClient.status()
            await send(.fullDiskAccessStatusResponse(status))
            let isEnabled = launchAtLoginClient.isEnabled()
            await send(.launchAtLoginStateLoaded(isEnabled))
        }
    }

    private func refreshFullDiskAccess() -> Effect<Action> {
        .run { [fullDiskAccessClient] send in
            let status = fullDiskAccessClient.status()
            await send(.fullDiskAccessStatusResponse(status))
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

    private func startIndexingIfReady(state: inout State) -> Effect<Action> {
        logger.info(
            "Onboarding indexing check: fullDiskAccess=\(state.fullDiskAccessStatus), filesAndFolders=\(state.filesAndFoldersStatus), helperFilesAndFolders=\(state.helperFilesAndFoldersStatus), inBackground=\(state.isIndexingInBackground)",
        )
        guard state.fullDiskAccessStatus == .granted,
              state.filesAndFoldersStatus == .granted,
              state.helperFilesAndFoldersStatus == .granted,
              !state.isIndexingInBackground
        else {
            return .none
        }

        state.isIndexingInBackground = true
        return .run { [indexingClient] _ in
            logger.info("Onboarding indexing triggered.")
            await indexingClient.start()
        }
    }

    private func refreshCompletionState(state: inout State) {
        state.isComplete = state.fullDiskAccessStatus == .granted && state.allFilesAndFoldersGranted
    }
}
