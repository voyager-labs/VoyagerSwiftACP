import ComposableArchitecture
import Foundation

enum FullDiskAccessStatus: String, Equatable, Sendable {
    case granted = "Granted"
    case needsAction = "Needs Action"
    case denied = "Denied"
    case unknown = "Unknown"

    var message: String {
        switch self {
        case .granted:
            "You're all set for Full Disk Access."
        case .needsAction:
            "Turn on Full Disk Access to keep going."
        case .denied:
            "Full Disk Access is off. You can enable it anytime."
        case .unknown:
            "Check Full Disk Access in System Settings."
        }
    }
}

struct FolderAccessItem: Equatable, Identifiable, Sendable {
    let id: String
    let title: String
    let status: FolderAccessPermission
}

@Reducer
struct PermissionsFeature {
    @ObservableState
    struct State: Equatable, Sendable {
        var isComplete: Bool = false
        var fullDiskAccessStatus: FullDiskAccessStatus = .unknown
        var systemSettingsError: String?
        var filesAndFoldersStatus: FilesAndFoldersStatus = .idle
        var folderAccessResult: FolderAccessResult?
        var helperFilesAndFoldersStatus: FilesAndFoldersStatus = .idle
        var helperFolderAccessResult: FolderAccessResult?
        var isRequestingFilesAndFolders: Bool = false
        var launchAtLoginEnabled: Bool = false
        var launchAtLoginError: String?
        var hasAttemptedFullDiskAccessEnable: Bool = false

        var fullDiskAccessStatusMessage: String {
            fullDiskAccessStatus.message
        }

        var showsFullDiskAccessAction: Bool {
            fullDiskAccessStatus != .granted
        }

        var nextDisabledMessage: String? {
            if fullDiskAccessStatus != .granted {
                return "Turn on Full Disk Access to continue."
            }
            return allFilesAndFoldersGranted
                ? nil
                : "Allow Desktop, Documents, and Downloads for Voyager and Voyager Helper to continue."
        }

        var filesAndFoldersMessage: String {
            if isRequestingFilesAndFolders {
                return "Requesting access…"
            }
            if allFilesAndFoldersGranted {
                return "Access granted for Voyager and Voyager Helper (Desktop, Documents, Downloads)."
            }

            switch (filesAndFoldersStatus, helperFilesAndFoldersStatus) {
            case (.idle, .idle):
                return "Tap Grant Access when you're ready."
            case (.notGranted, .notGranted):
                return
                    "No folders were granted for Voyager and Voyager Helper. "
                        + "You can enable them later in System Settings."
            default:
                return
                    "Some folders are still off for Voyager or Voyager Helper. "
                        + "You can enable them later in System Settings."
            }
        }

        var folderAccessItems: [FolderAccessItem] {
            guard let result = folderAccessResult else { return [] }
            return [
                FolderAccessItem(id: "desktop", title: "Desktop", status: result.desktop),
                FolderAccessItem(id: "documents", title: "Documents", status: result.documents),
                FolderAccessItem(id: "downloads", title: "Downloads", status: result.downloads),
            ]
        }

        var helperFolderAccessItems: [FolderAccessItem] {
            guard let result = helperFolderAccessResult else { return [] }
            return [
                FolderAccessItem(id: "helper-desktop", title: "Desktop", status: result.desktop),
                FolderAccessItem(id: "helper-documents", title: "Documents", status: result.documents),
                FolderAccessItem(id: "helper-downloads", title: "Downloads", status: result.downloads),
            ]
        }

        var allFilesAndFoldersGranted: Bool {
            filesAndFoldersStatus == .granted && helperFilesAndFoldersStatus == .granted
        }
    }

    enum Action: Sendable {
        case onAppear
        case appDidBecomeActive
        case fullDiskAccessStatusResponse(FullDiskAccessStatus)
        case openSystemSettingsTapped
        case systemSettingsOpenResult(Bool)
        case requestFilesAndFoldersTapped
        case filesAndFoldersResponse(FolderAccessResult)
        case helperFilesAndFoldersResponse(FolderAccessResult)
        case launchAtLoginToggled(Bool)
        case launchAtLoginUpdateSucceeded
        case launchAtLoginUpdateFailed(Bool)
        case launchAtLoginStateLoaded(Bool)
    }

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
                return .none

            case let .helperFilesAndFoldersResponse(result):
                state.isRequestingFilesAndFolders = false
                state.helperFolderAccessResult = result
                state.helperFilesAndFoldersStatus = result.status
                refreshCompletionState(state: &state)
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

    private func refreshCompletionState(state: inout State) {
        state.isComplete = state.fullDiskAccessStatus == .granted && state.allFilesAndFoldersGranted
    }
}
