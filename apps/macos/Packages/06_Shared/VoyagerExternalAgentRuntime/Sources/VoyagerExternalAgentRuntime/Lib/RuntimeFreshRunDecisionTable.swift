struct RuntimeFreshRunSnapshot: Equatable {
    var projection: RuntimeProjection
    var receiptToken: String?
    var lease: RuntimeControlPlane.RuntimeLease
    var runReference: RuntimeRunReference
}

enum RuntimeFreshRunSignal: Equatable {
    case reserve
    case orphanLaunching
    case adapterLaunchFailed
    case callerCancel
    case receipt(token: String)
    case receiptPersistFailed
    case providerEvent(kind: RuntimeEventKind, hasGap: Bool, isDuplicate: Bool, isStale: Bool)
    case providerResult(RuntimeOutcome)
    case persistConflict(persisted: RuntimeFreshRunSnapshot)
    case cleanupFailed
}

enum RuntimeFreshRunDecision: Equatable {
    case persist(projection: RuntimeProjection, attachReceipt: String?, lease: RuntimeControlPlane.RuntimeLease)
    case adoptPersisted(RuntimeFreshRunSnapshot)
    case ignore
    case throwCancellation
    case throwHost(RuntimeHostError)
}

enum RuntimeFreshRunDecisionTable {
    static func decide(
        _ signal: RuntimeFreshRunSignal,
        on snapshot: RuntimeFreshRunSnapshot,
    ) -> RuntimeFreshRunDecision {
        if case let .persistConflict(persisted) = signal {
            return .adoptPersisted(persisted)
        }

        if snapshot.projection.isTerminal {
            return terminalDecision(signal, on: snapshot)
        }

        return activeDecision(signal, on: snapshot)
    }

    static func allowsRelaunch(_ snapshot: RuntimeFreshRunSnapshot) -> Bool {
        guard snapshot.lease == .none else { return false }
        return snapshot.projection == .policyReady || snapshot.projection == .launchFailed
    }

    private static func activeDecision(
        _ signal: RuntimeFreshRunSignal,
        on snapshot: RuntimeFreshRunSnapshot,
    ) -> RuntimeFreshRunDecision {
        switch signal {
        case .reserve:
            allowsRelaunch(snapshot) ? .ignore : .throwHost(.duplicateRunReference)
        case .orphanLaunching:
            orphanDecision(on: snapshot)
        case .adapterLaunchFailed:
            adapterLaunchFailureDecision(on: snapshot)
        case .callerCancel:
            cancellationDecision(on: snapshot)
        case let .receipt(token):
            receiptDecision(token: token, on: snapshot)
        case .receiptPersistFailed:
            receiptPersistenceFailureDecision(on: snapshot)
        case let .providerEvent(kind, hasGap, isDuplicate, isStale):
            providerEventDecision(
                kind: kind,
                hasGap: hasGap,
                isDuplicate: isDuplicate,
                isStale: isStale,
                on: snapshot,
            )
        case let .providerResult(outcome):
            providerResultDecision(outcome, on: snapshot)
        case .persistConflict, .cleanupFailed:
            .ignore
        }
    }

    private static func orphanDecision(
        on snapshot: RuntimeFreshRunSnapshot,
    ) -> RuntimeFreshRunDecision {
        guard snapshot.projection == .launching,
              normalizedReceipt(snapshot.receiptToken) == nil,
              snapshot.lease == .none
        else { return .throwHost(.activeRunExists) }
        return .persist(projection: .interrupted, attachReceipt: nil, lease: .none)
    }

    private static func adapterLaunchFailureDecision(
        on snapshot: RuntimeFreshRunSnapshot,
    ) -> RuntimeFreshRunDecision {
        if let receipt = normalizedReceipt(snapshot.receiptToken) {
            return .persist(projection: .interrupted, attachReceipt: receipt, lease: .none)
        }
        guard snapshot.projection == .launching,
              isLaunching(snapshot.lease)
        else { return .ignore }
        return .persist(projection: .launchFailed, attachReceipt: nil, lease: .none)
    }

    private static func receiptPersistenceFailureDecision(
        on snapshot: RuntimeFreshRunSnapshot,
    ) -> RuntimeFreshRunDecision {
        guard let receipt = normalizedReceipt(snapshot.receiptToken)
        else { return .throwHost(.persistenceFailure) }
        return .persist(projection: .interrupted, attachReceipt: receipt, lease: .none)
    }

    private static func providerEventDecision(
        kind: RuntimeEventKind,
        hasGap: Bool,
        isDuplicate: Bool,
        isStale: Bool,
        on snapshot: RuntimeFreshRunSnapshot,
    ) -> RuntimeFreshRunDecision {
        guard !hasGap, !isDuplicate, !isStale,
              let terminal = terminalProjection(kind),
              acceptsProviderTerminal(on: snapshot)
        else { return .ignore }
        return .persist(
            projection: terminal,
            attachReceipt: normalizedReceipt(snapshot.receiptToken),
            lease: .none,
        )
    }

    private static func providerResultDecision(
        _ outcome: RuntimeOutcome,
        on snapshot: RuntimeFreshRunSnapshot,
    ) -> RuntimeFreshRunDecision {
        guard let receipt = normalizedReceipt(snapshot.receiptToken),
              acceptsProviderTerminal(on: snapshot)
        else { return .ignore }
        return .persist(
            projection: projection(outcome),
            attachReceipt: receipt,
            lease: .none,
        )
    }

    private static func terminalDecision(
        _ signal: RuntimeFreshRunSignal,
        on snapshot: RuntimeFreshRunSnapshot,
    ) -> RuntimeFreshRunDecision {
        switch signal {
        case let .receipt(token):
            guard let receipt = normalizedReceipt(token) else {
                return .throwHost(.malformedAdapterResponse)
            }
            guard let existing = normalizedReceipt(snapshot.receiptToken) else {
                return .persist(projection: snapshot.projection, attachReceipt: receipt, lease: .none)
            }
            return existing == receipt ? .ignore : .throwHost(.malformedAdapterResponse)
        case .persistConflict:
            return .ignore
        default:
            return .ignore
        }
    }

    private static func cancellationDecision(
        on snapshot: RuntimeFreshRunSnapshot,
    ) -> RuntimeFreshRunDecision {
        guard let receipt = normalizedReceipt(snapshot.receiptToken) else {
            if isLaunching(snapshot.lease), snapshot.projection == .launching {
                return .persist(projection: .launchCancelled, attachReceipt: nil, lease: .none)
            }
            return .throwCancellation
        }

        switch snapshot.lease {
        case let .launching(value):
            return .persist(
                projection: .running,
                attachReceipt: receipt,
                lease: .detachedConsuming(value),
            )
        case let .detachedLaunching(value):
            return .persist(
                projection: .running,
                attachReceipt: receipt,
                lease: .detachedConsuming(value),
            )
        case let .consuming(value):
            return .persist(
                projection: snapshot.projection,
                attachReceipt: receipt,
                lease: .detachedConsuming(value),
            )
        case .detachedConsuming:
            return .throwCancellation
        case .none, .restored, .resuming:
            return .throwCancellation
        }
    }

    private static func receiptDecision(
        token: String,
        on snapshot: RuntimeFreshRunSnapshot,
    ) -> RuntimeFreshRunDecision {
        guard let receipt = normalizedReceipt(token) else {
            return .throwHost(.malformedAdapterResponse)
        }
        if let existing = normalizedReceipt(snapshot.receiptToken) {
            return existing == receipt ? .ignore : .throwHost(.malformedAdapterResponse)
        }

        switch snapshot.lease {
        case let .launching(value):
            return .persist(
                projection: .running,
                attachReceipt: receipt,
                lease: .consuming(value),
            )
        case let .detachedLaunching(value):
            return .persist(
                projection: .running,
                attachReceipt: receipt,
                lease: .detachedConsuming(value),
            )
        case .none, .consuming, .detachedConsuming, .restored, .resuming:
            return .throwHost(.invalidEvent)
        }
    }

    private static func acceptsProviderTerminal(
        on snapshot: RuntimeFreshRunSnapshot,
    ) -> Bool {
        guard normalizedReceipt(snapshot.receiptToken) != nil else { return false }
        guard isConsuming(snapshot.lease) else { return false }
        switch snapshot.projection {
        case .running, .eventProjected, .eventDuplicateIgnored, .eventOutOfOrder:
            return true
        case .policyPending, .policyReady, .launchBlocked, .launchCancelled, .launchFailed,
             .launching, .completed, .failed, .interrupted:
            return false
        }
    }

    private static func normalizedReceipt(_ token: String?) -> String? {
        guard let token, token.contains(where: { !$0.isWhitespace }) else { return nil }
        return token
    }

    private static func isLaunching(_ lease: RuntimeControlPlane.RuntimeLease) -> Bool {
        if case .launching = lease { return true }
        return false
    }

    private static func isConsuming(_ lease: RuntimeControlPlane.RuntimeLease) -> Bool {
        switch lease {
        case .consuming, .detachedConsuming: true
        case .none, .launching, .detachedLaunching, .restored, .resuming: false
        }
    }

    private static func terminalProjection(_ kind: RuntimeEventKind) -> RuntimeProjection? {
        switch kind {
        case .completed: .completed
        case .failed: .failed
        case .interrupted: .interrupted
        case .policyReady, .approvalRequested, .inputRequested, .progress: nil
        }
    }

    private static func projection(_ outcome: RuntimeOutcome) -> RuntimeProjection {
        switch outcome {
        case .completed: .completed
        case .failed: .failed
        case .interrupted: .interrupted
        }
    }
}

extension RuntimeControlPlane.Session {
    func freshRunSnapshot(receiptToken: String? = nil) -> RuntimeFreshRunSnapshot {
        RuntimeFreshRunSnapshot(
            projection: stored.projection,
            receiptToken: receiptToken ?? stored.providerInternalSessionReference?.rawValue,
            lease: lease,
            runReference: stored.runReference,
        )
    }
}
