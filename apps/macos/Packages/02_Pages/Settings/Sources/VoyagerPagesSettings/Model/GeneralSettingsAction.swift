import ComposableArchitecture

@CasePathable
public enum GeneralSettingsAction: CasePathable, Equatable, Sendable {
    case loadSettings
    case setStartingDirectory(String)
    case selectDirectoryOption(DirectoryOption)
    case openOtherDirectoryPanel
    case startingDirectorySelected(String?)
    case toggleLaunchAtStartup(Bool)
    case toggleAutomaticUpdate(Bool)
    case toggleAlertBeforeQuit(Bool)
    case checkForUpdates

    // SET-010 Default File Viewer
    case defaultFileViewerSectionAppeared
    case defaultFileViewerDiagnoseRequested
    case defaultFileViewerDiagnosisCompleted(DefaultFileViewerStatus)
    case setAsDefaultFileViewerTapped
    case setAsDefaultFileViewerSucceeded
    case setAsDefaultFileViewerFailed(DefaultFileViewerError)
    case restoreDefaultFileViewerTapped
    case restoreDefaultFileViewerSucceeded
    case restoreDefaultFileViewerFailed(DefaultFileViewerError)
}
