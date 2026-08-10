import Foundation

public actor RuntimeControlPlane {
    struct Session {
        var stored: RuntimeStoredSession
        var acceptedCount: Int
        var processedCount: Int
        var hostAcceptedCount: Int
        var hostProcessedCount: Int
        var active: Bool
        var awaitingResumption: Bool

        init(
            stored: RuntimeStoredSession,
            active: Bool = false,
            awaitingResumption: Bool = false,
        ) {
            self.stored = stored
            acceptedCount = stored.acceptedEventCount
            processedCount = stored.processedEventCount
            hostAcceptedCount = stored.hostAcceptedEventCount
            hostProcessedCount = stored.hostProcessedEventCount
            self.active = active
            self.awaitingResumption = awaitingResumption
        }
    }

    let store: any RuntimeStateStore
    var adapters: [RuntimeAdapterID: any ExternalAgentRuntimeAdapter] = [:]
    var sessions: [ExternalAgentSessionReference: Session] = [:]
    var hydrationTask: Task<RuntimeStoredState?, Error>?
    var hydrated = false
    var terminalPending: [ExternalAgentSessionReference: Int] = [:]
    var persistenceMutationLocked = false
    var persistenceMutationWaiters: [CheckedContinuation<Void, Never>] = []
    var persistingHosts: Set<ExternalAgentSessionReference> = []

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
        let reservation = try await commit(host: request.externalAgentSessionReference) { plane in
            try plane.reserve(request)
        }
        var providerStarted = false
        do {
            let receipt = try await reservation.adapter.launch(request)
            providerStarted = true
            do {
                try await commit(host: reservation.host) { plane in
                    try plane.bind(receipt, to: request, descriptor: reservation.descriptor)
                }
            } catch {
                if sessions[reservation.host]?.stored.projection == .launching {
                    try await markInterrupted(reservation.host)
                }
                throw error
            }
            let result = try await consume(receipt, from: reservation.adapter, host: reservation.host)
            if sessions[reservation.host]?.stored.projection.isTerminal == true {
                return resultRespectingStoredTerminal(result, host: reservation.host)
            }
            beginTerminalTransition(reservation.host)
            defer { endTerminalTransition(reservation.host) }
            try await commit(host: reservation.host) { plane in
                plane.finish(result, host: reservation.host)
            }
            return resultRespectingStoredTerminal(result, host: reservation.host)
        } catch let error as RuntimeHostError {
            try await markFailedRun(reservation.host, providerStarted: providerStarted)
            throw error
        } catch {
            try await markFailedRun(reservation.host, providerStarted: providerStarted)
            throw normalizeAdapterError(error)
        }
    }

    private func markFailedRun(
        _ host: ExternalAgentSessionReference,
        providerStarted: Bool,
    ) async throws {
        guard sessions[host]?.stored.projection == .launching else {
            if sessions[host]?.active == true {
                try await markInterrupted(host)
            }
            return
        }
        if providerStarted {
            try await markInterrupted(host)
        } else {
            try await markLaunchFailed(host)
        }
    }

    private func markLaunchFailed(_ host: ExternalAgentSessionReference) async throws {
        try await commit(host: host) { plane in
            plane.update(host) { session in
                guard session.stored.projection == .launching else { return }
                session.stored = session.stored.withProjection(.launchFailed)
                session.active = false
            }
        }
    }

    func markInterrupted(_ host: ExternalAgentSessionReference) async throws {
        try await commit(host: host) { plane in
            plane.update(host) { session in
                guard session.active, !session.stored.projection.isTerminal else { return }
                session.stored = session.stored.withProjection(.interrupted)
                session.active = false
            }
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
