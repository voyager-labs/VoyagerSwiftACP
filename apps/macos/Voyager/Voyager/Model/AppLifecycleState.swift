import ComposableArchitecture
import Foundation
import VoyagerFeaturesAccountAccess

@ObservableState
struct AppLifecycleState: Equatable {
    var didStartHelper = false
    var didFinishLaunching = false
    var terminationAttemptID: UUID?
    var accessGateGeneration = 0
    var accessGatePhase = AppLifecycleAccessGatePhase.unresolved
    var isCheckingAccountAccess = false
    var lastAccessStatus: AccessStatus?
    var accountAccessGateResolved = false
    var sessionLapseGuard: AccountAccessFeature.State?
    var sessionEndReason: AccountSessionEndReason?

    var isExternalRouteFlushAllowed: Bool {
        sessionLapseGuard == nil && accessGatePhase.allowsExternalRouteFlush
    }

    mutating func beginAccessCheck() -> Int {
        accessGateGeneration += 1
        accessGatePhase = .checking(generation: accessGateGeneration)
        isCheckingAccountAccess = true
        sessionEndReason = nil
        return accessGateGeneration
    }

    mutating func invalidateAccessCheck() {
        accessGateGeneration += 1
        isCheckingAccountAccess = false
    }

    func isCurrentAccessGateGeneration(_ generation: Int) -> Bool {
        accessGateGeneration == generation
    }

    mutating func resolveAccessGranted(_ snapshot: AccessStatusSnapshot, generation: Int) {
        accessGatePhase = .granted(snapshot: snapshot, generation: generation)
        lastAccessStatus = snapshot.status
        accountAccessGateResolved = true
        isCheckingAccountAccess = false
        sessionEndReason = nil
    }

    mutating func resolveAccessUnlockRequired(_ snapshot: AccessStatusSnapshot, generation: Int) {
        accessGatePhase = .unlockRequired(snapshot: snapshot, generation: generation)
        lastAccessStatus = snapshot.status
        accountAccessGateResolved = true
        isCheckingAccountAccess = false
    }

    mutating func resolveAccessFailure(_ error: AccessError, generation: Int) {
        accessGatePhase = .accessFailure(error: error, generation: generation)
        lastAccessStatus = nil
        accountAccessGateResolved = true
        isCheckingAccountAccess = false
    }

    mutating func resolveSessionEnded(reason: AccountSessionEndReason?) {
        accessGateGeneration += 1
        lastAccessStatus = nil
        accountAccessGateResolved = false
        isCheckingAccountAccess = false
        sessionEndReason = reason

        if reason == .explicitSignOut {
            accessGatePhase = .signedOut(generation: accessGateGeneration)
        } else {
            accessGatePhase = .sessionLapsed(reason: reason, generation: accessGateGeneration)
        }
    }
}

enum AppLifecycleAccessGatePhase: Equatable {
    case unresolved
    case checking(generation: Int)
    case granted(snapshot: AccessStatusSnapshot, generation: Int)
    case unlockRequired(snapshot: AccessStatusSnapshot, generation: Int)
    case accessFailure(error: AccessError, generation: Int)
    case sessionLapsed(reason: AccountSessionEndReason?, generation: Int)
    case signedOut(generation: Int)

    var allowsExternalRouteFlush: Bool {
        if case .granted = self { return true }
        return false
    }
}
