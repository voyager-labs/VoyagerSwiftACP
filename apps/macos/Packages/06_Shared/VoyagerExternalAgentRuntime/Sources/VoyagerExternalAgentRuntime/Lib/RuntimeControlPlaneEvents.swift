import Foundation

extension RuntimeControlPlane {
    private struct EventCursor {
        let lastSequence: UInt64
        let acceptedCount: Int
        let acceptedKeys: [RuntimeIdempotencyKey]
    }

    func accept(
        _ event: RuntimeEventEnvelope,
        host: ExternalAgentSessionReference,
        expectedSource: RuntimeEventSource,
    ) async throws -> RuntimeResult? {
        try validateEventAdmission(event, host: host, expectedSource: expectedSource)
        let terminal = terminalResult(for: event)
        do {
            return try await commit(host: host) { plane, registry in
                try plane.apply(
                    event,
                    host: host,
                    expectedSource: expectedSource,
                    terminal: terminal,
                    in: &registry,
                )
            }
        } catch RuntimeHostError.persistenceConflict where terminal != nil {
            let persistedTerminal = try await withPersistedState { plane, loaded -> RuntimeResult? in
                guard let loaded else { return nil }
                plane.sessions = plane.reconciledRegistry(candidate: plane.sessions, persisted: loaded)
                guard let session = plane.sessions[host],
                      session.stored.runReference == event.runReference
                else { return nil }
                return plane.terminalResult(for: session.stored)
            }
            try Task.checkCancellation()
            if let persistedTerminal { return persistedTerminal }
            return try await commit(host: host) { plane, registry in
                try plane.apply(
                    event,
                    host: host,
                    expectedSource: expectedSource,
                    terminal: terminal,
                    in: &registry,
                )
            }
        }
    }

    private func validateEventAdmission(
        _ event: RuntimeEventEnvelope,
        host: ExternalAgentSessionReference,
        expectedSource: RuntimeEventSource,
    ) throws {
        guard host.rawValue.isRuntimeBounded,
              event.externalAgentSessionReference == host,
              event.source == expectedSource,
              event.providerEventID.rawValue.isRuntimeBounded,
              event.idempotencyKey.rawValue.isRuntimeBounded,
              let session = sessions[host],
              event.runReference == session.stored.runReference
        else { throw RuntimeHostError.malformedAdapterResponse }
    }

    private func apply(
        _ event: RuntimeEventEnvelope,
        host: ExternalAgentSessionReference,
        expectedSource: RuntimeEventSource,
        terminal: RuntimeResult?,
        in registry: inout SessionRegistry,
    ) throws -> RuntimeResult? {
        try validate(event, host: host, expectedSource: expectedSource, in: registry)
        guard var session = registry[host] else { throw RuntimeHostError.malformedAdapterResponse }
        let isProvider = expectedSource == .provider
        try advanceProcessedCount(in: &session, isProvider: isProvider)
        let cursor = eventCursor(for: session, isProvider: isProvider)
        if cursor.acceptedKeys.contains(event.idempotencyKey) {
            session.stored = session.stored
                .withEvidence(.ignoredDuplicate(event.idempotencyKey))
            session.revision += 1
            registry[host] = session
            return nil
        }
        if event.sequence <= cursor.lastSequence {
            let projection = session.stored.projection == .launching
                ? RuntimeProjection.launching
                : .eventOutOfOrder
            session.stored = session.stored
                .withEvidence(.staleSequence(
                    lastAccepted: cursor.lastSequence,
                    received: event.sequence,
                ))
                .withProjection(projection)
            session.revision += 1
            registry[host] = session
            return nil
        }
        guard cursor.acceptedCount < RuntimeBoundaryLimits.acceptedEventsPerRun else {
            throw RuntimeHostError.malformedAdapterResponse
        }
        let expected = cursor.lastSequence + 1
        let hasGap = event.sequence != expected
        if hasGap {
            session.stored = session.stored.withEvidence(
                .sequenceGap(expected: expected, received: event.sequence),
            )
        }
        let acceptedTerminal = hasGap ? nil : terminal
        let acceptedProjection = projection(
            after: event.kind,
            from: session.stored.projection,
            hasGap: hasGap,
        )
        persistAccepted(
            event,
            source: expectedSource,
            session: &session,
            projection: acceptedProjection,
            registry: &registry,
        )
        return acceptedTerminal
    }

    private func advanceProcessedCount(in session: inout Session, isProvider: Bool) throws {
        let count = isProvider ? session.processedCount : session.hostProcessedCount
        guard count < RuntimeBoundaryLimits.acceptedEventsPerRun else {
            throw RuntimeHostError.malformedAdapterResponse
        }
        if isProvider {
            session.processedCount += 1
            session.stored = session.stored.withProcessedEventCount(session.processedCount)
        } else {
            session.hostProcessedCount += 1
            session.stored = session.stored.withHostProcessedEventCount(session.hostProcessedCount)
        }
    }

    private func eventCursor(for session: Session, isProvider: Bool) -> EventCursor {
        if isProvider {
            return EventCursor(
                lastSequence: session.stored.lastSequence,
                acceptedCount: session.acceptedCount,
                acceptedKeys: session.stored.acceptedIdempotencyKeys,
            )
        }
        return EventCursor(
            lastSequence: session.stored.hostLastSequence,
            acceptedCount: session.hostAcceptedCount,
            acceptedKeys: session.stored.hostAcceptedIdempotencyKeys,
        )
    }

    private func validate(
        _ event: RuntimeEventEnvelope,
        host: ExternalAgentSessionReference,
        expectedSource: RuntimeEventSource,
        in registry: SessionRegistry,
    ) throws {
        guard let session = registry[host] else { throw RuntimeHostError.malformedAdapterResponse }
        let acceptsInactiveHostTerminal = expectedSource == .host
            && terminalResult(for: event) != nil
            && !session.stored.projection.isTerminal
        guard session.lease.isActive || acceptsInactiveHostTerminal,
              event.source == expectedSource,
              event.runReference == session.stored.runReference,
              event.externalAgentSessionReference == host,
              event.providerEventID.rawValue.isRuntimeBounded,
              event.idempotencyKey.rawValue.isRuntimeBounded,
              allows(event.kind, from: session.stored.projection)
        else { throw RuntimeHostError.malformedAdapterResponse }
    }

    private func persistAccepted(
        _ event: RuntimeEventEnvelope,
        source: RuntimeEventSource,
        session: inout Session,
        projection: RuntimeProjection,
        registry: inout SessionRegistry,
    ) {
        let host = event.externalAgentSessionReference
        let isProvider = source == .provider
        let restorationClaim = session.stored.restorationClaim
        if isProvider {
            session.acceptedCount += 1
        } else {
            session.hostAcceptedCount += 1
        }
        let providerKeys = isProvider
            ? Array((session.stored.acceptedIdempotencyKeys + [event.idempotencyKey])
                .suffix(RuntimeBoundaryLimits.persistedEventEntries))
            : session.stored.acceptedIdempotencyKeys
        let hostKeys = isProvider
            ? session.stored.hostAcceptedIdempotencyKeys
            : Array((session.stored.hostAcceptedIdempotencyKeys + [event.idempotencyKey])
                .suffix(RuntimeBoundaryLimits.persistedEventEntries))
        session.stored = RuntimeStoredSession(
            externalAgentSessionReference: host,
            providerInternalSessionReference: session.stored.providerInternalSessionReference,
            runReference: session.stored.runReference,
            adapterID: session.stored.adapterID,
            adapterVersion: session.stored.adapterVersion,
            capabilitySnapshot: session.stored.capabilitySnapshot,
            storedContext: session.stored.storedContext,
            projection: projection,
            providerLaunchAttempted: session.stored.providerLaunchAttempted,
            lastSequence: isProvider ? event.sequence : session.stored.lastSequence,
            acceptedEventCount: session.acceptedCount,
            processedEventCount: session.processedCount,
            acceptedIdempotencyKeys: providerKeys,
            hostLastSequence: isProvider ? session.stored.hostLastSequence : event.sequence,
            hostAcceptedEventCount: session.hostAcceptedCount,
            hostProcessedEventCount: session.hostProcessedCount,
            hostAcceptedIdempotencyKeys: hostKeys,
            providerNamespace: session.stored.providerNamespace,
            providerBranch: session.stored.providerBranch,
            eventEvidence: session.stored.eventEvidence,
        )
        session.stored.restorationClaim = projection.isTerminal
            ? nil
            : restorationClaim
        if projection.isTerminal, session.lease.isDetachedOwner {
            session.lease = .none
        }
        session.revision += 1
        registry[host] = session
    }

    private func projection(
        after kind: RuntimeEventKind,
        from current: RuntimeProjection,
        hasGap: Bool,
    ) -> RuntimeProjection {
        if current == .launching,
           hasGap || ![.completed, .failed, .interrupted].contains(kind)
        {
            return .launching
        }
        if hasGap {
            return .eventOutOfOrder
        }
        return switch kind {
        case .policyReady:
            current
        case .completed:
            .completed
        case .failed:
            .failed
        case .interrupted:
            .interrupted
        case .approvalRequested, .inputRequested, .progress:
            .eventProjected
        }
    }

    private func allows(_ kind: RuntimeEventKind, from projection: RuntimeProjection) -> Bool {
        switch projection {
        case .launching:
            kind != .policyReady
        case .running, .eventProjected, .eventDuplicateIgnored, .eventOutOfOrder:
            kind != .policyReady
        case .policyPending, .policyReady, .launchBlocked, .launchCancelled, .launchFailed,
             .completed, .failed, .interrupted:
            false
        }
    }

    private func terminalResult(for event: RuntimeEventEnvelope) -> RuntimeResult? {
        let outcome: RuntimeOutcome? = switch event.kind {
        case .completed: .completed
        case .failed: .failed
        case .interrupted: .interrupted
        default: nil
        }
        return outcome.map {
            RuntimeResult(runReference: event.runReference, outcome: $0, artifactReferences: [])
        }
    }
}

public extension RuntimeControlPlane {
    func ingestHostEvent(_ event: RuntimeEventEnvelope) async throws -> RuntimeResult? {
        try await hydrateIfNeeded()
        return try await accept(
            event,
            host: event.externalAgentSessionReference,
            expectedSource: .host,
        )
    }
}
