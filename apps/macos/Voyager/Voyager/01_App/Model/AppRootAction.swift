import ComposableArchitecture
import Foundation
import VoyagerPagesSettings

@CasePathable
enum AppRootAction: CasePathable, Sendable {
    case lifecycle(AppLifecycleFeature.Action)
    case helperExternalFileChanged(HelperExternalFileChangeEvent)
    case flushPendingReplay
    case appPreferences(AppPreferencesFeature.Action)
    case windowManager(WindowManagerFeature.Action)
    case updater(UpdaterFeature.Action)
    case settings(SettingsFeature.Action)
    case menuCommands(MenuCommandsFeature.Action)
}
