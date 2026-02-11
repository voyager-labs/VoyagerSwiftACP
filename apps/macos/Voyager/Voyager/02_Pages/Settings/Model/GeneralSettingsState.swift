import ComposableArchitecture

@ObservableState
struct GeneralSettingsState: Equatable {
    var startingDirectory: String = ""
    var selectedDirectoryOption: DirectoryOption = .home
    var isSelectingDirectory: Bool = false
    var startingDirectoryError: String?
    var launchAtStartup: Bool = false
    var launchAtStartupError: String?
    var automaticUpdate: Bool = false
    var automaticUpdateError: String?
    var alertBeforeQuit: Bool = false
}
