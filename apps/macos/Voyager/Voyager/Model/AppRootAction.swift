import ComposableArchitecture
import Foundation
import VoyagerFeaturesUpdateVersion
import VoyagerPagesSettings

@CasePathable
enum AppRootAction: CasePathable {
    case lifecycle(AppLifecycleFeature.Action)
    case appDidBecomeActive
    case openAISettings
    case appPreferences(AppPreferencesFeature.Action)
    case windowManager(WindowManagerFeature.Action)
    case updater(UpdaterFeature.Action)
    case settings(SettingsFeature.Action)
    case menuCommands(MenuCommandsFeature.Action)
}
