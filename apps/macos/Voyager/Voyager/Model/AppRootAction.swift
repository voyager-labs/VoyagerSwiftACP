import ComposableArchitecture
import Foundation
import VoyagerFeaturesUpdateVersion
import VoyagerPagesSettings
import VoyagerShared

@CasePathable
enum AppRootAction: CasePathable {
    case lifecycle(AppLifecycleFeature.Action)
    case appDidBecomeActive
    case startHelperExternalFileBridge
    case helperStateUpdated(HelperState)
    case helperExternalFileChanged(HelperExternalFileChangeEvent)
    case flushPendingReplay
    case pendingReplayLoaded([String])
    case registerHelperWatchRootsIfNeeded
    case registerHelperWatchRoots([String])
    case openAISettings
    /// 외부 Deep Link URL 수신 (FMW-003-handle_deep_link). 창 없으면 버퍼링, 있으면 T10에서 OpenRouter로 전달
    case receiveExternalURL(URL)
    case appPreferences(AppPreferencesFeature.Action)
    case windowManager(WindowManagerFeature.Action)
    case updater(UpdaterFeature.Action)
    case settings(SettingsFeature.Action)
    case menuCommands(MenuCommandsFeature.Action)
    /// Open Router: 외부 URL/경로 처리
    case openRouter(OpenRouterAction)
}
