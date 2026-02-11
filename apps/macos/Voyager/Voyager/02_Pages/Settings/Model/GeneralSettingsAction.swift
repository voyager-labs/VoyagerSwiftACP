import ComposableArchitecture

@CasePathable
enum GeneralSettingsAction: CasePathable, Sendable {
    case loadSettings
    case setStartingDirectory(String)
    case selectDirectoryOption(DirectoryOption)
    case openOtherDirectoryPanel
    case startingDirectorySelected(String?)
    case toggleLaunchAtStartup(Bool)
    case toggleAutomaticUpdate(Bool)
    case toggleAlertBeforeQuit(Bool)
    case checkForUpdates
}
