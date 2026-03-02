import ComposableArchitecture
import VoyagerEntitiesSettings

@CasePathable
enum PermissionsAction: CasePathable, Sendable {
    case onAppear
    case appDidBecomeActive
    case fullDiskAccessStatusResponse(FullDiskAccessStatus)
    case openSystemSettingsTapped
    case systemSettingsOpenResult(Bool)
    case launchAtLoginToggled(Bool)
    case launchAtLoginUpdateSucceeded
    case launchAtLoginUpdateFailed(Bool)
    case launchAtLoginStateLoaded(Bool)
}
