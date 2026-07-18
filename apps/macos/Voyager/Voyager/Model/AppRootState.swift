import ComposableArchitecture
import Foundation
import VoyagerFeaturesExternalFileRouter
import VoyagerFeaturesUpdateVersion
import VoyagerPagesSettings

enum AppRootExternalOpenPhase: Equatable {
    case normalizing
    case planning
    case applying
    case alerting
    case activating
    case advancing
}

struct AppRootPendingExternalURL: Equatable {
    var requestID: UUID
    var url: URL
}

struct AppRootExternalOpenBatch: Equatable {
    var request: ExternalFileRouterBatchRequest
    var requiresInitialWindowFallback: Bool
}

struct AppRootActiveExternalOpenBatch: Equatable {
    var batch: AppRootExternalOpenBatch
    var preferredWindowIDs: [WindowManagerState.WindowID]
    var normalizedItems: [ExternalFileRouterBatchItemResult] = []
    var orderedFailures: [ExternalFileRouterBatchItemResult] = []
    var placementPlan: ExternalOpenPlacementPlan?
    var nextFailureOffset = 0
    var phase = AppRootExternalOpenPhase.normalizing
}

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
    var windowPresenceBeforeWindowManagerAction: Bool?
    /// Cold state에서 첫 창 오픈까지 버퍼링된 외부 URL (Deep Link) 큐
    var pendingExternalURLs: [URL] = []
    /// Router terminal을 기다리는 단일 pending deep-link occurrence
    var activePendingExternalURL: AppRootPendingExternalURL?
    /// no-window 외부 URL flush delegate 중복 예약을 막는다.
    var isExternalURLFlushDelegateScheduled = false
    /// no-window 외부 URL 처리 중 빈 initial-window fallback을 막는다.
    var isExternalURLRouteInFlightWithoutWindow = false
    var externalOpenBatchQueue: [AppRootExternalOpenBatch] = []
    var activeExternalOpenBatch: AppRootActiveExternalOpenBatch?
    var isInitialWindowFallbackPending = false
}
