import ComposableArchitecture
import Foundation
import VoyagerFeaturesExternalFileRouter
import VoyagerFeaturesUpdateVersion
import VoyagerPagesSettings

struct ExternalOpenAlertCompletion: Equatable {
    var batchID: UUID
    var failureIndex: Int
}

@CasePathable
enum AppRootAction: CasePathable {
    case lifecycle(AppLifecycleFeature.Action)
    case appDidBecomeActive
    case openAISettings
    /// 외부 Deep Link URL 수신 (FMW-003-handle_deep_link). 창 없으면 버퍼링, 있으면 T10에서 ExternalFileRouter로 전달
    case receiveExternalURL(URL)
    /// ACC-001 소유 인증 callback 수신. FMW 라우터가 소유하지 않는 route를 명시적으로 분리한다.
    case receiveAuthCallbackURL(URL)
    /// legacy tracked Router auth handoff. AppDelegate production ingress는 receiveAuthCallbackURL을 직접 사용한다.
    case receiveTrackedAuthCallbackURL(URL, requestID: UUID)
    /// 외부 file:// URL 수신 (System Open Event, NSServices)
    case receiveExternalFileURL(URL, source: RouteSource, mode: DeepLinkMode)
    /// callback 한 번의 ordered file URL batch 수신
    case receiveExternalFileBatch([URL], source: RouteSource, mode: DeepLinkMode)
    /// 외부 `.voycoll` 문서 열기 수신. legacy ingress를 batch queue에 연결한다.
    case receiveCollectionFileURL(URL)
    case externalOpenAlertCompleted(ExternalOpenAlertCompletion)
    case externalOpenAdvanceToNextBatch(batchID: UUID)
    case appPreferences(AppPreferencesFeature.Action)
    case windowManager(WindowManagerFeature.Action)
    case updater(UpdaterFeature.Action)
    case settings(SettingsFeature.Action)
    case menuCommands(MenuCommandsFeature.Action)
    /// ExternalFileRouter: 외부 URL/경로 처리
    case externalFileRouter(ExternalFileRouterAction)
}
