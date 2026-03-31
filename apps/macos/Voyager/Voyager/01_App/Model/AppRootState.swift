import ComposableArchitecture
import VoyagerPagesSettings

@ObservableState
struct AppRootState: Equatable {
    var lifecycle = AppLifecycleFeature.State()
    var appPreferences = AppPreferencesFeature.State()
    var windowManager = WindowManagerFeature.State()
    var updater = UpdaterFeature.State()
    var settings = SettingsFeature.State()
    var menuCommands = MenuCommandsFeature.State()
    var pendingReplayPaths: [String] = []
}
