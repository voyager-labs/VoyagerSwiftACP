import ComposableArchitecture

@ObservableState
public struct GeneralSettingsState: Equatable {
    var startingDirectory: String = ""
    var selectedDirectoryOption: DirectoryOption = .home
    var isSelectingDirectory: Bool = false
    var startingDirectoryError: String?
    var launchAtStartup: Bool = false
    var launchAtStartupError: String?
    var automaticUpdate: Bool = false
    var automaticUpdateError: String?
    var alertBeforeQuit: Bool = false

    // SET-010 Default File Viewer
    var defaultFileViewerStatus: DefaultFileViewerStatus = .unknown
    var isDiagnosingDefaultFileViewer: Bool = false
    var isSettingDefaultFileViewer: Bool = false
    var isRestoringDefaultFileViewer: Bool = false
    var defaultFileViewerErrorMessage: String?

    public init() {}
}
