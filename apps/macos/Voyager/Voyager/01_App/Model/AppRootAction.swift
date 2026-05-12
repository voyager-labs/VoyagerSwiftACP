import ComposableArchitecture
import Foundation
import VoyagerFeaturesUpdateVersion
import VoyagerPagesSettings

@CasePathable
enum AppRootAction: CasePathable, Sendable {
    case lifecycle(AppLifecycleFeature.Action)
    case appDidBecomeActive
    case startHelperExternalFileBridge
    case helperStateUpdated(HelperState)
    case helperExternalFileChanged(HelperExternalFileChangeEvent)
    case flushPendingReplay
    case pendingReplayLoaded([String])
    case registerHelperWatchRootsIfNeeded
    case registerHelperWatchRoots([String])
    case appPreferences(AppPreferencesFeature.Action)
    case windowManager(WindowManagerFeature.Action)
    case updater(UpdaterFeature.Action)
    case settings(SettingsFeature.Action)
    case menuCommands(MenuCommandsFeature.Action)
}
