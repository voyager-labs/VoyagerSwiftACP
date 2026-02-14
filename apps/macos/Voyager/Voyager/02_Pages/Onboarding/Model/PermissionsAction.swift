import ComposableArchitecture

@CasePathable
enum PermissionsAction: CasePathable, Sendable {
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
