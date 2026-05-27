import ComposableArchitecture
import VoyagerEntitiesAppPreferences

@CasePathable
enum PermissionsAction: CasePathable, Sendable {
    case onAppear
    case onDisappear
    case appDidBecomeActive
    case fullDiskAccessStatusResponse(FullDiskAccessStatus)
    case helperFolderAccessStatusLoaded(FolderAccessResult)
    case fullDiskAccessRefreshResponse(Int, FullDiskAccessStatus)
    case helperFolderAccessRefreshLoaded(Int, FolderAccessResult)
    case requestHelperFolderAccessTapped
    case helperFolderAccessResponse(FolderAccessResult)
    case openSystemSettingsTapped
    case systemSettingsOpenResult(Bool)
    case launchAtLoginToggled(Bool)
    case launchAtLoginUpdateSucceeded
    case launchAtLoginUpdateFailed(Bool)
    case launchAtLoginStateLoaded(Bool)
}
