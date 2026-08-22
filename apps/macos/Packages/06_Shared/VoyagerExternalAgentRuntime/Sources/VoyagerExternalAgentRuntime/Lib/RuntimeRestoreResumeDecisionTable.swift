import Foundation

enum RuntimeRestoreResumeDecisionTable {
    enum ClaimState: Equatable {
        case absent
        case ownedLive
        case foreignLive
        case expired
    }

    struct Snapshot: Equatable {
        let projection: RuntimeProjection
        let lease: RuntimeControlPlane.RuntimeLease
        let claimState: ClaimState

        init(
            projection: RuntimeProjection,
            lease: RuntimeControlPlane.RuntimeLease,
            claimState: ClaimState,
        ) {
            self.projection = projection
            self.lease = lease
            self.claimState = claimState
        }
    }

    enum Signal: Equatable {
        case evaluateRestore
        case acquireClaim
        case beginResume
        case heartbeat
        case claimLost
        case restoreAfterFailure
        case persistConflict
    }

    enum Decision: Equatable {
        case stale
        case acquireClaim
        case beginResume
        case renewClaim
        case restoreClaim
        case adoptPersisted
        case throwHost(RuntimeHostError)
    }

    static func decide(_ signal: Signal, on snapshot: Snapshot) -> Decision {
        if signal == .persistConflict {
            return .adoptPersisted
        }

        guard !snapshot.projection.isTerminal else { return .stale }

        switch signal {
        case .evaluateRestore, .acquireClaim:
            return claimAcquisitionDecision(on: snapshot)
        case .beginResume:
            return beginResumeDecision(on: snapshot)
        case .heartbeat:
            return heartbeatDecision(on: snapshot)
        case .claimLost, .restoreAfterFailure:
            return restoreClaimDecision(on: snapshot)
        case .persistConflict:
            return .adoptPersisted
        }
    }

    private static func claimAcquisitionDecision(on snapshot: Snapshot) -> Decision {
        guard snapshot.lease == .none else { return .throwHost(.activeRunExists) }
        switch snapshot.claimState {
        case .absent, .ownedLive, .expired:
            return .acquireClaim
        case .foreignLive:
            return .stale
        }
    }

    private static func beginResumeDecision(on snapshot: Snapshot) -> Decision {
        guard case .restored = snapshot.lease else { return .throwHost(.invalidEvent) }
        switch snapshot.claimState {
        case .ownedLive:
            return .beginResume
        case .absent, .expired:
            return .restoreClaim
        case .foreignLive:
            return .stale
        }
    }

    private static func heartbeatDecision(on snapshot: Snapshot) -> Decision {
        guard case .resuming = snapshot.lease else { return .stale }
        switch snapshot.claimState {
        case .ownedLive:
            return .renewClaim
        case .absent, .expired:
            return .restoreClaim
        case .foreignLive:
            return .stale
        }
    }

    private static func restoreClaimDecision(on snapshot: Snapshot) -> Decision {
        guard isRestored(snapshot.lease) || isResuming(snapshot.lease) else { return .stale }
        switch snapshot.claimState {
        case .foreignLive:
            return .stale
        case .absent, .ownedLive, .expired:
            return .restoreClaim
        }
    }

    private static func isResuming(_ lease: RuntimeControlPlane.RuntimeLease) -> Bool {
        if case .resuming = lease { return true }
        return false
    }

    private static func isRestored(_ lease: RuntimeControlPlane.RuntimeLease) -> Bool {
        if case .restored = lease { return true }
        return false
    }
}

extension RuntimeRestoreResumeDecisionTable.ClaimState: Sendable {}
extension RuntimeRestoreResumeDecisionTable.Snapshot: Sendable {}
extension RuntimeRestoreResumeDecisionTable.Signal: Sendable {}
extension RuntimeRestoreResumeDecisionTable.Decision: Sendable {}
