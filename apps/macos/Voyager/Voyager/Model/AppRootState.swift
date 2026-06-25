import ComposableArchitecture
import Foundation
import VoyagerFeaturesExternalFileRouter
import VoyagerFeaturesUpdateVersion
import VoyagerPagesSettings

@ObservableState
struct AppRootState: Equatable {
    var lifecycle: AppLifecycleFeature.State = .init()
    var appPreferences: AppPreferencesFeature.State = .init()
    var windowManager: WindowManagerFeature.State = .init()
    var updater: UpdaterFeature.State = .init()
    var settings: SettingsFeature.State = .init()
    var menuCommands: MenuCommandsFeature.State = .init()
    /// ExternalFileRouter: 외부 URL/경로를 받아 File Manager Window로 라우팅
    var externalFileRouter: ExternalFileRouterState = .init()
    var isHelperExternalFileBridgeStarted = false
    var lastHelperReady = false
    var windowPresenceBeforeWindowManagerAction: Bool?
    /// Cold state에서 첫 창 오픈까지 버퍼링된 외부 URL (Deep Link)
    var pendingExternalURL: URL?
    /// Cold state에서 첫 창 오픈까지 버퍼링된 외부 file:// URL 큐
    struct PendingExternalFileRoute: Equatable {
        var url: URL
        var source: RouteSource
        var mode: DeepLinkMode
    }

    var pendingExternalFileRoutes: [PendingExternalFileRoute] = []
}
