import Foundation

public actor RuntimeControlPlane {
    typealias SessionRegistry = [ExternalAgentSessionReference: Session]

    enum RuntimeLease: Equatable {
        case none
        case launching(UInt64)
        case consuming(UInt64)
        case restored(UInt64)
        case resuming(UInt64)

        var isActive: Bool {
            self != .none
        }

        var isAwaitingResumption: Bool {
            if case .restored = self { return true }
            return false
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
    var adapters: [RuntimeAdapterID: any ExternalAgentRuntimeAdapter] = [:]
    var sessions: SessionRegistry = [:]
    var hydrationTask: Task<RuntimeStoredState?, Error>?
    var hydrated = false
    var persistenceMutationLocked = false
    var persistenceMutationWaiters: [CheckedContinuation<Void, Never>] = []
    var pendingPersistenceMutations: [ExternalAgentSessionReference: Int] = [:]

    public init(store: any RuntimeStateStore) {
        self.store = store
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

    public func run(_ request: RuntimeLaunchRequest) async throws -> RuntimeResult {
        try await hydrateIfNeeded()
        if try await retireOrphanedDirectRunIfNeeded(request) {
            throw RuntimeHostError.duplicateRunReference
        }
        let reservation = try await commit(host: request.externalAgentSessionReference) { plane, registry in
            try plane.reserveTransition(request, in: &registry)
        }
        let receipt: RuntimeLaunchReceipt
        do {
            receipt = try await reservation.adapter.launch(request)
        } catch {
            return try await resolveLaunchFailure(
                error,
                reservation: reservation,
                runReference: request.runReference,
            )
        }
        let receiptTransition: ReceiptTransition
        do {
            receiptTransition = try await commit(host: reservation.host) { plane, registry in
                try plane.recordReceiptTransition(
                    receipt,
                    request: request,
                    descriptor: reservation.descriptor,
                    lease: reservation.lease,
                    in: &registry,
                )
            }
        } catch {
            try? await reconcileStartedProviderFailure(reservation: reservation)
            throw error
        }
        switch receiptTransition {
        case let .terminal(result):
            return result
        case let .consuming(lease):
            return try await consumeAndFinish(
                receipt,
                reservation: reservation,
                lease: lease,
            )
        }
    }

    private func resolveLaunchFailure(
        _ error: any Error,
        reservation: RunReservation,
        runReference: RuntimeRunReference,
    ) async throws -> RuntimeResult {
        let primary = normalizeAdapterError(error)
        let cleanupApplied = try? await commit(host: reservation.host) { plane, registry in
            plane.failLaunchTransition(
                host: reservation.host,
                lease: reservation.lease,
                in: &registry,
            )
        }
        if cleanupApplied != true,
           let terminal = storedTerminalResult(host: reservation.host, runReference: runReference)
        {
            return terminal
        }
        throw primary
    }

    private func consumeAndFinish(
        _ receipt: RuntimeLaunchReceipt,
        reservation: RunReservation,
        lease: UInt64,
    ) async throws -> RuntimeResult {
        do {
            let result = try await consume(receipt, from: reservation.adapter, host: reservation.host)
            if sessions[reservation.host]?.stored.projection.isTerminal == true {
                return resultRespectingStoredTerminal(result, host: reservation.host)
            }
            return try await commit(host: reservation.host) { plane, registry in
                try plane.finishTransition(
                    result,
                    host: reservation.host,
                    lease: lease,
                    in: &registry,
                )
            }
        } catch {
            let primary = (error as? RuntimeHostError) ?? normalizeAdapterError(error)
            try? await commit(host: reservation.host) { plane, registry in
                try plane.interruptTransition(
                    host: reservation.host,
                    lease: lease,
                    in: &registry,
                )
            }
            throw primary
        }
    }

    private func reconcileStartedProviderFailure(
        reservation: RunReservation,
    ) async throws {
        try await commit(host: reservation.host) { plane, registry in
            try plane.interruptTransition(
                host: reservation.host,
                lease: reservation.lease,
                in: &registry,
            )
        }
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

    func normalizeAdapterError(_ error: any Error) -> RuntimeHostError {
        guard let failure = error as? RuntimeAdapterFailure else { return .adapterUnavailable }
        return .adapterFailure(failure.kind, failure.diagnosticCode)
    }
}

extension RuntimeStoredSession {
    func withProjection(_ projection: RuntimeProjection) -> Self {
        Self(
            externalAgentSessionReference: externalAgentSessionReference,
            providerInternalSessionReference: providerInternalSessionReference,
            runReference: runReference,
            adapterID: adapterID,
            adapterVersion: adapterVersion,
            capabilitySnapshot: capabilitySnapshot,
            contextPolicy: contextPolicy,
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
    }
}
