import Foundation

extension RuntimeControlPlane {
    private struct EventCursor {
        let lastSequence: UInt64
        let acceptedCount: Int
        let acceptedKeys: [RuntimeIdempotencyKey]
    }

    private struct AcceptedEventProjection {
        let terminal: RuntimeResult?
        let projection: RuntimeProjection
        let lease: RuntimeLease?
    }

    func accept(
        _ event: RuntimeEventEnvelope,
        host: ExternalAgentSessionReference,
        expectedSource: RuntimeEventSource,
        restoredContext: RuntimeRestoredResumeContext? = nil,
    ) async throws -> RuntimeResult? {
        try validateEventAdmission(event, host: host, expectedSource: expectedSource)
        if let restoredContext {
            try requireRestoredResumeContext(
                restoredContext,
                host: host,
                runReference: event.runReference,
            )
        }
        let terminal = terminalResult(for: event)
        do {
            return try await commit(host: host) { plane, registry in
                try plane.apply(
                    event,
                    expectedSource: expectedSource,
                    terminal: terminal,
                    restoredContext: restoredContext,
                    in: &registry,
                )
            }
        } catch RuntimeHostError.persistenceConflict where terminal != nil {
            let persistedTerminal = try await readRepairPersistedEventTerminal(
                host: host,
                runReference: event.runReference,
                restoredContext: restoredContext,
            )
            if let persistedTerminal { return persistedTerminal }
            return try await repairTerminalEventAfterConflict(
                event,
                host: host,
                expectedSource: expectedSource,
                terminal: terminal,
                restoredContext: restoredContext,
            )
        }
    }

    private func repairTerminalEventAfterConflict(
        _ event: RuntimeEventEnvelope,
        host: ExternalAgentSessionReference,
        expectedSource: RuntimeEventSource,
        terminal: RuntimeResult?,
        restoredContext: RuntimeRestoredResumeContext?,
    ) async throws -> RuntimeResult {
        do {
            let result = try await commit(host: host) { plane, registry in
                try plane.apply(
                    event,
                    expectedSource: expectedSource,
                    terminal: terminal,
                    restoredContext: restoredContext,
                    in: &registry,
                )
            }
            guard let result else { throw RuntimeHostError.persistenceConflict }
            return result
        } catch RuntimeHostError.persistenceConflict {
            let persistedTerminal = try await readRepairPersistedEventTerminal(
                host: host,
                runReference: event.runReference,
                restoredContext: restoredContext,
            )
            guard let persistedTerminal else { throw RuntimeHostError.persistenceConflict }
            return persistedTerminal
        }
    }

    private func readRepairPersistedEventTerminal(
        host: ExternalAgentSessionReference,
        runReference: RuntimeRunReference,
        restoredContext: RuntimeRestoredResumeContext?,
    ) async throws -> RuntimeResult? {
        try await withPersistedState { plane, loaded -> RuntimeResult? in
            if let restoredContext {
                try plane.requireRestoredResumeContext(
                    restoredContext,
                    host: host,
                    runReference: runReference,
                )
            }
            let expectedSession = plane.sessions[host]
            let current = expectedSession?.freshRunSnapshot()
            guard let loaded else { return nil }
            if let restoredContext {
                try plane.requireRestoredResumeContext(
                    restoredContext,
                    host: host,
                    runReference: runReference,
                    in: expectedSession.map { [host: $0] },
                )
            }
            guard let adopted = plane.adoptingPersistedTerminal(
                host: host,
                runReference: runReference,
                expectedSession: expectedSession,
                loaded: loaded,
            ) else { return nil }
            let persisted = adopted.freshRunSnapshot()
            guard case .adoptPersisted = RuntimeFreshRunDecisionTable.decide(
                .persistConflict(persisted: persisted),
                on: current ?? persisted,
            ) else { return nil }
            var reconciled = plane.reconciledRegistry(candidate: plane.sessions, persisted: loaded)
            reconciled[host] = adopted
            if let restoredContext {
                try plane.requireRestoredResumeContext(
                    restoredContext,
                    host: host,
                    runReference: runReference,
                    in: reconciled,
                )
            }
            plane.sessions = reconciled
            return plane.terminalResult(for: adopted.stored)
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
              event.sequence != UInt64.max,
              let session = sessions[host],
              event.runReference == session.stored.runReference
        else { throw RuntimeHostError.malformedAdapterResponse }
    }

    private func apply(
        _ event: RuntimeEventEnvelope,
        expectedSource: RuntimeEventSource,
        terminal: RuntimeResult?,
        restoredContext: RuntimeRestoredResumeContext?,
        in registry: inout SessionRegistry,
    ) throws -> RuntimeResult? {
        let host = event.externalAgentSessionReference
        if let restoredContext {
            try requireRestoredResumeContext(
                restoredContext,
                host: host,
                runReference: event.runReference,
                in: registry,
            )
        }
        try validate(event, host: host, expectedSource: expectedSource, in: registry)
        guard var session = registry[host] else { throw RuntimeHostError.malformedAdapterResponse }
        let isProvider = expectedSource == .provider
        let cursor = eventCursor(for: session, isProvider: isProvider)
        // 예산 포화 시 유일한 예외는 새로운 멱등키의 연속 단말 이벤트(정책 투영이 단말로 수렴)뿐이며,
        // 중복·stale·gap·nonterminal은 fail-closed로 거부되고 어떤 저장 변화도 남기지 않는다.
        let saturatingTerminal = try resolveSaturatedAdmission(
            event,
            terminal: terminal,
            session: session,
            isProvider: isProvider,
            cursor: cursor,
        )
        try advanceProcessedCount(in: &session, isProvider: isProvider, saturating: saturatingTerminal)
        if try applyReplayEvidence(
            event,
            session: &session,
            cursor: cursor,
            registry: &registry,
            bypassesBudget: saturatingTerminal,
        ) { return nil }
        let hasGap = gapEvidence(for: event, cursor: cursor, session: &session)
        let accepted = acceptedEventProjection(
            event,
            terminal: terminal,
            session: session,
            isProvider: isProvider,
            hasGap: hasGap,
        )
        persistAccepted(
            event,
            source: expectedSource,
            session: &session,
            projection: accepted.projection,
            registry: &registry,
        )
        if let lease = accepted.lease, session.lease != lease {
            session.lease = lease
            session.revision += 1
            registry[host] = session
        }
        return accepted.terminal
    }

    private func applyReplayEvidence(
        _ event: RuntimeEventEnvelope,
        session: inout Session,
        cursor: EventCursor,
        registry: inout SessionRegistry,
        bypassesBudget bypassesBudget: Bool = false,
    ) throws -> Bool {
        let host = event.externalAgentSessionReference
        if cursor.acceptedKeys.contains(event.idempotencyKey) {
            session.stored = session.stored.withEvidence(.ignoredDuplicate(event.idempotencyKey))
            session.revision += 1
            registry[host] = session
            return true
        }
        guard event.sequence > cursor.lastSequence else {
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
            return true
        }
        guard bypassesBudget || cursor.acceptedCount < RuntimeBoundaryLimits.acceptedEventsPerRun else {
            throw RuntimeHostError.malformedAdapterResponse
        }
        return false
    }

    private func budgetSaturated(session: Session, cursor: EventCursor, isProvider: Bool) -> Bool {
        let processed = isProvider ? session.processedCount : session.hostProcessedCount
        return processed >= RuntimeBoundaryLimits.acceptedEventsPerRun
            || cursor.acceptedCount >= RuntimeBoundaryLimits.acceptedEventsPerRun
    }

    /// 예산 포화 여부를 판정하고, 포화 상태에서 수용 가능한 단말 예외가 아니면 fail-closed로 거부한다.
    private func resolveSaturatedAdmission(
        _ event: RuntimeEventEnvelope,
        terminal: RuntimeResult?,
        session: Session,
        isProvider: Bool,
        cursor: EventCursor,
    ) throws -> Bool {
        let saturated = budgetSaturated(session: session, cursor: cursor, isProvider: isProvider)
        let saturatingTerminal = saturated && admitsSaturatedTerminal(
            event,
            terminal: terminal,
            session: session,
            isProvider: isProvider,
            cursor: cursor,
        )
        if saturated, !saturatingTerminal {
            throw RuntimeHostError.malformedAdapterResponse
        }
        return saturatingTerminal
    }

    /// 예산 포화 상태에서 수용 가능한 유일한 예외인지 판정한다.
    /// 새로운 멱등키로 연속 시퀀스에 도착한 단말 이벤트이면서 정책 투영이 단말로 수렴할 때만 참이다.
    private func admitsSaturatedTerminal(
        _ event: RuntimeEventEnvelope,
        terminal: RuntimeResult?,
        session: Session,
        isProvider: Bool,
        cursor: EventCursor,
    ) -> Bool {
        guard let terminal,
              !cursor.acceptedKeys.contains(event.idempotencyKey),
              event.sequence > cursor.lastSequence,
              event.sequence - cursor.lastSequence == 1
        else { return false }
        let accepted = acceptedEventProjection(
            event,
            terminal: terminal,
            session: session,
            isProvider: isProvider,
            hasGap: false,
        )
        return accepted.projection.isTerminal
    }

    /// 뺄셈 기반 연속성 판정으로 lastSequence + 1 계산의 UInt64 오버플로를 원천 차단하고,
    /// 갭이 감지되면 시퀀스 갭 증거를 기록한다.
    private func gapEvidence(for event: RuntimeEventEnvelope, cursor: EventCursor, session: inout Session) -> Bool {
        // applyReplayEvidence가 false를 반환하면 event.sequence > cursor.lastSequence가 보장된다.
        let hasGap = event.sequence - cursor.lastSequence != 1
        guard hasGap else { return false }
        session.stored = session.stored.withEvidence(.sequenceGap(
            expected: cursor.lastSequence &+ 1,
            received: event.sequence,
        ))
        return true
    }

    private func acceptedEventProjection(
        _ event: RuntimeEventEnvelope,
        terminal: RuntimeResult?,
        session: Session,
        isProvider: Bool,
        hasGap: Bool,
    ) -> AcceptedEventProjection {
        let usesFreshRunProviderPolicy = switch session.lease {
        case .consuming, .detachedConsuming:
            true
        case .none, .launching, .detachedLaunching, .restored, .resuming:
            false
        }
        let providerDecision: RuntimeFreshRunDecision? = if isProvider,
                                                            terminal != nil,
                                                            usesFreshRunProviderPolicy
        {
            RuntimeFreshRunDecisionTable.decide(
                .providerEvent(
                    kind: event.kind,
                    hasGap: hasGap,
                    isDuplicate: false,
                    isStale: false,
                ),
                on: session.freshRunSnapshot(),
            )
        } else {
            nil
        }
        switch providerDecision {
        case let .persist(projection, _, lease):
            return AcceptedEventProjection(terminal: terminal, projection: projection, lease: lease)
        case .ignore, .recordCleanupFailure, .throwCancellation, .throwHost, .adoptPersisted:
            return AcceptedEventProjection(
                terminal: nil,
                projection: hasGap ? .eventOutOfOrder : nonterminalProjection(from: session.stored.projection),
                lease: nil,
            )
        case nil:
            return AcceptedEventProjection(
                terminal: hasGap ? nil : terminal,
                projection: projection(
                    after: event.kind,
                    from: session.stored.projection,
                    hasGap: hasGap,
                ),
                lease: nil,
            )
        }
    }

    private func nonterminalProjection(from current: RuntimeProjection) -> RuntimeProjection {
        switch current {
        case .launching:
            .launching
        case .running, .eventProjected:
            .eventProjected
        case .eventDuplicateIgnored:
            .eventDuplicateIgnored
        case .eventOutOfOrder:
            .eventOutOfOrder
        case .policyPending, .policyReady, .launchBlocked, .launchCancelled, .launchFailed,
             .completed, .failed, .interrupted:
            current
        }
    }

    private func advanceProcessedCount(in session: inout Session, isProvider: Bool, saturating: Bool = false) throws {
        let count = isProvider ? session.processedCount : session.hostProcessedCount
        guard count < RuntimeBoundaryLimits.acceptedEventsPerRun else {
            // 포화 예외가 허용된 단말 이벤트는 처리 카운터를 상한에 고정한다(초과 증가 금지).
            guard saturating else { throw RuntimeHostError.malformedAdapterResponse }
            return
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
            // 수용 카운터는 상한에서 포화되며 어떤 경로로도 초과하지 않는다.
            session.acceptedCount = min(session.acceptedCount + 1, RuntimeBoundaryLimits.acceptedEventsPerRun)
        } else {
            session.hostAcceptedCount = min(session.hostAcceptedCount + 1, RuntimeBoundaryLimits.acceptedEventsPerRun)
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
