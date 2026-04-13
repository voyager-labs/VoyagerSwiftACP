import ComposableArchitecture
import VoyagerEntitiesSettings

@CasePathable
enum PermissionsAction: CasePathable, Sendable {
    case onAppear
    case onDisappear
    case appDidBecomeActive
    case fullDiskAccessStatusResponse(FullDiskAccessStatus)
    case helperFolderAccessStatusLoaded(FolderAccessResult)
    case requestHelperFolderAccessTapped
    case helperFolderAccessResponse(FolderAccessResult)
    case openSystemSettingsTapped
    case systemSettingsOpenResult(Bool)
    case launchAtLoginToggled(Bool)
    case launchAtLoginUpdateSucceeded
    case launchAtLoginUpdateFailed(Bool)
    case launchAtLoginStateLoaded(Bool)
}
