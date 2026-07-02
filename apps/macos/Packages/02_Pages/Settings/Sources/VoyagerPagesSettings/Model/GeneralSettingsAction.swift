import ComposableArchitecture
import VoyagerEntitiesEntry

public enum DefaultFileViewerDiagnosisSource: Equatable, Sendable {
    case sectionAppeared
    case manual
    case afterSetSucceeded
    case afterRestoreSucceeded
    case afterSetFailed
    case afterRestoreFailed

    var shouldClearErrorOnHealthyStatus: Bool {
        switch self {
        case .sectionAppeared, .manual, .afterSetSucceeded, .afterRestoreSucceeded:
            true
        case .afterSetFailed, .afterRestoreFailed:
            false
        }
    }
}

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
    case defaultFileViewerDiagnoseRequested(DefaultFileViewerDiagnosisSource)
    case defaultFileViewerDiagnosisCompleted(DefaultFileViewerStatus, source: DefaultFileViewerDiagnosisSource)
    case setAsDefaultFileViewerTapped
    case setAsDefaultFileViewerSucceeded
    case setAsDefaultFileViewerFailed(FileOpError)
    case restoreDefaultFileViewerTapped
    case restoreDefaultFileViewerSucceeded
    case restoreDefaultFileViewerFailed(FileOpError)
}
