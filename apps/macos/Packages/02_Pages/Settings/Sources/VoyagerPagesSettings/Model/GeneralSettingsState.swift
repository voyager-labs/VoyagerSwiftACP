import ComposableArchitecture

public enum DefaultFileViewerPhase: Equatable, Sendable {
    case idle
    case diagnosing(DefaultFileViewerDiagnosisSource)
    case setting
    case restoring
}

@ObservableState
public struct GeneralSettingsState: Equatable {
    var startingDirectory: String = ""
    var selectedDirectoryOption: DirectoryOption = .home
    var standardDirectories: StandardDirectories = .defaultValue
    var isSelectingDirectory: Bool = false
    var startingDirectoryError: String?
    var launchAtStartup: Bool = false
    var launchAtStartupError: String?
    var automaticUpdate: Bool = false
    var automaticUpdateError: String?
    var alertBeforeQuit: Bool = false

    // SET-010 Default File Viewer
    var defaultFileViewerStatus: DefaultFileViewerStatus = .unknown
    var defaultFileViewerPhase: DefaultFileViewerPhase = .idle
    var defaultFileViewerErrorMessage: String?

    var isDiagnosingDefaultFileViewer: Bool {
        guard case .diagnosing = defaultFileViewerPhase else { return false }
        return true
    }

    var isSettingDefaultFileViewer: Bool {
        defaultFileViewerPhase == .setting
    }

    var isRestoringDefaultFileViewer: Bool {
        defaultFileViewerPhase == .restoring
    }

    public init() {}
}
