import Foundation

public enum RuntimeCleanupFailureKind: Sendable, Equatable {
    case persistence
}

public struct RuntimeCleanupFailureEvidence: Sendable, Equatable {
    public let runReference: RuntimeRunReference
    public let kind: RuntimeCleanupFailureKind

    public init(runReference: RuntimeRunReference, kind: RuntimeCleanupFailureKind) {
        self.runReference = runReference
        self.kind = kind
    }
}

public actor RuntimeControlPlane {
    typealias SessionRegistry = [ExternalAgentSessionReference: Session]

    enum RuntimeLease: Equatable {
        case none
        case launching(UInt64)
        case detachedLaunching(UInt64)
        case consuming(UInt64)
        case detachedConsuming(UInt64)
        case restored(UInt64)
        case resuming(UInt64)

        var isActive: Bool {
            self != .none
        }

        var isAwaitingResumption: Bool {
            if case .restored = self { return true }
            return false
        }

        var isDetachedOwner: Bool {
            switch self {
            case .detachedLaunching, .detachedConsuming:
                true
            default:
                false
            }
        }
    }

    struct Session: Equatable {
        var stored: RuntimeStoredSession
        var acceptedCount: Int
        var processedCount: Int
        var hostAcceptedCount: Int
        var hostProcessedCount: Int
        var lease: RuntimeLease
        var revision: UInt64

        init(
            stored: RuntimeStoredSession,
            lease: RuntimeLease = .none,
            revision: UInt64 = 0,
        ) {
            self.stored = stored
            acceptedCount = stored.acceptedEventCount
            processedCount = stored.processedEventCount
            hostAcceptedCount = stored.hostAcceptedEventCount
            hostProcessedCount = stored.hostProcessedEventCount
            self.lease = lease
            self.revision = revision
        }

        mutating func issueLease(_ makeLease: (UInt64) -> RuntimeLease) -> UInt64 {
            revision += 1
            lease = makeLease(revision)
            return revision
        }
    }

    let store: any RuntimeStateStore
    let restorationOwnerToken = UUID().uuidString
    let restorationHeartbeatInterval: Duration
    var adapters: [RuntimeAdapterID: any ExternalAgentRuntimeAdapter] = [:]
    var sessions: SessionRegistry = [:]
    var hydrationTask: Task<RuntimeStoredState?, Error>?
    var hydrationGeneration: UInt64 = 0
    var hydrationWaiterCounts: [UInt64: Int] = [:]
    var hydrationDeliveryOrdinal = 0
    var hydrationDeliveryPauseOrdinal: Int?
    var hydrationDeliveryPauseBackground = false
    var hydrationDeliveryPauseContinuation: CheckedContinuation<Void, Never>?
    var hydrationWaiterAdmissionContinuations: [(Int, CheckedContinuation<Void, Never>)] = []
    var hydrationPauseObservedContinuations: [CheckedContinuation<Void, Never>] = []
    var hydrationDeliveryIsPaused = false
    var hydrationInstallCount = 0
    var hydrated = false
    var persistenceMutationLocked = false
    var persistenceMutationWaiters: [CheckedContinuation<Void, Never>] = []
    var pendingPersistenceMutations: [ExternalAgentSessionReference: Int] = [:]
    var cleanupFailureEvidenceByHost: [ExternalAgentSessionReference: RuntimeCleanupFailureEvidence] = [:]

    var hydrationWaiterCount: Int {
        hydrationWaiterCounts.values.reduce(0, +)
    }

    public init(store: any RuntimeStateStore) {
        self.store = store
        restorationHeartbeatInterval = .seconds(20)
    }

    init(store: any RuntimeStateStore, restorationHeartbeatInterval: Duration) {
        self.store = store
        self.restorationHeartbeatInterval = restorationHeartbeatInterval
    }

    public func register(_ adapter: any ExternalAgentRuntimeAdapter) throws {
        let id = adapter.descriptor.id
        guard id.rawValue.isRuntimeBounded,
              adapter.descriptor.providerNamespace.isRuntimeBounded,
              adapter.descriptor.adapterVersion.isRuntimeBounded
        else { throw RuntimeHostError.malformedAdapterResponse }
        guard adapters[id] == nil else { throw RuntimeHostError.duplicateAdapterRegistration }
        adapters[id] = adapter
    }

    public func adapterDescriptor(for id: RuntimeAdapterID) -> RuntimeAdapterDescriptor? {
        adapters[id]?.descriptor
    }

    public func projection(for host: ExternalAgentSessionReference) -> RuntimeProjection? {
        sessions[host]?.stored
            .projection
    }

    public func eventEvidence(for host: ExternalAgentSessionReference) -> [RuntimeEventEvidence] {
        sessions[host]?
            .stored.eventEvidence ?? []
    }

    public func acceptedEventCount(for host: ExternalAgentSessionReference) -> Int {
        sessions[host]?.acceptedCount ?? 0
    }

    public func cleanupFailureEvidence(
        for host: ExternalAgentSessionReference,
    ) -> RuntimeCleanupFailureEvidence? {
        cleanupFailureEvidenceByHost[host]
    }

    func normalizeAdapterError(_ error: any Error) -> RuntimeHostError {
        guard let failure = error as? RuntimeAdapterFailure else { return .adapterUnavailable }
        return .adapterFailure(failure.kind, failure.diagnosticCode)
    }
}

extension RuntimeStoredSession {
    func withProjection(_ projection: RuntimeProjection) -> Self {
        var copy = Self(
            externalAgentSessionReference: externalAgentSessionReference,
            providerInternalSessionReference: providerInternalSessionReference,
            runReference: runReference,
            adapterID: adapterID,
            adapterVersion: adapterVersion,
            capabilitySnapshot: capabilitySnapshot,
            storedContext: storedContext,
            projection: projection,
            providerLaunchAttempted: providerLaunchAttempted,
            lastSequence: lastSequence,
            acceptedEventCount: acceptedEventCount,
            processedEventCount: processedEventCount,
            acceptedIdempotencyKeys: acceptedIdempotencyKeys,
            hostLastSequence: hostLastSequence,
            hostAcceptedEventCount: hostAcceptedEventCount,
            hostProcessedEventCount: hostProcessedEventCount,
            hostAcceptedIdempotencyKeys: hostAcceptedIdempotencyKeys,
            providerNamespace: providerNamespace,
            providerBranch: providerBranch,
            eventEvidence: eventEvidence,
        )
        copy.restorationClaim = projection.isTerminal ? nil : restorationClaim
        return copy
    }

    func withRestorationClaim(_ claim: RuntimeRestorationClaim?) -> Self {
        var copy = self
        copy.restorationClaim = claim
        return copy
    }
}
