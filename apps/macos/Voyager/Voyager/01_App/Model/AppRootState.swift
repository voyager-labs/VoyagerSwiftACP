import ComposableArchitecture
import VoyagerPagesFileManager
import VoyagerPagesSettings

@ObservableState
struct AppRootState: Equatable {
    var lifecycle: AppLifecycleFeature.State = .init()
    var appPreferences: AppPreferencesFeature.State = .init()
    var windowManager: WindowManagerFeature.State = .init()
    var updater: UpdaterFeature.State = .init()
    var settings: SettingsFeature.State = .init()
    var menuCommands: MenuCommandsFeature.State = .init()
    var isHelperExternalFileBridgeStarted = false
    var lastHelperReady = false
    var windowPresenceBeforeWindowManagerAction: Bool?
}
