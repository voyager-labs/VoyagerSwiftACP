import ComposableArchitecture
import Foundation

@CasePathable
enum AppRootAction: CasePathable, Sendable {
    case lifecycle(AppLifecycleFeature.Action)
    case appPreferences(AppPreferencesFeature.Action)
    case windowManager(WindowManagerFeature.Action)
    case updater(UpdaterFeature.Action)
    case menuCommands(MenuCommandsFeature.Action)
}
