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
            "Full Disk Access is granted. You can continue."
        case .needsAction:
            "Full Disk Access is required to continue. Please enable it in System Settings."
        case .denied:
            "Full Disk Access was denied. You can change this in System Settings."
        case .unknown:
            "We couldn't confirm your Full Disk Access status yet."
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
            fullDiskAccessStatus == .granted ? nil : "Full Disk Access is required to continue."
        }

        var filesAndFoldersMessage: String? {
            filesAndFoldersStatus.message
        }

        var folderAccessItems: [FolderAccessItem] {
            guard let result = folderAccessResult else { return [] }
            return [
                FolderAccessItem(id: "desktop", title: "Desktop", status: result.desktop),
                FolderAccessItem(id: "documents", title: "Documents", status: result.documents),
                FolderAccessItem(id: "downloads", title: "Downloads", status: result.downloads),
            ]
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
        case launchAtLoginToggled(Bool)
        case launchAtLoginUpdateSucceeded
        case launchAtLoginUpdateFailed(Bool)
        case launchAtLoginStateLoaded(Bool)
    }

    @Dependency(\.folderAccessClient)
    var folderAccessClient
    @Dependency(\.fullDiskAccessClient)
    var fullDiskAccessClient
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
                state.isComplete = resolvedStatus == .granted
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
                return .run { [folderAccessClient] send in
                    let result = await folderAccessClient.requestAccess()
                    await send(.filesAndFoldersResponse(result))
                }

            case let .filesAndFoldersResponse(result):
                state.isRequestingFilesAndFolders = false
                state.folderAccessResult = result
                state.filesAndFoldersStatus = result.status
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
                    "We couldn't update your Login Items. You can manage this in System Settings."
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
}
