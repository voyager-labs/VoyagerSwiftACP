import ComposableArchitecture
import Foundation
import VoyagerFeaturesAccountAccess

@ObservableState
struct AppLifecycleState: Equatable {
    var accountAccess: AccountAccessFeature.State = Self.makeAccountAccessState()
    var didStartHelper = false
    var didFinishLaunching = false
    var terminationAttemptID: UUID?
    var accessGatePhase = AppLifecycleAccessGatePhase.unresolved
    var sessionEndReason: AccountSessionEndReason?

    var isExternalRouteFlushAllowed: Bool {
        accessGatePhase.allowsExternalRouteFlush
    }

    /// recoveryRequired와 signedOut 단계에서 guard overlay가 canonical child state를 사용한다.
    /// 두 번째 stored state 없이 phase 기반 presentation만 제공한다.
    var presentedAccountAccess: AccountAccessFeature.State? {
        switch accessGatePhase {
        case .recoveryRequired, .signedOut:
            accountAccess
        case .unresolved, .checking, .granted, .terminating:
            nil
        }
    }

    private static func makeAccountAccessState() -> AccountAccessFeature.State {
        var state = AccountAccessFeature.State()
        state.handoffContext = .paywall
        return state
    }
}

enum AppLifecycleAccessGatePhase: Equatable {
    case unresolved
    case checking
    case granted
    case recoveryRequired
    case signedOut
    case terminating

    var allowsExternalRouteFlush: Bool {
        self == .granted
    }
}
